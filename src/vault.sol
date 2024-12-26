// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// OpenZeppelin's ERC-4626, ERC-20 contracts and IERC20 interface
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Aave V3 Pool interface for deposit/withdraw functionality
import {IPool} from "lib/aave-v3-core/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";

// Interfaces for Stader's ETHx integration
import {IStaderConfig} from "./Interfaces/IStaderConfig.sol";
import {IStaderStakePoolManager} from "./Interfaces/IStaderStakePoolManager.sol";
import {IUserWithdrawalManager} from "./Interfaces/IUserWithdrawalManager.sol";

// import WETH Interface
import {IWETH} from "./Interfaces/IWETH.sol";

// import IRewardsController interface from Aave V3 Origin
import {IRewardsController} from "lib/aave-v3-origin/src/contracts/rewards/interfaces/IRewardsController.sol";

// Import Uniswap's interfaces
import {ISwapRouter} from "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TransferHelper} from "lib/v3-periphery/contracts/libraries/TransferHelper.sol";

contract Vault is ERC4626 {
    IPool public pool; // Aave Pool Interface
    IPoolAddressesProvider public poolAddressesProvider; // Aave Pool Address Provider
    IStaderConfig public staderConfig; // Stader's config contract.
    IStaderStakePoolManager public stakePoolManager; // Stader's Stake pool manager
    IUserWithdrawalManager public userWithdrawManager; // Stader's user withdrawal manager
    IRewardsController public rewardsController; // Aave rewards controller
    ISwapRouter public swapRouter; // Uniswap V3 swap router instance
    IERC20 public ethxToken; // ETHx token
    IERC20 public aethxToken; // Aave's ETHx token
    IERC20 public sdToken; // Stader token address (SD Token)
    IERC20 public usdcToken; // USDC token address
    IWETH public wethToken; // Wrapped ETH contract

    address public vaultAdministrator; // Vault Administrator

    // Uniswap hardcoded Fee Tier (0.3% fee tier)
    uint24 public constant POOLFEE = 3000;

    ///// EVENTS /////

    // Event for deposit ETHx
    event DepositETHx(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    // Event for minted shares on DepositETH()
    event SharesMinted(address indexed receiver, uint256 shares);

    // Events for withdrawal
    event ETHxWithdrawnFromAave(uint256 amount);
    event WithdrawRequestCreated(
        uint256 requestId,
        address indexed receiver,
        uint256 amount
    );

    // Event to check burned shares
    event SharesBurned(address indexed receiver, uint256 sharesBurned);

    // Event to signal compounding success
    event Compounded(uint256 totalAssetsBefore, uint256 totalAssetsAfter);

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
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
        ERC4626(IERC20(IStaderConfig(_staderConfigAddress).getETHxToken()))
    {
        vaultAdministrator = msg.sender;
        _initializeStaderComponents(_stakePoolAddress, _staderConfigAddress);
        _initializeAaveComponents(
            _poolAddressesProvider,
            _rewardsControllerAddress
        );
        _initializeTokens(
            _swapRouterAddress,
            _wethAddress,
            _usdcAddress,
            _aethxAddress
        );
    }

    modifier onlyOwner() {
        require(
            msg.sender == vaultAdministrator,
            "Caller not vault administrator"
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
        require(msg.value > 0, "Deposit amount must be greater than zero");

        // Step 1: Convert ETH to ETHx via Stader's stake pool
        uint256 assets = _convertEthToEthx(msg.value);
        require(assets > 0, "Failed to receive ETHx tokens");

        // Step 2: Calculate shares
        shares = _previewDeposit(assets);

        // Step 3: Deposit ETHx into Aave
        _depositEthxToAave(assets);

        // Step 4: Mint shares to the receiver
        _mintShares(_receiver, shares);

        return shares;
    }

    function deposit(
        uint256 _assets,
        address _receiver
    ) public override returns (uint256 shares) {
        // Step 1: Validate input and allowance
        _validateDeposit(_assets, msg.sender);

        // Step 2: Transfer ETHx from the user to the vault
        _transferEthxToVault(_assets, msg.sender);

        // Step 3: Calculate the shares to mint
        shares = _previewDeposit(_assets);

        // Step 4: Stake ETHx into Aave
        _depositEthxToAave(_assets);

        // Step 5: Mint shares to the receiver
        _mintShares(_receiver, shares);

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
    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) public override returns (uint256 shares) {
        // Step 1: Withdraw ETHx from Aave to the vault
        _withdrawFromAave(_amount);

        // Step 2: Validate ETHx balance after Aave withdrawal
        _validateEthxBalanceAfterWithdrawal(_amount);

        // Step 3: Burn shares and transfer ETHx to the receiver
        shares = _burnSharesAndTransfer(_amount, _receiver, _owner);

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

    /// === HELPER FUNCTIONS FOR INITIALIZATION === ///

    function _initializeStaderComponents(
        address _stakePoolAddress,
        address _staderConfigAddress
    ) private {
        stakePoolManager = IStaderStakePoolManager(_stakePoolAddress);
        staderConfig = IStaderConfig(_staderConfigAddress);
        ethxToken = IERC20(staderConfig.getETHxToken());
        sdToken = IERC20(staderConfig.getStaderToken());
        userWithdrawManager = IUserWithdrawalManager(
            staderConfig.getUserWithdrawManager()
        );
        ethxToken.approve(address(userWithdrawManager), type(uint256).max);
    }

    function _initializeAaveComponents(
        address _poolAddressesProvider,
        address _rewardsControllerAddress
    ) private {
        poolAddressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        pool = IPool(poolAddressesProvider.getPool());
        rewardsController = IRewardsController(_rewardsControllerAddress);
    }

    function _initializeTokens(
        address _swapRouterAddress,
        address _wethAddress,
        address _usdcAddress,
        address _aethxAddress
    ) private {
        swapRouter = ISwapRouter(_swapRouterAddress);
        wethToken = IWETH(_wethAddress);
        usdcToken = IERC20(_usdcAddress);
        aethxToken = IERC20(_aethxAddress);
        ethxToken.approve(address(pool), type(uint256).max);
    }

    /// === HELPER FUNCTIONS FOR DEPOSIT === ///

    // Helper function: Convert ETH to ETHx
    function _convertEthToEthx(uint256 ethAmount) internal returns (uint256) {
        uint256 ethxAmount = stakePoolManager.deposit{value: ethAmount}(
            address(this)
        );
        return ethxAmount;
    }

    // Helper function: Deposit ETHx to Aave
    function _depositEthxToAave(uint256 ethxAmount) internal {
        pool.supply(address(ethxToken), ethxAmount, address(this), 0);
    }

    function _previewDeposit(uint256 amount) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return amount;
        }
        return (amount * supply) / totalAssets();
    }

    // Helper function: Mint shares to the receiver
    function _mintShares(address receiver, uint256 shares) internal {
        _mint(receiver, shares);
        emit SharesMinted(receiver, shares);
    }

    // Helper function: Validates the deposit input and allowance
    function _validateDeposit(
        uint256 _assets,
        address _depositor
    ) internal view {
        require(_assets > 0, "Deposit amount must be greater than zero");
        require(
            ethxToken.allowance(_depositor, address(this)) >= _assets,
            "Insufficient ETHx allowance"
        );
    }

    function _transferEthxToVault(
        uint256 _assets,
        address _depositor
    ) internal {
        ethxToken.transferFrom(_depositor, address(this), _assets);
    }

    /// === HELPER FUNCTIONS FOR WITHDRAW === ///

    function _withdrawFromAave(uint256 _amount) internal {
        pool.withdraw(address(ethxToken), _amount, address(this));
        emit ETHxWithdrawnFromAave(_amount);
    }

    function _validateEthxBalanceAfterWithdrawal(
        uint256 _amount
    ) internal view {
        uint256 ethxBalanceAfterAave = ethxToken.balanceOf(address(this));
        require(
            ethxBalanceAfterAave >= _amount,
            "Insufficient ETHx after Aave withdrawal"
        );
    }

    function _burnSharesAndTransfer(
        uint256 _amount,
        address _receiver,
        address _owner
    ) internal returns (uint256 shares) {
        shares = super.withdraw(_amount, _receiver, _owner);
        emit SharesBurned(_receiver, shares);
    }

    /// === HELPER FUNCTIONS FOR CLAIMING AND COMPOUNDING === ///

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
    function _swapStaderTokensToWETH(
        uint256 _staderAmount
    ) internal returns (uint256 wethAmount) {
        // 1: Approve the swapRouter to spend SD tokens on behalf of the contract
        TransferHelper.safeApprove(
            address(sdToken),
            address(swapRouter),
            _staderAmount
        );

        // 2. Set up parameters for the swap
        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: abi.encodePacked(
                    sdToken,
                    POOLFEE,
                    usdcToken,
                    POOLFEE,
                    wethToken
                ),
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
        // 1. Record the vault's totalAssets and totalSupply before compounding
        uint256 totalAssetsBefore = totalAssets();

        // 2. Unwrap the WETH into ETH
        wethToken.withdraw(wethAmount);
        uint256 ethAmount = wethAmount; // Since WETH is 1:1 convertible to ETH
        require(ethAmount > 0, "Deposit amount must be greater than zero");

        // 3. Stake the ETH into Stader to mint ETHx tokens
        uint256 ethxAmount = stakePoolManager.deposit{value: ethAmount}(
            address(this)
        );
        require(ethxAmount > 0, "Staking ETH failed, no ETHx received");

        // 4. Record the vault's aETHx balance before the deposit
        uint256 aEthxBalanceBefore = aethxToken.balanceOf(address(this));

        // 5. Deposit ETHx tokens into Aave's pool to mint aETHx tokens
        pool.supply(address(ethxToken), ethxAmount, address(this), 0); // No referral code

        // 6. Record the vault's aETHx balance after the deposit
        uint256 aEthxBalanceAfter = aethxToken.balanceOf(address(this));

        // 7. Ensure that the vault received aETHx in exchange
        require(
            aEthxBalanceAfter > aEthxBalanceBefore,
            "No aETHx received from Aave"
        );

        // 8. Ensure that the totalAssets of the vault has increased after compounding
        uint256 totalAssetsAfter = totalAssets();

        require(
            totalAssetsAfter > totalAssetsBefore,
            "Total assets did not increase after compounding"
        );

        // 6. Emit an event to signal compounding success
        emit Compounded(totalAssetsBefore, totalAssetsAfter);
    }

    /// === HELPER FUNCTIONS FOR TESTING === ///

    function claimRewards() external returns (uint256) {
        return _claimRewards();
    }

    function swapStaderTokensToWETH(
        uint256 _staderAmount
    ) external returns (uint256) {
        return _swapStaderTokensToWETH(_staderAmount);
    }

    function depositWETHForCompounding(uint256 _wethAmount) external {
        return _depositWETHForCompounding(_wethAmount);
    }

    /// === HELPER FUNCTIONS FOR WRAPPING / UNWRAPPING ETH === ///

    // payable callback function to unwrap WETH into ETH
    receive() external payable {}

    //// HELPER FUNCTION FOR ADMIN SETUP////

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
