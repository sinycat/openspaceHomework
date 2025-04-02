// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TwoThirdSignWallet
 * @dev 一个2/3多签钱包合约，需要三个所有者中的两个同意才能执行交易
 */
contract TwoThirdSignWallet is ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // 交易结构体
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 numConfirmations;
        mapping(address => bool) isConfirmed;
    }

    // 所有者地址数组
    address[3] public owners;
    // 地址是否为所有者的映射
    mapping(address => bool) public isOwner;
    // 所需确认数
    uint256 public constant REQUIRED_CONFIRMATIONS = 2;
    // 交易计数器
    uint256 public transactionCount;
    // 交易映射
    mapping(uint256 => Transaction) public transactions;

    // 事件
    event Deposit(address indexed sender, uint256 amount);
    event SubmitTransaction(address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data);
    event ConfirmTransaction(address indexed owner, uint256 indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint256 indexed txIndex);

    // 修饰符：仅所有者可调用
    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    // 修饰符：交易必须存在
    modifier txExists(uint256 _txIndex) {
        require(_txIndex < transactionCount, "transaction not exists");
        _;
    }

    // 修饰符：交易未执行
    modifier notExecuted(uint256 _txIndex) {
        require(!transactions[_txIndex].executed, "transaction executed");
        _;
    }

    // 修饰符：交易未被当前所有者确认
    modifier notConfirmed(uint256 _txIndex) {
        require(!transactions[_txIndex].isConfirmed[msg.sender], "transaction confirmed");
        _;
    }

    /**
     * @dev 构造函数，设置三个所有者
     * @param _owners 三个所有者的地址数组
     */
    constructor(address[3] memory _owners) {
        require(_owners[0] != address(0) && _owners[1] != address(0) && _owners[2] != address(0), "owners cannot be zero address");
        require(_owners[0] != _owners[1] && _owners[0] != _owners[2] && _owners[1] != _owners[2], "owners must be different");

        for (uint256 i = 0; i < 3; i++) {
            owners[i] = _owners[i];
            isOwner[_owners[i]] = true;
        }
    }

    /**
     * @dev 接收ETH的回退函数
     */
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev 提交交易
     * @param _to 接收者地址
     * @param _value 发送的ETH数量
     * @param _data 调用数据
     * @return 交易索引
     */
    function submitTransaction(address _to, uint256 _value, bytes memory _data) 
        public 
        onlyOwner 
        returns (uint256)
    {
        uint256 txIndex = transactionCount;

        Transaction storage transaction = transactions[txIndex];
        transaction.to = _to;
        transaction.value = _value;
        transaction.data = _data;
        transaction.executed = false;
        transaction.numConfirmations = 0;

        transactionCount++;

        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
        
        // 提交者自动确认交易
        confirmTransaction(txIndex);
        
        return txIndex;
    }

    /**
     * @dev 确认交易
     * @param _txIndex 交易索引
     */
    function confirmTransaction(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.isConfirmed[msg.sender] = true;
        transaction.numConfirmations++;

        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    /**
     * @dev 执行交易
     * @param _txIndex 交易索引
     */
    function executeTransaction(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        nonReentrant
    {
        Transaction storage transaction = transactions[_txIndex];

        require(transaction.numConfirmations >= REQUIRED_CONFIRMATIONS, "insufficient confirmations");

        transaction.executed = true;

        (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "transaction execution failed");

        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    /**
     * @dev 撤销确认
     * @param _txIndex 交易索引
     */
    function revokeConfirmation(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];

        require(transaction.isConfirmed[msg.sender], "transaction not confirmed");

        transaction.isConfirmed[msg.sender] = false;
        transaction.numConfirmations--;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    /**
     * @dev 获取所有者
     * @return 所有者地址数组
     */
    function getOwners() public view returns (address[3] memory) {
        return owners;
    }

    /**
     * @dev 获取交易数量
     * @return 交易总数
     */
    function getTransactionCount() public view returns (uint256) {
        return transactionCount;
    }

    /**
     * @dev 获取交易详情
     * @param _txIndex 交易索引
     * @return to 接收者地址
     * @return value 发送的ETH数量
     * @return data 调用数据
     * @return executed 是否已执行
     * @return numConfirmations 确认数量
     */
    function getTransaction(uint256 _txIndex)
        public
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 numConfirmations
        )
    {
        Transaction storage transaction = transactions[_txIndex];

        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations
        );
    }

    /**
     * @dev 检查交易是否被特定所有者确认
     * @param _txIndex 交易索引
     * @param _owner 所有者地址
     * @return 是否确认
     */
    function isConfirmed(uint256 _txIndex, address _owner)
        public
        view
        returns (bool)
    {
        Transaction storage transaction = transactions[_txIndex];
        return transaction.isConfirmed[_owner];
    }
}
