// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interface for Stader's stake pool manager
interface IStaderStakePoolManager {
    function deposit(address _receiver) external payable returns (uint256);
}
