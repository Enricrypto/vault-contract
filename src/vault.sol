// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// OpenZeppelin's ERC-4626, ERC-20 contracts and IERC20 interface
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// Aave V3 Pool interface for deposit/withdraw functionality
import "aave-v3-core/contracts/interfaces/IPool.sol";

// Interfaces for Stader's ETHx integration
import "ethx/contracts/interfaces/IStaderConfig.sol";
import "ethx/contracts/interfaces/IStaderStakePoolManager.sol";
import "ethx/contracts/interfaces/IUserWithdrawalManager.sol";

// import WETH Interface
import "./Interfaces/IWETH.sol";

// import IRewardsController and IRewardsDistributor interfaces from Aave V3 Origin
import "aave-v3-origin/src/contracts/rewards/interfaces/IRewardsController.sol";
import "aave-v3-origin/src/contracts/rewards/interfaces/IRewardsDistributor.sol";

// Import Uniswap's interfaces
import "v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract Vault is ERC4626 {
    IPool public pool; // Aave Pool Interface
    IStaderConfig public staderConfig; // Stader's config contract.
    IStaderStakePoolManager public stakePoolManager; // Stader's Stake pool manager
    IUserWithdrawalManager public userWithdrawManager; // Stader's user withdrawal manager
    ISwapRouter public swapRouter; // Uniswap V3 swap router instance
    IERC20 public ethxToken; // ETHx token
    IERC20 public aEthxToken; // Aave's ETHx token
    IERC20 public sdToken; // Stader token address (SD Token)
    IRewardsController public rewardsController; // Aave's rewards controller
    address public vaultAdministrator; // Vault Administrator

    // Mainnet config address. ** Change to testnet address as needed **
    address private constant _STADER_CONFIG_ADDRESS =
        0x4ABEF2263d5A5ED582FC9A9789a41D85b68d69DB;

    // Uniswap hardcoded variables for swapping ETH to USDC
    uint24 public constant FEE_TIER = 3000;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @dev Initializes the Vault contract with the addresses of essential components including
     * Aave pool, Uniswap router, Stader's SD token, and the Aave rewards controller.
     * The contract deployer is assigned as the vault administrator.
     * @param _poolAddress The address of the Aave pool contract.
     * @param _swapRouterAddress The address of the Uniswap swap router contract.
     * @param _sdAddress The address of the Stader token contract (SD Token).
     * @param _rewardsControllerAddress The address of the Aave rewards controller contract.
     */
    constructor(
        address _poolAddress,
        address _swapRouterAddress,
        address _sdAddress,
        address _rewardsControllerAddress
    )
        ERC20("My Vault", "VLT") // Call the ERC20 constructor for name and symbol
        ERC4626(IERC20(_STADER_CONFIG_ADDRESS)) // Replace with ETHx token address from the config
    {
        // Initialize the vault administrator to the contract deployer (msg.sender)
        vaultAdministrator = msg.sender;
        // Initialize the Aave Pool interface.
        pool = IPool(_poolAddress);
        // Initialize the Stader config.
        staderConfig = IStaderConfig(_STADER_CONFIG_ADDRESS);
        // Uniswap Router address using the ISwapRouter interface casting
        swapRouter = ISwapRouter(_swapRouterAddress);
        // Get the ETHx token address from Stader config.
        ethxToken = IERC20(staderConfig.getETHxToken());
        // Retrieve and set the user withdrawal manager address from the Stader config and cast it to the `IUserWithdrawalManager` interface.
        userWithdrawManager = IUserWithdrawalManager(
            staderConfig.getUserWithdrawManager()
        );
        // Dynamically retrieve the aETHx address from Aave's pool
        aEthxToken = IERC20(
            pool.getReserveData(address(ethxToken)).aTokenAddress
        );
        // SD Token address
        sdToken = IERC20(_sdAddress);
        // Initialize Rewards Controller Interface
        rewardsController = IRewardsController(_rewardsControllerAddress);
        // Approve the Aave pool to spend ETHx
        ethxToken.approve(address(pool), type(uint256).max);
    }

    modifier onlyOwner() {
        require(
            msg.sender == vaultAdministrator,
            "Not the vault administrator"
        );
        _;
    }

    /**
     * @dev Deposits ETH into the vault, converts it to ETHx, mints shares to the user, and updates
     * the total assets and total shares of the vault.
     * This function allows users to deposit ETH into the vault and receive shares in return,
     * with the underlying ETH being staked through Stader and compounded in Aave.
     * @param _receiver The address receiving the vault shares.
     * @return shares The amount of shares minted for the user based on their deposit.
     */
    function depositETH(
        address _receiver
    ) public payable returns (uint256 shares) {
        require(msg.value > 0, "No ETH sent");

        // Step 1: Convert ETH to ETHx via Stader's stake pool manager
        uint256 amountInETHx = stakePoolManager.deposit{value: msg.value}(
            address(this)
        );

        // Step 2: Deposit ETHx into Aave
        pool.supply(address(ethxToken), amountInETHx, address(this), 0);

        // Step 3: Use ERC-4626 previewDeposit to calculate shares
        shares = previewDeposit(amountInETHx);

        // Step 4: Update vault and mint shares to receiver
        _mint(_receiver, shares); // ERC-4626 standard function for minting shares

        return shares;
    }

    /**
     * @dev Withdraws ETHx from the vault and requests unstake from Stader for ETH redemption.
     * The user will burn shares in exchange for the equivalent amount of ETHx.
     * @param _amount The amount of ETHx to withdraw.
     * @param _receiver The address that will receive the withdrawn ETH.
     * @param _owner The address of the user redeeming the shares.
     * @return shares The amount of shares burned.
     */
    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) public override returns (uint256 shares) {
        // Step 1: Withdraw ETHx from Aave pool to the vault
        pool.withdraw(address(ethxToken), _amount, address(this));

        // Step 2: Burn shares for the equivalent amount in ETHx and recalculates the remaining shares in the pool
        shares = super.withdraw(_amount, _receiver, _owner);

        return shares;
    }

    /**
     * @dev Claims rewards from Aave for the vault. Only the Vault Administrator can call this function.
     * This function collects rewards in Stader (SD tokens), aggregates them, and returns the total amount.
     * @return totalClaimed The total amount of Stader rewards claimed.
     */
    function _claimRewards() internal returns (uint256 totalClaimed) {
        // Step 1: Claim all rewards from Aave for this contract
        (
            address[] memory rewardsList,
            uint256[] memory claimedAmounts
        ) = rewardsController.claimAllRewards(
                // passing an empty array (new address[]) tells Aave to claim rewards
                // for all assets that the contract has staked
                new address[],
                address(this)
            );

        // Step 2: Aggregate total claimed Stader tokens (SD)
        // The loop iterates through each reward token and its corresponding amount.
        // It sums up the total rewards claimed, which is returned as totalClaimed
        totalClaimed = 0;
        for (uint256 i = 0; i < rewardsList.length; i++) {
            uint256 rewardAmount = claimedAmounts[i];
            if (rewardAmount > 0) {
                totalClaimed += rewardAmount;
            }
        }

        // Step 3: Return the total claimed amount (in Stader tokens)
        return totalClaimed;
    }

    /**
     * @dev Swaps Stader tokens (SD) for ETH using the Uniswap V3 router.
     * The function approves the swap, sets the path (SD -> WETH), and performs the trade on Uniswap.
     * @param _staderAmount The amount of Stader tokens to swap.
     * @return ethAmount The amount of ETH received from the swap.
     */
    function _swapStaderTokensToETH(
        uint256 _staderAmount
    ) internal returns (uint256 ethAmount) {
        // Approve the swapRouter to spend the Stader (SD) tokens
        sdToken.approve(address(swapRouter), _staderAmount);

        // Path: Stader tokens -> WETH (ETH)
        address;
        path[0] = address(sdToken); // Stader token (SD)
        path[1] = WETH; // Wrapped ETH (WETH)

        // Perform the swap on Uniswap V3 (assume exactInputSingle for simplicity)
        ethAmount = swapRouter.exactInputSingle(
            IUniV3Router.ExactInputSingleParams({
                tokenIn: address(sdToken),
                tokenOut: WETH,
                fee: FEE_TIER, // Swap fee tier (typically 0.3%) hardcoded
                recipient: address(this),
                amountIn: _staderAmount,
                amountOutMinimum: 0, // You can set slippage protection here
                sqrtPriceLimitX96: 0
            })
        );

        return ethAmount;
    }

    /**
     * @dev Deposits ETH into Stader, mints ETHx, and then supplies it to Aave for compounding.
     * This function facilitates the process of compounding by converting ETH to ETHx
     * and depositing it into Aave to earn interest.
     * @param ethAmount The amount of ETH to deposit and compound.
     */
    function _depositETHForCompounding(uint256 ethAmount) internal {
        // Step 1: Deposit ETH into Stader and mint ETHx
        uint256 ethxMinted = stakePoolManager.deposit{value: ethAmount}(
            address(this)
        );
        require(ethxMinted > 0, "Stader staking did not yield ETHx");

        // Step 2: Deposit the newly minted ETHx into Aave
        pool.supply(address(ethxToken), ethxMinted, address(this), 0); // No referral code
    }

    /**
     * @dev Claims Stader rewards, swaps them to ETH, and deposits the ETH into Stader and Aave.
     * This function automates the entire compounding process: claiming rewards, converting them to ETH,
     * and depositing them to earn more yield in Aave.
     */
    function claimAndCompound() external onlyOwner {
        // Step 1: Claim Stader tokens from Aave
        uint256 totalClaimed = _claimRewards();

        // Step 2: Swap the Stader tokens to ETH
        uint256 ethAmount = _swapStaderTokensToETH(totalClaimed);

        // Step 3: Deposit ETH to Stader, mint ETHx, and deposit into Aave
        _depositETHForCompounding(ethAmount);
    }

    /**
     * @dev Calculates the total assets managed by the vault, including both ETHx and aETHx
     * (Aave's interest-bearing ETHx).
     * This function returns the total value of all ETHx and aETHx held by the vault.
     * @return TotalBalance that is the total value of assets (ETHx + aETHx) in the vault.
     */
    function totalAssets() public view override returns (uint256 totalBalance) {
        // 1. Balance of ETHx directly held in the vault
        uint256 ethxBalance = ethxToken.balanceOf(address(this));

        // Assets in ETHx that are already deposited into Aave and accruing interest.
        uint256 aEthxBalance = aEthxToken.balanceOf(address(this));

        // 3. Total assets in ETHx: ETHx held in vault + ETHx held in Aave (via aETHx)
        totalBalance = ethxBalance + aEthxBalance;

        return totalBalance;
    }

    /**
     * @dev Allows the vault administrator to change the vault's administrator.
     * This function can only be called by the current vault administrator.
     * @param newAdministrator The address of the new vault administrator.
     */
    function setVaultAdministrator(
        address newAdministrator
    ) external onlyOwner {
        vaultAdministrator = newAdministrator;
    }
}
