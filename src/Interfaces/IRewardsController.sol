// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRewardsController {
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        address reward
    ) external returns (uint256);
}
