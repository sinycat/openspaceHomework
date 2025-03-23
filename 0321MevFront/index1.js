import { createPublicClient, createWalletClient, http, parseEther, encodeFunctionData } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import dotenv from 'dotenv';

// 加载环境变量
dotenv.config();

//  实现标准购买 已实际成交
// 从 .env 获取配置
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const NFT_CONTRACT_ADDRESS = process.env.NFT_CONTRACT_ADDRESS;
const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL;
const FLASHBOTS_RPC = process.env.FLASHBOTS_RPC;

// 验证环境变量
if (!PRIVATE_KEY || !NFT_CONTRACT_ADDRESS || !SEPOLIA_RPC_URL || !FLASHBOTS_RPC) {
  console.error('请确保 .env 文件中包含所有必要的环境变量');
  process.exit(1);
}

const AMOUNT_TO_BUY = 2;
const PRICE_PER_NFT = parseEther('0.01');

// NFT 合约 ABI
const NFT_ABI = [
  {
    inputs: [],
    name: 'isPresaleActive',
    outputs: [{ type: 'bool', name: '' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ type: 'uint256', name: 'amount' }],
    name: 'presale',
    outputs: [],
    stateMutability: 'payable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'enablePresale',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
];

// 创建客户端 - 使用环境变量中的 RPC URL
const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(SEPOLIA_RPC_URL),
});

const account = privateKeyToAccount(PRIVATE_KEY);
const walletClient = createWalletClient({
  account,
  chain: sepolia,
  transport: http(SEPOLIA_RPC_URL),
});

// 监听预售状态并购买 NFT
async function monitorAndBuyNFT() {
  console.log('开始监听 OpenspaceNFT 预售状态...');

  // 检查初始预售状态
  let isActive = await publicClient.readContract({
    address: NFT_CONTRACT_ADDRESS,
    abi: NFT_ABI,
    functionName: 'isPresaleActive',
  });

  if (isActive) {
    console.log('预售已经激活，准备购买 NFT');
    await buyNFTWithFlashbots();
    return;
  }

  // 设置轮询检查预售状态
  const intervalId = setInterval(async () => {
    try {
      isActive = await publicClient.readContract({
        address: NFT_CONTRACT_ADDRESS,
        abi: NFT_ABI,
        functionName: 'isPresaleActive',
      });

      if (isActive) {
        console.log('预售已激活，准备购买 NFT');
        clearInterval(intervalId);
        await buyNFTWithFlashbots();
      } else {
        console.log('预售尚未激活，继续监听...');
      }
    } catch (error) {
      console.error('监听预售状态时出错:', error);
    }
  }, 2000); // 每2秒检查一次
}

// 使用 Flashbots 购买 NFT
async function buyNFTWithFlashbots() {
  try {
    // 准备交易
    const presaleCalldata = encodeFunctionData({
      abi: NFT_ABI,
      functionName: 'presale',
      args: [AMOUNT_TO_BUY],
    });

    // 获取当前区块号和下一个区块号
    const currentBlockNumber = await publicClient.getBlockNumber();
    const targetBlockNumber = currentBlockNumber + 1n;
    
    console.log(`当前区块: ${currentBlockNumber}, 目标区块: ${targetBlockNumber}`);

    // 获取当前 gas 价格和估算 gas 限制
    const gasPrice = await publicClient.getGasPrice();
    
    // 尝试更精确地估算 gas
    let estimatedGas;
    try {
      estimatedGas = await publicClient.estimateGas({
        account: account.address,
        to: NFT_CONTRACT_ADDRESS,
        data: presaleCalldata,
        value: PRICE_PER_NFT * BigInt(AMOUNT_TO_BUY),
      });
      console.log(`精确估算的 gas 限制: ${estimatedGas}`);
    } catch (estimateError) {
      console.warn('无法精确估算 gas，使用默认值:', estimateError);
      estimatedGas = 200000n; // 默认值
    }
    
    // 根据购买数量动态调整 gas 限制
    // NFT 铸造通常每个 NFT 消耗约 60,000-80,000 gas
    const baseGas = 50000n; // 基础交易 gas
    const gasPerNFT = 70000n; // 每个 NFT 的估计 gas
    const calculatedGas = baseGas + gasPerNFT * BigInt(AMOUNT_TO_BUY);
    
    // 取估算值和计算值中的较大者，并增加 30% 的安全余量
    const gasLimit = BigInt(Math.max(
      Number(estimatedGas * 130n / 100n),
      Number(calculatedGas * 130n / 100n)
    ));
    
    // 为了抢购紧俏 NFT，适当提高 gas 价格
    const priorityGasPrice = gasPrice * 120n / 100n; // 增加 20% 的 gas 价格
    
    console.log(`最终设置的 gas 限制: ${gasLimit}, 提高后的 gas 价格: ${priorityGasPrice}`);

    // 创建交易
    const transaction = {
      to: NFT_CONTRACT_ADDRESS,
      data: presaleCalldata,
      value: PRICE_PER_NFT * BigInt(AMOUNT_TO_BUY),
      gasLimit: gasLimit,
      chainId: 11155111, // Sepolia 链 ID
      gasPrice: priorityGasPrice, // 使用提高后的 gas 价格
      type: '0x0', // Legacy 交易
    };

    // 签名交易
    const signedTransaction = await walletClient.signTransaction(transaction);
    
    // 尝试使用 Flashbots
    console.log('尝试使用 Flashbots 发送交易...');
    try {
      // 发送 bundle 到 Flashbots
      const response = await fetch(FLASHBOTS_RPC, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jsonrpc: '2.0',
          id: 1,
          method: 'eth_sendBundle',
          params: [{
            txs: [signedTransaction],
            blockNumber: "0x" + targetBlockNumber.toString(16)
          }],
        }),
      });
      
      const bundleResponse = await response.json();
      console.log('Flashbots bundle 提交结果:', bundleResponse);
      
      if (bundleResponse.error) {
        throw new Error(`Flashbots bundle 提交失败: ${bundleResponse.error.message}`);
      }
      
      const bundleHash = bundleResponse.result;
      console.log('Flashbots 交易哈希:', bundleHash);
      
      // 查询 bundle 状态
      const statsResponse = await fetch(FLASHBOTS_RPC, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jsonrpc: '2.0',
          id: 1,
          method: 'flashbots_getBundleStats',
          params: [bundleHash],
        }),
      });
      
      const statsResult = await statsResponse.json();
      console.log('Bundle 状态:', statsResult.result);
      
      return; // Flashbots 成功，直接返回
    } catch (flashbotsError) {
      console.error('Flashbots 方式失败:', flashbotsError);
      console.log('尝试使用标准方式发送交易...');
    }
    
    // 使用标准方式发送交易
    const hash = await walletClient.sendRawTransaction({ serializedTransaction: signedTransaction });
    console.log('标准交易已提交，交易哈希:', hash);
    
    // 等待交易确认
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    console.log('交易状态:', receipt.status);
    console.log('交易详情:', receipt);
    
  } catch (error) {
    console.error('所有交易方式都失败:', error);
    
    // 最后的备选方案
    console.log('尝试使用 writeContract 方法...');
    try {
      const hash = await walletClient.writeContract({
        address: NFT_CONTRACT_ADDRESS,
        abi: NFT_ABI,
        functionName: 'presale',
        args: [AMOUNT_TO_BUY],
        value: PRICE_PER_NFT * BigInt(AMOUNT_TO_BUY),
        gas: 500000n, // 直接设置较高的 gas 限制
      });
      
      console.log('writeContract 交易已提交，交易哈希:', hash);
      
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      console.log('writeContract 交易状态:', receipt.status);
      
    } catch (writeContractError) {
      console.error('所有方法都失败:', writeContractError);
    }
  }
}

// 启动监听
monitorAndBuyNFT().catch(console.error);
