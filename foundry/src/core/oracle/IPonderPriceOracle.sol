// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        PONDER ORACLE INTERFACE
    //////////////////////////////////////////////////////////////*/

/**
 * @title IPonderPriceOracle
 * @notice Interface for the Ponder Price Oracle
 * @dev Defines the external interface for price feeds and TWAP calculations
 */
interface IPonderPriceOracle {
    /*//////////////////////////////////////////////////////////////
                             PRICE QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Get time-weighted average price
    /// @dev Calculates TWAP over specified period using stored observations
    /// @param pair Address of the trading pair
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of input token
    /// @param period Time period over which to calculate TWAP
    /// @return amountOut Amount of output token based on TWAP
    function consult(
        address pair,
        address tokenIn,
        uint256 amountIn,
        uint256 period
    )
        external
        view
        returns (uint256 amountOut);

    /// @notice Get current spot price
    /// @dev Retrieves the latest price from the pair's reserves
    /// @param pair Address of the trading pair
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of input token
    /// @return amountOut Amount of output token based on spot price
    function getCurrentPrice(
        address pair,
        address tokenIn,
        uint256 amountIn
    )
        external
        view
        returns (uint256 amountOut);

    /*//////////////////////////////////////////////////////////////
                         OBSERVATION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Get historical observation data
    /// @dev Retrieves specific price observation for a pair
    /// @param pair Address of the trading pair
    /// @param index Index of the observation to retrieve
    /// @return timestamp Timestamp of the observation
    /// @return price0Cumulative Cumulative price of token0 at observation
    /// @return price1Cumulative Cumulative price of token1 at observation
    function observations(
        address pair,
        uint256 index
    )
        external
        view
        returns (uint32 timestamp, uint256 price0Cumulative, uint256 price1Cumulative);

    /// @notice Get observation count
    /// @dev Returns number of stored observations for a pair
    /// @param pair Address of the trading pair
    /// @return Number of observations stored
    function observationLength(address pair) external view returns (uint256);

    /// @notice Update price data
    /// @dev Records a new price observation for the specified pair
    /// @param pair Address of the trading pair to update
    function update(address pair) external;

    /// @notice Get last update time
    /// @dev Returns timestamp of the last observation for a pair
    /// @param pair Address of the trading pair
    /// @return Last update timestamp
    function lastUpdateTime(address pair) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          IMMUTABLE REFERENCES
    //////////////////////////////////////////////////////////////*/

    /// @notice Get factory address
    /// @dev Returns immutable factory contract address
    function factory() external view returns (address);

    /// @notice Get base token address
    /// @dev Returns immutable routing token reference
    function baseToken() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Price update event
    /// @param pair Pair being updated
    /// @param price0Cumulative New token0 price
    /// @param price1Cumulative New token1 price
    /// @param blockTimestamp Update timestamp
    event OracleUpdated(
        address indexed pair,
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint32 blockTimestamp
    );

    /// @notice Pair initialization event
    /// @param pair Pair being initialized
    /// @param timestamp Initialization time
    event PairInitialized(address indexed pair, uint32 timestamp);

    /*//////////////////////////////////////////////////////////////
                             CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invalid trading pair address
    error InvalidPair();

    /// @notice Invalid token in trading pair
    error InvalidToken();

    /// @notice Update attempted too soon
    error UpdateTooFrequent();

    /// @notice Price data has expired
    error StalePrice();

    /// @notice Not enough observations recorded
    error InsufficientData();

    /// @notice Invalid time period requested
    error InvalidPeriod();

    /// @notice Pair already initialized
    error AlreadyInitialized();

    /// @notice Pair not yet initialized
    error NotInitialized();

    /// @notice Zero address provided
    error ZeroAddress();

    /// @notice Zero time elapsed between prices
    /// @dev Prevents division by zero in TWAP
    error ElapsedTimeZero();

    /// @notice Time elapsed exceeds safety threshold
    /// @dev Prevents manipulation via long delays
    error InvalidTimeElapsed();
}
