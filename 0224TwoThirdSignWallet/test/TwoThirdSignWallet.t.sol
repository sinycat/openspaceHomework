// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TwoThirdSignWallet.sol";

contract TwoThirdSignWalletTest is Test {
    TwoThirdSignWallet public wallet;
    
    address public owner1;
    address public owner2;
    address public owner3;
    address public nonOwner;
    
    uint256 public initialBalance = 10 ether;
    
    // 测试用的接收合约
    address public receiver;
    
    function setUp() public {
        // 设置测试账户
        owner1 = makeAddr("owner1");
        owner2 = makeAddr("owner2");
        owner3 = makeAddr("owner3");
        nonOwner = makeAddr("nonOwner");
        receiver = makeAddr("receiver");
        
        // 部署多签钱包合约
        address[3] memory owners = [owner1, owner2, owner3];
        wallet = new TwoThirdSignWallet(owners);
        
        // 向钱包转入初始资金
        vm.deal(address(wallet), initialBalance);
    }
    
    // 测试构造函数和初始状态
    function testInitialState() public view {
        // 验证所有者设置正确
        address[3] memory owners = wallet.getOwners();
        assertEq(owners[0], owner1);
        assertEq(owners[1], owner2);
        assertEq(owners[2], owner3);
        
        // 验证所有者映射正确
        assertTrue(wallet.isOwner(owner1));
        assertTrue(wallet.isOwner(owner2));
        assertTrue(wallet.isOwner(owner3));
        assertFalse(wallet.isOwner(nonOwner));
        
        // 验证交易计数为0
        assertEq(wallet.getTransactionCount(), 0);
        
        // 验证钱包余额
        assertEq(address(wallet).balance, initialBalance);
    }
    
    // 测试提交交易
    function testSubmitTransaction() public {
        // 切换到owner1
        vm.startPrank(owner1);
        
        // 提交一个转账交易
        uint256 txIndex = wallet.submitTransaction(receiver, 1 ether, "");
        
        // 验证交易计数增加
        assertEq(wallet.getTransactionCount(), 1);
        
        // 获取交易详情并验证
        (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations) = wallet.getTransaction(txIndex);
        
        assertEq(to, receiver);
        assertEq(value, 1 ether);
        assertEq(data.length, 0);
        assertFalse(executed);
        assertEq(numConfirmations, 1); // 提交者自动确认
        
        // 验证提交者已确认
        assertTrue(wallet.isConfirmed(txIndex, owner1));
        
        vm.stopPrank();
    }
    
    // 测试确认交易
    function testConfirmTransaction() public {
        // 先提交一个交易
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(receiver, 1 ether, "");
        
        // owner2确认交易
        vm.prank(owner2);
        wallet.confirmTransaction(txIndex);
        
        // 验证确认状态
        (,,,, uint256 numConfirmations) = wallet.getTransaction(txIndex);
        assertEq(numConfirmations, 2);
        assertTrue(wallet.isConfirmed(txIndex, owner1));
        assertTrue(wallet.isConfirmed(txIndex, owner2));
        assertFalse(wallet.isConfirmed(txIndex, owner3));
    }
    
    // 测试执行交易
    function testExecuteTransaction() public {
        // 记录初始余额
        uint256 initialReceiverBalance = receiver.balance;
        
        // 提交并确认交易
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(receiver, 1 ether, "");
        
        vm.prank(owner2);
        wallet.confirmTransaction(txIndex);
        
        // 执行交易
        vm.prank(owner3);
        wallet.executeTransaction(txIndex);
        
        // 验证交易已执行
        (,,, bool executed,) = wallet.getTransaction(txIndex);
        assertTrue(executed);
        
        // 验证资金已转移
        assertEq(receiver.balance, initialReceiverBalance + 1 ether);
        assertEq(address(wallet).balance, initialBalance - 1 ether);
    }
    
    // 测试撤销确认
    function testRevokeConfirmation() public {
        // 提交并确认交易
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(receiver, 1 ether, "");
        
        vm.prank(owner2);
        wallet.confirmTransaction(txIndex);
        
        // 验证确认数
        (,,,, uint256 numConfirmations) = wallet.getTransaction(txIndex);
        assertEq(numConfirmations, 2);
        
        // owner1撤销确认
        vm.prank(owner1);
        wallet.revokeConfirmation(txIndex);
        
        // 验证确认已撤销
        (,,,, numConfirmations) = wallet.getTransaction(txIndex);
        assertEq(numConfirmations, 1);
        assertFalse(wallet.isConfirmed(txIndex, owner1));
        assertTrue(wallet.isConfirmed(txIndex, owner2));
    }
    
    // 测试非所有者无法提交交易
    function testNonOwnerCannotSubmitTransaction() public {
        vm.prank(nonOwner);
        vm.expectRevert("not owner");
        wallet.submitTransaction(receiver, 1 ether, "");
    }
    
    // 测试确认数不足无法执行交易
    function testCannotExecuteWithInsufficientConfirmations() public {
        // 只有一个确认
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(receiver, 1 ether, "");
        
        // 尝试执行
        vm.prank(owner1);
        vm.expectRevert("insufficient confirmations");
        wallet.executeTransaction(txIndex);
    }
    
    // 测试交易执行后无法再次执行
    function testCannotExecuteTwice() public {
        // 提交并确认交易
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(receiver, 1 ether, "");
        
        vm.prank(owner2);
        wallet.confirmTransaction(txIndex);
        
        // 执行交易
        vm.prank(owner3);
        wallet.executeTransaction(txIndex);
        
        // 尝试再次执行
        vm.prank(owner1);
        vm.expectRevert("transaction executed");
        wallet.executeTransaction(txIndex);
    }
    
    // 测试已确认的交易不能重复确认
    function testCannotConfirmTwice() public {
        // 提交交易
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(receiver, 1 ether, "");
        
        // 尝试再次确认
        vm.prank(owner1);
        vm.expectRevert("transaction confirmed");
        wallet.confirmTransaction(txIndex);
    }
    
    // 测试接收ETH功能
    function testReceiveEth() public {
        uint256 amount = 1 ether;
        uint256 beforeBalance = address(wallet).balance;
        
        // 向钱包发送ETH
        vm.deal(address(this), amount);
        (bool success,) = address(wallet).call{value: amount}("");
        assertTrue(success);
        
        // 验证余额增加
        assertEq(address(wallet).balance, beforeBalance + amount);
    }
} 