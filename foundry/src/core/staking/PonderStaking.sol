// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { IPonderStaking } from "./IPonderStaking.sol";
import { IPonderToken } from "../token/IPonderToken.sol";
import { PonderStakingStorage } from "./storage/PonderStakingStorage.sol";
import { PonderStakingTypes } from "./types/PonderStakingTypes.sol";
import { PonderKAP20 } from "../token/PonderKAP20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";

/*//////////////////////////////////////////////////////////////
                      PONDER STAKING CONTRACT
//////////////////////////////////////////////////////////////*/

/**
 * @title PonderStaking
 * @notice Implementation of Ponder protocol's staking mechanism
 * @dev Handles staking of PONDER tokens for xPONDER shares
 *      Implements rebase mechanism to distribute protocol fees
 *      Inherits storage layout and ERC20 functionality
 */
contract PonderStaking is IPonderStaking, PonderStakingStorage, PonderKAP20("Staked KOI", "xKOI") {
    using PonderStakingTypes for *;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                         IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice PONDER token contract reference
    IERC20 public immutable PONDER;

    /// @notice Protocol router for performing swaps
    IPonderRouter public immutable ROUTER;

    /// @notice Protocol factory for pair and token management
    IPonderFactory public immutable FACTORY;
    function enter(uint256 amount, address recipient) external override returns (uint256 shares) { }

    function leave(uint256 shares) external override returns (uint256 amount) { }

    function claimFees() external override returns (uint256 amount) { }

    function rebase() external override { }

    function getPendingFees(address user) external view override returns (uint256) { }

    function getAccumulatedFeesPerShare() external view override returns (uint256) { }

    function getPonderAmount(uint256 shares) external view override returns (uint256) { }

    function getSharesAmount(uint256 amount) external view override returns (uint256) { }

    function minimumFirstStake() external view override returns (uint256) { }

    function transferOwnership(address newOwner) public override (IPonderStaking, PonderKAP20) { }

    function acceptOwnership() external override { }
}
