// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/StakingPool.sol";
import "../src/KKToken.sol";

contract StakingPoolTest is Test {
    StakingPool public stakingPool;
    KKToken public kkToken;

    address constant USER1 = address(0x1);
    address constant USER2 = address(0x2);
    address constant USER3 = address(0x3);
    address constant USER4 = address(0x4);
    address constant USER5 = address(0x5);

    function setUp() public {
        // 部署合约
        kkToken = new KKToken();
        stakingPool = new StakingPool(address(kkToken));
        
        // 设置质押池地址，允许质押池铸造代币
        kkToken.setStakingPool(address(stakingPool));
        
        // 给测试用户一些ETH
        vm.deal(USER1, 100 ether);
        vm.deal(USER2, 100 ether);
        vm.deal(USER3, 100 ether);
        vm.deal(USER4, 100 ether);
        vm.deal(USER5, 100 ether);
    }

    // 辅助函数：触发奖励更新
    function updateRewards(address user) internal {
        vm.prank(user);
        stakingPool.stake{value: 0}();
    }

    // 基本质押测试
    function testBasicStake() public {
        uint256 stakeAmount = 10 ether;
        
        // 确认初始状态
        assertEq(stakingPool.balanceOf(USER1), 0, "Initial stake should be 0");
        
        // USER1质押ETH
        vm.startPrank(USER1);
        uint256 initialBalance = USER1.balance;
        stakingPool.stake{value: stakeAmount}();
        vm.stopPrank();
        
        // 验证质押结果
        assertEq(USER1.balance, initialBalance - stakeAmount, "ETH balance should decrease");
        assertEq(stakingPool.balanceOf(USER1), stakeAmount, "Staked balance should match");
        assertEq(stakingPool.totalStaked(), stakeAmount, "Total staked should match");
    }

    // 基本赎回测试
    function testBasicUnstake() public {
        uint256 stakeAmount = 10 ether;
        uint256 unstakeAmount = 5 ether;
        
        // USER1质押ETH
        vm.startPrank(USER1);
        stakingPool.stake{value: stakeAmount}();
        uint256 initialBalance = USER1.balance;
        
        // 前进10个区块
        vm.roll(block.number + 10);
        
        // USER1取回部分质押
        stakingPool.unstake(unstakeAmount);
        vm.stopPrank();
        
        // 验证取回结果
        assertEq(USER1.balance, initialBalance + unstakeAmount, "ETH should be returned");
        assertEq(stakingPool.balanceOf(USER1), stakeAmount - unstakeAmount, "Remaining staked balance should match");
        assertEq(stakingPool.totalStaked(), stakeAmount - unstakeAmount, "Total staked should decrease");
    }

    // 多次质押测试
    function testMultipleStakes() public {
        vm.startPrank(USER1);
        
        // 第一次质押
        uint256 stakeAmount1 = 5 ether;
        stakingPool.stake{value: stakeAmount1}();
        
        // 前进10个区块
        vm.roll(block.number + 10);
        
        // 第二次质押，此时应该获得奖励
        uint256 stakeAmount2 = 7 ether;
        stakingPool.stake{value: stakeAmount2}();
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // 第三次质押，再次获得奖励
        uint256 stakeAmount3 = 3 ether;
        stakingPool.stake{value: stakeAmount3}();
        
        vm.stopPrank();
        
        // 验证总质押金额
        assertEq(stakingPool.balanceOf(USER1), 15 ether, "Total staked should be 15 ETH");
        assertEq(stakingPool.totalStaked(), 15 ether, "Total staked should be 15 ETH");
        
        // 验证获得的奖励
        uint256 tokenBalance = kkToken.balanceOf(USER1);
        assertEq(tokenBalance, 148, "USER1 should have received 148 tokens");
    }

    // 多次赎回测试
    function testMultipleUnstakes() public {
        vm.startPrank(USER1);
        
        // 质押20 ETH
        stakingPool.stake{value: 20 ether}();
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // 第一次赎回
        stakingPool.unstake(5 ether);
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // 第二次赎回
        stakingPool.unstake(7 ether);
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // 第三次赎回
        stakingPool.unstake(3 ether);
        
        vm.stopPrank();
        
        // 验证剩余质押金额
        assertEq(stakingPool.balanceOf(USER1), 5 ether, "Remaining stake should be 5 ETH");
        assertEq(stakingPool.totalStaked(), 5 ether, "Total staked should be 5 ETH");
        
        // 验证获得的奖励
        uint256 tokenBalance = kkToken.balanceOf(USER1);
        assertEq(tokenBalance, 133, "USER1 should have received 133 tokens");
    }

    // 多用户同时质押测试
    function testMultipleUsersStakingSimultaneously() public {
        // 5个用户同时质押不同金额
        vm.prank(USER1);
        stakingPool.stake{value: 10 ether}();
        
        vm.prank(USER2);
        stakingPool.stake{value: 20 ether}();
        
        vm.prank(USER3);
        stakingPool.stake{value: 15 ether}();
        
        vm.prank(USER4);
        stakingPool.stake{value: 5 ether}();
        
        vm.prank(USER5);
        stakingPool.stake{value: 30 ether}();
        
        // 验证总质押金额
        assertEq(stakingPool.totalStaked(), 80 ether, "Total staked should be 80 ETH");
        
        // 前进10个区块
        vm.roll(block.number + 10);
        
        // 触发所有用户的奖励更新
        updateRewards(USER1);
        updateRewards(USER2);
        updateRewards(USER3);
        updateRewards(USER4);
        updateRewards(USER5);
        
        // 计算总奖励
        uint256 totalRewards = kkToken.balanceOf(USER1) + 
                              kkToken.balanceOf(USER2) + 
                              kkToken.balanceOf(USER3) + 
                              kkToken.balanceOf(USER4) + 
                              kkToken.balanceOf(USER5);
        
        // 验证总奖励
        assertEq(totalRewards, 80, "Total rewards should be 80 tokens");
    }

    // 多用户交替质押和赎回测试
    function testAlternatingStakesAndUnstakes() public {
        // USER1质押
        vm.prank(USER1);
        stakingPool.stake{value: 10 ether}();
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // USER2质押
        vm.prank(USER2);
        stakingPool.stake{value: 20 ether}();
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // USER1赎回一部分
        vm.prank(USER1);
        stakingPool.unstake(5 ether);
        
        // 验证USER1的奖励
        uint256 reward1 = kkToken.balanceOf(USER1);
        assertApproxEqAbs(reward1, 60, 3, "USER1 reward calculation");
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // USER3质押
        vm.prank(USER3);
        stakingPool.stake{value: 15 ether}();
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // USER2赎回一部分
        vm.prank(USER2);
        stakingPool.unstake(10 ether);
        
        // 验证USER2的奖励
        uint256 reward2 = kkToken.balanceOf(USER2);
        assertApproxEqAbs(reward2, 80, 3, "USER2 reward calculation");
    }

    // 全部赎回测试
    function testFullUnstake() public {
        // USER1质押
        vm.startPrank(USER1);
        stakingPool.stake{value: 10 ether}();
        
        // 前进10个区块
        vm.roll(block.number + 10);
        
        // 全部赎回
        stakingPool.unstake(10 ether);
        vm.stopPrank();
        
        // 验证质押金额为0
        assertEq(stakingPool.balanceOf(USER1), 0, "USER1 should have 0 ETH staked");
        assertEq(stakingPool.totalStaked(), 0, "Total staked should be 0 ETH");
        
        // 验证奖励
        uint256 tokenBalance = kkToken.balanceOf(USER1);
        assertEq(tokenBalance, 100, "USER1 should have received 100 tokens");
    }

    // 零质押测试
    function testZeroStake() public {
        // 尝试零质押
        vm.prank(USER1);
        stakingPool.stake{value: 0}();
        
        // 验证质押金额为0
        assertEq(stakingPool.balanceOf(USER1), 0, "USER1 should have 0 ETH staked");
        assertEq(stakingPool.totalStaked(), 0, "Total staked should be 0 ETH");
    }

    // 尝试超额赎回测试
    function testOverUnstake() public {
        // USER1质押
        vm.startPrank(USER1);
        stakingPool.stake{value: 5 ether}();
        
        // 尝试超额赎回
        vm.expectRevert("Insufficient balance");
        stakingPool.unstake(10 ether);
        vm.stopPrank();
        
        // 验证质押金额未变
        assertEq(stakingPool.balanceOf(USER1), 5 ether, "USER1 should still have 5 ETH staked");
        assertEq(stakingPool.totalStaked(), 5 ether, "Total staked should still be 5 ETH");
    }

    // 测试复杂的质押模式
    function testComplexStakingPattern() public {
        // 第1轮：USER1和USER2质押
        vm.prank(USER1);
        stakingPool.stake{value: 10 ether}();
        
        vm.prank(USER2);
        stakingPool.stake{value: 15 ether}();
        
        // 前进3个区块
        vm.roll(block.number + 3);
        
        // 第2轮：USER3质押，USER1增加质押
        vm.prank(USER3);
        stakingPool.stake{value: 20 ether}();
        
        vm.prank(USER1);
        stakingPool.stake{value: 5 ether}();
        
        // 前进3个区块
        vm.roll(block.number + 3);
        
        // 第3轮：USER2和USER3部分赎回
        vm.prank(USER2);
        stakingPool.unstake(5 ether);
        
        vm.prank(USER3);
        stakingPool.unstake(10 ether);
        
        // 第4轮：USER4和USER5质押
        vm.prank(USER4);
        stakingPool.stake{value: 12 ether}();
        
        vm.prank(USER5);
        stakingPool.stake{value: 8 ether}();
        
        // 前进3个区块
        vm.roll(block.number + 3);
        
        // 第5轮：USER1部分赎回，USER3部分赎回
        vm.prank(USER1);
        stakingPool.unstake(7 ether);
        
        vm.prank(USER3);
        stakingPool.unstake(10 ether);
        
        // 前进3个区块
        vm.roll(block.number + 3);
        
        // 第6轮：所有用户增加质押
        vm.prank(USER1);
        stakingPool.stake{value: 3 ether}();
        
        vm.prank(USER2);
        stakingPool.stake{value: 2 ether}();
        
        vm.prank(USER3);
        stakingPool.stake{value: 5 ether}();
        
        vm.prank(USER4);
        stakingPool.stake{value: 4 ether}();
        
        vm.prank(USER5);
        stakingPool.stake{value: 6 ether}();
        
        // 验证最终质押金额
        assertEq(stakingPool.balanceOf(USER1), 11 ether, "USER1 final stake incorrect");
        assertEq(stakingPool.balanceOf(USER2), 12 ether, "USER2 final stake incorrect");
        assertEq(stakingPool.balanceOf(USER3), 5 ether, "USER3 final stake incorrect");
        assertEq(stakingPool.balanceOf(USER4), 16 ether, "USER4 final stake incorrect");
        assertEq(stakingPool.balanceOf(USER5), 14 ether, "USER5 final stake incorrect");
        
        // 计算总质押金额
        uint256 totalStaked = stakingPool.balanceOf(USER1) + 
                             stakingPool.balanceOf(USER2) + 
                             stakingPool.balanceOf(USER3) + 
                             stakingPool.balanceOf(USER4) + 
                             stakingPool.balanceOf(USER5);
        
        assertEq(stakingPool.totalStaked(), totalStaked, "Total staked incorrect");
    }

    // 测试未分配奖励的处理
    function testUnallocatedRewards() public {
        // 前进10个区块，此时没有人质押
        vm.roll(block.number + 10);
        
        // USER1质押
        vm.prank(USER1);
        stakingPool.stake{value: 10 ether}();
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // USER2质押
        vm.prank(USER2);
        stakingPool.stake{value: 10 ether}();
        
        // 验证USER1获得了所有未分配的奖励
        updateRewards(USER1);
        uint256 reward1 = kkToken.balanceOf(USER1);
        assertEq(reward1, 250, "USER1 should receive 250 tokens (200 unallocated + 50 direct)");
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // 验证USER1和USER2平分这5个区块的奖励
        updateRewards(USER1);
        updateRewards(USER2);
        
        uint256 newReward1 = kkToken.balanceOf(USER1) - reward1;
        uint256 reward2 = kkToken.balanceOf(USER2);
        
        assertEq(newReward1, 20, "USER1 should receive 20 more tokens");
        assertEq(reward2, 20, "USER2 should receive 20 tokens");
    }

    // 测试所有用户都赎回后的情况
    function testAllUsersUnstake() public {
        // 多用户质押
        vm.prank(USER1);
        stakingPool.stake{value: 10 ether}();
        
        vm.prank(USER2);
        stakingPool.stake{value: 15 ether}();
        
        vm.prank(USER3);
        stakingPool.stake{value: 20 ether}();
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // 所有用户赎回
        vm.prank(USER1);
        stakingPool.unstake(10 ether);
        
        vm.prank(USER2);
        stakingPool.unstake(15 ether);
        
        vm.prank(USER3);
        stakingPool.unstake(20 ether);
        
        // 验证总质押金额为0
        assertEq(stakingPool.totalStaked(), 0, "Total staked should be 0 after all users unstake");
        
        // 前进5个区块
        vm.roll(block.number + 5);
        
        // 新用户质押
        vm.prank(USER4);
        stakingPool.stake{value: 10 ether}();
        
        // 验证新用户获得了所有未分配的奖励
        updateRewards(USER4);
        uint256 reward4 = kkToken.balanceOf(USER4);
        assertEq(reward4, 100, "USER4 should receive 100 tokens (10 blocks * 10/block)");
    }
}