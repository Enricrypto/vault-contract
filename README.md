## WETH Vault Contract
This repository contains a smart contract that implements a vault for handling deposits and withdrawals of WETH (Wrapped Ether) while interacting with the Aave V3 protocol. The vault follows the ERC-4626 standard for tokenized vaults, enabling users to deposit ETH, receive shares, and earn interest by supplying liquidity to Aave. The contract wraps and unwraps ETH into WETH automatically, and it accrues interest by interacting with Aave's liquidity pool for WETH.

## Features
ERC-4626 Tokenized Vault: Implements the ERC-4626 standard for yield-bearing vaults.
ETH to WETH Conversion: Automatically wraps ETH to WETH on deposits and unwraps it on withdrawals.
Aave V3 Integration: Deposits WETH into Aave and receives aWETH tokens, which accrue interest over time.
Non-reentrant Design: Uses OpenZeppelin's ReentrancyGuard to prevent reentrancy attacks.

## Contract Overview
Vault.sol
The main vault contract interacts with WETH and Aave V3. Key features include:

WETH Wrapping: Accepts ETH deposits, automatically converting them into WETH using the WETH contract.
Aave Deposits: Deposits WETH into Aave and receives aWETH, which represents the deposited WETH and its accrued interest.
Withdrawals: Users can withdraw WETH or ETH, with the corresponding aWETH being burned from the vault and WETH being returned from Aave.
Key Functions
deposit(uint256 amount, address receiver): Deposits WETH into Aave and mints vault shares for the user based on the deposited amount.
withdraw(uint256 amount, address receiver, address owner): Withdraws WETH from Aave, unwraps it to ETH, and transfers it to the receiver. The vault shares corresponding to the withdrawn amount are burned.
totalAssets(): Returns the total amount of WETH held by the vault, which includes both the WETH held in the contract and the aWETH deposited in Aave.

## Dependencies
The contract uses the following dependencies:

OpenZeppelin Contracts: Provides the base ERC-4626 implementation and security utilities like ReentrancyGuard.
Aave V3 Protocol: Interacts with Aave's pool to deposit and withdraw WETH.
WETH9 Contract: Handles the wrapping and unwrapping of ETH into WETH.
**These are imported from:**

OpenZeppelin
Aave V3 Core
Installation
To get started, clone the repository and install the dependencies:

bash
Copy code
git clone https://github.com/enricrypto/weth-vault-contract.git
cd weth-vault-contract
forge install
If you're using Hardhat for testing or deployment, make sure you have Node.js and Hardhat installed:

bash
Copy code
npm install
Deploying the Contract
Ensure you have an Ethereum development environment such as Hardhat or Foundry (with forge).
Modify the constructor parameters (Aave Pool Address and WETH Address) in the deployment script or directly in the contract if necessary.
For deploying the contract via Forge:

bash
Copy code
forge create Vault --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
Testing
The contract can be tested using Forge or Hardhat. Make sure you have configured a local network or forked mainnet to simulate interaction with Aave.

## To run tests:

bash
Copy code
forge test
You can write additional unit tests to ensure the correctness of the vault contract, including:

Deposit and Withdrawal: Test the correct minting and burning of vault shares during deposits and withdrawals.
Total Assets Calculation: Ensure that the vault correctly calculates the total assets, including WETH held directly and in Aave.
Aave Interaction: Ensure the contract interacts correctly with Aave to supply and withdraw WETH.
How it Works
Deposits: Users deposit ETH, which is automatically wrapped into WETH and deposited into Aave. Users receive shares in exchange, representing their claim to the assets.

Earning Interest: As long as WETH remains in Aave, users earn interest on their deposits. The accrued interest is reflected in the increasing value of their shares.

Withdrawals: Users can redeem their shares for WETH or ETH. When withdrawing, the contract unwraps WETH back into ETH if necessary.

## License
This project is licensed under the MIT License.

Feel free to customize this README to better fit your specific requirements!


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

TASKS
1) Use ERC-4626 as the base vault structure (OpenZeppelin’s implementation).✅
2) Override the deposit, withdraw, and totalAssets functions to interact with Aave’s ETHx market. ✅
3) The vault should handle ETH wrapping (since ETH needs to be wrapped into WETH for Aave).✅
4) Interact with Aave's Pool contract to deposit and withdraw assets. ✅

NEW TASKS
1) use the EthX market instead of weth ✅
2) add another function to compound rewards ✅
3) that function should claim the stader token ✅ 
Sell SD token for ETH, stake ETH for ETHx on Stader and then stake it on Aave
4) function that uses uniswapV3 to sell the Stader token for ETH/USDC ✅ 
5) use vm.warp or similar to manipulate time on your fork tests so you get enough rewards in your test 

** issue when overiding the deposit function from the ERC4626, as it's non payable and I need a payable function **