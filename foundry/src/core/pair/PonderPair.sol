// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { PonderKAP20 } from "src/core/token/PonderKAP20.sol";
import { IPonderPair } from "src/core/pair/IPonderPair.sol";
import { PonderFeesLib } from "src/core/pair/libraries/PonderFeesLib.sol";
import { PonderPairStorage } from "src/core/pair/storage/PonderPairStorage.sol";
import { PonderPairTypes } from "src/core/pair/types/PonderPairTypes.sol";
import { IPonderFactory } from "src/core/factory/IPonderFactory.sol";
import { IPonderCallee } from "src/core/pair/IPonderCallee.sol";
import { Math } from "src/core/libraries/Math.sol";
import { UQ112x112 } from "src/core/libraries/UQ112x112.sol";

/*//////////////////////////////////////////////////////////////
                            PONDER PAIR CORE
    //////////////////////////////////////////////////////////////*/

/**
 * @title PonderPair
 * @notice Core AMM implementation for Ponder protocol
 * @dev Manages liquidity provision, swaps and fee collection
 * @dev Implements constant product formula (x * y = k) with fees
 */
contract PonderPair is
    IPonderPair,
    PonderPairStorage,
    PonderKAP20("Ponder LP", "PONDER-LP"),
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using UQ112x112 for uint224;
    using PonderPairTypes for PonderPairTypes.SwapData;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Factory contract that deployed this pair
    /// @dev Set during construction, cannot be changed
    address internal immutable _FACTORY;

    /// @notice Sets up pair with factory reference
    /// @dev Called once during contract deployment
    constructor() {
        _FACTORY = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fetches minimum liquidity requirement
    /// @dev Amount burned during first mint to prevent pool drain
    /// @return Minimum liquidity amount threshold as uint256
    function minimumLiquidity() external pure returns (uint256) {
        return PonderPairTypes.MINIMUM_LIQUIDITY;
    }
}
