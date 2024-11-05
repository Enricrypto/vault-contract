// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interface for Stader's user withdrawal manager
interface IUserWithdrawalManager {
    function requestWithdraw(
        uint256 _amountInETHx,
        address _owner
    ) external returns (uint256);
    function claim(uint256 _requestId) external;
    function userWithdrawRequests(
        uint256 _requestId
    ) external view returns (address, address, address, uint256, uint256);
}
