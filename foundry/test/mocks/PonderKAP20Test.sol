// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import { PonderKAP20 } from "src/core/token/PonderKAP20.sol";

contract TestPonderKAP20 is PonderKAP20 {
    constructor() PonderKAP20("Ponder LP Token", "PONDER-LP") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
