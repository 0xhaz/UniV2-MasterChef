// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { PonderKAP20 } from "src/core/token/PonderKAP20.sol";
import { PonderTokenStorage } from "src/core/token/storage/PonderTokenStorage.sol";
import { PonderTokenTypes } from "src/core/token/types/PonderTokenTypes.sol";
import { IPonderToken } from "src/core/token/IPonderToken.sol";
import { IPonderStaking } from "src/core/staking/IPonderStaking.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER TOKEN IMPLEMENTATION
//////////////////////////////////////////////////////////////*/

/**
 * @title PonderTokens
 * @notice Implementation of Ponder protocol's token
 * @dev ERC20 token with team vesting and governance features
 *      Manages token distribution, vesting and access control
 */
contract PonderToken is PonderKAP20, PonderTokenStorage, IPonderToken {
    using PonderTokenTypes for *;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Contract deployment timestamp
    /// @dev Used for vesting and minting calculations
    /// @dev Immutable to prevent tampering
    uint256 private immutable _DEPLOYMENT_TIME;

    /// @notice Address for team and reserve allocations
    address private immutable _TEAM_RESERVE;

    /// @notice Flag for if team locked staking has been initialized
    bool private _stakingInitialized;

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys and initializes the token contract
    /// @dev Sets up initial allocations and team staking
    /// @param teamReserve_ Address receiving team and reserve tokens
    /// @param launcher_ Address of the protocol launcher
    /// @param staking_ Address of the Ponder staking contract
    /// @custom:security Team allocation is force-staked for 2 years
    constructor(
        address teamReserve_,
        address launcher_,
        address staking_
    )
        PonderKAP20("Koi", "KOI")
    {
        if (teamReserve_ == address(0)) revert PonderTokenTypes.ZeroAddress();

        // Set core contract parameters
        _owner = msg.sender;
        _DEPLOYMENT_TIME = block.timestamp;
        _TEAM_RESERVE = teamReserve_;
        _launcher = launcher_;
        _staking = IPonderStaking(staking_);

        // Mint team allocation to this contract for force-staking
        _mint(address(this), PonderTokenTypes.TEAM_ALLOCATION);

        // Mint initial liquidity allocation to launcher for pool creation
        _mint(launcher_, PonderTokenTypes.INITIAL_LIQUIDITY);
    }

    /// @notice Burns tokens from caller's balance
    /// @dev Only callable by launcher or owner
    /// @dev Has minimum and maximum burn limits
    /// @param amount Quantity of tokens to burn
    /// @dev Reverts if amount < 1000 or > 1% of total supply
    function burn(uint256 amount) external {
        if (msg.sender != _launcher && msg.sender != _owner) {
            revert PonderTokenTypes.OnlyLauncherOrOwner();
        }
        if (amount < 1000) revert PonderTokenTypes.BurnAmountTooSmall();
        if (amount > totalSupply() / 100) revert PonderTokenTypes.BurnAmountTooLarge();
        if (balanceOf(msg.sender) < amount) revert PonderTokenTypes.InsufficientBalance();

        _burn(msg.sender, amount);
        _totalBurned += amount;

        emit PonderTokenTypes.TokensBurned(msg.sender, amount);
    }

    /// @notice Mints new tokens
    /// @dev Only callable by minter (MasterChef)
    /// @param to Address to receive minted tokens
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external {
        if (msg.sender != _minter) revert PonderTokenTypes.Forbidden();
        if (totalSupply() + amount > PonderTokenTypes.MAXIMUM_SUPPLY) {
            revert PonderTokenTypes.SupplyExceeded();
        }

        _mint(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates minting privileges address
    /// @dev Restricted to owner
    /// @dev Cannot be zero address
    /// @param minter_ New address to receive minting rights
    /// @dev Emits MinterUpdated event
    function setMinter(address minter_) external {
        if (msg.sender != _owner) revert PonderTokenTypes.Forbidden();
        if (minter_ == address(0)) revert PonderTokenTypes.ZeroAddress();

        address oldMinter = _minter;
        _minter = minter_;
        emit PonderTokenTypes.MinterUpdated(oldMinter, minter_);
    }

    function owner() public view override (IPonderToken, PonderKAP20) returns (address) { }

    function transferOwnership(address newOwner)
        external
        override (IPonderToken, PonderKAP20)
        onlyOwner
    { }

    function setLauncher(address launcher_) external override { }

    function acceptOwnership() external override { }

    function minter() external view override returns (address) { }

    function pendingOwner() external view override returns (address) { }

    function teamReserve() external view override returns (address) { }

    function launcher() external view override returns (address) { }

    function staking() external view override returns (address) { }

    function totalBurned() external view override returns (uint256) { }

    function deploymentTime() external view override returns (uint256) { }

    function maximumSupply() external pure override returns (uint256) { }

    function teamAllocation() external pure override returns (uint256) { }
}
