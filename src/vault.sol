// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// OpenZeppelin's ERC-4626 and ERC-20 contracts
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

// Aave V3 Pool interface for deposit/withdraw functionality
import "lib/aave-v3-core/contracts/interfaces/IPool.sol";

// Interface for WETH (for wrapping/unwrapping ETH)
import "lib/aave-v3-core/contracts/dependencies/weth/WETH9.sol";

contract Vault is ERC4626 {
    IPool public pool; // for reference to the Aave pool interface for deposits and withdrawals.
    WETH9 public weth; // for  reference to the WETH contract, allows to wrap/unwrap Ether.
    address public wethAddress; // stores the address of the WETH contract on the blockchain.
    address public poolAddress; // stores the Aave pool contract address.
    address public aWethAddress;

    // vault will be working with WETH as the underlying asset. It allows the vault to manage WETH in accordance with the ERC-4626 standard.
    constructor(
        address _poolAddress,
        address payable _wethAddress
    )
        ERC20("My Vault", "VLT") // Call the ERC20 constructor for name and symbol
        ERC4626(IERC20(_wethAddress)) // Call the ERC4626 constructor with the underlying asset (WETH)
    {
        pool = IPool(_poolAddress); // Initialize the Aave pool interface.
        weth = WETH9(_wethAddress); // Initialize the WETH contract.
        wethAddress = _wethAddress; // Store the WETH contract address.
        poolAddress = _poolAddress; // Store the Aave pool address.

        // Dynamically retrieve the aWETH address from Aave's Pool
        aWethAddress = pool.getReserveData(_wethAddress).aTokenAddress;
    }

    // Receive ETH and wrap is as WETH
    receive() external payable {
        weth.deposit{value: msg.value}(); // calls the deposit function of the WETH contract, which is responsible for converting ETH into WETH
    }

    function deposit(
        uint256 amount,
        address receiver
    ) public override returns (uint256 shares) {
        // Approve the Aave pool to spend WETH
        weth.approve(address(pool), amount);

        // Deposit WETH into Aaave
        // wethAddress is the ERC20 token that is being supplied, address of the WETH token
        pool.supply(wethAddress, amount, address(this), 0); // 0 is the referral code that we are not using in this case.

        // Call ERC4626 to mint shares for the user
        // Aave issues aTokens(shares) that represent the vault's share and accrued interest
        // super is used to call a function from the parent contract in this case from the ERC4626 contract
        // using it because I'm overriding the deposit function in the contract but still want to invoke the original logic from the parent contract ERC4626.
        shares = super.deposit(amount, receiver);

        return shares;
    }

    function withdraw(
        uint256 amount, // Amount of WETH (or underlying ETH) to withdraw
        address receiver, // Address that will receive the ETH
        address owner // Address whose shares are being redeemed
    ) public override returns (uint256 shares) {
        // calculate and burn shares
        shares = previewWithdraw(amount); // previewWithdraw is a function from the ERC4626 contract.

        // Burn vault shares from the owner (handled by the ERC4626 implementation)
        _burn(owner, shares);

        // withdraw WETH from Aave's pool. Withdraw is a function from the Aave's contract.
        pool.withdraw(wethAddress, amount, address(this));

        // Unwrap WETH back to ETH
        weth.withdraw(amount);

        // Transfer ETH to receiver
        // call is a low-level function in Solidity that can be used to send ETH and interact with another contract or address.
        (bool success, ) = receiver.call{value: amount}(""); // ('') means not additional data is being sent, just ETH.
        require(success, "ETH transfer failed");

        return shares;
    }

    function totalAssets() public view override returns (uint256) {
        // Assets that are held in the vault and may be deposited into Aave soon.
        uint256 wethBalance = weth.balanceOf(address(this));

        // Assets that are already deposited into Aave and accruing interest.
        uint256 aWethBalance = IERC20(aWethAddress).balanceOf(address(this));

        // total assets = WETH in vault + ETH in Aave (represented by aWETH)
        return wethBalance + aWethBalance;
    }
}
