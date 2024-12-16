// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// OpenZeppelin's ERC-4626, ERC-20 contracts and IERC20 interface
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// Aave V3 Pool interface for deposit/withdraw functionality
import "lib/aave-v3-core/contracts/interfaces/IPool.sol";
import "lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";

// Interfaces for Stader's ETHx integration
import "lib/ethx/contracts/interfaces/IStaderConfig.sol";
import "lib/ethx/contracts/interfaces/IStaderStakePoolManager.sol";
import "lib/ethx/contracts/interfaces/IUserWithdrawalManager.sol";

// import WETH Interface
import "./Interfaces/IWETH.sol";

// import IRewardsController and IRewardsDistributor interfaces from Aave V3 Origin
import "lib/aave-v3-origin/src/contracts/rewards/interfaces/IRewardsController.sol";
import "lib/aave-v3-origin/src/contracts/rewards/interfaces/IRewardsDistributor.sol";

// Import Uniswap's interfaces
import "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "lib/v3-periphery/contracts/libraries/TransferHelper.sol";

contract Vault is ERC4626 {
    IPool public pool; // Aave Pool Interface
    IPoolAddressesProvider public poolAddressesProvider; // Aave Pool Address Provider
    IStaderConfig public staderConfig; // Stader's config contract.
    IStaderStakePoolManager public stakePoolManager; // Stader's Stake pool manager
    IUserWithdrawalManager public userWithdrawManager; // Stader's user withdrawal manager
    IRewardsController public rewardsController; // Aave rewards controller
    ISwapRouter public immutable swapRouter; // Uniswap V3 swap router instance
    IERC20 public ethxToken; // ETHx token
    IERC20 public aethxToken; // Aave's ETHx token
    IERC20 public sdToken; // Stader token address (SD Token)
    IERC20 public usdcToken; // USDC token address
    IWETH public wethToken; // Wrapped ETH contract

    address public vaultAdministrator; // Vault Administrator

    // Uniswap hardcoded Fee Tier (0.3% fee tier)
    uint24 public constant POOLFEE = 3000;

    ///// EVENTS /////
    event Log(uint256 value);
    // Declare the event to log the withdrawal details
    event ETHxWithdrawnFromAave(uint256 amount);
    event WithdrawRequestCreated(uint256 requestId, address indexed receiver, uint256 amount);
    // Event for minted shares on DepositETH()
    event SharesMinted(address indexed receiver, uint256 shares);

    event WithdrawRequestFinalized(uint256 requestId);
    event SharesBurned(address indexed receiver, uint256 sharesBurned);
    event Withdrawal(address indexed receiver, uint256 amount, uint256 sharesBurned);
    event DepositETHx(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event ApprovalSet(address indexed spender, uint256 amount, bool success);

    /**
     * @dev Initializes the Vault contract with the addresses of essential components including
     * Aave pool, Uniswap router, Stader's SD token, and the Aave rewards controller.
     * The contract deployer is assigned as the vault administrator.
     * @param _poolAddressesProvider The address of the Aave pool contract.
     * @param _swapRouterAddress The address of the Uniswap swap router contract.
     * @param _staderConfigAddress The address of the Stader Configuration
     * @param _rewardsControllerAddress The address of Aave Rewards controller
     */
    constructor(
        address _stakePoolAddress, // Stader stake pool address
        address _poolAddressesProvider,
        address _swapRouterAddress,
        address _wethAddress,
        address _usdcAddress,
        address _staderConfigAddress,
        address _rewardsControllerAddress,
        address _aethxAddress,
        string memory _name, // string for the ERC20 token name (vault shares)
        string memory _symbol // string for the ERC20 token symbol
    )
        ERC20(_name, _symbol) // vault shares. Call the ERC20 constructor for name and symbol
        ERC4626(IERC20(IStaderConfig(_staderConfigAddress).getETHxToken())) // users deposit ETHx -underlying asset- tokens to receive vault shares
    {
        // Initialize the vault administrator to the contract deployer (msg.sender)
        vaultAdministrator = msg.sender;
        // Initialize the Stader Pool interface, pool for staking operations on Stader
        stakePoolManager = IStaderStakePoolManager(_stakePoolAddress);
        // Initialize the Aave Pool interface.
        poolAddressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        pool = IPool(poolAddressesProvider.getPool());
        // Initialize the Stader config.
        staderConfig = IStaderConfig(_staderConfigAddress);
        // Get the ethxToken token address from Stader config.
        ethxToken = IERC20(staderConfig.getETHxToken());
        // SD Token address
        sdToken = IERC20(staderConfig.getStaderToken());
        // Uniswap Router address for performing token swaps
        swapRouter = ISwapRouter(_swapRouterAddress);
        // Retrieve and set the user withdrawal manager address from the Stader config and cast it to the `IUserWithdrawalManager` interface.
        userWithdrawManager = IUserWithdrawalManager(staderConfig.getUserWithdrawManager());
        // WETH interface for handling wrapped/unwrapped ETH.
        wethToken = IWETH(_wethAddress);
        // Setup Aave Rewards Controller to claim rewards (like SD tokens) accrued from Aave-based assets like aETHx.
        rewardsController = IRewardsController(_rewardsControllerAddress);
        // aETHx token interface, Aave's yield-bearing token that represents staked ETHx in the Aave Pool.
        aethxToken = IERC20(_aethxAddress);
        // USDC token interface
        usdcToken = IERC20(_usdcAddress);
        // Vault approves the Aave pool to spend ETHx tokens from the vault
        ethxToken.approve(address(pool), type(uint256).max);
        // Approve Stader (userWithdrawManager) to withdraw ETHx tokens from the vault
        ethxToken.approve(address(userWithdrawManager), type(uint256).max);
    }

    modifier onlyOwner() {
        require(msg.sender == vaultAdministrator, "Caller is not the vault administrator");
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
    function depositETH(address _receiver) public payable returns (uint256 shares) {
        require(msg.value > 0, "Deposit amount must be greater than zero");

        // Step 1: Convert ETH to ETHx via Stader's stake pool manager
        // msg.value is the ETH received by the vault
        // address(this) specifies that the ETHx tokens minted in return for the ETH are sent back to the Vault
        uint256 amountInETHx = stakePoolManager.deposit{value: msg.value}(address(this));
        require(amountInETHx > 0, "Failed to receive ETHx tokens");
        // emit Log(this.totalAssets()); // Log the total assets in the vault

        // Step 2: Calculate the shares to mint using helper function
        shares = _previewDeposit(amountInETHx);
        emit SharesMinted(_receiver, shares);

        // Step 3: Deposit ETHx into Aave
        pool.supply(address(ethxToken), amountInETHx, address(this), 0);

        // Step 4: Update vault and mint shares to receiver
        _mint(_receiver, shares); // Mint shares for the receiver, following ERC-4626 standard

        return shares; // Return the amount of shares minted
    }

    function deposit(uint256 _assets, address _receiver) public override returns (uint256 shares) {
        require(_assets > 0, "Deposit amount must be greater than zero");
        require(ethxToken.allowance(msg.sender, address(this)) >= _assets, "Insufficient ETHx allowance");

        // Step 1: Transfer ETHx from the user to the vault
        ethxToken.transferFrom(msg.sender, address(this), _assets);

        // Step 2: Calculate the shares to mint using helper function
        shares = _previewDeposit(_assets);

        // Step 3: Stake ETHx into Aave
        pool.supply(address(ethxToken), _assets, address(this), 0);

        // Step 4: Mint shares to the receiver
        _mint(_receiver, shares);

        emit DepositETHx(msg.sender, _receiver, _assets, shares);

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
    function withdraw(uint256 _amount, address _receiver, address _owner) public override returns (uint256 shares) {
        // Step 1: Withdraw ETHx from Aave pool to the vault (converting aETHx to ETHx)
        pool.withdraw(address(ethxToken), _amount, address(this));

        // Check balance of ETHx in the Vault after the withdrawal
        uint256 ethxBalanceAfterAave = ethxToken.balanceOf(address(this));
        require(ethxBalanceAfterAave >= _amount, "Insufficient ETHx after Aave withdrawal");

        // Emit event for ETHx withdrawal
        emit ETHxWithdrawnFromAave(_amount);

        // Step 2: Burn the user's shares based on the withdrawn ETHx balance
        shares = super.withdraw(_amount, _receiver, _owner);

        // Emit event after burning shares
        emit SharesBurned(_receiver, shares);

        return shares;
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
        uint256 wethAmount = _swapStaderTokensToWETH(totalClaimed);

        // Step 3: Deposit ETHx into Aave for compounding
        _depositWETHForCompounding(wethAmount);
    }

    /**
     * @dev Calculates the total assets managed by the vault, including both ETHx and aETHx
     * (Aave's interest-bearing ETHx).
     * This function returns the total value of all ETHx and aETHx held by the vault.
     * @return totalBalance that is the total value of assets (ETHx + aETHx) in the vault.
     */
    function totalAssets() public view override returns (uint256 totalBalance) {
        // 1. Balance of ETHx directly held in the vault
        uint256 ethxBalance = ethxToken.balanceOf(address(this));

        // Assets in ETHx that are already deposited into Aave and accruing interest.
        uint256 aethxBalance = aethxToken.balanceOf(address(this));

        // 3. Total assets in ETHx: ETHx held in vault + ETHx held in Aave (via aETHx)
        totalBalance = ethxBalance + aethxBalance;

        return totalBalance;
    }

    //// HELPER FUNCTIONS ////

    function _previewDeposit(uint256 amount) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return amount;
        }
        return (amount * supply) / totalAssets();
    }

    /**
     * @dev Claims rewards from Aave for the vault. Only the Vault Administrator can call this function.
     * This function collects rewards in Stader (SD tokens), aggregates them, and returns the total amount.
     * @return totalClaimed The total amount of Stader rewards claimed.
     */
    function _claimRewards() internal returns (uint256 totalClaimed) {
        // Step 1: Define the Aave assets (aToken address) for ETHx staking
        // Claim rewards function from rewards controller of Aave expects an array of assets
        address[] memory assets = new address[](1);
        assets[0] = address(aethxToken); // Assign the address of the aETHx token
        // Step 2: Define the Stader token reward address
        address reward = address(sdToken); // The Stader token (SD) address
        // Step 3: Claim the rewards for Stader (SD) tokens
        uint256 claimedAmount = rewardsController.claimRewards(
            assets, // The list of Aave assets (aETHx in this case)
            type(uint256).max, // claim all rewards
            address(this), // The address to receive the rewards
            reward // Claim only Stader (SD) tokens
        );
        // Step 4: Return the total claimed Stader tokens (SD)
        totalClaimed = claimedAmount;
        return totalClaimed;
    }

    /**
     * @dev Swaps Stader tokens (SD) for WETH using the Uniswap V3 router.
     * The function approves the swap, sets the path (SD -> USDC -> WETH), and performs the trade on Uniswap.
     * @param _staderAmount The amount of Stader tokens to swap.
     * @return wethAmount The amount of WETH received from the swap.
     */
    function _swapStaderTokensToWETH(uint256 _staderAmount) internal returns (uint256 wethAmount) {
        // 1: Approve the swapRouter to spend SD tokens on behalf of the contract
        TransferHelper.safeApprove(address(sdToken), address(swapRouter), _staderAmount);

        // 2. Set up parameters for the swap
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(sdToken, POOLFEE, usdcToken, POOLFEE, wethToken),
            recipient: address(this),
            deadline: block.timestamp + 300, // 5 minutes deadline
            amountIn: _staderAmount,
            amountOutMinimum: 0 // No slippage protection, adjust as needed
        });

        // 3. Call the Uniswap router's exactInput method to swap tokens
        // Perform the swap and receive WETH in return
        uint256 weth = swapRouter.exactInput(params);

        // Return the amount of WETH received
        return weth;
    }

    /**
     * @dev Deposits ETH into Stader, mints ETHx, and then supplies it to Aave for compounding.
     * This function facilitates the process of compounding by converting ETH to ETHx
     * and depositing it into Aave to earn interest.
     * @param wethAmount The amount of WETH to deposit and compound.
     */
    function _depositWETHForCompounding(uint256 wethAmount) internal {
        // 1. Unwrapp the WETH into ETH
        wethToken.withdraw(wethAmount);
        uint256 ethAmount = wethAmount; // Since WETH is 1:1 convertible to ETH

        // 2. Stake the ETH into Stader to minth ETHx tokens
        require(ethAmount > 0, "Deposit amount must be greater than zero");
        uint256 ethxAmount = stakePoolManager.deposit{value: ethAmount}(address(this));
        require(ethxAmount > 0, "Staking ETH failed, no ETHx received");

        // 3. Record the vault's WETH balance before the deposit
        uint256 aEthxBalanceBefore = aethxToken.balanceOf(address(this));

        // 4. Deposit ETHx tokens into Aave's pool to mint aETHx tokens
        pool.supply(address(ethxToken), ethxAmount, address(this), 0); // No referral code

        // 5. Record the vault's aETHx balance after the deposit
        uint256 aEthxBalanceAfter = aethxToken.balanceOf(address(this));

        // 6. Ensure that the vault received aETHx in exchange
        require(aEthxBalanceAfter > aEthxBalanceBefore, "No aETHx received from Aave");
    }

    /**
     * @dev Allows the vault administrator to change the vault's administrator.
     * This function can only be called by the current vault administrator.
     * @param newAdministrator The address of the new vault administrator.
     */
    function setVaultAdministrator(address newAdministrator) external onlyOwner {
        vaultAdministrator = newAdministrator;
    }

    // Add this function to your Vault contract for testing purposes only
    function claimRewards() external returns (uint256) {
        return _claimRewards();
    }

    function swapStaderTokensToWETH(uint256 _staderAmount) external returns (uint256) {
        return _swapStaderTokensToWETH(_staderAmount);
    }

    function depositWETHForCompounding(uint256 _wethAmount) external {
        return _depositWETHForCompounding(_wethAmount);
    }

    // payable callback function to unwrap WETH into ETH
    receive() external payable {}
}
