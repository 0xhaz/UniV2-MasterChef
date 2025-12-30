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

    /// @notice Initializes the staking contract
    /// @param _ponder Address of the PONDER token contract
    /// @param _router Address of the PonderRouter contract
    /// @param _factory Address of the PonderFactory contract
    constructor(address _ponder, address _router, address _factory) {
        if (_ponder == address(0) || _router == address(0) || _factory == address(0)) {
            revert PonderKAP20.ZeroAddress();
        }
        PONDER = IERC20(_ponder);
        ROUTER = IPonderRouter(_router);
        FACTORY = IPonderFactory(_factory);
        stakingOwner = msg.sender;
        lastRebaseTime = block.timestamp;
        DEPLOYMENT_TIME = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                       STAKING OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stakes PONDER tokens for xPONDER shares
    /// @param amount Amount of PONDER tokens to stake
    /// @param recipient Address to receive the xPONDER shares
    /// @return shares Amount of xPONDER shares minted to recipient
    function enter(uint256 amount, address recipient) external returns (uint256 shares) {
        if (amount == 0) revert IPonderStaking.InvalidAmount();
        if (recipient == address(0)) revert PonderKAP20.ZeroAddress();

        uint256 totalPonder = PONDER.balanceOf(address(this));
        uint256 totalShares = totalSupply();

        // Calculate shares and initialize fee debt
        if (totalShares == 0) {
            if (amount < PonderStakingTypes.MINIMUM_FIRST_STAKE) {
                revert IPonderStaking.InsufficientFirstStake();
            }
            shares = amount;
        } else {
            // Maintain precision by checking which order of operation is safe
            uint256 scaledAmount = amount * PonderStakingTypes.FEE_PRECISION;
            if (scaledAmount / PonderStakingTypes.FEE_PRECISION != amount) {
                // If scaling would overflow, fall back to original calculation
                shares = (amount * totalShares) / totalPonder;
            } else {
                // Scale up, multiply, then scale down for more precision
                shares =
                    (scaledAmount * totalShares) / (totalPonder * PonderStakingTypes.FEE_PRECISION);
            }
        }

        // Calculate fee debt - use same scaling approach for consistency
        uint256 scaledShares = shares * PonderStakingTypes.FEE_PRECISION;
        if (scaledShares / PonderStakingTypes.FEE_PRECISION != shares) {
            // If scaling would overflow, fall back to original calculation
            userFeeDebt[recipient] =
                (shares * accumulatedFeesPerShare) / PonderStakingTypes.FEE_PRECISION;
        } else {
            // Scale up for precision, then scale down
            userFeeDebt[recipient] = (scaledShares * accumulatedFeesPerShare)
                / (PonderStakingTypes.FEE_PRECISION * PonderStakingTypes.FEE_PRECISION);
        }

        _mint(recipient, shares);
        totalDepositedPonder += amount;

        PONDER.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(recipient, amount, shares);
    }

    /// @notice Withdraws PONDER by burning xPONDER shares
    /// @param shares Amount of xPONDER shares to burn
    /// @return amount Amount of PONDER tokens withdrawn
    function leave(uint256 shares) external returns (uint256 amount) {
        if (msg.sender == IPonderToken(address(PONDER)).teamReserve()) {
            // This check enforces team token lockup period which is intentionally using
            // block.timestamp The TEAM_LOCK_DURATION is a long-term duration (days/month) making
            // this resistant to manipulation
            // slither-disable-next-line timestamp
            if (block.timestamp < DEPLOYMENT_TIME + PonderStakingTypes.TEAM_LOCK_DURATION) {
                revert IPonderStaking.TeamStakingLocked();
            }
        }

        if (shares == 0) revert IPonderStaking.InvalidAmount();
        if (shares > balanceOf(msg.sender)) revert IPonderStaking.InvalidSharesAmount();

        uint256 totalShares = totalSupply();
        amount = (shares * PONDER.balanceOf(address(this))) / totalShares;

        if (amount < PonderStakingTypes.MINIMUM_WITHDRAW) {
            revert IPonderStaking.MinimumSharesRequired();
        }

        uint256 pendingFees = _getPendingFees(msg.sender, shares);

        userFeeDebt[msg.sender] = ((balanceOf(msg.sender) - shares) * accumulatedFeesPerShare)
            / PonderStakingTypes.FEE_PRECISION;

        _burn(msg.sender, shares);

        totalDepositedPonder -= amount;
        if (pendingFees > 0) {
            totalUnclaimedFees -= pendingFees;
        }

        emit Withdrawn(msg.sender, amount, shares);
        if (pendingFees > 0) {
            emit FeesClaimed(msg.sender, pendingFees);
        }

        PONDER.safeTransfer(msg.sender, amount);
        if (pendingFees > 0) {
            PONDER.safeTransfer(msg.sender, pendingFees);
        }
    }

    function claimFees() external override returns (uint256 amount) { }

    function rebase() external override { }

    function getPendingFees(address user) external view override returns (uint256) { }

    function getAccumulatedFeesPerShare() external view override returns (uint256) { }

    function getPonderAmount(uint256 shares) external view override returns (uint256) { }

    function getSharesAmount(uint256 amount) external view override returns (uint256) { }

    function minimumFirstStake() external view override returns (uint256) { }

    function transferOwnership(address newOwner) public override (IPonderStaking, PonderKAP20) { }

    function acceptOwnership() external override { }

    function _getPendingFees(
        address user,
        uint256 sharesToWithdraw
    )
        internal
        view
        returns (uint256)
    {
        uint256 userShares = balanceOf(user);
        uint256 scaledShares = userShares * PonderStakingTypes.FEE_PRECISION;
        uint256 accumulatedFees =
            (scaledShares * accumulatedFeesPerShare) / PonderStakingTypes.FEE_PRECISION;
        uint256 userDebt = userFeeDebt[user];

        uint256 pendingFees;
        if (accumulatedFees > userDebt) {
            pendingFees = accumulatedFees - userDebt;

            // Adjust pending fees if withdrawing only a portion of shares
            if (sharesToWithdraw < userShares) {
                pendingFees = (pendingFees * sharesToWithdraw * PonderStakingTypes.FEE_PRECISION)
                    / scaledShares;
            }
        }
        return pendingFees;
    }
}
