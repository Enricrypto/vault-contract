// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Vault.sol"; // Path to your Vault contract
import "lib/aave-v3-core/contracts/interfaces/IPool.sol"; // Aave's Pool Interface
import "lib/aave-v3-core/contracts/dependencies/weth/WETH9.sol"; // WETH Interface

contract VaultTest is Test {
    Vault public vault;
    WETH9 public weth;
    IPool public aavePool;
    address public user;

    // set up the test environment
    function setUp() public {
        // set the block number for the fork
        uint256 forkId = vm.createFork(
            "https://mainnet.infura.io/v3/080ce310be6f452bacc7868005900063",
            17300000
        );
        vm.selectFork(forkId); // Activate the fork

        address payable _wethAddress = payable(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        ); // WETH Mainnet address
        address _poolAddress = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // Aave Pool Mainnet

        // initialize the vault contract
        vault = new Vault(_poolAddress, _wethAddress);

        // Check if the deployment was successful
        require(address(vault) != address(0), "Vault deployment failed");

        // assign user
        user = address(0x1234); // example user address

        // fund user with ETH
        vm.deal(user, 100 ether);
    }

    // test the deposit functionality

    function testDeposit() public {
        // user's initial WETh balance should be 0
        uint256 initialWethBalance = weth.balanceOf(user);
        assertEq(initialWethBalance, 0);

        vm.startPrank(user); // Start simulating the user

        // Send Ether to the Vault contract (triggers receive function)
        (bool success, ) = (address(vault)).call{value: 10 ether}(""); // Sending Ether to the Vault contract
        require(success, "Failed to send Ether to the Vault");

        vm.stopPrank();

        // check if WETH was deposited into Aave
        uint256 wethBalanceInAave = weth.balanceOf(address(vault));
        assertEq(
            wethBalanceInAave,
            10 ether,
            "WETH balance in vault should be 10 ether"
        );

        //check if shares were correctly minted for the specific user
        uint256 userShares = vault.balanceOf(user);
        assertGt(userShares, 0, "User did not receive shares after deposit"); // Gt asserts that one value is greater than the other
    }
}
