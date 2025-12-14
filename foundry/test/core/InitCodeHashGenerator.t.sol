// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { PonderPair } from "src/core/pair/PonderPair.sol";

contract InitCodeHashGenerator is Test {
    function testGenerateInitCodeHash() public pure {
        bytes memory bytecode = type(PonderPair).creationCode;
        bytes32 initCodeHash = keccak256(bytecode);
        console.logBytes32(initCodeHash);
    }
}
