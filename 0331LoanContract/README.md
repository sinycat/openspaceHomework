# 固定利率存款贷款市场平台

## 项目概述

LoanMarketplace是一个基于以太坊的去中心化金融平台，提供固定利率的存款和贷款服务。该平台支持ETH和多种ERC20代币，允许用户创建存款要约、贷款要约，并通过抵押品保障贷款安全。  
部署地址:   https://sepolia.etherscan.io/address/0x04bdc38ee5bcf9eb1e652291017f73ab5b406220

## 主要功能

### 存款功能
- 创建存款要约：用户可以存入ETH或ERC20代币，设定期望的利率和期限
- 取消存款要约：在要约被接受前，存款人可以随时取消并收回资金
- 接受存款要约：借款人可以提供抵押品接受存款要约，获得贷款

### 贷款功能
- 创建贷款要约：借款人可以提供抵押品，设定所需贷款金额、利率和期限
- 取消贷款要约：在要约被接受前，借款人可以随时取消并收回抵押品
- 接受贷款要约：贷款人可以提供资金接受贷款要约，获得固定利息收益

### 贷款管理
- 还款：借款人可以在贷款期限内还款，包括本金和利息
- 清算：当抵押率低于最低要求或贷款逾期时，任何人都可以清算贷款并获得奖励

## 平台特点

1. 固定利率：所有贷款采用固定利率，提供稳定可预期的收益和成本
2. 灵活的抵押品：支持ETH和多种ERC20代币作为抵押品
3. 价格预言机：使用Chainlink预言机获取实时价格数据，确保抵押率计算准确
4. 多种还款激励：
   - 提前还款：利息翻倍，鼓励按时还款
   - 宽限期：到期后短期内保持原利率
   - 逾期惩罚：逾期后利率翻倍，增加逾期成本
5. 清算机制：保护贷款人资金安全，同时为清算人提供激励

## 使用指南

### 作为存款人（贷款人）

1. 创建存款要约
``` solidity
function createDepositOffer(
    address tokenAddress,  // 存款代币地址（0x0表示ETH）
    uint256 amount,        // 存款金额
    uint256 interestRate,  // 年化利率（以基点表示，100 = 1%）
    uint256 duration       // 存款期限（以秒为单位）
)
```

2. 取消存款要约
``` solidity
function cancelDepositOffer(uint256 offerId)
```

3. 接受贷款要约
``` solidity
function acceptLoanOffer(uint256 offerId)
```

### 作为借款人

1. 创建贷款要约
``` solidity
function createLoanOffer(
    address loanTokenAddress,     // 借入代币地址
    uint256 loanAmount,           // 借入金额
    address collateralTokenAddress, // 抵押代币地址（0x0表示ETH）
    uint256 collateralAmount,     // 抵押金额
    uint256 interestRate,         // 年化利率（以基点表示）
    uint256 duration              // 贷款期限（以秒为单位）
)
```

2. 取消贷款要约
``` solidity
function cancelLoanOffer(uint256 offerId)
```

3. 接受存款要约
``` solidity
function acceptDepositOffer(
    uint256 offerId,
    address collateralTokenAddress,
    uint256 collateralAmount
)
```

4. 还款 
``` solidity
function repayLoan(uint256 loanId)
```

### 清算人

1. 清算不健康贷款
``` solidity
function liquidateLoan(uint256 loanId)
```

## 平台参数

- 平台费率：0.5%（可由平台所有者调整）
- 最低抵押率：150%（可由平台所有者调整）
- 宽限期：3天（可由平台所有者调整）
- 清算奖励：5%（可由平台所有者调整）

## 风险提示

1. 价格波动风险：加密资产价格波动可能导致抵押率下降，引发清算
2. 智能合约风险：尽管合约经过审计，但仍可能存在未知漏洞
3. 预言机风险：价格预言机可能出现延迟或错误数据
4. 流动性风险：在市场波动时期，可能难以找到匹配的贷款/存款要约