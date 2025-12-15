// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { IPonderStaking } from "src/core/staking/IPonderStaking.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER TOKEN STORAGE
//////////////////////////////////////////////////////////////*/

/**
 * @title PonderTokenStorage
 * @notice Storage layout for Ponder protocol's token system
 * @dev Abstract contract defining state variables for token implmementation
 *      Storage stlots are carefully ordered to optimize gas costs
 *      Includes storage gap for future upgrades
 */
abstract contract PonderTokenStorage {
    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Address authorized to mint farming rewards
    /// @dev Has time-limited minting privileges
    /// @dev Can only mint until MINTING_END timestamp
    address internal _minter;

    /// @notice Address with administrative privileges
    /// @dev Can update protocol parameters and roles
    /// @dev Transferable through two-step process
    address internal _owner;

    /// @notice Address proposed in ownership transfer
    /// @dev Part of two-step ownership transfer pattern
    /// @dev Must accept ownership to become effective owner
    address internal _pendingOwner;

    /*//////////////////////////////////////////////////////////////
                        ALLOCATION ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Protocol staking contract address
    /// @dev Can only be set once via setStaking
    IPonderStaking internal _staking;

    /// @notice Special purpose launcher address
    /// @dev Has privileged access to specific operations
    /// @dev Used for initial token distribution
    address internal _launcher;

    /*//////////////////////////////////////////////////////////////
                          TOKEN ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Cumulative amount of PONDER tokens burned
    /// @dev Increases with each burn operation
    /// @dev Used for tracking total supply adjustments
    uint256 internal _totalBurned;

    /*//////////////////////////////////////////////////////////////
                            UPGRADE GAP
    //////////////////////////////////////////////////////////////*/

    /// @notice Gap for future storage variables
    /// @dev Reserved storage slots for future versions
    /// @dev Prevents storage collision in upgrades
    uint256[50] private __gap;
}
