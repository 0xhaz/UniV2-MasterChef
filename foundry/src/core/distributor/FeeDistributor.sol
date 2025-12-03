// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { IFeeDistributor } from "src/core/distributor/IFeeDistributor.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPonderPair } from "src/core/pair/IPonderPair.sol";
import { IPonderFactory } from "src/core/factory/IPonderFactory.sol";
import { IPonderRouter } from "src/core/periphery/IPonderRouter.sol";
import { IPonderStaking } from "src/core/staking/IPonderStaking.sol";
import { IPonderPriceOracle } from "src/core/oracle/IPonderPriceOracle.sol";

/*//////////////////////////////////////////////////////////////
                        FEE DISTRIBUTOR
//////////////////////////////////////////////////////////////*/

/**
 * @title FeeDistributor
 * @notice Fee distributor with gas-aware processing, queue management, and error recovery
 * @dev Implements incremental processing, priority queues, and comprehensive monitoring
 */
contract FeeDistributor is IFeeDistributor, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum number of pairs that can be processed in a single collection
    uint256 public constant MAX_PAIRS_PER_COLLECTION = 20;

    /// @notice Maximum number of jobs to process in a single queue processing call
    uint256 public constant MAX_JOBS_PER_BATCH = 10;

    /// @notice Maximum consecutive failures before circuit breaker activates
    uint256 public constant MAX_FAILURES = 5;

    /// @notice Distribution cooldown period (1 hour)
    uint256 public constant DISTRIBUTION_COOLDOWN = 1 hours;

    /// @notice Slippage tolerance for swap (0.5%)
    uint256 public constant SLIPPAGE_TOLERANCE = 995; // 0.5% slippage
    uint256 public constant SLIPPAGE_BASE = 1000; // 100%

    /*//////////////////////////////////////////////////////////////
                            ENUMS AND STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Types of processing jobs
    enum ProcessingType {
        REGULAR_TOKEN,
        LP_TOKEN,
        EMERGENCY
    }

    /// @notice Processing job structure
    struct ProcessingJob {
        // Token address to process
        address token;
        // Amount to process
        uint256 amount;
        // Priority score (higher = process first)
        uint256 priority;
        // Estimated gas cost
        uint256 estimatedGas;
        // When job was created
        uint256 timestamp;
        // Type of processing job
        ProcessingType jobType;
        // Number of consecutive failures
        uint256 failureCount;
    }

    /*//////////////////////////////////////////////////////////////
                            PROTOCOL STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The protocol's factory contract for managing pairs
    IPonderFactory public immutable FACTORY;

    /// @notice The protocol's router contract for swap operations
    IPonderRouter public immutable ROUTER;

    /// @notice The address of the protocol's PONDER token
    address public immutable PONDER;

    /// @notice The protocol's staking contract for PONDER tokens
    IPonderStaking public immutable STAKING;

    /// @notice The protocol's price oracle for USD value calculations
    IPonderPriceOracle public immutable PRICE_ORACLE;

    /// @notice The base token (KKUB) used for multi-hop swaps
    address public immutable KKUB;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Balance tracking for incremental processing
    mapping(address => uint256) public lastProcessedBalance;

    /// @notice Pending balance amounts waiting for processing
    mapping(address => uint256) public pendingBalance;

    /// @notice Array of tokens we're tracking for balance changes
    address[] public trackedTokens;

    /// @notice Mapping to check if token is already tracked (to avoid duplicates)
    mapping(address => bool) public isTokenTracked;

    /// @notice Processing queue array
    ProcessingJob[] public processingQueue;

    /// @notice Mapping from token address to queue index (1-based, 0 means not in queue)
    mapping(address => uint256) public tokenQueueIndex;

    /// @notice Circuit breaker state
    bool public emergencyPaused;

    /// @notice Consecutive failure counter
    uint256 public failureCount;

    /// @notice Success/failure tracking for analytics
    uint256 public totalJobsProcessed;
    uint256 public totalJobsFailed;

    /// @notice Last time queue was processed
    uint256 public lastQueueProcessTime;

    /// @notice Contract owner (for access control)
    address public owner;

    /// @notice Last time distribution occurred
    uint256 public lastDistributionTimestamp;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the enhanced fee distributor contract
    /// @param _factory Address of the protocol factory contract
    /// @param _router Address of the protocol router contract
    /// @param _ponder Address of the PONDER token contract
    /// @param _staking Address of the PONDER staking contract
    /// @param _priceOracle Address of the price oracle contract
    /// @param _kkub Address of the KKUB base token for multi-hop swaps
    constructor(
        address _factory,
        address _router,
        address _ponder,
        address _staking,
        address _priceOracle,
        address _kkub
    ) {
        if (
            _factory == address(0) || _router == address(0) || _ponder == address(0)
                || _staking == address(0) || _priceOracle == address(0) || _kkub == address(0)
        ) {
            revert IFeeDistributor.ZeroAddress();
        }

        FACTORY = IPonderFactory(_factory);
        ROUTER = IPonderRouter(_router);
        PONDER = _ponder;
        STAKING = IPonderStaking(_staking);
        PRICE_ORACLE = IPonderPriceOracle(_priceOracle);
        KKUB = _kkub;

        owner = msg.sender;

        _safeApprove(_ponder, _router, type(uint256).max);
        _safeApprove(_kkub, _router, type(uint256).max);

        _addTokenToTracking(_ponder);
        _addTokenToTracking(_kkub);
    }

    /*//////////////////////////////////////////////////////////////
                            COLLECTION PHASE
    //////////////////////////////////////////////////////////////*/

    /// @notice Collects fees from pairs - ultra minimal like Uniswap
    /// @param pairs Array of pair addresses to collect fees from
    /// @dev Just sync and skim - no complex tracking during collection
    function collectFees(address[] calldata pairs) external nonReentrant {
        if (emergencyPaused) revert EmergencyPaused();
        if (pairs.length == 0) revert EmptyArray();
        if (pairs.length > MAX_PAIRS_PER_COLLECTION) revert TooManyPairs();

        for (uint256 i = 0; i < pairs.length; i++) {
            _collectFeesFromPair(pairs[i]);
        }

        emit FeesCollected(pairs, 0, block.timestamp);
    }

    /// @notice Collects fees from a single pair
    /// @param pair Address of the pair to collect fees from
    function _collectFeesFromPair(address pair) internal {
        if (pair == address(0)) revert InvalidPairAddress();

        try IPonderPair(pair).sync() {
            try IPonderPair(pair).skim(address(this)) { }
            catch {
                emit CollectionFailed(pair, "Skim failed");
            }
        } catch {
            emit CollectionFailed(pair, "Sync failed");
        }
    }

    /// @notice Updates balance tracking - called manually when needed
    function updateBalanceTracking() external {
        uint256 trackedCount = trackedTokens.length;

        for (uint256 i = 0; i < trackedCount; i++) {
            address token = trackedTokens[i];
            uint256 currentBalance = IERC20(token).balanceOf(address(this));
            uint256 lastBalance = lastProcessedBalance[token];

            if (currentBalance > lastBalance) {
                uint256 newAmount = currentBalance - lastBalance;
                pendingBalance[token] += newAmount;

                _addToProcessingQueue(token, newAmount);

                emit BalanceUpdated(token, lastBalance, currentBalance, newAmount);
            }
        }
    }

    function distribute() external override { }

    function convertFees(address token) external override { }

    function minimumAmount() external pure override returns (uint256) { }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _safeApprove(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = _getSafeAllowance(token, address(this), spender);
        if (currentAllowance >= amount) return;

        try IERC20(token).approve(spender, amount) returns (bool success) {
            if (!success) revert IFeeDistributor.ApprovalFailed();
        } catch {
            try IERC20(token).approve(spender, 0) {
                try IERC20(token).approve(spender, amount) returns (bool success) {
                    if (!success) revert IFeeDistributor.ApprovalFailed();
                } catch {
                    revert IFeeDistributor.ApprovalFailed();
                }
            } catch {
                revert IFeeDistributor.ApprovalFailed();
            }
        }
    }

    /// @notice Safe allowance checking that handles broken USDT implementation
    /// @param token Token address
    /// @param tokenOwner Owner of the tokens
    /// @param spender Spender address
    /// @return allowance Current allowance amount
    function _getSafeAllowance(
        address token,
        address tokenOwner,
        address spender
    )
        internal
        view
        returns (uint256)
    {
        try IERC20(token).allowance(tokenOwner, spender) returns (uint256 amount) {
            return amount;
        } catch {
            (bool success, bytes memory data) = token.staticcall(
                abi.encodeWithSignature("allowance(address,address)", tokenOwner, spender)
            );
            if (success && data.length >= 32) {
                return abi.decode(data, (uint256));
            }
        }
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollectionFailed(address indexed pair, string reason);

    /*//////////////////////////////////////////////////////////////
                             CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/
    error EmergencyPaused();
    error EmptyArray();
    error TooManyPairs();
}
