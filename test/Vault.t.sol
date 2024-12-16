// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.10;

// Import test utilities and required interfaces
import {Test, console} from "lib/forge-std/src/Test.sol";
import "../src/Vault.sol";

contract Tester is Test {
    // Declare Vault instance
    Vault public vault;
    // === User and receiver address for testing ===
    address public user = 0xBB343290A619b43D73Bd78C9fda8E10c4BE678Cc;
    address public ethxUser = 0x8D125F00DFf639617F7475a881A3a3b3a082A746;
    address public receiver = 0xBf7870e2a52D417D91Dc3Eaf37A95Fa55d1a5277;
    // === Declare token interfaces ===
    IERC20 public ethxToken; // ETHx token interface
    IERC20 public sdToken; // Stader token interface
    IERC20 public aethxToken; // Aethx token interface
    IERC20 public usdcToken; // USDC token interface
    IWETH public wethToken; // WETH token interface
    IStaderStakePoolManager public stakePoolManager;
    IPoolAddressesProvider public poolAddressesProvider;
    IPool public pool;
    IRewardsController public rewardsController;
    ISwapRouter public swapRouter;

    // Constants for addresses
    address constant _STADER_STAKE_POOL_ADDRESS = 0xcf5EA1b38380f6aF39068375516Daf40Ed70D299;
    address constant _POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant _SWAP_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant _WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant _STADER_CONFIG_ADDRESS = 0x4ABEF2263d5A5ED582FC9A9789a41D85b68d69DB;
    address constant _REWARDS_CONTROLLER_ADDRESS = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address constant _AETHX_TOKEN_ADDRESS = 0x1c0E06a0b1A4c160c17545FF2A951bfcA57C0002;
    address constant _USDC_TOKEN_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Add name and symbol for ERC20 token
    string constant _VAULT_NAME = "Stader Vault";
    string constant _VAULT_SYMBOL = "sETHx";

    /// @notice Setup the test environment
    function setUp() public {
        // Fork the Ethereum mainnet at the latest block
        vm.createSelectFork("mainnet");

        // Deploy the Vault contract
        vault = new Vault(
            _STADER_STAKE_POOL_ADDRESS, // _stakePoolAddress
            _POOL_ADDRESSES_PROVIDER, // _poolAddressesProvider
            _SWAP_ROUTER_ADDRESS, // _swapRouterAddress
            _WETH_ADDRESS, // _wethAddress
            _USDC_TOKEN_ADDRESS, // _USDCAddress
            _STADER_CONFIG_ADDRESS, // _staderConfigAddress
            _REWARDS_CONTROLLER_ADDRESS, // _rewardsControllerAddress
            _AETHX_TOKEN_ADDRESS,
            _VAULT_NAME, // _name (ERC20 token name, AKA vault shares)
            _VAULT_SYMBOL // _symbol (ERC20 token symbol)
        );

        // Declare and initialize token interfaces from the Vault contract
        ethxToken = IERC20(vault.ethxToken()); // Initialize the ETHx token interface from vault
        sdToken = IERC20(vault.sdToken()); // Initialize the SD token interface from vault
        aethxToken = IERC20(vault.aethxToken()); // Initialize the aETHx token interface from vault
        usdcToken = IERC20(vault.usdcToken()); // Initialize the USDC token interface from vault
        wethToken = IWETH(vault.wethToken()); // Initialize the WETH token interface from vault
        // Instantiate the stakePoolManager interface
        stakePoolManager = IStaderStakePoolManager(_STADER_STAKE_POOL_ADDRESS);
        // Initialize PoolAddressesProvider and Pool
        poolAddressesProvider = IPoolAddressesProvider(_POOL_ADDRESSES_PROVIDER);
        // Initialize the pool with the PoolAddressesProvider
        pool = IPool(poolAddressesProvider.getPool());
        // Initialize Uniswap Router using the ISwapRouter interface casting
        swapRouter = ISwapRouter(_SWAP_ROUTER_ADDRESS);
    }

    function testConstructorInitialization() public view {
        // Verify that the vault administrator is the deployer (msg.sender)
        assertEq(vault.vaultAdministrator(), address(this), "Vault administrator is incorrect");

        // Verify that the stake pool manager address is set correctly
        assertEq(
            address(vault.stakePoolManager()), _STADER_STAKE_POOL_ADDRESS, "Stake Pool Manager address is incorrect"
        );

        // Verify that the PoolAddressesProvider is set correctly
        assertEq(
            address(vault.poolAddressesProvider()),
            _POOL_ADDRESSES_PROVIDER,
            "PoolAddressesProvider address is incorrect"
        );

        // Verify that the Uniswap SwapRouter address is set correctly
        assertEq(address(vault.swapRouter()), _SWAP_ROUTER_ADDRESS, "Uniswap SwapRouter address is incorrect");

        // Verify that the WETH address is set correctly
        assertEq(address(vault.wethToken()), _WETH_ADDRESS, "WETH address is incorrect");

        // Verify that the StaderConfig address is set correctly
        assertEq(address(vault.staderConfig()), _STADER_CONFIG_ADDRESS, "StaderConfig address is incorrect");

        // Verify that the ETHx token is correctly fetched from StaderConfig
        assertEq(
            address(vault.ethxToken()),
            IStaderConfig(_STADER_CONFIG_ADDRESS).getETHxToken(),
            "ETHx token address is incorrect"
        );

        // Verify that the SD token is correctly fetched from StaderConfig
        assertEq(
            address(vault.sdToken()),
            IStaderConfig(_STADER_CONFIG_ADDRESS).getStaderToken(),
            "SD token address is incorrect"
        );

        // Verify that the UserWithdrawalManager address is correctly fetched
        assertEq(
            address(vault.userWithdrawManager()),
            IStaderConfig(_STADER_CONFIG_ADDRESS).getUserWithdrawManager(),
            "UserWithdrawalManager address is incorrect"
        );

        // Verify that the RewardsController address is set correctly
        assertEq(
            address(vault.rewardsController()), _REWARDS_CONTROLLER_ADDRESS, "RewardsController address is incorrect"
        );

        // Verify that the aETHx token address is set correctly
        assertEq(address(vault.aethxToken()), _AETHX_TOKEN_ADDRESS, "aETHx token address is incorrect");

        // Verify that the vault shares name and symbol are set correctly
        assertEq(vault.name(), _VAULT_NAME, "Vault name is incorrect");
        assertEq(vault.symbol(), _VAULT_SYMBOL, "Vault symbol is incorrect");

        // Verify that ETHx token approval for the Aave pool is set to max
        assertEq(
            vault.ethxToken().allowance(address(vault), address(pool)),
            type(uint256).max,
            "ETHx token allowance for Aave pool is incorrect"
        );

        // Verify that ETHx token approval for the UserWithdrawalManager is set to max
        assertEq(
            vault.ethxToken().allowance(address(vault), address(vault.userWithdrawManager())),
            type(uint256).max,
            "ETHx token allowance for UserWithdrawalManager is incorrect"
        );
    }

    /// @notice Test depositing ETH and interacting with Aave
    function testDepositETH() public {
        uint256 depositAmount = 1 ether; // Define the deposit amount

        // Fund the user with ETH for testing
        vm.deal(user, depositAmount);

        // Check initial ETH balance for the user
        uint256 initialUserETHBalance = user.balance;
        assertEq(initialUserETHBalance, depositAmount, "User's ETH balance should match the deposit amount");

        // Check initial Vault ETHx balance (should be zero)
        uint256 initialVaultEthxBalance = ethxToken.balanceOf(address(vault));
        assertEq(initialVaultEthxBalance, 0, "Vault's initial ETHx balance should be zero");

        // Check initial user Vault shares (should be zero)
        uint256 initialUserShares = vault.balanceOf(user);
        assertEq(initialUserShares, 0, "User's initial Vault shares balance should be zero");

        vm.startPrank(user);
        vault.depositETH{value: depositAmount}(user);
        vm.stopPrank();

        assertEq(user.balance, 0, "User ETH balance should be 0");

        uint256 afterUserShares = vault.balanceOf(user);

        assertGt(afterUserShares, initialUserShares, "User initial shares should increase after deposit");

        uint256 updatedVaultAethxBalance = aethxToken.balanceOf(address(vault));

        assertGt(updatedVaultAethxBalance, 0, "Balance of aethx in vault should be greater than 0");
    }

    function testDeposit() public {
        uint256 depositAmount = 10 ether; // amount of ETHx to deposit

        // Check the user's initial ETHx balance
        uint256 initialUserEthxBalance = ethxToken.balanceOf(user);
        require(initialUserEthxBalance >= depositAmount, "User does not have enough ETHx tokens");

        // Check initial Vault balance
        uint256 initialVaultAethxBalance = aethxToken.balanceOf(address(vault));
        assertEq(initialVaultAethxBalance, 0, "Vault's initial aETHx balance should be zero");

        // Check initial user Vault shares (should be zero)
        uint256 initialUserShares = vault.balanceOf(user);
        assertEq(initialUserShares, 0, "User's initial Vault shares balance should be zero");

        // Approve the Vault to transfer ETHx tokens on behalf of the user
        vm.startPrank(user);
        ethxToken.approve(address(vault), depositAmount);

        // Deposit ETHx into the Vault
        uint256 sharesMinted = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Ensure the user no longer has the deposited ETHx
        uint256 updatedUserEthxBalance = ethxToken.balanceOf(user);
        assertEq(
            updatedUserEthxBalance,
            initialUserEthxBalance - depositAmount,
            "User's ETHx balance should decrease by the deposit amount"
        );

        // Check that the user received Vault shares
        uint256 updatedUserShares = vault.balanceOf(user);
        assertEq(updatedUserShares, sharesMinted, "User's Vault shares should match the minted shares");

        // Check that the Vault's aETHx balance has increased
        uint256 updatedVaultAethxBalance = aethxToken.balanceOf(address(vault));
        assertGt(updatedVaultAethxBalance, 0, "Vault's aETHx balance should be greater than 0 after deposit");

        // Check that the Vault's ETHx balance is zero (all staked in Aave)
        uint256 updatedVaultEthxBalance = ethxToken.balanceOf(address(vault));
        assertEq(updatedVaultEthxBalance, 0, "Vault's ETHx balance should be zero after staking in Aave");
    }

    function testWithdraw() public {
        uint256 depositAmount = 100 ether; // Amount of ETHx to deposit
        uint256 withdrawAmount = 50 ether; // Amount of ETHx to withdraw

        // Check initial balances for user and vault
        uint256 initialUserEthxBalance = ethxToken.balanceOf(user);
        uint256 initialReceiverEthxBalance = ethxToken.balanceOf(receiver);
        // Check initial amount of shares minted by the vault
        uint256 initialVaultShares = vault.totalSupply();
        // Check initial total assets inside the vault before deposit
        uint256 totalAssetsBefore = vault.totalAssets();

        // Check initial vault shares (should be zero before deposit)
        assertEq(initialVaultShares, 0, "Vault's initial shares should be zero");

        // 1. First, deposit ETHx tokens to get shares
        vm.startPrank(user);
        // Approve the Vault to transfer ETHx tokens on behalf of the user
        ethxToken.approve(address(vault), depositAmount);

        // Deposit ETHx tokens into the vault
        uint256 sharesMinted = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Ensure the user no longer has the deposited ETHx
        uint256 updatedUserEthxBalance = ethxToken.balanceOf(user);
        assertEq(
            updatedUserEthxBalance,
            initialUserEthxBalance - depositAmount,
            "User's ETHx balance should decrease by the deposit amount"
        );

        // Check that the user received Vault shares
        uint256 updatedUserShares = vault.balanceOf(user);
        assertEq(updatedUserShares, sharesMinted, "User's Vault shares should match the minted shares");

        // Check total assets in vault after deposit
        uint256 totalAssetsAfter = vault.totalAssets();
        assertEq(
            totalAssetsAfter, totalAssetsBefore + depositAmount, "Total assets should increase by the deposited amount"
        );

        // Update the total supply of shares minted by the vault after deposit
        uint256 updatedVaultShares = vault.totalSupply();

        // 2. Now, proceed to withdraw ETHx from the vault
        vm.startPrank(user);

        // Withdraw ETHx (this will burn shares and transfer ETHx back to the receiver)
        uint256 burnedShares = vault.withdraw(withdrawAmount, receiver, user);

        vm.stopPrank();

        // 3. Assertions after withdrawal
        // Check that the receiver received the correct amount of ETHx back
        uint256 receiverEthxAfter = ethxToken.balanceOf(receiver);
        assertEq(
            receiverEthxAfter,
            initialReceiverEthxBalance + withdrawAmount,
            "Receiver should receive back the correct amount of ETHx"
        );

        // Check total assets in vault after withdrawal
        uint256 totalAssetsPostWithdrawal = vault.totalAssets();
        assertApproxEqAbs(
            totalAssetsPostWithdrawal,
            totalAssetsAfter - withdrawAmount,
            1,
            "Total assets should decrease by the withdrawn amount"
        );

        // Check that the amount of shares in the vault has been reduced by the burned amount
        uint256 vaultSharesAfterWithdrawal = vault.totalSupply();
        assertEq(
            vaultSharesAfterWithdrawal,
            updatedVaultShares - burnedShares,
            "Vault's total shares should decrease by the amount burned"
        );

        // Check that the user's share balance has been burned
        uint256 userSharesAfterWithdrawal = vault.balanceOf(user);
        assertEq(
            userSharesAfterWithdrawal,
            updatedUserShares - burnedShares,
            "User's share balance should decrease after withdrawal"
        );
    }

    function testClaimRewards() public {
        uint256 depositAmount = 100 ether;

        // 1. Check initial balances
        uint256 initialVaultAssets = vault.totalAssets();
        uint256 initialVaultShares = vault.totalSupply();
        uint256 initialUserShares = vault.balanceOf(ethxUser);
        uint256 initialUserEthxBalance = ethxToken.balanceOf(ethxUser);

        // 2. Approve Vault to transfer ETHx tokens on behalf of the user
        vm.startPrank(ethxUser);
        ethxToken.approve(address(vault), depositAmount);

        // 3. Deposit ETHx tokens into the vault and send them to Aaave pool
        uint256 sharesMinted = vault.deposit(depositAmount, ethxUser);
        vm.stopPrank();

        assertEq(
            vault.totalAssets(), initialVaultAssets + depositAmount, "Vault assets should increase after the deposit"
        );
        assertEq(vault.totalSupply(), initialVaultShares + sharesMinted, "Shares should increase after the deposit");
        assertGt(
            initialUserEthxBalance, ethxToken.balanceOf(ethxUser), "ETHx balance of user should decrease after deposit"
        );
        assertGt(vault.balanceOf(ethxUser), initialUserShares, "User shares should increase after the deposit");

        // 4. Simulate time progression for rewards to accrue
        uint256 timeFastForward = 30 days; // Example duration to accrue rewards
        vm.warp(block.timestamp + timeFastForward);

        // Check Vault's SD balance before claiming rewards
        uint256 vaultInitialSdTokenBalance = sdToken.balanceOf(address(vault));

        // 5. Claim rewards
        vm.startPrank(address(ethxUser));
        uint256 totalClaimed = vault.claimRewards();
        vm.stopPrank();

        // 6. Validate that rewards have been claimed and are in the vault
        uint256 sdBalanceAfterClaim = sdToken.balanceOf(address(vault));
        assertEq(
            sdBalanceAfterClaim,
            vaultInitialSdTokenBalance + totalClaimed,
            "SD token balance should match after claimed rewards"
        );
    }

    function testSwapStaderTokensToWETH() public {
        uint256 staderAmount = 10 ether;

        // 1. Assign (mint) SD tokens to vault
        deal(address(sdToken), address(vault), staderAmount);

        // 2. Ensure the vault's SD Balance is correct
        uint256 initialSdBalance = sdToken.balanceOf(address(vault));
        assertEq(initialSdBalance, staderAmount, "Vault should initially hold the specific amount of SD tokens");
        console.log("initialSdBalance:", initialSdBalance);

        // 3. Store initial ETH balance of the vault (before swap)
        uint256 initialWethBalance = ethxToken.balanceOf(address(vault));
        console.log("initialWethBalance:", initialWethBalance);

        // 4. Trigger the swap function to convert SD to ETHx
        vm.startPrank(address(vault));
        uint256 wethAmountReceived = vault.swapStaderTokensToWETH(staderAmount);
        console.log("wethAmountReceived:", wethAmountReceived);
        vm.stopPrank();

        // 5. Verify balances after swap
        uint256 finalWethBalance = wethToken.balanceOf(address(vault));
        uint256 finalSdBalance = sdToken.balanceOf(address(vault));

        // Assertions
        assertGt(finalWethBalance, initialWethBalance, "Vault's WETH balance should increase after the swap");
        assertEq(
            finalSdBalance, initialSdBalance - staderAmount, "Vault's SD balance should decrease by the swapped amount"
        );

        // Verify the WETH amount received matches expectations (if you know an expected range)
        assertGt(wethAmountReceived, 0, "WETH amount received should be greater than zero");
    }

    function testDepositWETHForCompounding() public {
        uint256 wethDeposit = 100 ether;

        // assign WETH tokens to vault
        deal(address(wethToken), address(vault), wethDeposit);

        uint256 initialVaultWETHBalance = wethToken.balanceOf(address(vault));
        console.log("initialVaultWETHBalance: ", initialVaultWETHBalance);

        uint256 initialVaultAethxBalance = aethxToken.balanceOf(address(vault));

        vm.startPrank(address(vault));
        vault.depositWETHForCompounding(wethDeposit);
        vm.stopPrank();

        assertGt(
            initialVaultWETHBalance,
            wethToken.balanceOf(address(vault)),
            "WETH balance of vault should decrease after deposit"
        );

        assertGt(
            aethxToken.balanceOf(address(vault)),
            initialVaultAethxBalance,
            "Vault's aETHx balance should increase after deposit"
        );
    }
}
