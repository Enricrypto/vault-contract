// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// OpenZeppelin's ERC-4626, ERC-20 contracts and IERC20 interface
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// Aave V3 Pool interface for deposit/withdraw functionality
import "lib/aave-v3-core/contracts/interfaces/IPool.sol";

// Interfaces for Stader's ETHx integration
import "./Interfaces/IStaderConfig.sol"; // Send ETH and receive minted ETHx token.
import "./Interfaces/IStaderStakePoolManager.sol";
import "./Interfaces/IUserWithdrawalManager.sol";

// import WETH Interface
import "./Interfaces/IWETH.sol";

// import Aave Rewards Controller Interface
import "./Interfaces/IRewardsController.sol";

// Import Uniswap's interfaces
import "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "lib/v3-periphery/contracts/libraries/TransferHelper.sol";
import "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract Vault is ERC4626 {
    IPool public pool; // for reference to the Aave pool interface for deposits and withdrawals.
    IStaderConfig public staderConfig; // Reference to Stader's configuration contract.
    IStaderStakePoolManager public stakePoolManager; // Stake pool manager for ETH staking
    IUserWithdrawalManager public userWithdrawManager; // interface of user withdrawal manager from Stader contract
    ISwapRouter public swapRouter; // Uniswap V3 swap router instance
    IRewardsController public rewardsController; // interface of Aave's rewards controller
    address public ethxAddress; // stores the address of the ETHx contract
    address public aEthxAddress; // Address of the aETHx token
    address public usdcAddress; // USDC token address
    address public SD; // Stader token address

    // Mainnet config address. ** Change to testnet address as needed **
    address private constant _STADER_CONFIG_ADDRESS =
        0x4ABEF2263d5A5ED582FC9A9789a41D85b68d69DB;

    // Uniswap harcdoded variables for swapping ETH to USDC
    uint24 public constant FEE_TIER = 3000;
    address public constant USDC = 0xA0b86991C6218b36c1d19D4a2e9Eb0cE3606EB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @dev Constructor initializes necessary contracts and tokens.
     * @param _poolAddress Address of the Aave pool contract.
     * @param _swapRouterAddress Address of the Uniswap swap router.
     * @param _usdcAddress Address of the USDC token contract.
     * @param _sdAddress Address of the SD token contract.
     */
    constructor(
        address _poolAddress,
        address _swapRouterAddress,
        address _usdcAddress,
        address _sdAddress
    )
        ERC20("My Vault", "VLT") // Call the ERC20 constructor for name and symbol
        ERC4626(IERC20(_STADER_CONFIG_ADDRESS)) // Replace with ETHx token address from the config
    {
        // Initialize the Aave pool interface.
        pool = IPool(_poolAddress);
        // Initialize the Stader config.
        staderConfig = IStaderConfig(_STADER_CONFIG_ADDRESS);
        // Uniswap Router address using the ISwapRouter interface casting
        swapRouter = ISwapRouter(_swapRouterAddress);
        // Get the ETHx token address from Stader config.
        ethxAddress = staderConfig.getETHxToken();
        // Retrieve and set the user withdrawal manager address from the Stader config and cast it to the `IUserWithdrawalManager` interface.
        userWithdrawManager = IUserWithdrawalManager(
            staderConfig.getUserWithdrawManager()
        );
        // Dynamically retrieve the aETHx address from Aave's pool
        aEthxAddress = pool.getReserveData(ethxAddress).aTokenAddress;
        // USDC address
        usdcAddress = _usdcAddress;
        // SD Token address
        SD = _sdAddress;
        // Approve the Aave pool to spend ETHx
        IERC20(ethxAddress).approve(address(pool), type(uint256).max);
    }

    /**
     * @dev Deposits ETH, converts it to ETHx, deposits ETHx into Aave, and mints vault shares to the receiver.
     * @param _receiver The address receiving the vault shares.
     */
    function depositETH(
        address _receiver
    ) public payable returns (uint256 shares) {
        require(msg.value > 0, "No ETH sent");

        // Step 1: Convert ETH to ETHx via Stader's stake pool manager
        uint256 amountInETHx = stakePoolManager.deposit{value: msg.value}(
            address(this)
        );

        // Step 2: Deposit ETHx into Aave and mint vault shares
        pool.supply(ethxAddress, amountInETHx, address(this), 0); // No referral code

        // Step 3: Call the original nonpayable deposit function from ERC4626
        shares = super.deposit(amountInETHx, _receiver);

        return shares;
    }

    /**
     * @dev Withdraws an amount of ETHx from the vault and requests unstake from Stader, allowing ETH redemption.
     * @param _amount The amount of ETHx to withdraw.
     * @param _receiver The address to receive the ETH.
     * @param _owner The owner of the shares being redeemed.
     */
    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) public override returns (uint256 shares) {
        // Step 1: Burn shares for the equivalent amount in ETHx
        shares = super.withdraw(_amount, _receiver, _owner);

        // Step 2: Withdraw ETHx from Aave pool to the vault
        pool.withdraw(ethxAddress, _amount, address(this));

        return shares;
    }

    /**
     * @dev Claims SD token rewards and swaps them for ETH.
     */
    function claimAndSwapSDForETH() external returns (uint256 amountOut) {
        // Step 1: Claim SD token rewards
        address;
        assets[0] = address(this); // Assuming the contract itself has rewards
        rewardsController.claimRewards(
            assets,
            type(uint256).max, // Claim the max amount of rewards available
            address(this), // Send claimed rewards to this contract
            address(SD) // Specify SD as the reward token
        );

        // Step 2: Check SD balance after claiming rewards
        uint256 sdBalance = SD.balanceOf(address(this));
        require(sdBalance > 0, "No SD tokens to swap");

        // Step 3: Approve Uniswap to spend the SD tokens
        SD.approve(address(swapRouter), sdBalance);

        // Step 4: Set up swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(SD),
                tokenOut: WETH, // Swap SD to WETH
                fee: FEE_TIER,
                recipient: address(this), // The contract receives the WETH
                deadline: block.timestamp, // Current timestamp as deadline
                amountIn: sdBalance, // Swap the entire balance of SD tokens
                amountOutMinimum: 0, // Optional: set a minimum amount of ETH expected
                sqrtPriceLimitX96: 0 // No price limit
            });

        // Step 5: Execute the swap on Uniswap V3
        amountOut = swapRouter.exactInputSingle(params);

        // Step 6: Convert WETH to ETH if needed
        // Assuming you want to convert WETH back to ETH after the swap
        IWETH(WETH).withdraw(amountOut); // IWETH interface is needed to unwrap WETH

        return amountOut; // Returns the amount of ETH received from the swap
    }

    /**
     * @dev Calculates the total assets managed by the vault, including both ETHx and aETHx (Aave's interest-bearing ETHx).
     */
    function totalAssets() public view override returns (uint256) {
        // 1. Balance of ETHx directly held in the vault
        uint256 ethxBalance = IERC20(ethxAddress).balanceOf(address(this));

        // Assets in ETHx that are already deposited into Aave and accruing interest.
        uint256 aEthxBalance = IERC20(aEthxAddress).balanceOf(address(this));

        // 3. Total assets in ETHx: ETHx held in vault + ETHx held in Aave (via aETHx)
        return ethxBalance + aEthxBalance;
    }

    /**
     * @dev Compounds the newly acquired ETH (from swapping SD rewards) by converting it to ETHx
     * and depositing the resulting ETHx into Aave. The existing staked ETHx in Aave remains untouched.
     */
    function compoundRewards() external {
        // Step 1: Check the current ETH balance in the contract
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "No new ETH to compound");

        // Step 2: Stake the new ETH in Stader to receive ETHx
        uint256 ethxMinted = stakePoolManager.deposit{value: ethBalance}(
            address(this)
        );

        // Step 3: Confirm that ETHx was minted
        require(ethxMinted > 0, "Stader staking did not yield ETHx");

        // Step 4: Deposit the newly minted ETHx into Aave
        pool.supply(ethxAddress, ethxMinted, address(this), 0); // No referral code
    }
}
