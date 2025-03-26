// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./TestMyLeverDex.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @dev 模拟 USDC 代币，用于测试
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

/**
 * @title MyLeverDexTest
 * @dev MyLeverDex 合约的测试套件
 */
contract MyLeverDexTest is Test {
    TestMyLeverDex public dex;
    MockUSDC public usdc;
    address public owner;
    address public user1;
    address public user2;

    /**
     * @dev 设置测试环境
     */
    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        
        // 部署模拟的 USDC 代币
        usdc = new MockUSDC();
        
        // 部署测试 DEX 合约
        dex = new TestMyLeverDex(address(usdc), 1000 * 10**18, 1000 * 10**18);
        console.log("Initial ETH price:", dex.vUSDCAmount() * 1e18 / dex.vETHAmount());
        
        // 给测试用户分配 USDC
        usdc.transfer(user1, 1000 * 10**18);
        usdc.transfer(user2, 1000 * 10**18);
    }

    /**
     * @dev 测试开启多头头寸
     */
    function testOpenLongPosition() public {
        console.log("\n--- Testing Open Long Position ---");
        
        // 用户1开启多头头寸
        vm.startPrank(user1);
        usdc.approve(address(dex), 100 * 10**18);
        dex.openPosition(100 * 10**18, 2, true);
        vm.stopPrank();

        // 验证头寸信息
        (uint256 margin, uint256 borrowed, int256 position, uint256 entryPrice) = dex.positions(user1);
        console.log("Position opened:");
        console.log("- Margin:", margin);
        console.log("- Position size:", int(position));
        console.log("- Entry price:", entryPrice);
        
        assertEq(margin, 100 * 10**18);
        assertEq(borrowed, 100 * 10**18);
        assertTrue(position > 0);
    }

    /**
     * @dev 测试开启空头头寸
     */
    function testOpenShortPosition() public {
        console.log("\n--- Testing Open Short Position ---");
        
        // 用户1开启空头头寸
        vm.startPrank(user1);
        usdc.approve(address(dex), 100 * 10**18);
        dex.openPosition(100 * 10**18, 2, false);
        vm.stopPrank();

        // 验证头寸信息
        (uint256 margin, uint256 borrowed, int256 position, uint256 entryPrice) = dex.positions(user1);
        console.log("Position opened:");
        console.log("- Margin:", margin);
        console.log("- Position size:", int(position));
        console.log("- Entry price:", entryPrice);
        
        assertEq(margin, 100 * 10**18);
        assertEq(borrowed, 100 * 10**18);
        assertTrue(position < 0);
    }

    /**
     * @dev 测试关闭头寸
     */
    function testClosePosition() public {
        console.log("\n--- Testing Close Position ---");
        
        // 用户1开启多头头寸
        vm.startPrank(user1);
        usdc.approve(address(dex), 100 * 10**18);
        dex.openPosition(100 * 10**18, 2, true);
        
        // 记录关闭头寸前的余额
        uint256 balanceBefore = usdc.balanceOf(user1);
        
        // 关闭头寸
        dex.closePosition();
        vm.stopPrank();

        // 验证头寸已关闭
        (uint256 margin, , int256 position, ) = dex.positions(user1);
        uint256 balanceAfter = usdc.balanceOf(user1);
        
        console.log("Position closed:");
        console.log("- USDC returned:", balanceAfter - balanceBefore);
        
        assertEq(margin, 0);
        assertEq(position, 0);
        assertTrue(balanceAfter >= balanceBefore);
    }

    /**
     * @dev 测试清算头寸
     */
    function testLiquidatePosition() public {
        console.log("\n--- Testing Liquidate Position ---");
        
        // 用户1开启多头头寸
        vm.startPrank(user1);
        usdc.approve(address(dex), 100 * 10**18);
        dex.openPosition(100 * 10**18, 2, true);
        vm.stopPrank();

        // 记录初始余额
        uint256 initialBalance = usdc.balanceOf(user2);
        
        // 模拟市场波动 - ETH 价格大幅下跌，使多头头寸亏损超过保证金的 80%
        uint256 initialETH = dex.vETHAmount();
        uint256 initialUSDC = dex.vUSDCAmount();
        uint256 initialPrice = initialUSDC * 1e18 / initialETH;
        
        // 将 ETH 价格下跌 90%，使多头头寸亏损严重
        uint256 newETH = initialETH * 10; // ETH 数量增加 10 倍，价格下跌 90%
        uint256 newUSDC = initialUSDC;
        uint256 newPrice = newUSDC * 1e18 / newETH;
        
        // 使用测试辅助函数设置新的价格
        dex.setVirtualAmounts(newETH, newUSDC);
        console.log("Price change: -", (initialPrice - newPrice) * 100 / initialPrice, "%");
        
        // 计算当前盈亏
        int256 pnl = dex.calculatePnL(user1);
        (uint256 margin, , , ) = dex.positions(user1);
        console.log("Current PnL as % of margin:", int(pnl) * 100 / int(margin));
        
        // 用户2清算用户1的头寸
        vm.prank(user2);
        dex.liquidatePosition(user1);

        // 验证清算后用户2获得了奖励
        uint256 finalBalance = usdc.balanceOf(user2);
        uint256 reward = finalBalance - initialBalance;
        console.log("Liquidation reward:", reward);
        
        // 验证用户1的头寸已被清算
        (uint256 marginAfter, , int256 positionAfter, ) = dex.positions(user1);
        
        assertTrue(finalBalance > initialBalance);
        assertEq(marginAfter, 0);
        assertEq(positionAfter, 0);
    }

    /**
     * @dev 测试计算盈亏
     */
    function testCalculatePnL() public {
        console.log("\n--- Testing Calculate PnL ---");
        
        // 用户1开启多头头寸
        vm.startPrank(user1);
        usdc.approve(address(dex), 100 * 10**18);
        dex.openPosition(100 * 10**18, 2, true);
        vm.stopPrank();

        // 计算初始盈亏
        int256 initialPnL = dex.calculatePnL(user1);
        
        // 模拟市场波动 - ETH 价格上涨 50%
        uint256 initialETH = dex.vETHAmount();
        uint256 initialUSDC = dex.vUSDCAmount();
        uint256 initialPrice = initialUSDC * 1e18 / initialETH;
        
        // 设置新的价格 - ETH 价格上涨 50%
        uint256 newETH = initialETH * 2 / 3;  // 减少 ETH 数量，价格上涨
        uint256 newUSDC = initialUSDC;        // 保持 USDC 数量不变
        uint256 newPrice = newUSDC * 1e18 / newETH;
        
        dex.setVirtualAmounts(newETH, newUSDC);
        console.log("Price change: +", (newPrice - initialPrice) * 100 / initialPrice, "%");

        // 计算波动后的盈亏
        int256 finalPnL = dex.calculatePnL(user1);
        (uint256 margin, , , ) = dex.positions(user1);
        console.log("Final PnL as % of margin:", int(finalPnL) * 100 / int(margin));
        
        // 验证盈亏变化 - 多头应该盈利
        assertTrue(finalPnL > initialPnL, "Final PnL should be greater than initial PnL");
    }

    /**
     * @dev 测试重复开仓失败情况
     */
    function test_RevertWhen_OpenPositionTwice() public {
        // 用户1开启多头头寸
        vm.startPrank(user1);
        usdc.approve(address(dex), 200 * 10**18);
        dex.openPosition(100 * 10**18, 2, true);
        
        // 尝试再次开启头寸，应该失败
        vm.expectRevert("Position already open");
        dex.openPosition(100 * 10**18, 2, true);
        vm.stopPrank();
    }

    /**
     * @dev 测试关闭不存在头寸失败情况
     */
    function test_RevertWhen_CloseNonExistentPosition() public {
        // 尝试关闭不存在的头寸，应该失败
        vm.prank(user1);
        vm.expectRevert("No open position");
        dex.closePosition();
    }

    /**
     * @dev 测试清算不符合条件头寸失败情况
     */
    function test_RevertWhen_LiquidateNonEligiblePosition() public {
        // 用户1开启多头头寸
        vm.startPrank(user1);
        usdc.approve(address(dex), 100 * 10**18);
        dex.openPosition(100 * 10**18, 2, true);
        vm.stopPrank();

        // 尝试清算不符合条件的头寸，应该失败
        vm.prank(user2);
        vm.expectRevert("Position not eligible for liquidation");
        dex.liquidatePosition(user1);
    }
}