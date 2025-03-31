// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory tokenName, string memory tokenSymbol, uint8 _decimals) ERC20(tokenName, tokenSymbol) {
        _mint(msg.sender, 1000000 * 10 ** _decimals);
    }

    function decimals() public pure override returns (uint8) {
        return 6; // USDC和USDT通常是6位小数
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}