import { createPublicClient, createWalletClient, http, parseEther, encodeFunctionData, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import dotenv from 'dotenv';
// 导入 ethers v5
import { ethers } from 'ethers';
// import { flashbots } from '@flashbots/ethers-provider';


//  用quicknode 没成功
// 加载环境变量
dotenv.config();

// 从 .env 获取配置
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const NFT_CONTRACT_ADDRESS = process.env.NFT_CONTRACT_ADDRESS;
const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL;
const SEPOLIA_WS_URL = process.env.SEPOLIA_WS_URL;
const QUICKNODE_RPC_URL = process.env.QUICKNODE_RPC_URL;
const QUICKNODE_WS_URL = process.env.QUICKNODE_WS_URL;
const FLASHBOTS_RPC = process.env.FLASHBOTS_RPC;

// 验证环境变量
if (!PRIVATE_KEY || !NFT_CONTRACT_ADDRESS || !SEPOLIA_RPC_URL || !SEPOLIA_WS_URL || !FLASHBOTS_RPC || !QUICKNODE_RPC_URL || !QUICKNODE_WS_URL) {
  console.error('请确保 .env 文件中包含所有必要的环境变量');
  process.exit(1);
}

const AMOUNT_TO_BUY = 2;
const PRICE_PER_NFT = parseEther('0.0001');

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

// 启动监听
listenForPresaleActivation();

// 监听 NFT 合约的 Presale 激活事件
async function listenForPresaleActivation() {
  // 使用 Sepolia RPC URL
  console.log(`开始监听 Presale 激活事件，连接到 Sepolia 网络...`);
  
  // 隐藏敏感信息，只显示 URL 的一部分
  const maskUrl = (url) => {
    if (!url) return "未设置";
    try {
      const urlObj = new URL(url);
      return `${urlObj.protocol}//${urlObj.hostname.slice(0, 4)}...${urlObj.hostname.slice(-4)}`;
    } catch (e) {
      return url.slice(0, 10) + "..." + url.slice(-5);
    }
  };
  
  console.log(`HTTP RPC: ${maskUrl(SEPOLIA_RPC_URL)}`);
  console.log(`监听合约地址: ${NFT_CONTRACT_ADDRESS}`);
  
  // 创建 HTTP provider 用于常规查询
  const provider = new ethers.providers.JsonRpcProvider(SEPOLIA_RPC_URL);
  
  // 设置标志
  let hasPurchased = false;  // 是否已尝试购买（无论成功与否）
  let enablePresaleDetected = false;  // 是否检测到 enablePresale 方法执行
  let processedTxHashes = new Set(); // 已处理的交易哈希集合
  
  // 定义轮询间隔变量
  let pollInterval = null;
  
  // 创建一个购买函数，确保只执行一次
  const executePurchase = async (source) => {
    // 如果已经尝试过购买，跳过
    if (hasPurchased) {
      console.log(`[${source}] ⚠️ 已经尝试过购买，不再重复购买`);
      return true;
    }
    
    // 标记为已尝试购买（无论成功与否）
    hasPurchased = true;
    console.log(`[${source}] 🚀 首次尝试购买...`);
    
    try {
      console.log(`[${source}] 尝试使用 Flashbots 购买...`);
      const result = await buyNFTWithFlashbots();
      
      if (result) {
        console.log(`[${source}] ✅ 购买成功!`);
        
        // 购买完成，停止所有监听
        console.log(`[${source}] 🏁 购买流程完成，停止所有监听`);
        cleanupAndExit();
        return true;
      } else {
        console.log(`[${source}] ❌ Flashbots 购买失败，不再尝试其他方式`);
        
        // 购买失败，但仍然停止所有监听（只尝试一次）
        console.log(`[${source}] 🏁 购买尝试完成，停止所有监听`);
        cleanupAndExit();
        return false;
      }
    } catch (buyError) {
      console.error(`[${source}] ❌ 购买过程中出错:`, buyError);
      console.error(`[${source}] 错误详情:`, buyError.message);
      
      // 购买出错，但仍然停止所有监听（只尝试一次）
      console.log(`[${source}] 🏁 购买尝试完成，停止所有监听`);
      cleanupAndExit();
      return false;
    }
  };
  
  // 检查 isPresaleActive 状态并在激活时购买
  const checkPresaleStatusAndBuy = async (source) => {
    if (hasPurchased) return; // 如果已经购买，不再检查
    
    // 只有在检测到 enablePresale 方法执行后才检查状态
    if (!enablePresaleDetected) {
      console.log(`[${source}] 尚未检测到 enablePresale 方法执行，跳过状态检查`);
      return false;
    }
    
    const contract = new ethers.Contract(
      NFT_CONTRACT_ADDRESS,
      NFT_ABI,
      provider
    );
    
    console.log(`[${source}] 🔍 检查 isPresaleActive 状态...`);
    
    try {
      const isActive = await contract.isPresaleActive();
      console.log(`[${source}] isPresaleActive = ${isActive} (${new Date().toISOString()})`);
      
      if (isActive) {
        console.log(`[${source}] ✅ isPresaleActive 已激活，立即购买!`);
        await executePurchase(source);
        return true;
      }
    } catch (error) {
      console.error(`[${source}] 检查 isPresaleActive 状态出错:`, error.message);
    }
    
    return false;
  };
  
  // 清理资源并退出的函数
  const cleanupAndExit = () => {
    console.log('清理资源...');
    
    // 清理轮询间隔
    if (pollInterval) {
      clearInterval(pollInterval);
    }
    
    provider.removeAllListeners();
    console.log('资源清理完成');
  };
  
  // 监听 pending 交易
  const setupPendingTransactionListener = () => {
    console.log('设置 pending 交易监听器...');
    
    // 计算多种可能的 enablePresale 函数选择器
    const enablePresaleSelectors = [
      // 无参数版本
      new ethers.utils.Interface(["function enablePresale()"]).getSighash("enablePresale"),
      // 带布尔参数版本
      new ethers.utils.Interface(["function enablePresale(bool)"]).getSighash("enablePresale"),
      // 带状态参数版本
      new ethers.utils.Interface(["function enablePresale(bool _state)"]).getSighash("enablePresale"),
      // 其他可能的变体
      "0xa8eac492", // 已知的选择器
      "0xd1454bf4", // 另一个可能的选择器
      "0x5bea0f8e", // 另一个可能的选择器
    ];
    
    console.log(`可能的 enablePresale 函数选择器:`);
    enablePresaleSelectors.forEach(selector => console.log(`- ${selector}`));
    
    // 测试 pending 交易监听是否工作
    console.log('测试 pending 交易监听...');
    let pendingReceived = false;
    
    // 监听 pending 交易
    provider.on('pending', async (txHash) => {
      // 标记已收到 pending 交易
      if (!pendingReceived) {
        pendingReceived = true;
        console.log('✅ 成功接收 pending 交易通知，监听器正常工作');
      }
      
      try {
        // 如果已经购买或已经检测到 enablePresale，跳过
        if (hasPurchased || enablePresaleDetected) return;
        
        // 检查是否已处理过这个交易
        if (processedTxHashes.has(txHash)) return;
        
        // 添加到已处理集合
        processedTxHashes.add(txHash);
        
        // 获取交易详情
        const tx = await provider.getTransaction(txHash);
        
        // 如果交易不存在，跳过
        if (!tx) {
          return;
        }
        
        // 如果交易不是发送到我们的合约，跳过
        if (!tx.to || tx.to.toLowerCase() !== NFT_CONTRACT_ADDRESS.toLowerCase()) {
          return;
        }
        
        console.log(`[PENDING] 发现合约交易: ${txHash}`);
        console.log(`[PENDING] 发送者: ${tx.from}`);
        console.log(`[PENDING] 接收者: ${tx.to}`);
        console.log(`[PENDING] 数据长度: ${tx.data ? tx.data.length : 0}`);
        
        // 获取交易数据
        const txData = tx.data || tx.input;
        
        // 检查交易是否有数据
        if (!txData || txData === '0x') {
          console.log(`[PENDING] 交易没有数据，跳过`);
          return;
        }
        
        // 获取函数选择器（前 10 个字符，包括 0x 前缀）
        const selector = txData.slice(0, 10);
        console.log(`[PENDING] 函数选择器: ${selector}`);
        
        // 检查是否是 enablePresale 函数调用
        if (enablePresaleSelectors.includes(selector)) {
          console.log('[PENDING] 🎯 检测到 enablePresale 函数调用!');
          console.log(`[PENDING] 匹配的选择器: ${selector}`);
          
          // 标记为已检测到 enablePresale
          enablePresaleDetected = true;
          
          // 检查状态并购买
          await checkPresaleStatusAndBuy('PENDING');
        } else {
          console.log(`[PENDING] 不是 enablePresale 函数调用，跳过`);
        }
      } catch (error) {
        console.error(`处理 pending 交易 ${txHash} 时出错:`, error.message);
      }
    });
    
    // 设置超时检查，确认 pending 交易监听是否工作
    setTimeout(() => {
      if (!pendingReceived) {
        console.log('⚠️ 30 秒内未收到任何 pending 交易通知，监听器可能不工作');
        console.log('尝试使用备用方法...');
        
        // 设置备用监听方法 - 使用区块监听
        setupBlockListener();
      }
    }, 30000);
    
    console.log('pending 交易监听器已设置');
  };
  
  // 备用方法：监听新区块
  const setupBlockListener = () => {
    console.log('设置区块监听器...');
    
    provider.on('block', async (blockNumber) => {
      try {
        if (hasPurchased || enablePresaleDetected) return;
        
        console.log(`[BLOCK] 新区块: ${blockNumber}`);
        
        // 获取区块
        const block = await provider.getBlock(blockNumber, true);
        
        // 检查区块中的所有交易
        if (block && block.transactions) {
          console.log(`[BLOCK] 区块 ${blockNumber} 包含 ${block.transactions.length} 个交易`);
          
          for (const tx of block.transactions) {
            // 如果交易不是发送到我们的合约，跳过
            if (!tx.to || tx.to.toLowerCase() !== NFT_CONTRACT_ADDRESS.toLowerCase()) {
              continue;
            }
            
            console.log(`[BLOCK] 发现合约交易: ${tx.hash}`);
            
            // 获取交易数据
            const txData = tx.data || tx.input;
            
            // 检查交易是否有数据
            if (!txData || txData === '0x') {
              continue;
            }
            
            // 获取函数选择器
            const selector = txData.slice(0, 10);
            console.log(`[BLOCK] 函数选择器: ${selector}`);
            
            // 检查是否是 enablePresale 函数调用
            if (enablePresaleSelectors.includes(selector)) {
              console.log('[BLOCK] 🎯 检测到 enablePresale 函数调用!');
              
              // 标记为已检测到 enablePresale
              enablePresaleDetected = true;
              
              // 检查状态并购买
              await checkPresaleStatusAndBuy('BLOCK');
              break;
            }
          }
        }
      } catch (error) {
        console.error(`处理区块 ${blockNumber} 时出错:`, error.message);
      }
    });
    
    console.log('区块监听器已设置');
  };
  
  try {
    console.log('开始监听 enablePresale 方法...');
    
    // 设置 pending 交易监听器
    setupPendingTransactionListener();
    
    // 设置 HTTP 轮询，但只在检测到 enablePresale 后才检查状态
    console.log('设置 HTTP 轮询...');
    pollInterval = setInterval(async () => {
      try {
        // 只有在检测到 enablePresale 后才检查状态
        if (enablePresaleDetected) {
          await checkPresaleStatusAndBuy('HTTP-POLL');
        } else {
          console.log('[HTTP-POLL] 等待 enablePresale 方法执行...');
        }
      } catch (error) {
        console.error('[HTTP-POLL] 轮询出错:', error.message);
      }
    }, 3000); // 每 3 秒检查一次
    
    // 添加清理函数
    process.on('SIGINT', () => {
      console.log('接收到中断信号，清理资源并退出...');
      cleanupAndExit();
      process.exit(0);
    });
    
    console.log('监听器已设置，等待 enablePresale 方法执行...');
    
  } catch (error) {
    console.error('连接或初始设置时出错:', error);
  }
  
  // 添加错误处理，防止连接问题导致程序崩溃
  provider.on('error', (error) => {
    console.error('Provider 连接错误:', error);
    console.log('尝试重新连接...');
    
    // 清理现有的资源
    cleanupAndExit();
    
    // 5秒后尝试重新启动监听
    setTimeout(() => {
      console.log('重新启动监听...');
      listenForPresaleActivation();
    }, 5000);
  });
}

// 使用 Flashbots 购买 NFT（实际使用 QuickNode）
async function buyNFTWithFlashbots() {
  try {
    console.log('使用 QuickNode 获取区块链数据...');
    
    // 使用 QuickNode 获取当前区块号和下一个区块号
    const publicClientQuickNode = createPublicClient({
      chain: sepolia,
      transport: http(QUICKNODE_RPC_URL, {
        timeout: 30000, // 增加超时时间到 30 秒
        retryCount: 3,  // 失败时重试 3 次
        retryDelay: 1000 // 重试间隔 1 秒
      }),
    });

    // 获取当前区块号
    console.log('获取当前区块号...');
    let currentBlockNumber;
    try {
      currentBlockNumber = await publicClientQuickNode.getBlockNumber();
    } catch (blockError) {
      console.error('获取区块号失败:', blockError.message);
      console.log('使用备用方法获取区块号...');
      
      // 使用 Sepolia RPC 作为备用
      const backupClient = createPublicClient({
        chain: sepolia,
        transport: http(SEPOLIA_RPC_URL),
      });
      currentBlockNumber = await backupClient.getBlockNumber();
    }
    
    const targetBlockNumber = currentBlockNumber + 1n;
    console.log(`当前区块: ${currentBlockNumber}, 目标区块: ${targetBlockNumber}`);
    
    // 创建 QuickNode 钱包客户端
    const walletClientQuickNode = createWalletClient({
      account,
      chain: sepolia,
      transport: http(QUICKNODE_RPC_URL, {
        timeout: 30000,
        retryCount: 3,
        retryDelay: 1000
      }),
    });
    
    console.log('准备交易数据...');
    
    // 使用 QuickNode 直接发送交易
    console.log('使用 QuickNode 发送交易...');
    try {
      const hash = await walletClientQuickNode.writeContract({
        address: NFT_CONTRACT_ADDRESS,
        abi: NFT_ABI,
        functionName: 'presale',
        args: [AMOUNT_TO_BUY],
        value: PRICE_PER_NFT * BigInt(AMOUNT_TO_BUY),
        gas: 500000n,
      });
      
      console.log('交易已提交，交易哈希:', hash);
      
      // 等待交易确认
      console.log('等待交易确认...');
      const receipt = await publicClientQuickNode.waitForTransactionReceipt({ 
        hash,
        timeout: 60000, // 60 秒超时
        confirmations: 1 // 需要 1 个确认
      });
      
      console.log('交易已确认!');
      console.log(`区块号: ${receipt.blockNumber}`);
      console.log(`状态: ${receipt.status === 1n ? '成功' : '失败'}`);
      
      return receipt.status === 1n;
    } catch (txError) {
      console.error('QuickNode 交易失败:', txError.message);
      
      // 如果是 gas 估算错误，尝试使用更高的 gas
      if (txError.message.includes('gas') || txError.message.includes('fee')) {
        console.log('尝试使用更高的 gas 限制和价格...');
        
        try {
          const hash = await walletClientQuickNode.writeContract({
            address: NFT_CONTRACT_ADDRESS,
            abi: NFT_ABI,
            functionName: 'presale',
            args: [AMOUNT_TO_BUY],
            value: PRICE_PER_NFT * BigInt(AMOUNT_TO_BUY),
            gas: 1000000n, // 更高的 gas 限制
            maxFeePerGas: parseEther('0.000000100'), // 100 Gwei
            maxPriorityFeePerGas: parseEther('0.000000050'), // 50 Gwei
          });
          
          console.log('交易已提交（高 gas），交易哈希:', hash);
          
          // 等待交易确认
          console.log('等待交易确认...');
          const receipt = await publicClientQuickNode.waitForTransactionReceipt({ 
            hash,
            timeout: 60000, // 60 秒超时
            confirmations: 1 // 需要 1 个确认
          });
          
          console.log('交易已确认!');
          console.log(`区块号: ${receipt.blockNumber}`);
          console.log(`状态: ${receipt.status === 1n ? '成功' : '失败'}`);
          
          return receipt.status === 1n;
        } catch (highGasError) {
          console.error('高 gas 交易也失败:', highGasError.message);
          return false;
        }
      }
      
      return false;
    }
  } catch (error) {
    console.error('购买过程中出错:', error.message);
    return false;
  }
}