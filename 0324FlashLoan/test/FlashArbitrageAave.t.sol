// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import "forge-std/Test.sol";
import "../src/FlashArbitrageAave.sol";
import "../src/MyERC20Token.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Router.sol";
import "../src/interfaces/ILendingPool.sol";
import "../src/interfaces/IFlashLoanReceiver.sol";
import "../test/mocks/MockLendingPool.sol";

contract FlashArbitrageAaveTest is Test {
    FlashArbitrageAave public arbitrage;
    MyERC20Token public tokenA;
    MyERC20Token public tokenB;
    UniswapV2Factory public factory1;
    UniswapV2Router public router1;
    UniswapV2Factory public factory2;
    UniswapV2Router public router2;
    MockLendingPool public lendingPool;
    
    address public user = address(1);
    
    function setUp() public {
        // 部署代币
        tokenA = new MyERC20Token("Token A", "TKNA");
        tokenB = new MyERC20Token("Token B", "TKNB");
        
        // 部署 Uniswap 系统1
        factory1 = new UniswapV2Factory(address(this));
        router1 = new UniswapV2Router(address(factory1), address(tokenA));
        
        // 部署 Uniswap 系统2
        factory2 = new UniswapV2Factory(address(this));
        router2 = new UniswapV2Router(address(factory2), address(tokenA));
        
        // 部署 Aave 模拟池
        lendingPool = new MockLendingPool();
        
        // 部署套利合约
        arbitrage = new FlashArbitrageAave(
            address(factory1),
            address(router1),
            address(factory2),
            address(router2),
            address(tokenA),
            address(tokenB),
            address(lendingPool)
        );
        
        // 为 Uniswap 池子铸造代币
        tokenA.mint(address(this), 20000 * 10**18);
        tokenB.mint(address(this), 20000 * 10**18);
        
        // 在 PoolA 中创建 TokenA/TokenB 池子 (系统1)
        tokenA.approve(address(router1), 10000 * 10**18);
        tokenB.approve(address(router1), 10000 * 10**18);
        router1.addLiquidity(
            address(tokenA),
            address(tokenB),
            10000 * 10**18,
            10000 * 10**18,
            0,
            0,
            address(this),
            block.timestamp + 600
        );
        
        // 在 PoolB 中创建 TokenA/TokenB 池子 (系统2)，价格不同
        tokenA.approve(address(router2), 1000 * 10**18);
        tokenB.approve(address(router2), 10000 * 10**18);
        router2.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10**18,
            10000 * 10**18,
            0,
            0,
            address(this),
            block.timestamp + 600
        );
        
        // 为 Aave 池子铸造代币
        tokenA.mint(address(lendingPool), 10000 * 10**18);
        
        // 为用户铸造一些 TokenB
        tokenB.mint(user, 10 * 10**18);
    }
    
    // 测试完整的闪电贷套利流程
    function testFlashLoanArbitrage() public {
        // 记录用户初始 TokenB 余额
        uint256 initialTokenBBalance = tokenB.balanceOf(user);
        
        // 执行闪电贷套利
        vm.prank(user);
        arbitrage.executeFlashLoan(1 * 10**18);
        
        // 检查用户的 TokenB 余额是否增加
        uint256 finalTokenBBalance = tokenB.balanceOf(user);
        console.log("TokenB balance before arbitrage:", initialTokenBBalance / 1e18);
        console.log("TokenB balance after arbitrage:", finalTokenBBalance / 1e18);
        console.log("Profit in TokenB:", (finalTokenBBalance - initialTokenBBalance) / 1e18);
        
        // 确认套利成功
        assertGt(finalTokenBBalance, initialTokenBBalance, "Arbitrage should generate profit");
    }
} 