// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import "forge-std/Script.sol";
import "../src/WETH9.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Router.sol";
import "../src/MyERC20Token.sol";
import "../src/FlashArbitrageUniswap.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();

        // 部署 WETH
        WETH9 weth = new WETH9();
        console.log("WETH deployed at:", address(weth));

        // 部署 Uniswap 系统1
        UniswapV2Factory factory1 = new UniswapV2Factory(address(this));
        console.log("UniswapV2Factory1 deployed at:", address(factory1));
        UniswapV2Router router1 = new UniswapV2Router(address(factory1), address(weth));
        console.log("UniswapV2Router1 deployed at:", address(router1));

        // 部署 Uniswap 系统2
        UniswapV2Factory factory2 = new UniswapV2Factory(address(this));
        console.log("UniswapV2Factory2 deployed at:", address(factory2));
        UniswapV2Router router2 = new UniswapV2Router(address(factory2), address(weth));
        console.log("UniswapV2Router2 deployed at:", address(router2));

        // 部署代币
        MyERC20Token tokenA = new MyERC20Token("Token A", "TKA");
        console.log("TokenA deployed at:", address(tokenA));
        MyERC20Token tokenB = new MyERC20Token("Token B", "TKB");
        console.log("TokenB deployed at:", address(tokenB));

        // 部署 FlashArbitrageUniswap 合约
        FlashArbitrageUniswap arbitrage = new FlashArbitrageUniswap(
            address(factory1),
            address(router1),
            address(factory2),
            address(router2),
            address(tokenA),
            address(tokenB)
        );
        console.log("FlashArbitrageUniswap deployed at:", address(arbitrage));

        vm.stopBroadcast();
    }
}
