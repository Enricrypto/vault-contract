// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "../src/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals, uint256 totalSupply)
        ERC20(name, symbol, decimals, totalSupply)
    {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(amount);
    }
}
