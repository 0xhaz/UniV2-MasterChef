// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { PonderFactory } from "src/core/factory/PonderFactory.sol";
import { PonderFactoryTypes } from "src/core/factory/types/PonderFactoryTypes.sol";
import { ERC20Mint } from "mocks/ERC20Mint.sol";

contract PonderFactoryTest is Test {
    PonderFactory factory;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    ERC20Mint tokenC;
    address feeToSetter = address(0x1);
    address initialLauncher = address(0x2);
    address initialPonder = address(0x3);

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);
    event FeeToUpdated(address indexed oldFeeTo, address indexed newFeeTo);

    function setUp() public {
        factory = new PonderFactory(feeToSetter, initialLauncher, initialPonder);
        tokenA = new ERC20Mint("Token A", "TKA");
        tokenB = new ERC20Mint("Token B", "TKB");
        tokenC = new ERC20Mint("Token C", "TKC");
    }
}
