// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        PONDER FACTORY INTERFACE
    //////////////////////////////////////////////////////////////*/

/**
 * @title IPonderFactory
 * @notice Interface for managing Ponder protocol's trading pair lifecycle
 * @dev Defines core functionality for pair creation and protocol configuration
 */
interface IPonderFactory {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new trading pair is created
    /// @dev Includes sorted token addresses and pair indexing information
    /// @param token0 Address of the first token in the pair (lower address value)
    /// @param token1 Address of the second token in the pair (higher address value)
    /// @param pair Address of the newly created trading pair contract
    /// @param pairIndex Sequential index of the pair in allPairs array
    event PairCreated(
        address indexed token0, address indexed token1, address pair, uint256 pairIndex
    );

    /// @notice Emitted when protocol fee recipient is changed
    /// @dev Tracks changes in fee collection address
    /// @param oldFeeTo Previous address receiving protocol fees
    /// @param newFeeTo New address set to receive protocol fees
    event FeeToUpdated(address indexed oldFeeTo, address indexed newFeeTo);

    /// @notice Emitted when protocol launcher address is updated
    /// @dev Tracks changes in pair deployment permissions
    /// @param oldLauncher Previous launcher address
    /// @param newLauncher New launcher address
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);

    /// @notice Emitted when the fee configuration admin is changed
    /// @dev Tracks changes in fee management permissions
    /// @param oldFeeToSetter Previous fee configuration admin address
    /// @param newFeeToSetter New fee configuration admin address
    event FeeToSetterUpdated(address indexed oldFeeToSetter, address indexed newFeeToSetter);

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns current fee management admin
    /// @dev This address can update fee-related parameters
    /// @return Address with fee configuration permissions
    function feeToSetter() external view returns (address);

    /// @notice Returns current protocol fee recipient
    /// @dev This address receives collected protocol fees
    /// @return Address receiving protocol fees
    function feeTo() external view returns (address);

    /// @notice Returns current protocol launcher
    /// @dev Address authorized to deploy new pairs
    /// @return Address of the launcher contract
    function launcher() external view returns (address);

    /// @notice Returns protocol governance token
    /// @dev Core token of the Ponder protocol
    /// @return Address of the PONDER token contract
    function ponder() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            PAIR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates new trading pair for provided tokens
    /// @dev Deploys pair contract using CREATE2 for deterministic address
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return pair Address of the newly created trading pair
    function createPair(address tokenA, address tokenB) external returns (address pair);

    /// @notice Retrieves pair address for given tokens
    /// @dev Returns zero address if pair does not exist
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return pair Address of the trading pair contract
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    /*//////////////////////////////////////////////////////////////
                          ADMIN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates protocol fee recipient
    /// @dev Restricted to feeToSetter
    /// @param newFeeTo New fee collection address
    function setFeeTo(address newFeeTo) external;

    /// @notice Updates fee management admin
    /// @dev Restricted to current feeToSetter
    /// @param newFeeToSetter New fee configuration admin address
    function setFeeToSetter(address newFeeToSetter) external;

    /// @notice Initiates launcher update process
    /// @dev Starts timelock period for launcher change
    /// @param newLauncher Proposed new launcher address
    function setLauncher(address newLauncher) external;

    /// @notice Completes launcher update after timelock
    /// @dev Can only execute after timelock expires
    function applyLauncher() external;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error thrown when attempting to create a pair with same token twice
    /// @dev Prevents invalid pair creation with identical addresses
    error IdenticalAddresses();

    /// @notice Error thrown when a required address parameter is zero
    /// @dev Basic validation for address inputs
    error ZeroAddress();

    /// @notice Error thrown when attempting to create an already existing pair
    /// @dev Prevents duplicate pair creation
    error PairExists();

    /// @notice Error thrown when caller lacks required permissions
    /// @dev Access control for restricted functions
    error Forbidden();

    /// @notice Error thrown when setting an invalid fee receiver
    /// @dev Validates fee receiver address updates
    error InvalidFeeReceiver();

    /// @notice Error thrown when setting an invalid launcher address
    /// @dev Validates launcher address updates
    error InvalidLauncher();

    /// @notice Error thrown when attempting launcher update before timelock expires
    /// @dev Enforces timelock delay for launcher updates
    error TimeLocked();
}
