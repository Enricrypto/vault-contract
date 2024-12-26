// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ERC20} from "../src/ERC20.sol";

contract Token is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 totalSupply
    ) ERC20(name, symbol, decimals, totalSupply) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(amount);
    }
}

contract TokenScript is Script {
    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // address that I'm using to deploy my contract on mainnet
        address account = vm.addr(deployerPrivateKey);
        console.log("account:", account);

        // Fetch ETH_RPC_URL from environment variables
        string memory ethRpcUrl = vm.envString("ETH_RPC_URL");
        console.log("Using RPC URL:", ethRpcUrl);

        vm.startBroadcast(deployerPrivateKey);
        // deploy Token
        Token token = new Token(
            "Test Foundry",
            "TEST",
            18,
            1_000_000 * 10 ** 18
        );
        //  mint tokens
        token.mint(account, 300);
        vm.stopBroadcast();
    }
}
