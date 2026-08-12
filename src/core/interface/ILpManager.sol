// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ILpManager {
    event Withdraw(address indexed tokenAddress, address indexed recipient, uint256 amount);
    event LiquidityAdded(uint256 liquidityAdded, uint256 amount0Used, uint256 amount1Used);

    function withdraw(address recipient, uint256 amount) external;
    function addLiquidity(uint256 tokenAmount, uint256 usdtAmount, address to) external;
}
