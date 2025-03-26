// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Router.sol";
import "../src/WETH9.sol";
import "../src/MyERC20Token.sol";
import "../src/MyDex.sol";

contract DeployUniswapV2 is Script {
    function run() external {

        //  deploy to Anvil first count
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        vm.startBroadcast(deployerPrivateKey);

        // Deploy WETH9
        WETH9 weth = new WETH9();
        console.log("WETH9 deployed successfully, address:", address(weth));

        // Deploy two ERC20 tokens
        MyERC20Token tokenA = new MyERC20Token("Token A", "TKNA");
        console.log("Token A deployed successfully, address:", address(tokenA));

        // Mint some tokens for testing
        tokenA.mint(msg.sender, 1000000 * 10**18);
        console.log("Tokens minted successfully");

        // Deploy UniswapV2Factory
        address feeTo = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        UniswapV2Factory factory = new UniswapV2Factory(feeTo);
        console.log("UniswapV2Factory deployed successfully, address:", address(factory));

        UniswapV2Router router = new UniswapV2Router(address(factory), address(weth));
        console.log("UniswapV2Router deployed successfully, address:", address(router));

        MyDex dex = new MyDex(address(factory), address(router), address(weth));
        console.log("MyDex deployed successfully, address:", address(dex));

        vm.stopBroadcast();
    }
} 