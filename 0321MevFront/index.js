import { createPublicClient, createWalletClient, http, parseEther, encodeFunctionData, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import dotenv from 'dotenv';
// 导入 ethers v5
import { ethers } from 'ethers';

// 加载环境变量
dotenv.config();

// 从 .env 获取配置
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const NFT_CONTRACT_ADDRESS = process.env.NFT_CONTRACT_ADDRESS;
const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL;
const SEPOLIA_WS_URL = process.env.SEPOLIA_WS_URL;
const FLASHBOTS_RPC = process.env.FLASHBOTS_RPC;

// 验证环境变量
if (!PRIVATE_KEY || !NFT_CONTRACT_ADDRESS || !SEPOLIA_RPC_URL || !SEPOLIA_WS_URL || !FLASHBOTS_RPC) {
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
  // 使用 Sepolia RPC URL 和 WebSocket URL
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
  console.log(`WebSocket RPC: ${maskUrl(SEPOLIA_WS_URL)}`);
  console.log(`监听合约地址: ${NFT_CONTRACT_ADDRESS}`);
  
  // 创建 HTTP provider 用于常规查询和购买
  const provider = new ethers.providers.JsonRpcProvider(SEPOLIA_RPC_URL);
  
  // 设置标志
  let hasPurchased = false;  // 是否已尝试购买（无论成功与否）
  let processedTxHashes = new Set(); // 已处理的交易哈希集合
  
  // 创建 WebSocket provider 用于 pending 交易监听
  let wsProvider = null;
  let wsCheckInterval = null;
  
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
        console.log(`[${source}] ⚠️ Flashbots 购买未成功，尝试标准交易...`);
        
        console.log(`[${source}] 尝试使用标准交易购买...`);
        const standardResult = await useStandardTransaction();
        
        if (standardResult) {
          console.log(`[${source}] ✅ 标准交易购买成功!`);
          
          // 购买完成，停止所有监听
          console.log(`[${source}] 🏁 购买流程完成，停止所有监听`);
          cleanupAndExit();
          return true;
        } else {
          console.log(`[${source}] ❌ 所有购买尝试均失败，不再重试`);
          
          // 购买失败，但仍然停止所有监听（只尝试一次）
          console.log(`[${source}] 🏁 购买尝试完成，停止所有监听`);
          cleanupAndExit();
          return false;
        }
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
  const checkPresaleStatusAndBuy = async (txHash, source) => {
    if (hasPurchased) return; // 如果已经购买，不再检查
    
    const contract = new ethers.Contract(
      NFT_CONTRACT_ADDRESS,
      NFT_ABI,
      provider
    );
    
    console.log(`[${source}] 🔍 检测到 enablePresale 调用，开始检查 isPresaleActive 状态...`);
    
    // 多次检查 isPresaleActive 状态，直到激活或超时
    let attempts = 0;
    const maxAttempts = 20; // 最多检查 20 次
    const checkInterval = 500; // 每次检查间隔 0.5 秒
    
    const checkStatus = async () => {
      attempts++;
      const isActive = await contract.isPresaleActive();
      console.log(`[${source}] 检查 #${attempts}: isPresaleActive = ${isActive} (${new Date().toISOString()})`);
      
      if (isActive) {
        console.log(`[${source}] ✅ isPresaleActive 已激活，立即购买!`);
        await executePurchase(source);
        return true;
      }
      
      if (attempts >= maxAttempts) {
        console.log(`[${source}] ⚠️ 已达到最大检查次数 (${maxAttempts})，停止检查`);
        return false;
      }
      
      // 继续检查
      return new Promise(resolve => {
        setTimeout(async () => {
          const result = await checkStatus();
          resolve(result);
        }, checkInterval);
      });
    };
    
    await checkStatus();
  };
  
  // 清理资源并退出的函数
  const cleanupAndExit = () => {
    console.log('清理资源...');
    if (wsCheckInterval) {
      clearInterval(wsCheckInterval);
      wsCheckInterval = null;
    }
    
    if (wsProvider) {
      try {
        wsProvider.removeAllListeners();
        wsProvider.destroy();
      } catch (e) {
        console.log('清理 WebSocket 提供商时出错:', e.message);
      }
      wsProvider = null;
    }
    
    provider.removeAllListeners();
    console.log('资源清理完成');
  };
  
  // 设置 WebSocket 提供商和监听器
  const setupWebSocketProvider = () => {
    try {
      console.log('尝试设置 WebSocket 连接...');
      wsProvider = new ethers.providers.WebSocketProvider(SEPOLIA_WS_URL);
      
      // 计算 enablePresale 函数的选择器
      const enablePresaleInterface = new ethers.utils.Interface([
        "function enablePresale(bool _state)"
      ]);
      const enablePresaleSelector = enablePresaleInterface.getSighash("enablePresale");
      console.log(`enablePresale 函数的选择器: ${enablePresaleSelector}`);
      
      // 监听 pending 交易
      wsProvider.on("pending", async (txHash) => {
        if (hasPurchased) return; // 如果已经购买，不再监听
        
        try {
          // 检查是否已处理过这个交易
          if (processedTxHashes.has(txHash)) {
            return;
          }
          
          // 获取交易详情
          const tx = await wsProvider.getTransaction(txHash);
          
          // 如果交易不存在或者不是发送到我们的合约，跳过
          if (!tx || !tx.to || tx.to.toLowerCase() !== NFT_CONTRACT_ADDRESS.toLowerCase()) {
            return;
          }
          
          // 标记为已处理
          processedTxHashes.add(txHash);
          
          console.log(`[WS-PENDING] 发现合约交易: ${txHash}`);
          
          // 获取交易数据
          const txData = tx.data || tx.input;
          
          // 检查交易是否有数据
          if (!txData || txData === '0x') {
            console.log(`[WS-PENDING] 交易没有数据，跳过`);
            return;
          }
          
          // 获取函数选择器（前 10 个字符，包括 0x 前缀）
          const selector = txData.slice(0, 10);
          console.log(`[WS-PENDING] 函数选择器: ${selector}`);
          
          // 检查是否是 enablePresale 函数调用
          if (selector === enablePresaleSelector) {
            console.log('[WS-PENDING] 🎯 检测到 enablePresale 函数调用!');
            
            try {
              // 解码函数参数
              const decodedData = enablePresaleInterface.decodeFunctionData("enablePresale", txData);
              console.log(`[WS-PENDING] 解码参数: ${decodedData[0]}`); // _state 参数
              
              // 检查 _state 参数是否为 true
              if (decodedData[0] === true) {
                console.log('[WS-PENDING] 🔥 enablePresale(true) 调用，Presale 即将激活!');
                
                // 检查状态并购买
                await checkPresaleStatusAndBuy(txHash, 'WS-PENDING');
              }
            } catch (decodeError) {
              console.log(`[WS-PENDING] 解码交易数据时出错: ${decodeError.message}`);
            }
          } else if (selector === '0xd1454bf4') {
            // 特殊处理 0xd1454bf4 选择器
            console.log('[WS-PENDING] 🎯 检测到选择器 0xd1454bf4，这可能是 enablePresale 函数!');
            
            // 尝试手动解析参数
            const paramValue = txData.slice(10);
            
            // 检查参数是否为 true（通常是一堆 0 后跟一个 1）
            if (paramValue.endsWith('01')) {
              console.log('[WS-PENDING] 🔥 参数似乎是 true，可能是 Presale 激活!');
              
              // 检查状态并购买
              await checkPresaleStatusAndBuy(txHash, 'WS-PENDING');
            }
          }
        } catch (error) {
          console.error('处理 pending 交易时出错:', error.message);
        }
      });
      
      console.log('WebSocket pending 交易监听器已设置');
      
      // 使用 HTTP 轮询作为备份
      const checkPendingTransactions = async () => {
        if (hasPurchased) return; // 如果已经购买，不再检查
        
        try {
          const pendingBlock = await provider.send("eth_getBlockByNumber", ["pending", true]);
          
          if (!pendingBlock || !pendingBlock.transactions) {
            return;
          }
          
          // 遍历所有 pending 交易
          for (const tx of pendingBlock.transactions) {
            // 检查是否已处理过这个交易
            if (processedTxHashes.has(tx.hash)) {
              continue;
            }
            
            // 检查交易是否发送到我们的合约
            if (tx.to && tx.to.toLowerCase() === NFT_CONTRACT_ADDRESS.toLowerCase()) {
              // 标记为已处理
              processedTxHashes.add(tx.hash);
              
              console.log(`[HTTP-PENDING] 发现合约交易: ${tx.hash}`);
              
              // 获取交易数据
              const txData = tx.input || tx.data;
              
              // 检查交易是否有数据
              if (!txData || txData === '0x') {
                console.log(`[HTTP-PENDING] 交易没有数据，跳过`);
                continue;
              }
              
              // 获取函数选择器（前 10 个字符，包括 0x 前缀）
              const selector = txData.slice(0, 10);
              console.log(`[HTTP-PENDING] 函数选择器: ${selector}`);
              
              // 检查是否是 enablePresale 函数调用
              if (selector === enablePresaleSelector) {
                console.log('[HTTP-PENDING] 🎯 检测到 enablePresale 函数调用!');
                
                try {
                  // 解码函数参数
                  const decodedData = enablePresaleInterface.decodeFunctionData("enablePresale", txData);
                  console.log(`[HTTP-PENDING] 解码参数: ${decodedData[0]}`); // _state 参数
                  
                  // 检查 _state 参数是否为 true
                  if (decodedData[0] === true) {
                    console.log('[HTTP-PENDING] 🔥 enablePresale(true) 调用，Presale 即将激活!');
                    
                    // 检查状态并购买
                    await checkPresaleStatusAndBuy(tx.hash, 'HTTP-PENDING');
                  }
                } catch (decodeError) {
                  console.log(`[HTTP-PENDING] 解码交易数据时出错: ${decodeError.message}`);
                }
              } else if (selector === '0xd1454bf4') {
                // 特殊处理 0xd1454bf4 选择器
                console.log('[HTTP-PENDING] 🎯 检测到选择器 0xd1454bf4，这可能是 enablePresale 函数!');
                
                // 尝试手动解析参数
                const paramValue = txData.slice(10);
                
                // 检查参数是否为 true（通常是一堆 0 后跟一个 1）
                if (paramValue.endsWith('01')) {
                  console.log('[HTTP-PENDING] 🔥 参数似乎是 true，可能是 Presale 激活!');
                  
                  // 检查状态并购买
                  await checkPresaleStatusAndBuy(tx.hash, 'HTTP-PENDING');
                }
              }
            }
          }
        } catch (error) {
          console.error('检查 pending 交易时出错:', error.message);
        }
      };
      
      // 每 2 秒检查一次 pending 交易
      const pendingCheckInterval = setInterval(checkPendingTransactions, 2000);
      
      // 设置心跳检查，确保连接正常
      wsCheckInterval = setInterval(() => {
        try {
          if (wsProvider) {
            wsProvider.getBlockNumber().catch(error => {
              console.log('WebSocket 心跳检查失败:', error.message);
              console.log('尝试重新设置 WebSocket...');
              
              // 清理现有的 WebSocket
              clearInterval(pendingCheckInterval);
              if (wsProvider) {
                try {
                  wsProvider.removeAllListeners();
                  wsProvider.destroy();
                } catch (e) {}
                wsProvider = null;
              }
              
              // 重新设置 WebSocket
              setTimeout(setupWebSocketProvider, 5000);
            });
          }
        } catch (error) {
          console.error('心跳检查出错:', error.message);
        }
      }, 30000);
      
      // 初始检查
      checkPendingTransactions();
      
    } catch (wsError) {
      console.error('❌ WebSocket 设置失败:', wsError.message);
      console.log('⚠️ 将使用 HTTP 轮询作为备份');
      
      // 60 秒后重试
      setTimeout(setupWebSocketProvider, 60000);
    }
  };
  
  // 测试连接
  try {
    const blockNumber = await provider.getBlockNumber();
    console.log(`成功连接到 Sepolia 网络，当前区块: ${blockNumber}`);
    
    // 创建合约实例
    const contract = new ethers.Contract(
      NFT_CONTRACT_ADDRESS,
      NFT_ABI,
      provider
    );
    
    // 打印 ABI 中的所有函数，用于调试
    console.log('合约 ABI 中的函数:');
    const functions = NFT_ABI.filter(item => item.type === 'function').map(fn => fn.name);
    console.log(functions);
    
    // 设置 WebSocket 提供商和监听器
    setupWebSocketProvider();
    
    console.log('监听器已设置，等待 Presale 激活...');
    
  } catch (error) {
    console.error('连接或初始检查时出错:', error);
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
  
  // 处理程序退出
  process.on('SIGINT', () => {
    console.log('接收到中断信号，清理资源并退出...');
    cleanupAndExit();
    process.exit(0);
  });
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
    // const priorityGasPrice = gasPrice * 200n / 100n; // 增加 100% 的 gas 价格，提高被包含的可能性
    const priorityGasPrice = gasPrice * 3000n / 100n; // 增加 100% 的 gas 价格，提高被包含的可能性
    
    console.log(`最终设置的 gas 限制: ${gasLimit}, 提高后的 gas 价格: ${priorityGasPrice}`);
    console.log(`原始 gas 价格: ${ethers.utils.formatUnits(gasPrice.toString(), 'gwei')} gwei, 提高后: ${ethers.utils.formatUnits(priorityGasPrice.toString(), 'gwei')} gwei`);

    // 创建单个交易购买多个 NFT
    const transaction = {
      to: NFT_CONTRACT_ADDRESS,
      data: presaleCalldata,
      value: PRICE_PER_NFT * BigInt(AMOUNT_TO_BUY),
      gasLimit: gasLimit,
      chainId: 11155111, // Sepolia 链 ID
      gasPrice: priorityGasPrice,
      type: '0x0', // Legacy 交易
      nonce: await publicClient.getTransactionCount({
        address: account.address
      })
    };
    
    // 签名交易
    const signedTransaction = await walletClient.signTransaction(transaction);
    
    // 不要直接打印长字符串，可能会被截断
    console.log('已签名的交易长度:', signedTransaction.length);
    
    // 获取当前时间戳
    const currentTimestamp = Math.floor(Date.now() / 1000);
    
    // 尝试使用 Flashbots
    console.log('尝试使用 Flashbots 发送交易...');
    
    // 构建 Flashbots 请求 - 严格按照官方示例
    const params = {
      txs: [signedTransaction],
      blockNumber: "0x" + targetBlockNumber.toString(16),
      minTimestamp: currentTimestamp,
      maxTimestamp: currentTimestamp + 120
    };
    
    const flashbotsRequest = {
      jsonrpc: "2.0",
      id: 1, // JSON-RPC 请求的唯一标识符，用于匹配请求和响应
      method: "eth_sendBundle",
      params: [params]
    };
    
    // 将请求转换为 JSON 字符串
    const body = JSON.stringify(flashbotsRequest);
    
    // 创建 ethers v5 钱包
    const wallet = new ethers.Wallet(PRIVATE_KEY);
    
    // 使用 ethers v5 的方法签名 - 按照您成功的方法
    console.log('使用 ethers v5 签名...');
    
    // 计算哈希并签名
    const signature = wallet.address + ':' + await wallet.signMessage(ethers.utils.id(body));
    
    console.log('Flashbots 签名头部长度:', signature.length);
    
    // 发送请求到 Flashbots
    console.log('发送请求到 Flashbots...');
    const response = await fetch(FLASHBOTS_RPC, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'X-Flashbots-Signature': signature
      },
      body: body,
    });
    
    console.log('Flashbots 响应状态:', response.status);
    
    const bundleResponse = await response.json();
    console.log('Flashbots bundle 提交结果:', bundleResponse);
    
    if (bundleResponse.error) {
      console.error('Flashbots 提交失败:', bundleResponse.error);
      console.log('暂时不尝试标准交易，仅测试 Flashbots');
      return null;
    } else {
      // 从响应中提取 bundleHash
      const bundleHash = bundleResponse.result.bundleHash;
      console.log('Flashbots bundle 哈希:', bundleHash);
      
      // 等待交易确认
      console.log('等待 Flashbots 交易确认...');
      await new Promise(resolve => setTimeout(resolve, 15000));
      
      // 使用 flashbots_getBundleStatsV2 获取 bundle 状态
      console.log('使用 flashbots_getBundleStatsV2 获取 bundle 状态...');
      
      const statsParams = {
        bundleHash: bundleHash,
        blockNumber: "0x" + targetBlockNumber.toString(16)
      };
      
      const statsRequest = {
        jsonrpc: "2.0",
        id: 2, // 不同的 id，用于区分不同的 JSON-RPC 请求
        method: "flashbots_getBundleStatsV2",
        params: [statsParams]
      };
      
      const statsBody = JSON.stringify(statsRequest);
      
      // 签名统计请求
      const statsSignature = wallet.address + ':' + await wallet.signMessage(ethers.utils.id(statsBody));
      
      // 发送请求到 Flashbots
      const statsResponse = await fetch(FLASHBOTS_RPC, {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'X-Flashbots-Signature': statsSignature
        },
        body: statsBody,
      });
      
      console.log('Flashbots 统计响应状态:', statsResponse.status);
      
      const statsResult = await statsResponse.json();
      console.log('Flashbots bundle 统计结果:', statsResult);
      
      if (statsResult.error) {
        console.error('获取 Flashbots 统计失败:', statsResult.error);
        
        // 尝试检查下一个区块
        console.log('尝试检查下一个区块的 bundle 状态...');
        
        const nextBlockStatsParams = {
          bundleHash: bundleHash,
          blockNumber: "0x" + (targetBlockNumber + 1n).toString(16)
        };
        
        const nextBlockStatsRequest = {
          jsonrpc: "2.0",
          id: 3, // 又一个不同的 id
          method: "flashbots_getBundleStatsV2",
          params: [nextBlockStatsParams]
        };
        
        const nextBlockStatsBody = JSON.stringify(nextBlockStatsRequest);
        
        // 签名统计请求
        const nextBlockStatsSignature = wallet.address + ':' + await wallet.signMessage(ethers.utils.id(nextBlockStatsBody));
        
        // 发送请求到 Flashbots
        const nextBlockStatsResponse = await fetch(FLASHBOTS_RPC, {
          method: 'POST',
          headers: { 
            'Content-Type': 'application/json',
            'X-Flashbots-Signature': nextBlockStatsSignature
          },
          body: nextBlockStatsBody,
        });
        
        console.log('下一个区块 Flashbots 统计响应状态:', nextBlockStatsResponse.status);
        
        const nextBlockStatsResult = await nextBlockStatsResponse.json();
        console.log('下一个区块 Flashbots bundle 统计结果:', nextBlockStatsResult);
        
        // 检查是否有交易哈希
        if (nextBlockStatsResult.result && nextBlockStatsResult.result.transactions && nextBlockStatsResult.result.transactions.length > 0) {
          console.log('找到链上交易哈希:', nextBlockStatsResult.result.transactions);
        }
        
        if (nextBlockStatsResult.error) {
          console.error('获取下一个区块 Flashbots 统计失败:', nextBlockStatsResult.error);
        } else if (nextBlockStatsResult.result && nextBlockStatsResult.result.isIncluded) {
          console.log('Bundle 已包含在下一个区块中!');
          
          // 尝试从 bundle 中提取交易哈希
          if (nextBlockStatsResult.result.transactions && nextBlockStatsResult.result.transactions.length > 0) {
            const txHash = nextBlockStatsResult.result.transactions[0];
            console.log('链上交易哈希:', txHash);
            
            // 尝试获取交易收据
            try {
              const receipt = await publicClient.getTransactionReceipt({
                hash: txHash
              });
              
              if (receipt) {
                console.log('交易已确认:', receipt.status);
                return receipt;
              }
            } catch (error) {
              console.log('无法获取交易收据:', error);
            }
          }
        }
      } else if (statsResult.result && statsResult.result.isIncluded) {
        console.log('Bundle 已包含在目标区块中!');
        
        // 尝试从 bundle 中提取交易哈希
        if (statsResult.result.transactions && statsResult.result.transactions.length > 0) {
          const txHash = statsResult.result.transactions[0];
          console.log('链上交易哈希:', txHash);
          
          // 尝试获取交易收据
          try {
            const receipt = await publicClient.getTransactionReceipt({
              hash: txHash
            });
            
            if (receipt) {
              console.log('交易已确认:', receipt.status);
              return receipt;
            }
          } catch (error) {
            console.log('无法获取交易收据:', error);
          }
        }
      } else {
        console.log('Bundle 未包含在目标区块中');
        console.log('尝试检查更多区块（最多检查 5 个额外区块）...');
        
        // 检查额外的几个区块
        for (let i = 2; i <= 5; i++) {
          // 只在最后一次检查时打印日志
          if (i === 5) {
            console.log(`检查目标区块 +${i}...`);
          }
          
          const laterBlockStatsParams = {
            bundleHash: bundleHash,
            blockNumber: "0x" + (targetBlockNumber + BigInt(i)).toString(16)
          };
          
          const laterBlockStatsRequest = {
            jsonrpc: "2.0",
            id: 3 + i, // 递增的 id
            method: "flashbots_getBundleStatsV2",
            params: [laterBlockStatsParams]
          };
          
          const laterBlockStatsBody = JSON.stringify(laterBlockStatsRequest);
          
          // 签名统计请求
          const laterBlockStatsSignature = wallet.address + ':' + await wallet.signMessage(ethers.utils.id(laterBlockStatsBody));
          
          // 发送请求到 Flashbots
          const laterBlockStatsResponse = await fetch(FLASHBOTS_RPC, {
            method: 'POST',
            headers: { 
              'Content-Type': 'application/json',
              'X-Flashbots-Signature': laterBlockStatsSignature
            },
            body: laterBlockStatsBody,
          });
          
          const laterBlockStatsResult = await laterBlockStatsResponse.json();
          
          // 检查是否有交易哈希
          if (laterBlockStatsResult.result && laterBlockStatsResult.result.transactions && laterBlockStatsResult.result.transactions.length > 0) {
            console.log(`找到链上交易哈希 (区块 +${i}):`, laterBlockStatsResult.result.transactions);
          }
          
          if (laterBlockStatsResult.error) {
            console.log(`获取区块 +${i} Flashbots 统计失败:`, laterBlockStatsResult.error);
          } else if (laterBlockStatsResult.result && laterBlockStatsResult.result.isIncluded) {
            console.log(`Bundle 已包含在区块 +${i} 中!`);
            
            // 尝试从 bundle 中提取交易哈希
            if (laterBlockStatsResult.result.transactions && laterBlockStatsResult.result.transactions.length > 0) {
              const txHash = laterBlockStatsResult.result.transactions[0];
              console.log('链上交易哈希:', txHash);
              
              // 尝试获取交易收据
              try {
                const receipt = await publicClient.getTransactionReceipt({
                  hash: txHash
                });
                
                if (receipt) {
                  console.log('交易已确认:', receipt.status);
                  return receipt;
                }
              } catch (error) {
                console.log('无法获取交易收据:', error);
              }
            }
            
            break;
          }
        }
      }
      
      // 获取账户余额变化
      const balanceWei = await publicClient.getBalance({
        address: account.address,
      });
      
      // 将 Wei 转换为 Ether 并保留 6 位小数
      const balanceEther = ethers.utils.formatEther(balanceWei.toString());
      console.log(`当前账户余额: ${balanceEther} ETH`);
      
      console.log('请检查您的钱包或区块浏览器以确认交易状态');
      
      return {
        status: 'unknown',
        bundleHash: bundleHash
      };
    }
    
  } catch (flashbotsError) {
    console.error('Flashbots 方式失败:', flashbotsError);
    console.log('暂时不尝试标准交易，仅测试 Flashbots');
    return null;
  }
}

// 标准交易方式 - 单独封装
async function useStandardTransaction() {
  console.log('尝试使用标准交易方式...');
  try {
    const hash = await walletClient.writeContract({
      address: NFT_CONTRACT_ADDRESS,
      abi: NFT_ABI,
      functionName: 'presale',
      args: [AMOUNT_TO_BUY],
      value: PRICE_PER_NFT * BigInt(AMOUNT_TO_BUY),
      gas: 500000n,
    });
    
    console.log('标准交易已提交，交易哈希:', hash);
    
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    console.log('标准交易状态:', receipt.status);
    
    return receipt; // 返回交易收据
  } catch (error) {
    console.error('标准交易方式失败:', error);
    throw error;
  }
}

// 简化的交易方式 - 单独封装
async function useSimplifiedTransaction() {
  console.log('尝试使用简化的 writeContract 方法...');
  try {
    const hash = await walletClient.writeContract({
      address: NFT_CONTRACT_ADDRESS,
      abi: NFT_ABI,
      functionName: 'presale',
      args: [AMOUNT_TO_BUY],
      value: PRICE_PER_NFT * BigInt(AMOUNT_TO_BUY),
    });
    
    console.log('简化交易已提交，交易哈希:', hash);
    
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    console.log('简化交易状态:', receipt.status);
    
    return receipt; // 返回交易收据
  } catch (error) {
    console.error('简化交易方式失败:', error);
    throw error;
  }
}