// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/CallOptionToken.sol";
import "../src/OptionMarket.sol";
import "./mocks/MockERC20.sol";

contract CallOptionTokenTest is Test {
    CallOptionToken public callOption;
    OptionMarket public optionMarket;
    MockERC20 public mockUSDT;
    
    address public owner;
    address public user1;
    address public user2;
    
    uint256 public constant STRIKE_PRICE = 2000 ether; // 行权价格2000 USDT
    uint256 public constant OPTION_PRICE = 100 ether;  // 期权价格100 USDT
    uint256 public constant EXPIRY_DAYS = 30;          // 30天后到期
    uint256 public constant INITIAL_PRICE = 1800 ether; // 初始ETH价格1800 USDT
    
    // 添加 receive 函数以接收 ETH
    receive() external payable {}
    
    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        
        // 给测试账户一些ETH
        vm.deal(owner, 100 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // 部署模拟USDT合约
        mockUSDT = new MockERC20("Mock USDT", "USDT", 18);
        
        // 给测试用户铸造USDT
        mockUSDT.mint(user1, 10000 ether);
        mockUSDT.mint(user2, 10000 ether);
        mockUSDT.mint(owner, 10000 ether);
        
        // 部署期权Token合约，传入模拟USDT地址
        callOption = new CallOptionToken(
            "ETH Call Option",
            "ETHCALL",
            STRIKE_PRICE,
            EXPIRY_DAYS,
            INITIAL_PRICE,
            address(mockUSDT)  // 添加USDT地址参数
        );
        
        // 部署期权市场合约
        optionMarket = new OptionMarket(
            address(callOption),
            address(mockUSDT),
            OPTION_PRICE
        );
    }
    
    function testIssueOptions() public {
        // 发行期权
        uint256 ethAmount = 5 ether;
        callOption.issueOptions{value: ethAmount}();
        
        // 验证期权Token已经铸造给发行方
        assertEq(callOption.balanceOf(owner), ethAmount);
        assertEq(address(callOption).balance, ethAmount);
    }
    
    function testAddLiquidity() public {
        // 先发行期权
        uint256 ethAmount = 5 ether;
        callOption.issueOptions{value: ethAmount}();
        
        // 批准市场合约使用期权Token
        callOption.approve(address(optionMarket), ethAmount);
        mockUSDT.approve(address(optionMarket), 1000 ether);
        
        // 添加流动性
        optionMarket.addLiquidity(ethAmount, 500 ether);
        
        // 验证流动性已添加
        assertEq(callOption.balanceOf(address(optionMarket)), ethAmount);
        assertEq(mockUSDT.balanceOf(address(optionMarket)), 500 ether);
    }
    
    function testBuyOptions() public {
        // 先发行期权并添加流动性
        uint256 ethAmount = 5 ether;
        callOption.issueOptions{value: ethAmount}();
        callOption.approve(address(optionMarket), ethAmount);
        mockUSDT.approve(address(optionMarket), 1000 ether);
        optionMarket.addLiquidity(ethAmount, 500 ether);
        
        // 用户购买期权
        uint256 optionsToBuy = 1 ether;
        uint256 usdtCost = optionsToBuy * OPTION_PRICE / 1 ether;
        
        vm.startPrank(user1);
        mockUSDT.approve(address(optionMarket), usdtCost);
        optionMarket.buyOptions(optionsToBuy);
        vm.stopPrank();
        
        // 验证购买结果
        assertEq(callOption.balanceOf(user1), optionsToBuy);
        assertEq(mockUSDT.balanceOf(address(optionMarket)), 500 ether + usdtCost);
    }
    
    function testSellOptions() public {
        // 先发行期权并添加流动性
        uint256 ethAmount = 5 ether;
        callOption.issueOptions{value: ethAmount}();
        callOption.approve(address(optionMarket), ethAmount);
        mockUSDT.approve(address(optionMarket), 1000 ether);
        optionMarket.addLiquidity(ethAmount, 500 ether);
        
        // 用户购买期权
        uint256 optionsToBuy = 1 ether;
        uint256 usdtCost = optionsToBuy * OPTION_PRICE / 1 ether;
        
        vm.startPrank(user1);
        mockUSDT.approve(address(optionMarket), usdtCost);
        optionMarket.buyOptions(optionsToBuy);
        
        // 用户卖出期权
        callOption.approve(address(optionMarket), optionsToBuy);
        optionMarket.sellOptions(optionsToBuy);
        vm.stopPrank();
        
        // 验证卖出结果
        assertEq(callOption.balanceOf(user1), 0);
        assertEq(mockUSDT.balanceOf(user1), 10000 ether); // 回到初始状态
    }
    
    function testExerciseOption() public {
        // 先发行期权并添加流动性
        uint256 ethAmount = 5 ether;
        callOption.issueOptions{value: ethAmount}();
        callOption.approve(address(optionMarket), ethAmount);
        mockUSDT.approve(address(optionMarket), 1000 ether);
        optionMarket.addLiquidity(ethAmount, 500 ether);
        
        // 用户购买期权
        uint256 optionsToBuy = 1 ether;
        uint256 usdtCost = optionsToBuy * OPTION_PRICE / 1 ether;
        
        vm.startPrank(user1);
        mockUSDT.approve(address(optionMarket), usdtCost);
        optionMarket.buyOptions(optionsToBuy);
        vm.stopPrank();
        
        // 快进到到期日
        vm.warp(block.timestamp + EXPIRY_DAYS * 1 days - 1 hours);
        
        // 用户行权
        vm.startPrank(user1);
        uint256 usdtForExercise = optionsToBuy * STRIKE_PRICE / 1 ether;
        mockUSDT.approve(address(callOption), usdtForExercise);
        
        uint256 user1EthBefore = user1.balance;
        callOption.exercise(optionsToBuy);
        vm.stopPrank();
        
        // 验证行权结果
        assertEq(callOption.balanceOf(user1), 0); // 期权被销毁
        assertEq(user1.balance - user1EthBefore, optionsToBuy); // 获得了ETH
    }
    
    function testExpireOptions() public {
        // 先发行期权
        uint256 ethAmount = 5 ether;
        callOption.issueOptions{value: ethAmount}();
        
        // 快进到到期日之后
        vm.warp(block.timestamp + EXPIRY_DAYS * 1 days + 1 hours);
        
        // 项目方销毁过期期权
        uint256 ownerEthBefore = owner.balance;
        callOption.expireOptions();
        
        // 验证结果
        assertEq(owner.balance - ownerEthBefore, ethAmount); // 收回了ETH
        assertTrue(callOption.isExpired()); // 期权已标记为过期
    }
    
    function testCannotExerciseAfterExpiry() public {
        // 先发行期权并添加流动性
        uint256 ethAmount = 5 ether;
        callOption.issueOptions{value: ethAmount}();
        callOption.approve(address(optionMarket), ethAmount);
        mockUSDT.approve(address(optionMarket), 1000 ether);
        optionMarket.addLiquidity(ethAmount, 500 ether);
        
        // 用户购买期权
        uint256 optionsToBuy = 1 ether;
        uint256 usdtCost = optionsToBuy * OPTION_PRICE / 1 ether;
        
        vm.startPrank(user1);
        mockUSDT.approve(address(optionMarket), usdtCost);
        optionMarket.buyOptions(optionsToBuy);
        vm.stopPrank();
        
        // 快进到到期日之后
        vm.warp(block.timestamp + EXPIRY_DAYS * 1 days + 1 hours);
        
        // 用户尝试行权，应该失败
        vm.startPrank(user1);
        uint256 usdtForExercise = optionsToBuy * STRIKE_PRICE / 1 ether;
        mockUSDT.approve(address(callOption), usdtForExercise);
        
        vm.expectRevert("Options have expired");
        callOption.exercise(optionsToBuy);
        vm.stopPrank();
    }
    
    function testUpdateOptionPrice() public {
        // 更新期权价格
        uint256 newPrice = 120 ether;
        optionMarket.updateOptionPrice(newPrice);
        
        // 验证价格已更新
        assertEq(optionMarket.optionPrice(), newPrice);
    }
} 