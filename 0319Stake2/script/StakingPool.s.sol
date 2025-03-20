// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/KKToken.sol";
import "../src/StakingPool.sol";

contract StakingPoolScript is Script {
    function run() external {
        vm.startBroadcast();

        // 部署 KKToken 合约
        KKToken kkToken = new KKToken();
        console.log("KKToken deployed to:", address(kkToken));

        // 部署 StakingPool 合约
        StakingPool stakingPool = new StakingPool(address(kkToken));
        console.log("StakingPool deployed to:", address(stakingPool));

        // 设置 StakingPool 地址到 KKToken 合约
        kkToken.setStakingPool(address(stakingPool));
        console.log("StakingPool address set in KKToken contract");

        vm.stopBroadcast();
    }
}