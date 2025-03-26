// SPDX-License-Identifier:MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MyLeverDex
 * @dev 极简的杠杆交易 DEX 实现，使用虚拟 AMM 机制
 * 支持多头和空头头寸，以及清算机制
 */
contract MyLeverDex {

    uint public vK;  // 常数乘积公式中的常数 K = vETH * vUSDC
    uint public vETHAmount;  // 虚拟 ETH 数量，用于价格发现
    uint public vUSDCAmount; // 虚拟 USDC 数量，用于价格发现

    IERC20 public USDC;  // USDC 代币接口

    /**
     * @dev 用户头寸信息结构体
     * @param margin 保证金，用户提供的真实资金
     * @param borrowed 借入的资金，用于杠杆交易
     * @param position 虚拟 ETH 持仓，正值表示多头，负值表示空头
     * @param entryPrice 开仓价格，用于计算盈亏
     */
    struct PositionInfo {
        uint256 margin;    // 保证金
        uint256 borrowed;  // 借入的资金
        int256 position;   // 虚拟 ETH 持仓
        uint256 entryPrice; // 开仓价格
    }
    
    // 用户地址到持仓信息的映射
    mapping(address => PositionInfo) public positions;

    /**
     * @dev 构造函数
     * @param _usdc USDC 代币地址
     * @param vEth 初始虚拟 ETH 数量
     * @param vUSDC 初始虚拟 USDC 数量
     */
    constructor(address _usdc, uint vEth, uint vUSDC) {
        USDC = IERC20(_usdc);
        vETHAmount = vEth;
        vUSDCAmount = vUSDC;
        vK = vEth * vUSDC; // 初始化常数乘积
    }

    /**
     * @dev 开启杠杆头寸
     * @param _margin 用户提供的保证金
     * @param level 杠杆倍数
     * @param long 是否为多头，true 为多头，false 为空头
     */
    function openPosition(uint256 _margin, uint level, bool long) external {
        // 检查用户是否已有头寸
        require(positions[msg.sender].position == 0, "Position already open");

        // 获取用户头寸存储引用
        PositionInfo storage pos = positions[msg.sender];

        // 转移保证金
        USDC.transferFrom(msg.sender, address(this), _margin);
        
        // 计算总交易金额和借入金额
        uint amount = _margin * level;
        uint256 borrowAmount = amount - _margin;

        // 设置保证金和借入金额
        pos.margin = _margin;
        pos.borrowed = borrowAmount;
        
        // 记录开仓价格 (USDC/ETH)
        pos.entryPrice = vUSDCAmount * 1e18 / vETHAmount;

        // 根据多头或空头调整持仓和虚拟资产
        if (long) {
            // 多头：买入 ETH
            uint256 ethBought = amount * vETHAmount / vUSDCAmount;
            pos.position = int256(ethBought);
            vUSDCAmount += amount; // 增加虚拟 USDC
            vETHAmount -= ethBought; // 减少虚拟 ETH
        } else {
            // 空头：卖出 ETH
            uint256 ethSold = amount * vETHAmount / vUSDCAmount;
            pos.position = -int256(ethSold);
            vUSDCAmount -= amount; // 减少虚拟 USDC
            vETHAmount += ethSold; // 增加虚拟 ETH
        }
    }

    /**
     * @dev 关闭头寸并结算
     * 计算盈亏，返还剩余保证金，并清除头寸
     */
    function closePosition() external {
        // 获取用户头寸存储引用
        PositionInfo storage pos = positions[msg.sender];
        
        // 检查用户是否有头寸
        require(pos.position != 0, "No open position");

        // 计算盈亏
        int256 pnl = calculatePnL(msg.sender);
        
        // 计算应返还的金额
        uint256 returnAmount;
        if (pnl >= 0) {
            // 盈利情况
            returnAmount = pos.margin + uint256(pnl);
        } else if (uint256(-pnl) < pos.margin) {
            // 亏损但未超过保证金
            returnAmount = pos.margin - uint256(-pnl);
        } else {
            // 亏损超过保证金
            returnAmount = 0;
        }

        // 确保返还金额不超过合约余额
        uint256 contractBalance = USDC.balanceOf(address(this));
        if (returnAmount > contractBalance) {
            returnAmount = contractBalance;
        }

        // 更新 vAMM 状态
        if (pos.position > 0) {
            // 多头平仓：卖出 ETH
            uint256 ethAmount = uint256(pos.position);
            uint256 usdcAmount = ethAmount * vUSDCAmount / vETHAmount;
            vETHAmount += ethAmount;
            vUSDCAmount -= usdcAmount;
        } else {
            // 空头平仓：买入 ETH
            uint256 ethAmount = uint256(-pos.position);
            uint256 usdcAmount = ethAmount * vUSDCAmount / vETHAmount;
            vETHAmount -= ethAmount;
            vUSDCAmount += usdcAmount;
        }

        // 转账返还资金
        if (returnAmount > 0) {
            USDC.transfer(msg.sender, returnAmount);
        }

        // 删除用户持仓
        delete positions[msg.sender];
    }

    /**
     * @dev 清算头寸
     * 当用户头寸亏损超过一定阈值时，允许其他用户清算该头寸
     * 清算者获得一定奖励
     * @param _user 被清算用户地址
     */
    function liquidatePosition(address _user) external {
        // 清算人不能是自己
        require(msg.sender != _user, "Cannot liquidate own position");
        
        // 获取用户头寸存储引用
        PositionInfo storage pos = positions[_user];
        
        // 检查用户是否有头寸
        require(pos.position != 0, "No open position");
        
        // 计算盈亏
        int256 pnl = calculatePnL(_user);
        
        // 清算条件：亏损超过保证金的 80%
        require(pnl < -int256(pos.margin * 80 / 100), "Position not eligible for liquidation");

        // 计算清算者获得的奖励（固定为保证金的10%）
        uint256 liquidatorReward = pos.margin / 10;

        // 确保奖励不超过合约余额
        uint256 contractBalance = USDC.balanceOf(address(this));
        if (liquidatorReward > contractBalance) {
            liquidatorReward = contractBalance;
        }

        // 更新 vAMM 状态
        if (pos.position > 0) {
            // 多头平仓
            uint256 ethAmount = uint256(pos.position);
            uint256 usdcAmount = ethAmount * vUSDCAmount / vETHAmount;
            vETHAmount += ethAmount;
            vUSDCAmount -= usdcAmount;
        } else {
            // 空头平仓
            uint256 ethAmount = uint256(-pos.position);
            uint256 usdcAmount = ethAmount * vUSDCAmount / vETHAmount;
            vETHAmount -= ethAmount;
            vUSDCAmount += usdcAmount;
        }

        // 转账奖励给清算者
        if (liquidatorReward > 0) {
            USDC.transfer(msg.sender, liquidatorReward);
        }

        // 删除用户持仓
        delete positions[_user];
    }

    /**
     * @dev 计算用户头寸的盈亏
     * @param user 用户地址
     * @return 盈亏金额，正值表示盈利，负值表示亏损
     */
    function calculatePnL(address user) public view returns (int256) {
        PositionInfo memory pos = positions[user];
        if (pos.position == 0) return 0;
        
        // 计算当前价格 (USDC/ETH)
        uint256 currentPrice = vUSDCAmount * 1e18 / vETHAmount;
        
        int256 pnl;
        if (pos.position > 0) {
            // 多头：当前价格上涨则盈利，下跌则亏损
            if (currentPrice > pos.entryPrice) {
                // 价格上涨，盈利
                pnl = int256(uint256(pos.position) * (currentPrice - pos.entryPrice) / 1e18);
            } else {
                // 价格下跌，亏损
                pnl = -int256(uint256(pos.position) * (pos.entryPrice - currentPrice) / 1e18);
            }
        } else {
            // 空头：当前价格下跌则盈利，上涨则亏损
            if (currentPrice < pos.entryPrice) {
                // 价格下跌，盈利
                pnl = int256(uint256(-pos.position) * (pos.entryPrice - currentPrice) / 1e18);
            } else {
                // 价格上涨，亏损
                pnl = -int256(uint256(-pos.position) * (currentPrice - pos.entryPrice) / 1e18);
            }
        }
        
        return pnl;
    }
}