// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { IFeeDistributor } from "src/core/distributor/IFeeDistributor.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPonderPair } from "src/core/pair/IPonderPair.sol";
import { IPonderFactory } from "src/core/factory/IPonderFactory.sol";
import { IPonderRouter } from "src/periphery/router/IPonderRouter.sol";
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

    /// @notice Adds a token to tracking if not already tracked
    /// @param token Address of the token to track
    function _addTokenToTracking(address token) internal {
        if (!isTokenTracked[token] && token != address(0)) {
            trackedTokens.push(token);
            isTokenTracked[token] = true;
            lastProcessedBalance[token] = 0;
        }
    }

    /// @notice Manually add tokens to tracking when needed
    /// @param tokens Array of token addresses to start tracking
    function addTokensToTracking(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            _addTokenToTracking(tokens[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PROCESSING PHASE
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes jobs from the queue with gas management
    /// @param maxJobs Maximum number of jobs to attempt processing
    function processQueue(uint256 maxJobs) external nonReentrant {
        if (emergencyPaused) revert EmergencyPaused();
        if (maxJobs == 0) revert IFeeDistributor.InvalidAmount();
        if (maxJobs > MAX_JOBS_PER_BATCH) maxJobs = MAX_JOBS_PER_BATCH;

        uint256 gasStart = gasleft();
        uint256 jobsProcessed = 0;
        uint256 jobsFailed = 0;

        _sortQueueByPriority();

        while (jobsProcessed < maxJobs && processingQueue.length > 0) {
            ProcessingJob memory job = processingQueue[0];

            uint256 gasBeforeJob = gasleft();
            bool success = _processJob(job);
            uint256 gasUsedForJob = gasBeforeJob - gasleft();

            if (success) {
                _removeFromQueue(0);
                jobsProcessed++;
                totalJobsProcessed++;

                if (failureCount > 0) {
                    failureCount = 0;
                }
            } else {
                _handleJobFailure(0);
                jobsFailed++;
                totalJobsFailed++;
            }
        }

        lastQueueProcessTime = block.timestamp;
        uint256 totalGasUsed = gasStart - gasleft();

        emit QueueProcessed(jobsProcessed, jobsFailed, totalGasUsed, processingQueue.length);

        _tryAutoDistribute();
    }

    /// @notice Processes a single job from the queue
    /// @param job The processing job to execute
    /// @return success True if job processed successfully, false otherwise
    function _processJob(ProcessingJob memory job) internal returns (bool) {
        if (pendingBalance[job.token] < job.amount) {
            emit ProcessingFailed(job.token, job.amount, "Insufficient pending balance");
            return false;
        }

        uint256 actualBalance = IERC20(job.token).balanceOf(address(this));
        uint256 processAmount = actualBalance < job.amount ? actualBalance : job.amount;

        if (processAmount == 0) {
            emit ProcessingFailed(job.token, job.amount, "Zero process amount");
            return false;
        }

        pendingBalance[job.token] -= processAmount;

        try this._safeProcessToken(job.token, processAmount, job.jobType) {
            lastProcessedBalance[job.token] = IERC20(job.token).balanceOf(address(this));

            emit JobProcessed(job.token, processAmount, job.jobType);
            return true;
        } catch {
            pendingBalance[job.token] += processAmount;

            emit ProcessingFailed(job.token, processAmount, "Processing error");
            return false;
        }
    }

    /// @notice Safely processes a token with proper error handling
    /// @param token Address of the token to process
    /// @param amount Amount of the token to process
    /// @param jobType Type of processing job
    /// @dev This function is called externally by _processJob to enable try/catch
    function _safeProcessToken(address token, uint256 amount, ProcessingType jobType) external {
        if (msg.sender != address(this)) revert UnauthorizedCall();

        if (jobType == ProcessingType.LP_TOKEN) {
            _processLPTokenSafe(token, amount);
        } else {
            _convertTokenToPonderSafe(token, amount);
        }
    }

    /// @notice Safely processes LP tokens with gas management
    /// @param lpToken LP token address
    /// @param amount Amount of LP tokens to process
    function _processLPTokenSafe(address lpToken, uint256 amount) internal {
        IPonderPair pair = IPonderPair(lpToken);
        _safeApprove(lpToken, address(ROUTER), amount);

        (uint256 amount0, uint256 amount1) = ROUTER.removeLiquidity(
            pair.token0(), pair.token1(), amount, 0, 0, address(this), block.timestamp + 300
        );

        emit LPTokenProcessed(lpToken, amount, amount0, amount1);
    }

    /// @notice Safely converts regular tokens to PONDER
    /// @param token Token address to convert
    /// @param amount Amount of tokens to convert
    function _convertTokenToPonderSafe(address token, uint256 amount) internal {
        if (token == PONDER) return;

        address[] memory path = _getOptimalPathToPonder(token);
        if (path.length == 0) revert NoConversionPath();

        _safeApprove(token, address(ROUTER), amount);

        uint256[] memory amounts =
            ROUTER.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp + 300);

        emit FeesConverted(token, amount, amounts[amounts.length - 1]);
    }

    /*//////////////////////////////////////////////////////////////
                            QUEUE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds a token to the processing queue
    /// @param token Address of the token to add
    /// @param amount Amount of the token to process
    function _addToProcessingQueue(address token, uint256 amount) internal {
        uint256 existingIndex = tokenQueueIndex[token];
        if (existingIndex > 0 && existingIndex <= processingQueue.length) {
            ProcessingJob storage existingJob = processingQueue[existingIndex - 1];
            existingJob.amount += amount;
            existingJob.priority = _calculatePriority(token, existingJob.amount);
            existingJob.timestamp = block.timestamp;

            emit JobUpdated(token, existingJob.amount, existingJob.priority);

            return;
        }

        ProcessingType jobType =
            _isLPToken(token) ? ProcessingType.LP_TOKEN : ProcessingType.REGULAR_TOKEN;

        uint256 priority = _calculatePriority(token, amount);

        ProcessingJob memory job = ProcessingJob({
            token: token,
            amount: amount,
            priority: priority,
            estimatedGas: 200_000, // Simple fixed estimate
            timestamp: block.timestamp,
            jobType: jobType,
            failureCount: 0
        });

        processingQueue.push(job);
        tokenQueueIndex[token] = processingQueue.length;

        emit JobQueued(token, amount, priority, 200_000, jobType);
    }

    /// @notice Removes a job from the queue
    /// @param index Index of job to remove
    function _removeFromQueue(uint256 index) internal {
        if (index >= processingQueue.length) return;

        address tokenToRemove = processingQueue[index].token;

        if (index < processingQueue.length - 1) {
            ProcessingJob memory lastJob = processingQueue[processingQueue.length - 1];
            processingQueue[index] = lastJob;
            tokenQueueIndex[lastJob.token] = index + 1;
        }

        processingQueue.pop();
        delete tokenQueueIndex[tokenToRemove];

        emit JobRemoved(tokenToRemove, index);
    }

    /// @notice Sorts the queue by priority (highest first)
    function _sortQueueByPriority() internal {
        uint256 length = processingQueue.length;
        if (length <= 1) return;

        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (processingQueue[j].priority < processingQueue[j + 1].priority) {
                    ProcessingJob memory temp = processingQueue[j];
                    processingQueue[j] = processingQueue[j + 1];
                    processingQueue[j + 1] = temp;

                    tokenQueueIndex[processingQueue[j].token] = j + 1;
                    tokenQueueIndex[processingQueue[j + 1].token] = j + 2;
                }
            }
        }
    }

    /// @notice Calculates priority score for a token (minimal design)
    /// @param token Address of the token
    /// @param amount Amount of the token to process
    /// @return priority Calculated priority score (higher = more urgent)
    function _calculatePriority(address token, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;

        if (token == KKUB) {
            return 1000;
        }

        if (token == PONDER) {
            return 900;
        }

        return 100;
    }

    /// @notice Handles job failure with retry logic
    /// @param jobIndex Index of the failed job
    function _handleJobFailure(uint256 jobIndex) internal {
        if (jobIndex >= processingQueue.length) return;

        ProcessingJob storage job = processingQueue[jobIndex];
        job.failureCount += 1;

        failureCount += 1;

        if (failureCount >= MAX_FAILURES) {
            emergencyPaused = true;
            emit EmergencyPauseActivated(block.timestamp, "Failures");
            return;
        }

        if (job.failureCount >= 3) {
            emit JobAbandoned(job.token, job.amount, job.failureCount);
            _removeFromQueue(jobIndex);
            return;
        }

        job.priority = job.priority / 2;
        job.timestamp = block.timestamp;

        ProcessingJob memory failedJob = processingQueue[jobIndex];
        _removeFromQueue(jobIndex);
        processingQueue.push(failedJob);
        tokenQueueIndex[failedJob.token] = processingQueue.length;

        emit JobRetry(failedJob.token, failedJob.amount, failedJob.failureCount);
    }

    /*//////////////////////////////////////////////////////////////
                              DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Distributes accumulated PONDER tokens to staking contract
    function distribute() external nonReentrant {
        if (emergencyPaused) revert EmergencyPaused();

        uint256 ponderBalance = IERC20(PONDER).balanceOf(address(this));

        if (ponderBalance == 0) {
            revert IFeeDistributor.InvalidAmount();
        }

        if (block.timestamp < lastDistributionTimestamp + DISTRIBUTION_COOLDOWN) {
            revert IFeeDistributor.DistributionTooFrequent();
        }

        _distribute();
    }

    /// @notice Internal distribution logic
    function _distribute() internal {
        uint256 totalAmount = IERC20(PONDER).balanceOf(address(this));
        if (totalAmount == 0) return;

        lastDistributionTimestamp = block.timestamp;

        if (!IERC20(PONDER).transfer(address(STAKING), totalAmount)) {
            revert IFeeDistributor.TransferFailed();
        }

        emit FeesDistributed(totalAmount);
    }

    /// @notice Attempts automatic distribution if conditions are met
    function _tryAutoDistribute() internal {
        uint256 ponderBalance = IERC20(PONDER).balanceOf(address(this));

        if (
            ponderBalance > 0
                && block.timestamp >= lastDistributionTimestamp + DISTRIBUTION_COOLDOWN
        ) {
            _distribute();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN & EMERGENCY
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency pause mechanism to halt processing
    function emergencyPause() external onlyOwner {
        emergencyPaused = true;
        emit EmergencyPauseActivated(block.timestamp, "Manual");
    }

    /// @notice Resume operations after emergency pause
    function emergencyResume() external onlyOwner {
        emergencyPaused = false;
        failureCount = 0;
        emit EmergencyPauseDeactivated(block.timestamp);
    }

    /// @notice Manually process a stuck token with higher gas limits
    /// @param token Address of the token to process
    /// @param amount Amount of the token to process
    function emergencyProcessToken(address token, uint256 amount) external onlyOwner {
        if (!emergencyPaused) revert NotInEmergencyMode();
        if (gasleft() < 100_000) revert InsufficientGas();

        uint256 gasStart = gasleft();

        if (_isLPToken(token)) {
            _processLPTokenSafe(token, amount);
        } else {
            _convertTokenToPonderSafe(token, amount);
        }

        if (pendingBalance[token] >= amount) {
            pendingBalance[token] -= amount;
        }

        lastProcessedBalance[token] = IERC20(token).balanceOf(address(this));

        emit EmergencyProcessing(token, amount, gasStart - gasleft());
    }

    /// @notice Reset balance tracking for migration scenarios
    /// @param tokens Array of token addresses
    /// @param balances Array of balance values to set
    function resetBalanceTracking(
        address[] calldata tokens,
        uint256[] calldata balances
    )
        external
        onlyOwner
    {
        if (tokens.length != balances.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < tokens.length; i++) {
            lastProcessedBalance[tokens[i]] = balances[i];
            pendingBalance[tokens[i]] = 0;

            uint256 queueIndex = tokenQueueIndex[tokens[i]];
            if (queueIndex > 0) {
                _removeFromQueue(queueIndex - 1);
            }
        }

        emit BalanceTrackingReset(tokens, balances);
    }

    /// @notice Clear the entire processing queue
    function clearQueue() external onlyOwner {
        uint256 queueLength = processingQueue.length;

        for (uint256 i = 0; i < queueLength; i++) {
            delete tokenQueueIndex[processingQueue[i].token];
        }

        delete processingQueue;

        emit QueueCleared(queueLength);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW & MONITORING
    //////////////////////////////////////////////////////////////*/

    /// @notice Get comprehensive contract status (hyper-minimal)
    function getStatus()
        external
        view
        returns (
            uint256 queueLength,
            uint256 totalPendingUSD,
            uint256 ponderBalance,
            uint256 nextDistributionTime,
            bool canDistribute,
            uint256[3] memory avgGasPerJob,
            uint256 successRate
        )
    {
        queueLength = processingQueue.length;
        totalPendingUSD = 0;
        ponderBalance = IERC20(PONDER).balanceOf(address(this));
        nextDistributionTime = lastDistributionTimestamp + DISTRIBUTION_COOLDOWN;
        canDistribute = block.timestamp >= nextDistributionTime && ponderBalance > 0;

        avgGasPerJob[0] = 150_000;
        avgGasPerJob[1] = 300_000;
        avgGasPerJob[2] = 500_000;

        successRate = totalJobsProcessed + totalJobsFailed > 0
            ? (totalJobsProcessed * 10_000) / (totalJobsProcessed + totalJobsFailed)
            : 10_000;
    }

    /// @notice Get queue length
    /// @return length Number of jobs in the processing queue
    function getQueueLength() external view returns (uint256 length) {
        length = processingQueue.length;
    }

    /// @notice Get specific job details
    /// @param index Index of the job in the queue
    /// @return job Processing job details
    function getJobDetails(uint256 index) external view returns (ProcessingJob memory job) {
        if (index >= processingQueue.length) revert InvalidIndex();
        return processingQueue[index];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if token is an LP token
    /// @param token Token address
    /// @return isLP Whether token is LP token
    function _isLPToken(address token) internal view returns (bool) {
        if (token.code.length == 0) return false;

        try IPonderPair(token).factory() returns (address factory) {
            return factory == address(FACTORY);
        } catch {
            return false;
        }
    }

    /// @notice Checks if token has a conversion path to PONDER
    /// @param token Token address
    /// @return hasPath Whether conversion path exists
    function _hasConversionPath(address token) internal view returns (bool) {
        if (token == PONDER) return true;
        if (token == KKUB) return true;

        if (FACTORY.getPair(token, PONDER) != address(0)) return true;
        if (FACTORY.getPair(token, KKUB) != address(0)) return true;

        return false;
    }

    /// @notice Gets optimal swap path to PONDER
    /// @param tokenIn Input token address
    /// @return path Optimal swap path
    function _getOptimalPathToPonder(address tokenIn)
        internal
        view
        returns (address[] memory path)
    {
        if (tokenIn == PONDER) {
            path = new address[](1);
            path[0] = PONDER;
            return path;
        }

        address directPair = FACTORY.getPair(tokenIn, PONDER);
        if (directPair != address(0)) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = PONDER;
            return path;
        }

        address kkubPair = FACTORY.getPair(tokenIn, KKUB);
        address ponderKkubPair = FACTORY.getPair(KKUB, PONDER);

        if (kkubPair != address(0) && ponderKkubPair != address(0)) {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = KKUB;
            path[2] = PONDER;
            return path;
        }

        path = new address[](0);
    }

    /// @notice Safe token approval handling broken implementations
    /// @param token Token address
    /// @param spender Spender address
    /// @param amount Amount to approve
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

    /// @notice Emitted when fees are collected from pairs
    event FeesCollected(address[] indexed pairs, uint256 gasUsed, uint256 timestamp);

    /// @notice Emitted when fee collection fails for a pair
    event CollectionFailed(address indexed pair, string reason);

    /// @notice Emitted when balance tracking is updated
    event BalanceUpdated(
        address indexed token, uint256 lastBalance, uint256 newBalance, uint256 delta
    );

    /// @notice Emitted when processing queue is processed
    event QueueProcessed(
        uint256 jobsProcessed, uint256 jobsFailed, uint256 gasUsed, uint256 remainingJobs
    );

    /// @notice Emitted when a job is queued
    event JobQueued(
        address indexed token,
        uint256 amount,
        uint256 priority,
        uint256 estimatedGas,
        ProcessingType jobType
    );

    /// @notice Emitted when a job is processed successfully
    event JobProcessed(address indexed token, uint256 amount, ProcessingType jobType);

    /// @notice Emitted when a job is updated
    event JobUpdated(address indexed token, uint256 newAmount, uint256 newPriority);

    /// @notice Emitted when a job is removed from queue
    event JobRemoved(address indexed token, uint256 index);

    /// @notice Emitted when a job fails and is retried
    event JobRetry(address indexed token, uint256 amount, uint256 failureCount);

    event JobAbandoned(address indexed token, uint256 amount, uint256 failureCount);
    event ProcessingFailed(address indexed token, uint256 amount, string reason);
    event LPTokenProcessed(
        address indexed lpToken, uint256 lpAmount, uint256 amount0, uint256 amount1
    );
    event EmergencyPauseActivated(uint256 timestamp, string reason);
    event EmergencyPauseDeactivated(uint256 timestamp);

    event EmergencyProcessing(address indexed token, uint256 amount, uint256 gasUsed);
    event BalanceTrackingReset(address[] tokens, uint256[] balances);
    event QueueCleared(uint256 jobsCleared);

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error EmergencyPaused();
    error NotInEmergencyMode();
    error ArrayLengthMismatch();
    error EmptyArray();
    error TooManyPairs();
    error InvalidLPToken();
    error InsufficientBalance();

    /// @notice Thrown when no conversion path exists
    error NoConversionPath();

    /// @notice Thrown when unauthorized call is made
    error UnauthorizedCall();

    /// @notice Thrown when insufficient gas is available
    error InsufficientGas();

    /// @notice Thrown when invalid index is provided
    error InvalidIndex();

    /*//////////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function access to contract owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert IFeeDistributor.NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    INTERFACE IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Converts accumulated fees from specific tokens to PONDER
    /// @param token Address of the token to convert to PONDER
    /// @dev Public wrapper for internal conversion function
    function convertFees(address token) external nonReentrant {
        if (emergencyPaused) revert EmergencyPaused();
        if (token == address(0)) revert IFeeDistributor.ZeroAddress();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert IFeeDistributor.InvalidAmount();

        if (_isLPToken(token)) {
            _processLPTokenSafe(token, balance);
        } else {
            _convertTokenToPonderSafe(token, balance);
        }

        lastProcessedBalance[token] = IERC20(token).balanceOf(address(this));
        if (pendingBalance[token] >= balance) {
            pendingBalance[token] -= balance;
        }
    }

    /// @notice Returns minimum amount required for operations
    /// @return Minimum token amount threshold (1 USD equivalent)
    function minimumAmount() external pure returns (uint256) {
        return 0;
    }
}
