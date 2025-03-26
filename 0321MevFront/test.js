import { ethers } from 'ethers';
import dotenv from 'dotenv';

// 加载.env文件中的环境变量
dotenv.config();

// 从环境变量中获取私钥
const privateKey = process.env.PRIVATE_KEY;

// NFT合约地址
const NFT_CONTRACT_ADDRESS = process.env.NFT_CONTRACT_ADDRESS;

// NFT合约ABI (只包含presale函数)
const NFT_ABI = [
  "function presale(uint256 amount) external payable"
];

async function main() {
  // 使用明确的RPC URL
  // 这里使用Sepolia测试网的公共RPC端点
  const rpcUrl = process.env.SEPOLIA_ALCHEMY_RPC;
  
  console.log('连接到RPC:', rpcUrl);
  
  // 创建提供商
  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
  
  // 测试网络连接
  try {
    const network = await provider.getNetwork();
    console.log('已连接到网络:', network.name, '(chainId:', network.chainId, ')');
  } catch (error) {
    console.error('网络连接测试失败:', error.message);
    process.exit(1);
  }
  
  // 创建钱包实例
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log('使用钱包地址:', wallet.address);
  
  // 创建合约实例
  const nftContract = new ethers.Contract(NFT_CONTRACT_ADDRESS, NFT_ABI, wallet);
  
  // 调用presale方法，传入参数2
  const nftPrice = ethers.utils.parseEther("0.0001"); // 每个NFT的价格
  const amount = 2; // 购买数量
  const value = nftPrice.mul(amount); // 总价值
  
  console.log(`准备购买${amount}个NFT，总价值: ${ethers.utils.formatEther(value)} ETH`);
  
  try {
    const tx = await nftContract.presale(amount, {
      value: value,
      gasLimit: 300000 // 设置一个合理的gas限制
    });
    
    console.log('交易已发送，交易哈希:', tx.hash);
    console.log('等待交易确认...');
    
    const receipt = await tx.wait();
    console.log('交易已确认，区块号:', receipt.blockNumber);
  } catch (error) {
    console.error('交易失败:', error.message);
  }
}

main().catch(error => {
  console.error('程序执行出错:', error);
  process.exit(1);
});