// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { TestPonderKAP20 } from "test/mocks/PonderKAP20Test.sol";

contract PonderKAP20Test is Test {
    TestPonderKAP20 token;
    address alice = address(0x1);
    address bob = address(0x2);
    uint256 constant INITIAL_SUPPLY = 1000e18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new TestPonderKAP20();
    }

    function test_Metadata() public view {
        assertEq(token.name(), "Ponder LP Token");
        assertEq(token.symbol(), "PONDER-LP");
        assertEq(token.decimals(), 18);
    }

    function test_MintAndBurn() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, INITIAL_SUPPLY);
        token.mint(alice, INITIAL_SUPPLY);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), INITIAL_SUPPLY);
        token.burn(alice, INITIAL_SUPPLY);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_Approve() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 100);
        assertTrue(token.approve(bob, 100));
        assertEq(token.allowance(alice, bob), 100);
    }

    function test_Transfer() public {
        token.mint(alice, INITIAL_SUPPLY);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 200);
        assertTrue(token.transfer(bob, 200));
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 200);
        assertEq(token.balanceOf(bob), 200);
    }

    function test_TransferFrom() public {
        token.mint(alice, INITIAL_SUPPLY);

        vm.prank(alice);
        token.approve(bob, 100);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 50);
        assertTrue(token.transferFrom(alice, bob, 50));
        assertEq(token.allowance(alice, bob), 50);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 50);
        assertEq(token.balanceOf(bob), 50);
    }

    function test_Permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.domainSeparator(),
                    keccak256(
                        abi.encode(token.PERMIT_TYPEHASH(), owner, bob, 100, 0, block.timestamp)
                    )
                )
            )
        );

        token.permit(owner, bob, 100, block.timestamp, v, r, s);
        assertEq(token.allowance(owner, bob), 100);
        assertEq(token.nonces(owner), 1);
    }

    function test_Transfer_RevertInsufficientBalance() public {
        token.mint(alice, INITIAL_SUPPLY);
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, INITIAL_SUPPLY + 1);
    }

    function test_Transfer_RevertWithInsufficientAllowance() public {
        token.mint(alice, INITIAL_SUPPLY);
        vm.prank(alice);
        token.approve(bob, 100);
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, bob, 200);
    }

    function test_Permit_RevertWithExpiredDeadline() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.domainSeparator(),
                    keccak256(
                        abi.encode(token.PERMIT_TYPEHASH(), owner, bob, 100, 0, block.timestamp - 1)
                    )
                )
            )
        );

        vm.expectRevert();
        token.permit(owner, bob, 100, block.timestamp - 1, v, r, s);
    }

    function test_Mint_RevertToZeroAddress() public {
        vm.expectRevert();
        token.mint(address(0), INITIAL_SUPPLY);
    }

    function test_Burn_RevertFromZeroAddress() public {
        vm.expectRevert();
        token.burn(address(0), INITIAL_SUPPLY);
    }
}
