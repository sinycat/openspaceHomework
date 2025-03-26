// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import "forge-std/Test.sol";
import "../src/WETH9.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Router.sol";
import "../src/MyERC20Token.sol";
import "../src/FlashArbitrageUniswap.sol";
import "../src/interfaces/IUniswapV2Pair.sol";

contract FlashArbitrageUniswapTest is Test {
    WETH9 weth;
    UniswapV2Factory factory1;
    UniswapV2Router router1;
    UniswapV2Factory factory2;
    UniswapV2Router router2;
    MyERC20Token tokenA;
    MyERC20Token tokenB;
    FlashArbitrageUniswap arbitrage;
    
    address user = address(1);
    
    function setUp() public {
        // 部署 WETH
        weth = new WETH9();
        
        // 部署 Uniswap 系统1
        factory1 = new UniswapV2Factory(address(this));
        router1 = new UniswapV2Router(address(factory1), address(weth));
        
        // 部署 Uniswap 系统2
        factory2 = new UniswapV2Factory(address(this));
        router2 = new UniswapV2Router(address(factory2), address(weth));
        
        // 部署代币
        tokenA = new MyERC20Token("Token A", "TKA");
        tokenB = new MyERC20Token("Token B", "TKB");
        
        // 部署套利合约
        arbitrage = new FlashArbitrageUniswap(
            address(factory1),
            address(router1),
            address(factory2),
            address(router2),
            address(tokenA),
            address(tokenB)
        );
        
        // 创建流动性池并添加流动性
        
        // 1. 为 TokenA 铸造足够的代币
        tokenA.mint(address(this), 100000 * 10**18);
        
        // 2. 为 TokenB 铸造足够的代币
        tokenB.mint(address(this), 100000 * 10**18);
        
        // 3. 在 PoolA 中创建 TokenA/TokenB 池子 (系统1)
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
        
        // 4. 在 PoolB 中创建 TokenA/TokenB 池子 (系统2, 价格差异更大)
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
    }
    
    // 测试完整的闪电贷套利流程
    function testFlashSwapArbitrage() public {
        // 记录用户初始 TokenB 余额
        uint256 initialTokenBBalance = tokenB.balanceOf(user);
        
        // 打印初始池子状态
        address pairA = factory1.getPair(address(tokenA), address(tokenB));
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pairA).getReserves();
        console.log("PoolA initial reserves - TokenA:", address(tokenA) == IUniswapV2Pair(pairA).token0() ? reserve0 : reserve1);
        console.log("PoolA initial reserves - TokenB:", address(tokenA) == IUniswapV2Pair(pairA).token0() ? reserve1 : reserve0);
        
        address pairB = factory2.getPair(address(tokenA), address(tokenB));
        (reserve0, reserve1,) = IUniswapV2Pair(pairB).getReserves();
        console.log("PoolB initial reserves - TokenA:", address(tokenA) == IUniswapV2Pair(pairB).token0() ? reserve0 : reserve1);
        console.log("PoolB initial reserves - TokenB:", address(tokenA) == IUniswapV2Pair(pairB).token0() ? reserve1 : reserve0);
        
        // 执行闪电贷套利
        vm.prank(user);
        arbitrage.executeFlashSwap(1 * 10**18);
        
        // 检查用户的 TokenB 余额是否增加
        uint256 finalTokenBBalance = tokenB.balanceOf(user);
        console.log("TokenB balance before arbitrage:", initialTokenBBalance / 1e18);
        console.log("TokenB balance after arbitrage:", finalTokenBBalance / 1e18);
        console.log("Profit in TokenB:", (finalTokenBBalance - initialTokenBBalance) / 1e18);
        
        // 确认套利成功
        assertGt(finalTokenBBalance, initialTokenBBalance, "Arbitrage should generate profit");
    }
}
