// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IInvestingNFT {
    function recordInvestFromSwap(address user, uint256 amount) external;
    function investAccumulated(address user) external view returns (uint256);
}
