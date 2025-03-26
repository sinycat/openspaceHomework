##  内容说明

### 本项目有三个闪电贷合约 

#### 1. Uniswap经典闪电贷 从PoolA借TokenA 到PoolB换取TokenB 然后归还TokenB到PoolA , 还款保证K值不变 整个过程在一个区块内完成  PoolA中TokenA:TokenB=1:1,PoolB中TokenA:TokenB=1:10 见FlashArbitrageUniswap.sol文件

#### 2. AAVE闪电贷套利  从Aave 的 lendingPool 中借入 TokenA，然后在 PoolB 中用 TokenA 换取 TokenB， 再在 PoolA 中用部分 TokenB 换回 TokenA 来偿还借款   PoolA中TokenA:TokenB=1:1,PoolB中TokenA:TokenB=1:10 见FlashArbitrageAave文件 

#### 3. 非严格意义的闪电贷, 或者称为套利合约 合约接收用户的 TokenB  在 PoolA 中用 TokenB 换取 TokenA, 在 PoolB 中用获得的 TokenA 换取 TokenB 然后查询如果有利润,将利润转出,合约结束. PoolA中TokenA:TokenB=1:1,PoolB中TokenA:TokenB=1:10 见FlashArbitrageSelfOwned文件
