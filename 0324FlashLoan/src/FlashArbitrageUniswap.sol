// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Callee.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";

// 用Uniswap经典方式进行闪电贷 从PoolA借TokenA 到PoolB换取TokenB 然后还款到PoolA
// 还款保证K值不变 整个过程在一个区块内完成
contract FlashArbitrageUniswap is IUniswapV2Callee {
    address public factory1;
    address public router1;
    address public factory2;
    address public router2;
    address public tokenA;
    address public tokenB;
    
    // 存储临时数据的结构体
    struct FlashCallbackData {
        uint256 borrowAmount;
        address user;
        uint256 tokenBReceived;
    }
    
    // 临时存储回调数据
    FlashCallbackData private callbackData;
    
    constructor(
        address _factory1,
        address _router1,
        address _factory2,
        address _router2,
        address _tokenA,
        address _tokenB
    ) {
        factory1 = _factory1;
        router1 = _router1;
        factory2 = _factory2;
        router2 = _router2;
        tokenA = _tokenA;
        tokenB = _tokenB;
    }
    
    // 执行闪电兑换
    function executeFlashSwap(uint256 borrowAmount) external {
        // 获取 PoolA 的交易对地址 (系统1)
        address pairA = IUniswapV2Factory(factory1).getPair(tokenA, tokenB);
        require(pairA != address(0), "Pair A not found");
        
        // 确定 tokenA 是 token0 还是 token1
        address token0 = IUniswapV2Pair(pairA).token0();
        
        // 准备闪电贷数据
        uint256 amount0Out = tokenA == token0 ? borrowAmount : 0;
        uint256 amount1Out = tokenA == token0 ? 0 : borrowAmount;
        
        // 存储回调数据
        callbackData = FlashCallbackData({
            borrowAmount: borrowAmount,
            user: msg.sender,
            tokenBReceived: 0
        });
        
        // 执行闪电贷，传递有意义的回调数据
        bytes memory data = abi.encode(borrowAmount, msg.sender);
        IUniswapV2Pair(pairA).swap(amount0Out, amount1Out, address(this), data);
    }
    
    // 闪电贷回调函数
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        // 确保调用者是 PoolA 的交易对合约
        address pairA = IUniswapV2Factory(factory1).getPair(tokenA, tokenB);
        require(msg.sender == pairA, "Caller is not the pair contract");
        require(sender == address(this), "Sender is not this contract");
        
        // 解码数据（如果有）
        if (data.length > 0) {
            (uint256 borrowAmount, address user) = abi.decode(data, (uint256, address));
            callbackData.borrowAmount = borrowAmount;
            callbackData.user = user;
        }
        
        // 在 PoolB 中用 TokenA 换取 TokenB (系统2)
        _swapTokenAForTokenB();
        
        // 计算需要归还的金额
        uint256 amountBorrowed = amount0 > 0 ? amount0 : amount1;
        uint256 tokenBNeeded = _calculateRepayAmount(pairA, amountBorrowed);
        
        // 确保获得足够的 TokenB 进行套利
        require(callbackData.tokenBReceived > tokenBNeeded, "Arbitrage not profitable");
        
        // 直接将 TokenB 转给 PoolA 作为还款
        IERC20(tokenB).transfer(pairA, tokenBNeeded);
        
        // 将剩余的 TokenB 作为利润转给用户
        uint256 remainingTokenB = callbackData.tokenBReceived - tokenBNeeded;
        if (remainingTokenB > 0) {
            IERC20(tokenB).transfer(callbackData.user, remainingTokenB);
        }
    }
    
    // 在 PoolB 中用 TokenA 换取 TokenB
    function _swapTokenAForTokenB() private {
        IERC20(tokenA).approve(address(router2), callbackData.borrowAmount);
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        
        uint256[] memory amountsOut = IUniswapV2Router(router2).swapExactTokensForTokens(
            callbackData.borrowAmount,
            0,  // 不设置最小输出
            path,
            address(this),
            block.timestamp + 600
        );
        
        callbackData.tokenBReceived = amountsOut[1];
    }
    
    // 计算需要归还的 TokenB 数量   
     // 计算需要归还的 TokenB 数量
    function _calculateRepayAmount(address pairA, uint256 amountBorrowed) private view returns (uint256) {
        // 获取池子的储备金
        address token0 = IUniswapV2Pair(pairA).token0();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pairA).getReserves();
        
        uint256 reserveA;
        uint256 reserveB;
        
        if (tokenA == token0) {
            reserveA = reserve0;
            reserveB = reserve1;
        } else {
            reserveA = reserve1;
            reserveB = reserve0;
        }
        
        // 计算手续费 (0.3%)
        uint256 fee = (amountBorrowed * 3) / 997 + 1;
        uint256 amountToRepay = amountBorrowed + fee;
        
        // 计算新的 reserveA (减去需要归还的金额)
        uint256 newReserveA = reserveA - amountToRepay;
        
        // 计算需要的 reserveB，使得 newReserveA * newReserveB >= reserveA * reserveB
        uint256 numerator = reserveA * reserveB;
        uint256 denominator = newReserveA;
        uint256 newReserveB = (numerator + denominator - 1) / denominator; // 向上取整
        
        // 需要额外添加的 TokenB 数量
        uint256 tokenBNeeded = newReserveB - reserveB;
        
        return tokenBNeeded;
    }
}