// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IKYCBitkubChain } from "src/core/token/IKYCBitkubChain.sol";
import { IAdminProjectRouter } from "src/core/token/IAdminProjectRouter.sol";
import { IKAP20 } from "src/core/token/IKAP20.sol";

/*//////////////////////////////////////////////////////////////
                           PONDER KAP20 TOKEN
    //////////////////////////////////////////////////////////////*/

/**
 * @title PonderKAP20
 * @notice KAP20 implementation for Bitkub Chain with gasless approvals (EIP-2612)
 * @dev Extends OpenZeppelin ERC20 with permit functionality and Bitkub Chain compliance
 *      Used as base contract for PONDER token implementation on Bitkub Chain
 */
contract PonderKAP20 is ERC20, IKAP20 {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                         EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Domain separator for EIP-712 signatures
    /// @dev Cached on construction for gas optimization
    /// @dev Recomputed if chain ID or contract address changes
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;

    /// @notice Chain ID at contract deployment
    /// @dev Used to detect chain ID changes for domain separator
    /// @dev Set as immutable for gas optimization
    uint256 private immutable _CACHED_CHAIN_ID;

    /// @notice Contract address at deployment
    /// @dev Used to detect contract address changes
    /// @dev Set as immutable for gas optimization
    address private immutable _CACHED_THIS;

    /// @notice EIP-2612 permit typehash
    /// @dev keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256
    /// deadline)")
    /// @dev
    bytes32 private constant _PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @notice Permit nonces per address
    /// @dev Prevents signature replay attacks
    /// @dev Increments with each successful permit
    mapping(address => uint256) private _nonces;

    /*//////////////////////////////////////////////////////////////
                        KAP-20 ADDITIONAL STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Bitkub Chain KYC verification service
    /// @dev Used to verify KYC status of addresses
    IKYCBitkubChain public kyc;

    /// @notice Bitkub Chain admin project router
    /// @dev Used to verify admin privileges
    IAdminProjectRouter public adminProjectRouter;

    /// @notice Committee address for admin operations
    /// @dev Has highest authority for contract administration
    address public committee;

    /// @notice Transfer router for special transfer operations
    /// @dev Can execute internal and external transfers
    address public transferRouter;

    /// @notice Project identifier for admin verification
    /// @dev Used with adminProjectRouter
    string public constant PROJECT = "PONDER";

    /// @notice Minimum KYUC level required for token operations
    /// @dev Defautl is set in constructor
    uint256 public acceptedKYCLevel;

    /// @notice Flag to enforce KYC for all operations
    /// @dev When true, all operations require KYC verification
    bool public isActivatedOnlyKYCAddress;

    /// @notice Contract pause state
    /// @dev When true, most operations are disabled
    bool private _paused;

    /// @notice Owner address for admin operations
    /// @dev Initially set to deployer
    address private _owner;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Permit timestamp validation failed
    /// @dev Thrown when permit deadline has passed
    error PermitExpired();

    /// @notice Permit signature verification failed
    /// @dev Thrown for invalid or unauthorized signatures
    error InvalidSignature();

    /// @notice Contract is paused
    /// @dev Thrown when an operation is attempted while paused
    error PausedToken();

    /// @notice Caller is not authorized
    /// @dev Thrown when caller lacks required permissions
    error NotAuthorized();

    /// @notice Address is zero
    /// @dev Thrown when a zero address is provided
    error ZeroAddress();

    /// @notice KYC level is insufficient
    /// @dev Thrown when KYC verification fails
    error KYCNotApproved();

    /// @notice KYC level is invalid
    /// @dev Thrown when KYC level is invalid
    error InvalidKYCLevel();

    /// @notice Caller is not the owner
    /// @dev Thrown when a non-owner tries to call an owner-only function
    error NotOwner();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes token and permit functionality
    /// @dev Simplified constructor matching PonderERC20 for easier migration
    /// @param tokenName ERC20 token name
    /// @param tokenSymbol ERC20 token symbol
    constructor(string memory tokenName, string memory tokenSymbol) ERC20(tokenName, tokenSymbol) {
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_THIS = address(this);
        _CACHED_DOMAIN_SEPARATOR = _computeDomainSeparator();

        // Set deployer as owner
        _owner = msg.sender;

        // Initialize KAP parameters with safe defaults
        acceptedKYCLevel = 0;
        isActivatedOnlyKYCAddress = false;
        _paused = false;
    }

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensures function can only be called by the owner
    /// @dev Reverts with NotOwner if caller is not the owner
    modifier onlyOwner() virtual {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    /// @notice Ensures function can only be called when contract is not paused
    /// @dev Reverts with Paused error if contract is paused
    modifier whenNotPaused() {
        if (_paused) revert PausedToken();
        _;
    }

    /// @notice Ensures function can only be called by super admin
    /// @dev Reverts with NotAuthorized if caller is not super admin
    modifier onlySuperAdmin() {
        if (address(adminProjectRouter) == address(0)) return; // skip check if not set
        if (!adminProjectRouter.isSuperAdmin(msg.sender, PROJECT)) revert NotAuthorized();
        _;
    }

    /// @notice Ensures function can only be called by super admin or transfer router
    /// @dev Reverts with NotAuthorized if caller is neither super admin nor transfer router
    /// @dev Bypasses check if adminProjectRouter not set
    modifier onlySuperAdminOrTransferRouter() {
        if (address(adminProjectRouter) == address(0)) return; // skip check if not set
        if (!adminProjectRouter.isSuperAdmin(msg.sender, PROJECT) || msg.sender == transferRouter) {
            revert NotAuthorized();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           EIP-2612 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates EIP-712 domain separator
    /// @dev Incorporates name, version, chain ID, and contract address
    /// @return Domain separator hash
    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name())),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Retrieves current domain separator
    /// @dev Returns cached value if chain hasn't changed
    /// @return current domain separator hash
    function domainSeparator() public view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID && address(this) == _CACHED_THIS) {
            return _CACHED_DOMAIN_SEPARATOR;
        }
        return _computeDomainSeparator();
    }
}
