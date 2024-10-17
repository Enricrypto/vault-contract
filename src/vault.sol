// SPDX-License-Identifier: MIT

// OpenZeppelin's ERC-4626 and ERC-20 contracts
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC4626/ERC4626.sol";

// Aave V3 Pool interface for deposit/withdraw functionality
import "@aave/core-v3/contracts/interfaces/IPool.sol";

// Interface for WETH (for wrapping/unwrapping ETH)
import "@aave/core-v3/contracts/dependencies/weth/WETH9.sol";
