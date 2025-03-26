// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../src/MyLeverDex.sol";

/**
 * @title TestMyLeverDex
 * @dev 用于测试的 DEX 合约，继承自 MyLeverDex 并添加了测试辅助函数
 * 这些辅助函数仅用于测试目的，不应在生产环境中使用
 */
contract TestMyLeverDex is MyLeverDex {
    /**
     * @dev 构造函数
     * @param _usdc USDC 代币地址
     * @param vEth 初始虚拟 ETH 数量
     * @param vUSDC 初始虚拟 USDC 数量
     */
    constructor(address _usdc, uint vEth, uint vUSDC) MyLeverDex(_usdc, vEth, vUSDC) {}

    /**
     * @dev 设置虚拟资产数量，用于测试不同的市场条件
     * @param _vETH 新的虚拟 ETH 数量
     * @param _vUSDC 新的虚拟 USDC 数量
     * 注意：这会改变 vK 常数，模拟外部市场影响
     */
    function setVirtualAmounts(uint _vETH, uint _vUSDC) external {
        vETHAmount = _vETH;
        vUSDCAmount = _vUSDC;
        vK = _vETH * _vUSDC; // 更新常数乘积
    }
} 