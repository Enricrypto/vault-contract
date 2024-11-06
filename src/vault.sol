// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// OpenZeppelin's ERC-4626 and ERC-20 contracts
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

// Aave V3 Pool interface for deposit/withdraw functionality
import "lib/aave-v3-core/contracts/interfaces/IPool.sol";

// Interfaces for Stader's ETHx integration
import "./Interfaces/IStaderConfig.sol"; // Send ETH and receive minted ETHx token.
import "./Interfaces/IStaderStakePoolManager.sol";

// Import Uniswap's ISwapRouter interface
import "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract Vault is ERC4626 {
    IPool public pool; // for reference to the Aave pool interface for deposits and withdrawals.
    IStaderConfig public staderConfig; // Reference to Stader's configuration contract.
    IStaderStakePoolManager public stakePoolManager; // Stake pool manager for ETH staking
    ISwapRouter public swapRouter; // Uniswap V3 swap router instance
    address public ethxAddress; // stores the address of the ETHx contract
    address public userWithdrawManager; // address of the user withdrawal manager
    address public aEthxAddress; // Address of the aETHx token
    address public usdcAddress; // USDC token address

    // Mainnet config address. ** Change to testnet address as needed **
    address private constant _STADER_CONFIG_ADDRESS =
        0x4ABEF2263d5A5ED582FC9A9789a41D85b68d69DB;

    // vault will be working with WETH as the underlying asset. It allows the vault to manage WETH in accordance with the ERC-4626 standard.
    constructor(
        address _poolAddress,
        address _swapRouterAddress,
        address _usdcAddress
    )
        ERC20("My Vault", "VLT") // Call the ERC20 constructor for name and symbol
        ERC4626(IERC20(_STADER_CONFIG_ADDRESS)) // Replace with ETHx token address from the config
    {
        pool = IPool(_poolAddress); // Initialize the Aave pool interface.
        staderConfig = IStaderConfig(_STADER_CONFIG_ADDRESS); // Initialize the Stader config.

        // Uniswap Router address
        swapRouter = ISwapRouter(_swapRouterAddress);

        ethxAddress = staderConfig.getETHxToken(); // Get the ETHx token address from Stader config.
        userWithdrawManager = staderConfig.getUserWithdrawManager(); // Get user withdrawal manager address.

        // Dynamically retrieve the aETHx address from Aave's pool
        aEthxAddress = pool.getReserveData(ethxAddress).aTokenAddress;

        // USDC address
        usdcAddress = _usdcAddress;

        // Approve the Aave pool to spend ETHx
        IERC20(ethxAddress).approve(address(pool), type(uint256).max);
    }

    function deposit(
        uint256 _amount,
        address _receiver
    ) public payable override returns (uint256 shares) {
        require(msg.value == _amount, "Invalid ETH amount sent");

        // Step 1: Convert ETH to ETHx by staking via Stader's stake pool manager
        uint256 amountInETHx = stakePoolManager.deposit{value: _amount}(
            address(this)
        );

        // Step 2: Deposit ETHx into Aave
        pool.supply(ethxAddress, amountInETHx, address(this), 0); // Referral code is zero, assuming none used

        // Step 3: Mint vault shares equivalent to the deposit
        shares = super.deposit(amountInETHx, _receiver);

        return shares;
    }

    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) public override returns (uint256 shares) {
        uint256 amountInETHx = convertToETHx(_amount); // Calculate equivalent ETHx

        // Step 1: Burn shares for the equivalent amount in ETHx
        shares = super.withdraw(amountInETHx, _receiver, _owner);

        // Step 2: Withdraw ETHx from Aave pool to the vault
        pool.withdraw(ethxAddress, amountInETHx, address(this));

        // Step 3: Request unstake to redeem ETH via Stader’s user withdrawal manager
        userWithdrawManager.requestWithdraw(amountInETHx, _receiver);

        return shares;
    }

    function totalAssets() public view override returns (uint256) {
        // 1. Balance of ETHx directly held in the vault
        uint256 ethxBalance = IERC20(ethxAddress).balanceOf(address(this));

        // Assets in ETHx that are already deposited into Aave and accruing interest.
        uint256 aEthxBalance = IERC20(aEthxAddress).balanceOf(address(this));

        // 3. Total assets in ETHx: ETHx held in vault + ETHx held in Aave (via aETHx)
        return ethxBalance + aEthxBalance;
    }

    // Function to compound rewards in the Vault by reinvesting `aETHx` into `ETHx`
    function compoundRewards() external {
        // Step 1: Retrieve the vault's aETHx balance
        uint256 aEthxBalance = IERC20(aEthxAddress).balanceOf(address(this));
        require(aEthxBalance > 0, "No rewards to compound");

        // Step 2: Convert aETHx to ETHx by withdrawing from Aave
        pool.withdraw(aEthxAddress, aEthxRewards, address(this));

        // Step 3: After the withdrawal, the contract holds ETHx. Restake it in Aave to compound.
        // Redeposit ETHx into Aave pool
        pool.supply(ethxAddress, aEthxBalance, address(this), 0); // No referral code
    }

    // ** ======= HELPER FUNCTIONS ==========  **

    // Helper function to calculate the amount of ETHx in relation to ETH
    function convertToETHx(uint256 ethAmount) internal pure returns (uint256) {
        // Assuming a 1:1 peg between ETH and ETHx
        return ethAmount;
    }
}
