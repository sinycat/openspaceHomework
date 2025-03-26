// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IFlashLoanReceiver.sol";


//  AAVE闪电贷套利  从Aave 的 lendingPool 中借入 TokenA，然后在 PoolB 中用 TokenA 换取 TokenB，
// 再在 PoolA 中用部分 TokenB 换回 TokenA 来偿还闪电贷   
// PoolA,TokenA:TokenB=1:1,PoolB,TokenA:TokenB=1:10

contract FlashArbitrageAave is IFlashLoanReceiver {
    address public factory1;
    address public router1;
    address public factory2;
    address public router2;
    address public tokenA;
    address public tokenB;
    address public lendingPool;
    
    constructor(
        address _factory1,
        address _router1,
        address _factory2,
        address _router2,
        address _tokenA,
        address _tokenB,
        address _lendingPool
    ) {
        factory1 = _factory1;
        router1 = _router1;
        factory2 = _factory2;
        router2 = _router2;
        tokenA = _tokenA;
        tokenB = _tokenB;
        lendingPool = _lendingPool;
    }
    
    // 执行闪电贷套利
    function executeFlashLoan(uint256 borrowAmount) external {
        address[] memory assets = new address[](1);
        assets[0] = tokenA;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = borrowAmount;
        
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // 0 = no debt, 1 = stable, 2 = variable
        
        bytes memory params = abi.encode(msg.sender);
        
        ILendingPool(lendingPool).flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            params,
            0
        );
    }
    
    // 闪电贷回调函数
    function executeOperation(
        address[] calldata /* assets */,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == lendingPool, "Caller is not lending pool");
        require(initiator == address(this), "Initiator is not this contract");
        
        // 解码参数
        address user = abi.decode(params, (address));
        
        uint256 borrowAmount = amounts[0];
        uint256 fee = premiums[0];
        uint256 repayAmount = borrowAmount + fee;
        
        // 在 PoolB 中用 TokenA 换取 TokenB
        IERC20(tokenA).approve(address(router2), borrowAmount);
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        
        uint256[] memory amountsOut = IUniswapV2Router(router2).swapExactTokensForTokens(
            borrowAmount,
            0,  // 不设置最小输出
            path,
            address(this),
            block.timestamp + 600
        );
        
        uint256 tokenBReceived = amountsOut[1];
        
        // 在 PoolA 中用部分 TokenB 换回 TokenA
        path[0] = tokenB;
        path[1] = tokenA;
        
        // 计算需要多少 TokenB 才能换回 repayAmount 的 TokenA
        uint256[] memory amountsIn = IUniswapV2Router(router1).getAmountsIn(repayAmount, path);
        uint256 tokenBNeeded = amountsIn[0];
        
        // 确保获得足够的 TokenB 进行套利
        require(tokenBReceived > tokenBNeeded, "Arbitrage not profitable");
        
        // 用部分 TokenB 换回 TokenA 来偿还闪电贷
        IERC20(tokenB).approve(address(router1), tokenBNeeded);
        IUniswapV2Router(router1).swapExactTokensForTokens(
            tokenBNeeded,
            repayAmount,  // 确保获得足够的 TokenA
            path,
            address(this),
            block.timestamp + 600
        );
        
        // 批准 Aave 提取 TokenA
        IERC20(tokenA).approve(lendingPool, repayAmount);
        
        // 将剩余的 TokenB 作为利润转给用户
        uint256 remainingTokenB = IERC20(tokenB).balanceOf(address(this));
        if (remainingTokenB > 0) {
            IERC20(tokenB).transfer(user, remainingTokenB);
        }
        
        return true;
    }
    
    // 允许用户提取合约中的代币（以防万一）
    function withdrawToken(address token, uint256 amount) external {
        IERC20(token).transfer(msg.sender, amount);
    }
}
