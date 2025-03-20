// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract KKToken is ERC20 {
    address public stakingPool;

    constructor() ERC20("KK Token", "KKT") {}

    function setStakingPool(address _stakingPool) external {
        require(stakingPool == address(0), "Staking pool already set");
        stakingPool = _stakingPool;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == stakingPool, "Only staking pool can mint");
        _mint(to, amount);
    }
} 