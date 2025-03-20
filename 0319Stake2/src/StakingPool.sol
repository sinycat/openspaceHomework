// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface for the KK Token, which extends the ERC20 interface
interface IToken is IERC20 {
    // Function to mint new tokens
    function mint(address to, uint256 amount) external;
}

// Interface for the staking functionality
interface IStaking {
    // Stake ETH into the contract
    function stake() payable external;

    // Unstake a specified amount of ETH
    function unstake(uint256 amount) external;

    // Claim KK Token rewards
    function claim() external;

    // Get the staked ETH balance of an account
    function balanceOf(address account) external view returns (uint256);

    // Get the pending KK Token rewards for an account
    function earned(address account) external view returns (uint256);
}

// StakingPool contract implementing the IStaking interface
contract StakingPool is IStaking {
    // KK Token contract instance
    IToken public kkToken;
    // Reward per block in KK Tokens
    uint256 public rewardPerBlock = 10;
    uint256 public lastRewardBlock;
    uint256 public totalStaked;
    uint256 public accumulatedRewardPerShare;
    uint256 public unallocatedReward;

    // Mapping to store staked balances of each account
    mapping(address => uint256) private _balances;
    // Mapping to store rewards of each account
    mapping(address => uint256) private _rewardDebt;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    // Constructor to initialize the KK Token contract address
    constructor(address kkTokenAddress) {
        kkToken = IToken(kkTokenAddress);
        lastRewardBlock = block.number;
    }

    // Function to stake ETH into the contract
    function stake() payable external override {
        _updatePool();
        if (_balances[msg.sender] > 0) {
            uint256 pending = _balances[msg.sender] * accumulatedRewardPerShare / 1e18 - _rewardDebt[msg.sender];
            if (pending > 0) {
                kkToken.mint(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }
        _balances[msg.sender] += msg.value;
        totalStaked += msg.value;
        _rewardDebt[msg.sender] = _balances[msg.sender] * accumulatedRewardPerShare / 1e18;
        emit Staked(msg.sender, msg.value);
    }

    // Function to unstake a specified amount of ETH
    function unstake(uint256 amount) external override {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _updatePool();
        uint256 pending = _balances[msg.sender] * accumulatedRewardPerShare / 1e18 - _rewardDebt[msg.sender];
        if (pending > 0) {
            kkToken.mint(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }
        _balances[msg.sender] -= amount;
        totalStaked -= amount;
        _rewardDebt[msg.sender] = _balances[msg.sender] * accumulatedRewardPerShare / 1e18;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "ETH transfer failed");
        emit Unstaked(msg.sender, amount);
    }

    // Function to claim KK Token rewards
    function claim() external override {
        _updatePool();
        uint256 reward = _balances[msg.sender] * accumulatedRewardPerShare / 1e18 - _rewardDebt[msg.sender];
        if (reward > 0) {
            kkToken.mint(msg.sender, reward);
            _rewardDebt[msg.sender] = _balances[msg.sender] * accumulatedRewardPerShare / 1e18;
        }
    }

    // Function to get the staked ETH balance of an account
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    // Function to get the pending KK Token rewards for an account
    function earned(address account) external view override returns (uint256) {
        return _balances[account] * accumulatedRewardPerShare / 1e18 - _rewardDebt[account];
    }

    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint256 blocks = block.number - lastRewardBlock;
        uint256 reward = blocks * rewardPerBlock;
        if (totalStaked == 0) {
            unallocatedReward += reward;
            return;
        }
        accumulatedRewardPerShare += (reward + unallocatedReward) * 1e18 / totalStaked;
        unallocatedReward = 0;
        lastRewardBlock = block.number;
    }
}
