// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract OptionMarket is Ownable, ReentrancyGuard {
    IERC20 public optionToken;
    IERC20 public usdtToken;
    
    uint256 public optionPrice; // 期权Token的价格（以USDT计价）
    
    event OptionsPurchased(address buyer, uint256 optionsAmount, uint256 usdtAmount);
    event OptionsSold(address seller, uint256 optionsAmount, uint256 usdtAmount);
    
    /**
     * @dev 构造函数
     * @param _optionToken 期权Token地址
     * @param _usdtToken USDT地址
     * @param _optionPrice 期权Token价格（以USDT最小单位计）
     */
    constructor(
        address _optionToken,
        address _usdtToken,
        uint256 _optionPrice
    ) Ownable(msg.sender) {
        optionToken = IERC20(_optionToken);
        usdtToken = IERC20(_usdtToken);
        optionPrice = _optionPrice;
    }
    
    /**
     * @dev 购买期权
     * @param optionsAmount 要购买的期权数量
     */
    function buyOptions(uint256 optionsAmount) external nonReentrant {
        require(optionsAmount > 0, "Amount must be greater than 0");
        
        // 计算需要支付的USDT金额
        uint256 usdtAmount = optionsAmount * optionPrice / 1 ether;
        
        // 检查市场是否有足够的期权Token
        require(optionToken.balanceOf(address(this)) >= optionsAmount, "Insufficient option token in market");
        
        // 转移USDT从用户到市场
        require(usdtToken.transferFrom(msg.sender, address(this), usdtAmount), "Failed to transfer USDT");
        
        // 转移期权Token从市场到用户
        require(optionToken.transfer(msg.sender, optionsAmount), "Failed to transfer option token");
        
        emit OptionsPurchased(msg.sender, optionsAmount, usdtAmount);
    }
    
    /**
     * @dev 卖出期权
     * @param optionsAmount 要卖出的期权数量
     */
    function sellOptions(uint256 optionsAmount) external nonReentrant {
        require(optionsAmount > 0, "Amount must be greater than 0");
        
        // 计算可以获得的USDT金额
        uint256 usdtAmount = optionsAmount * optionPrice / 1 ether;
        
        // 检查市场是否有足够的USDT
        require(usdtToken.balanceOf(address(this)) >= usdtAmount, "Insufficient USDT in market");
        
        // 转移期权Token从用户到市场
        require(optionToken.transferFrom(msg.sender, address(this), optionsAmount), "Failed to transfer option token");
        
        // 转移USDT从市场到用户
        require(usdtToken.transfer(msg.sender, usdtAmount), "Failed to transfer USDT");
        
        emit OptionsSold(msg.sender, optionsAmount, usdtAmount);
    }
    
    /**
     * @dev 添加流动性（仅限所有者）
     * @param optionsAmount 添加的期权Token数量
     * @param usdtAmount 添加的USDT数量
     */
    function addLiquidity(uint256 optionsAmount, uint256 usdtAmount) external onlyOwner {
        if (optionsAmount > 0) {
            require(optionToken.transferFrom(msg.sender, address(this), optionsAmount), "Failed to transfer option token");
        }
        
        if (usdtAmount > 0) {
            require(usdtToken.transferFrom(msg.sender, address(this), usdtAmount), "Failed to transfer USDT");
        }
    }
    
    /**
     * @dev 移除流动性（仅限所有者）
     * @param optionsAmount 移除的期权Token数量
     * @param usdtAmount 移除的USDT数量
     */
    function removeLiquidity(uint256 optionsAmount, uint256 usdtAmount) external onlyOwner {
        if (optionsAmount > 0) {
            require(optionToken.balanceOf(address(this)) >= optionsAmount, "Insufficient option token balance");
            require(optionToken.transfer(msg.sender, optionsAmount), "Failed to transfer option token");
        }
        
        if (usdtAmount > 0) {
            require(usdtToken.balanceOf(address(this)) >= usdtAmount, "Insufficient USDT balance");
            require(usdtToken.transfer(msg.sender, usdtAmount), "Failed to transfer USDT");
        }
    }
    
    /**
     * @dev 更新期权价格（仅限所有者）
     * @param newPrice 新的期权价格
     */
    function updateOptionPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than 0");
        optionPrice = newPrice;
    }
}