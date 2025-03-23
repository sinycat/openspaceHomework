import { createPublicClient, createWalletClient, http, parseEther, encodeFunctionData, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import dotenv from 'dotenv';
// 导入 ethers v5
import { ethers } from 'ethers';

// 加载环境变量
dotenv.config();

//  实现Flashbots购买 但未入区块 未实际成交
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
monitorAndBuyNFT().catch(console.error);

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
      try {
        await buyNFTWithFlashbots();
      } catch (error) {
        console.error('Flashbots 购买失败，尝试标准方法');
        try {
          await useStandardTransaction();
        } catch (standardError) {
          console.error('标准方法失败，尝试简化方法');
          await useSimplifiedTransaction();
        }
      }
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
          try {
            await buyNFTWithFlashbots();
          } catch (error) {
            console.error('Flashbots 购买失败，尝试标准方法');
            try {
              await useStandardTransaction();
            } catch (standardError) {
              console.error('标准方法失败，尝试简化方法');
              await useSimplifiedTransaction();
            }
          }
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
    const priorityGasPrice = gasPrice * 200n / 100n; // 增加 100% 的 gas 价格，提高被包含的可能性
    
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
        
        // 检查更多区块
        console.log('尝试检查更多区块...');
        for (let i = 2; i <= 5; i++) {
          console.log(`检查目标区块 +${i}...`);
          
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