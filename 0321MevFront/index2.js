import { createPublicClient, createWalletClient, http, parseEther, encodeFunctionData, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import dotenv from 'dotenv';
// 导入 ethers v5
import { ethers } from 'ethers';

// 加载环境变量
dotenv.config();

//  实现监听 enablePresale方法设置 实现Flashbots购买 但未入区块 未实际成交
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
listenForPresaleActivation();

// 监听 NFT 合约的 Presale 激活事件
async function listenForPresaleActivation() {
  // 使用 Sepolia RPC URL
  console.log(`开始监听 Presale 激活事件，已连接到 Sepolia 网络`);
  console.log(`监听合约地址: ${NFT_CONTRACT_ADDRESS}`);
  
  // 创建 provider
  const provider = new ethers.providers.JsonRpcProvider(SEPOLIA_RPC_URL);
  
  // 测试连接
  try {
    const blockNumber = await provider.getBlockNumber();
    console.log(`成功连接到 Sepolia 网络，当前区块: ${blockNumber}`);
    
    // 创建合约实例用于监听事件
    const contract = new ethers.Contract(
      NFT_CONTRACT_ADDRESS,
      NFT_ABI,
      provider
    );
    
    // 检查当前 isPresaleActive 状态
    try {
      const isActive = await contract.isPresaleActive();
      console.log(`当前 isPresaleActive 状态: ${isActive}`);
      
      // 如果已经激活，直接执行购买逻辑
      if (isActive) {
        console.log('Presale 已经处于激活状态! 无需继续监听，直接准备购买...');
        
        // 打开购买功能 - 移除注释并实际执行购买
        console.log('开始执行购买流程...');
        
        try {
          const result = await buyNFTWithFlashbots();
          if (result) {
            console.log('购买成功!', result);
          } else {
            console.log('Flashbots 购买未成功，尝试标准交易...');
            const standardResult = await useStandardTransaction();
            if (standardResult) {
              console.log('标准交易购买成功!', standardResult);
            } else {
              console.log('所有购买尝试均失败');
            }
          }
        } catch (buyError) {
          console.error('购买过程中出错:', buyError);
        }
        
        return; // 如果已经激活，就不需要继续监听了
      }
    } catch (error) {
      console.log('获取合约状态时出错:', error.message);
    }
    
    // 打印一些合约信息以验证连接
    try {
      // 尝试调用一个简单的视图函数
      if (contract.interface.getFunction('isPresaleActive')) {
        const isActive = await contract.isPresaleActive();
        console.log(`当前 isPresaleActive 状态: ${isActive}`);
      }
    } catch (error) {
      console.log('获取合约信息时出错:', error.message);
    }
    
    // 监听合约的所有事件，过滤出 enablePresale 调用
    console.log(`开始实时监听地址: ${NFT_CONTRACT_ADDRESS} 的交易...`);
    
    // 使用 ethers 的 provider 监听区块
    provider.on('block', async (blockNumber) => {
      try {
        console.log(`检查新区块 ${blockNumber}...`);
        
        // 获取区块信息 - 只获取交易哈希
        const block = await provider.getBlock(blockNumber);
        
        // 检查区块中的所有交易
        if (block && block.transactions && block.transactions.length > 0) {
          console.log(`区块 ${blockNumber} 包含 ${block.transactions.length} 个交易`);
          
          // 遍历交易哈希并获取完整交易
          for (const txHash of block.transactions) {
            // 获取完整交易对象
            const tx = await provider.getTransaction(txHash);
            
            if (!tx || !tx.to) continue; // 跳过无效交易
            
            // 检查交易是否与我们的合约相关
            if (tx.to.toLowerCase() === NFT_CONTRACT_ADDRESS.toLowerCase()) {
              console.log(`发现合约交易: ${tx.hash}`);
              console.log(`交易数据: ${tx.data}`);
              
              // 获取交易收据以检查状态
              const receipt = await provider.getTransactionReceipt(tx.hash);
              if (receipt && receipt.status === 1) { // 交易成功
                console.log(`交易 ${tx.hash} 成功执行`);
                
                // 解析交易输入数据
                try {
                  // 尝试解码交易数据
                  const decodedData = contract.interface.parseTransaction({ data: tx.data });
                  console.log('解码的函数名:', decodedData.name);
                  console.log('解码的参数:', decodedData.args);
                  
                  // 检查是否是 enablePresale 函数调用
                  if (decodedData.name === 'enablePresale') {
                    console.log('检测到 enablePresale 函数调用!');
                    console.log('参数:', decodedData.args);
                    
                    // 检查 _state 参数是否为 true
                    if (decodedData.args[0] === true) {
                      console.log('Presale 已激活! 准备购买...');
                      
                      // 检查当前 isPresaleActive 状态
                      const isActive = await contract.isPresaleActive();
                      console.log(`合约 isPresaleActive 状态: ${isActive}`);
                      
                      if (isActive) {
                        // 执行购买逻辑
                        console.log('确认 Presale 已激活，开始购买流程...');
                        
                        // 打开购买功能
                        try {
                          const result = await buyNFTWithFlashbots();
                          if (result) {
                            console.log('购买成功!', result);
                          } else {
                            console.log('Flashbots 购买未成功，尝试标准交易...');
                            const standardResult = await useStandardTransaction();
                            if (standardResult) {
                              console.log('标准交易购买成功!', standardResult);
                            } else {
                              console.log('所有购买尝试均失败');
                            }
                          }
                        } catch (buyError) {
                          console.error('购买过程中出错:', buyError);
                        }
                        
                        // 停止监听，购买完成
                        console.log('购买流程完成，停止监听');
                        provider.removeAllListeners();
                        return;
                      } else {
                        console.log('奇怪，虽然检测到 enablePresale(true)，但合约状态显示 Presale 未激活');
                      }
                    } else {
                      console.log('enablePresale 被设置为 false，继续监听...');
                    }
                  }
                } catch (decodeError) {
                  console.log(`无法解码交易 ${tx.hash} 的数据:`, decodeError.message);
                  
                  // 尝试手动检查函数签名
                  const functionSignature = tx.data.substring(0, 10); // 前4个字节是函数签名
                  console.log('函数签名:', functionSignature);
                  
                  // enablePresale(bool) 的函数签名
                  if (functionSignature.toLowerCase() === '0x15e81934') {
                    console.log('函数签名匹配 enablePresale(bool)!');
                    
                    // 尝试手动解析参数
                    const paramData = tx.data.substring(10);
                    console.log('参数数据:', paramData);
                    
                    // bool 参数通常是 32 字节，如果最后一个字节是 1，则为 true
                    const isTrue = paramData.endsWith('01');
                    console.log('参数解析为:', isTrue ? 'true' : 'false');
                    
                    if (isTrue) {
                      console.log('检测到 enablePresale(true) 调用!');
                      console.log('【测试模式】检测成功，但暂不执行购买操作');
                      provider.removeAllListeners();
                      return;
                    }
                  }
                }
              } else {
                console.log(`交易 ${tx.hash} 执行失败或待处理`);
              }
            }
          }
        }
      } catch (error) {
        console.error('监听区块时出错:', error);
      }
    });
    
    console.log('监听器已设置，等待 Presale 激活...');
    
  } catch (error) {
    console.error('连接或初始检查时出错:', error);
  }
  
  // 添加错误处理，防止连接问题导致程序崩溃
  provider.on('error', (error) => {
    console.error('Provider 连接错误:', error);
    console.log('尝试重新连接...');
    
    // 5秒后尝试重新启动监听
    setTimeout(() => {
      console.log('重新启动监听...');
      listenForPresaleActivation();
    }, 5000);
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