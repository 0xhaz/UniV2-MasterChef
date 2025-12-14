// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { PonderKAP20 } from "src/core/token/PonderKAP20.sol";

contract ERC20Mint is PonderKAP20 {
    constructor(string memory _name, string memory _symbol) PonderKAP20(_name, _symbol) { }

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    function burn(address from, uint256 value) external {
        _burn(from, value);
    }
}
