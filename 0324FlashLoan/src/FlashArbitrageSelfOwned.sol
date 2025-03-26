// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";

// 1. 合约接收用户的 TokenB
// 2. 在 PoolA 中用 TokenB 换取 TokenA（在 PoolA 中，TokenA:TokenB = 1:1）
// 3. 在 PoolB 中用获得的 TokenA 换取 TokenB（在 PoolB 中，TokenA:TokenB = 1:10）
// 4. 检查是否获利，如果是，则将所有 TokenB 返回给用户

contract FlashArbitrageSelfOwned {
    address public factory1;
    address public router1;
    address public factory2;
    address public router2;
    address public tokenA;
    address public tokenB;
    
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
    
    // 执行套利
    function executeArbitrage(uint256 tokenBAmount) external {
        // 确保用户已经将足够的 TokenB 转给合约
        require(IERC20(tokenB).balanceOf(address(this)) >= tokenBAmount, "Not enough TokenB");
        
        // 记录初始 TokenB 余额
        uint256 initialTokenBBalance = IERC20(tokenB).balanceOf(address(this));
        
        // 在 PoolA 中用 TokenB 换取 TokenA
        IERC20(tokenB).approve(address(router1), tokenBAmount);
        address[] memory path = new address[](2);
        path[0] = tokenB;
        path[1] = tokenA;
        
        uint256[] memory amountsOut = IUniswapV2Router(router1).swapExactTokensForTokens(
            tokenBAmount,
            0,  // 不设置最小输出
            path,
            address(this),
            block.timestamp + 600
        );
        
        uint256 tokenAReceived = amountsOut[1];
        
        // 在 PoolB 中用 TokenA 换取 TokenB
        IERC20(tokenA).approve(address(router2), tokenAReceived);
        path[0] = tokenA;
        path[1] = tokenB;
        
        amountsOut = IUniswapV2Router(router2).swapExactTokensForTokens(
            tokenAReceived,
            0,  // 不设置最小输出
            path,
            address(this),
            block.timestamp + 600
        );
        
        // 检查是否获利
        uint256 finalTokenBBalance = IERC20(tokenB).balanceOf(address(this));
        require(finalTokenBBalance > initialTokenBBalance, "Arbitrage not profitable");
        
        // 将所有 TokenB 转给用户
        IERC20(tokenB).transfer(msg.sender, finalTokenBBalance);
    }
    
    // 允许用户提取合约中的代币（以防万一）
    function withdrawToken(address token, uint256 amount) external {
        IERC20(token).transfer(msg.sender, amount);
    }
}