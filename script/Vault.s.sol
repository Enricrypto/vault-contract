// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract MyScript is Script {
    event Loguint(uint);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        // MockERC20 mockERC20 = new MockERC20("SDToken", "SD");
        emit Loguint(deployerPrivateKey);
        vm.stopBroadcast();
    }
}
