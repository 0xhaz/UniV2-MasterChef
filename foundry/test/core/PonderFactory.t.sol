// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { PonderFactory } from "src/core/factory/PonderFactory.sol";
import { PonderFactoryTypes } from "src/core/factory/types/PonderFactoryTypes.sol";
import { PonderPair } from "src/core/pair/PonderPair.sol";
import { ERC20Mint } from "test/mocks/ERC20Mint.sol";

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
    event FeeToSetterUpdated(address indexed oldFeeToSetter, address indexed newFeeToSetter);

    function setUp() public {
        factory = new PonderFactory(feeToSetter, initialLauncher, initialPonder);
        tokenA = new ERC20Mint("Token A", "TKA");
        tokenB = new ERC20Mint("Token B", "TKB");
        tokenC = new ERC20Mint("Token C", "TKC");
    }

    function testCreatePair() public {
        address token0 = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB);
        address token1 = address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA);

        // Get pair creation bytecode
        bytes memory bytecode = type(PonderPair).creationCode;

        // Compute salt
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        // Compute the pair address using CREATE2
        address expectedPair = computeAddress(salt, keccak256(bytecode), address(factory));

        // Set up event expectation
        vm.expectEmit(true, true, true, true);
        emit PairCreated(token0, token1, expectedPair, 1);

        // Create the pair
        address pair = factory.createPair(address(tokenA), address(tokenB));

        // Verify the pair address
        assertFalse(pair == address(0), "Pair address should not be zero");
        assertEq(pair, expectedPair, "Pair address should match expected address");
        assertEq(factory.allPairsLength(), 1, "Factory should have one pair");
        assertEq(factory.allPairs(0), pair, "First pair in factory should match created pair");
        assertEq(
            factory.getPair(address(tokenA), address(tokenB)),
            pair,
            "getPair should return the correct pair address"
        );
        assertEq(
            factory.getPair(address(tokenB), address(tokenA)), pair, "getPair should be symmetric"
        );
    }

    function testCreatePairReversed() public {
        address pair1 = factory.createPair(address(tokenA), address(tokenB));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair1);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair1);
    }

    function test_CreatePair_RevertWithZeroAddress() public {
        vm.expectRevert();
        factory.createPair(address(0), address(tokenB));
    }

    function test_CreatePair_RevertWithIdenticalTokens() public {
        vm.expectRevert();
        factory.createPair(address(tokenA), address(tokenA));
    }

    function test_CreatePair_RevertWithExistingPair() public {
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert();
        factory.createPair(address(tokenA), address(tokenB));
    }

    function test_CreatePair_MultiplePairs() public {
        address pair1 = factory.createPair(address(tokenA), address(tokenB));
        address pair2 = factory.createPair(address(tokenA), address(tokenC));
        address pair3 = factory.createPair(address(tokenB), address(tokenC));

        assertEq(factory.allPairsLength(), 3, "Factory should have three pairs");
        assertEq(factory.allPairs(0), pair1, "First pair should match");
        assertEq(factory.allPairs(1), pair2, "Second pair should match");
        assertEq(factory.allPairs(2), pair3, "Third pair should match");
    }

    function test_SetFeeTo() public {
        address newFeeTo = address(0x4);

        vm.expectEmit(true, true, true, true);
        emit FeeToUpdated(factory.feeTo(), newFeeTo);

        vm.prank(feeToSetter);

        // Set feeTo
        factory.setFeeTo(newFeeTo);

        // Verify
        assertEq(factory.feeTo(), newFeeTo, "feeTo should be updated");
    }

    function test_SetFeeToSetter() public {
        address newFeeToSetter = address(0x5);

        vm.expectEmit(true, true, true, true);
        emit FeeToSetterUpdated(factory.feeToSetter(), newFeeToSetter);

        vm.prank(feeToSetter);
        // Set feeToSetter
        factory.setFeeToSetter(newFeeToSetter);

        // Verify
        assertEq(factory.feeToSetter(), newFeeToSetter, "feeToSetter should be updated");
    }

    function test_SetFeeToSetter_RevertWithUnauthorized() public {
        address newFeeToSetter = address(0x5);

        vm.prank(address(0x6));
        vm.expectRevert();
        factory.setFeeToSetter(newFeeToSetter);
    }

    function test_SetLauncher() public {
        address newLauncher = address(0x6);

        vm.startPrank(feeToSetter);

        // Expect event for setting launcher
        vm.expectEmit(true, true, false, true);
        emit LauncherUpdated(initialLauncher, newLauncher);
        factory.setLauncher(newLauncher);

        // Verify pending state
        assertEq(factory.pendingLauncher(), newLauncher, "pendingLauncher should be set");
        assertEq(factory.launcher(), initialLauncher, "launcher should remain unchanged");

        // Warp past timelock
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1);

        // Apply the launcher change
        factory.applyLauncher();

        // Verify final state
        assertEq(factory.launcher(), newLauncher, "launcher should be updated");

        vm.stopPrank();
    }

    function set_SetLauncher_RevertWithUnauthorized() public {
        address newLauncher = address(0x6);

        vm.prank(address(0x7));
        vm.expectRevert();
        factory.setLauncher(newLauncher);
    }

    function test_Launcher_Initialized() public view {
        assertEq(factory.launcher(), initialLauncher, "launcher should be initialized correctly");
    }

    function test_SetFee_EmitsEvent() public {
        address newFeeTo = address(0x8);
        vm.prank(feeToSetter);

        vm.expectEmit(true, false, true, true);
        emit FeeToUpdated(address(0), newFeeTo);

        factory.setFeeTo(newFeeTo);
        assertEq(factory.feeTo(), newFeeTo, "feeTo should be updated correctly");
    }

    function test_SetFee_MultipleTimes() public {
        address firstFeeTo = address(0x9);
        address secondFeeTo = address(0xa);

        vm.startPrank(feeToSetter);

        // First update
        vm.expectEmit(true, true, false, true);
        emit FeeToUpdated(address(0), firstFeeTo);
        factory.setFeeTo(firstFeeTo);
        assertEq(factory.feeTo(), firstFeeTo, "feeTo should be updated to firstFeeTo");

        // Second update
        vm.expectEmit(true, true, false, true);
        emit FeeToUpdated(firstFeeTo, secondFeeTo);
        factory.setFeeTo(secondFeeTo);
        assertEq(factory.feeTo(), secondFeeTo, "feeTo should be updated to secondFeeTo");

        vm.stopPrank();
    }

    function test_SetFee_RevertWithUnauthorized() public {
        address newFeeTo = address(0xb);

        vm.prank(address(0xc));
        vm.expectRevert();
        factory.setFeeTo(newFeeTo);
    }

    function test_SetLauncher_WithTimelock() public {
        address newLauncher = address(0xd);
        vm.startPrank(feeToSetter);

        // Initial set - should set pending launcher
        vm.expectEmit(true, true, false, true);
        emit LauncherUpdated(initialLauncher, newLauncher);
        factory.setLauncher(newLauncher);

        // Check pending launcher is set
        assertEq(factory.pendingLauncher(), newLauncher, "pendingLauncher should be set");
        assertEq(factory.launcher(), initialLauncher, "launcher should remain unchanged");

        // Try to apply before timelock - should revert
        vm.expectRevert();
        factory.applyLauncher();

        // Warp past timelock
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1);

        // Apply the launcher change
        vm.expectEmit(true, true, false, true);
        emit LauncherUpdated(initialLauncher, newLauncher);
        factory.applyLauncher();

        // Verify final state
        assertEq(factory.launcher(), newLauncher, "launcher should be updated");
        assertEq(factory.pendingLauncher(), address(0), "pendingLauncher should be cleared");

        vm.stopPrank();
    }

    function test_SetLauncher_RevertWithZeroAddress() public {
        vm.prank(feeToSetter);
        vm.expectRevert();
        factory.setLauncher(address(0));
    }

    function test_ApplyLauncher_RevertBeforeTimelock() public {
        address newLauncher = address(0xe);
        vm.startPrank(feeToSetter);

        // Set new launcher
        factory.setLauncher(newLauncher);

        // Get current time
        uint256 currentTime = block.timestamp;

        // Try to apply before timelock
        vm.warp(currentTime + PonderFactoryTypes.LAUNCHER_TIMELOCK - 1);

        // Try to apply before timelock
        vm.expectRevert();
        factory.applyLauncher();

        vm.stopPrank();
    }

    function test_SetLauncher_WhilePending() public {
        address firstLauncher = address(0xf);
        address secondLauncher = address(0x10);

        vm.startPrank(feeToSetter);

        // Set first launcher
        factory.setLauncher(firstLauncher);

        // Set second launcher before applying the first
        factory.setLauncher(secondLauncher);

        // Verify second launcher is pending
        assertEq(
            factory.pendingLauncher(), secondLauncher, "pendingLauncher should be secondLauncher"
        );

        vm.stopPrank();
    }

    function test_TimelockExpiry() public {
        address newLauncher = address(0x11);
        vm.startPrank(feeToSetter);

        // Set new launcher
        factory.setLauncher(newLauncher);

        // Warp way past timelock
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1 weeks);

        // Should still be able to apply
        factory.applyLauncher();

        assertEq(factory.launcher(), newLauncher, "launcher should be updated");

        vm.stopPrank();
    }

    function test_MultipleSetLauncher() public {
        address firstLauncher = address(0x12);
        address secondLauncher = address(0x13);

        vm.startPrank(feeToSetter);

        // Set first launcher
        factory.setLauncher(firstLauncher);

        // Warp past timelock
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1);

        // Apply first launcher
        factory.applyLauncher();

        assertEq(factory.launcher(), firstLauncher, "launcher should be firstLauncher");

        // Set second launcher
        factory.setLauncher(secondLauncher);

        // Warp past timelock
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1);

        // Apply second launcher
        factory.applyLauncher();

        assertEq(factory.launcher(), secondLauncher, "launcher should be secondLauncher");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    function computeAddress(
        bytes32 salt,
        bytes32 codeHash,
        address deployer
    )
        internal
        pure
        returns (address)
    {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, codeHash))))
        );
    }
}
