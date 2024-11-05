// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interface for Stader's configuration contract
interface IStaderConfig {
    function getStakePoolManager() external view returns (address);
    function getETHxToken() external view returns (address);
    function getUserWithdrawManager() external view returns (address);
}
