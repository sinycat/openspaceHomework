// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LoanMarketplace.sol";
import {MockToken} from "../src/MockToken.sol";

/**
 * Mock USDC deployed at: 0x8A7aE73eF40742B19E35bffa139e6B937FccF57c
  LoanMarketplace deployed at: 0x04Bdc38eE5Bcf9EB1E652291017f73Ab5B406220
  USDC/USD price feed: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E
  ETH/USD price feed: 0x694AA1769357215DE4FAC081bf1f309aDC325306
  
 */

contract DeployLoanMarketplace is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // 从环境变量读取私钥
        console.log("Deployer private key:", deployerPrivateKey);
        // vm.startBroadcast(deployerPrivateKey);
        vm.startBroadcast();

        // 部署 MockToken 作为 USDC
        MockToken usdc = new MockToken("Mock USDC", "USDC", 6);
        console.log("Mock USDC deployed at:", address(usdc));

        // 部署 LoanMarketplace
        LoanMarketplace marketplace = new LoanMarketplace(msg.sender);
        console.log("LoanMarketplace deployed at:", address(marketplace));

        // 设置价格预言机（假设 owner 是部署者）
        marketplace.setPriceFeed(address(0), 0x694AA1769357215DE4FAC081bf1f309aDC325306); // ETH/USD
        marketplace.setPriceFeed(address(usdc), 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E); // USDC/USD

        vm.stopBroadcast();
    }
}