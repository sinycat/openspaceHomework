// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CallOptionToken is ERC20, Ownable, ReentrancyGuard {
    // 期权参数
    uint256 public strikePrice; // 行权价格（以USDT计价）
    uint256 public expiryDate; // 到期日（Unix时间戳）
    uint256 public initialPrice; // 创建时的标的价格
    
    // 标的资产（这里假设是ETH）
    address public usdtAddress; // USDT合约地址
    
    // 状态变量
    bool public isExpired = false;
    
    // 事件
    event OptionsIssued(address issuer, uint256 underlyingAmount, uint256 optionsAmount);
    event OptionsExercised(address user, uint256 optionsAmount, uint256 underlyingAmount);
    event OptionsExpired(address owner, uint256 underlyingAmount);
    
    /**
     * @dev 构造函数
     * @param _name 期权Token名称
     * @param _symbol 期权Token符号
     * @param _strikePrice 行权价格（以USDT的最小单位计）
     * @param _expiryDays 到期天数
     * @param _initialPrice 初始标的价格
     * @param _usdtAddress USDT合约地址
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _strikePrice,
        uint256 _expiryDays,
        uint256 _initialPrice,
        address _usdtAddress
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        strikePrice = _strikePrice;
        expiryDate = block.timestamp + (_expiryDays * 1 days);
        initialPrice = _initialPrice;
        usdtAddress = _usdtAddress;
    }
    
    /**
     * @dev 发行期权Token（项目方角色）
     * 项目方转入ETH，合约发行相应数量的期权Token
     */
    function issueOptions() external payable onlyOwner {
        require(msg.value > 0, "Must send ETH");
        require(block.timestamp < expiryDate, "Options have expired");
        
        // 每个ETH可以发行的期权数量（这里简化为1:1，实际可能需要更复杂的计算）
        uint256 optionsToMint = msg.value;
        
        // 铸造期权Token给发行方
        _mint(msg.sender, optionsToMint);
        
        emit OptionsIssued(msg.sender, msg.value, optionsToMint);
    }
    
    /**
     * @dev 行权方法（用户角色）
     * @param optionsAmount 要行权的期权Token数量
     */
    function exercise(uint256 optionsAmount) external nonReentrant {
        require(block.timestamp <= expiryDate, "Options have expired");
        require(block.timestamp >= expiryDate - 1 days, "Can only exercise on the expiration date");
        require(balanceOf(msg.sender) >= optionsAmount, "Insufficient option token balance");
        
        // 计算需要支付的USDT金额
        uint256 usdtAmount = optionsAmount * strikePrice / 1 ether;
        
        // 转移USDT从用户到合约
        IERC20 usdt = IERC20(usdtAddress);
        require(usdt.transferFrom(msg.sender, address(this), usdtAmount), "Failed to transfer USDT");
        
        // 销毁用户的期权Token
        _burn(msg.sender, optionsAmount);
        
        // 转移ETH给用户
        (bool success, ) = payable(msg.sender).call{value: optionsAmount}("");
        require(success, "Failed to transfer ETH");
        
        emit OptionsExercised(msg.sender, optionsAmount, optionsAmount);
    }
    
    /**
     * @dev 过期销毁（项目方角色）
     * 销毁所有期权Token并赎回标的资产
     */
    function expireOptions() external onlyOwner {
        require(block.timestamp > expiryDate, "Options have not expired");
        require(!isExpired, "Options have been destroyed");
        
        isExpired = true;
        
        // 获取合约中剩余的ETH
        uint256 remainingEth = address(this).balance;
        
        // 转移所有ETH回到所有者
        (bool success, ) = payable(owner()).call{value: remainingEth}("");
        require(success, "Failed to transfer ETH");
        
        // 转移所有USDT回到所有者
        IERC20 usdt = IERC20(usdtAddress);
        uint256 usdtBalance = usdt.balanceOf(address(this));
        if (usdtBalance > 0) {
            require(usdt.transfer(owner(), usdtBalance), "Failed to transfer USDT");
        }
        
        emit OptionsExpired(owner(), remainingEth);
    }
    
    /**
     * @dev 检查期权是否可以行权
     * @return 如果可以行权返回true，否则返回false
     */
    function isExercisable() public view returns (bool) {
        return (block.timestamp <= expiryDate && 
                block.timestamp >= expiryDate - 1 days && 
                !isExpired);
    }
    
    /**
     * @dev 获取期权信息
     * @return _strikePrice 行权价格
     * @return _expiryDate 到期日
     * @return _initialPrice 初始价格
     * @return _isExpired 是否已过期
     */
    function getOptionInfo() external view returns (
        uint256 _strikePrice,
        uint256 _expiryDate,
        uint256 _initialPrice,
        bool _isExpired
    ) {
        return (strikePrice, expiryDate, initialPrice, isExpired);
    }
} 