// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FarmStorage, PoolInfo, UserInfo } from "./FarmStorage.sol";

// Farm distributes the ERC20 rewards based on staked LP to each user.
//
// Forked from https://github.com/SashimiProject/sashimiswap/blob/master/contracts/MasterChef.sol
// Modified for diamonds and decay rate support
library LibFarm {
  using SafeERC20 for IERC20;

  event Deposit(
    address indexed user,
    uint256 indexed pid,
    uint256 amount
  );
  event Withdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 amount
  );
  event EmergencyWithdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 amount
  );
  event Harvest(address indexed user, uint256 amount);

  // Helper getter function for a predefined set of rewards for 30 years
  function rewardPerBlock(uint256 period)
    internal
    pure
    returns (uint256)
  {
    // assumes 13,870,000 blocks per year to distribute a total of 1 trillion GLTR
    uint256[30] memory _rewardPerBlock = [
      uint256(7_209_805_335_256 gwei), // cast to force array to be uint256 (compiler issue)
      6_039_405_905_650 gwei,
      5_059_002_566_246 gwei,
      4_237_752_415_572 gwei,
      3_549_819_416_085 gwei,
      2_973_561_607_920 gwei,
      2_490_850_265_800 gwei,
      2_086_499_580_203 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei,
      1_747_788_920_901 gwei
    ];
    // Rewards should be zero after rewards are exhausted
    if (period >= _rewardPerBlock.length) {
      return 0;
    } else {
      return _rewardPerBlock[period];
    }
  }

  /// @notice Sums up the rewards for a specified number of blocks from the last reward block
  /// @param lastRewardBlock The block number of the last reward block to calculate from
  /// @param nrOfBlocks The number of blocks to calculate rewards for
  function sumRewardPerBlock(
    uint256 lastRewardBlock,
    uint256 nrOfBlocks
  ) internal view returns (uint256 totalReward) {
    uint256 decayPeriod = s().decayPeriod;

    // Blocks passed from the start block to the last reward block
    uint256 blocksPassedToLastRewardSinceStart = lastRewardBlock -
      s().startBlock;
    // Total amount of blocks left in the current period
    uint256 blocksLeftInCurrentPeriod = decayPeriod -
      (blocksPassedToLastRewardSinceStart % decayPeriod);
    // The period of the last reward block
    uint256 currentPeriod = blocksPassedToLastRewardSinceStart /
      decayPeriod;

    // Add min(current period, nrOfBlocks) * rewardPerBlock to total reward
    totalReward +=
      rewardPerBlock(currentPeriod) *
      (
        nrOfBlocks < blocksLeftInCurrentPeriod
          ? nrOfBlocks
          : blocksLeftInCurrentPeriod
      );

    // This block should be skipped and reward should be returned if the first period is the last one
    if (nrOfBlocks > blocksLeftInCurrentPeriod) {
      // We account for rewards being distributed for the first period
      ++currentPeriod;
      nrOfBlocks -= blocksLeftInCurrentPeriod;
      // Add to total rewards for each period that nrOfBlocks fills
      while (nrOfBlocks >= decayPeriod) {
        totalReward += rewardPerBlock(currentPeriod) * decayPeriod;
        nrOfBlocks -= decayPeriod;
        ++currentPeriod;
      }
      // Add the final rewards
      totalReward += rewardPerBlock(currentPeriod) * nrOfBlocks;
    }
  }

  function s() private pure returns (FarmStorage.Layout storage fs) {
    return FarmStorage.layout();
  }

  // Add a new lp to the pool. Can only be called by the owner.
  // DO NOT add the same LP token more than once. Rewards will be messed up if you do.
  function add(
    uint256 _allocPoint,
    IERC20 _lpToken,
    bool _withUpdate
  ) internal {
    require(
      !s().poolTokens[address(_lpToken)],
      "add: LP token already added"
    );
    s().poolTokens[address(_lpToken)] = true;
    if (_withUpdate) {
      massUpdatePools();
    }
    uint256 lastRewardBlock = block.number > s().startBlock
      ? block.number
      : s().startBlock;
    s().totalAllocPoint += _allocPoint;
    s().poolInfo.push(
      PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accERC20PerShare: 0
      })
    );
  }

  // Update the given pool's ERC20 allocation point. Can only be called by the owner.
  function set(
    uint256 _pid,
    uint256 _allocPoint,
    bool _withUpdate
  ) internal {
    require(
      s().poolTokens[address(s().poolInfo[_pid].lpToken)],
      "set: LP token not added"
    );
    if (_withUpdate) {
      massUpdatePools();
    }
    s().totalAllocPoint =
      s().totalAllocPoint -
      s().poolInfo[_pid].allocPoint +
      _allocPoint;
    s().poolInfo[_pid].allocPoint = _allocPoint;
  }

  // Update reward variables for all pools. Be careful of gas spending!
  function massUpdatePools() internal {
    uint256 length = s().poolInfo.length;
    for (uint256 pid = 0; pid < length; ) {
      updatePool(pid);
      unchecked {
        ++pid;
      }
    }
  }

  // Update reward variables of the given pool to be up-to-date.
  function updatePool(uint256 _pid) internal {
    PoolInfo storage pool = s().poolInfo[_pid];

    if (block.number <= pool.lastRewardBlock) {
      return;
    }
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (lpSupply == 0) {
      pool.lastRewardBlock = block.number;
      return;
    }

    uint256 nrOfBlocks = block.number - pool.lastRewardBlock;
    uint256 erc20Reward = (sumRewardPerBlock(
      pool.lastRewardBlock,
      nrOfBlocks
    ) * pool.allocPoint) / s().totalAllocPoint;

    pool.accERC20PerShare += (erc20Reward * 1e18) / lpSupply;
    pool.lastRewardBlock = block.number;
  }

  // Deposit LP tokens to Farm for ERC20 allocation.
  function deposit(uint256 _pid, uint256 _amount) internal {
    PoolInfo storage pool = s().poolInfo[_pid];
    UserInfo storage user = s().userInfo[_pid][msg.sender];

    updatePoolAndHarvest(msg.sender, _pid);

    if (_amount > 0) {
      pool.lpToken.safeTransferFrom(
        address(msg.sender),
        address(this),
        _amount
      );
      user.amount += _amount;
    }
    user.rewardDebt = (user.amount * pool.accERC20PerShare) / 1e18;
    emit Deposit(msg.sender, _pid, _amount);
  }

  // Withdraw LP tokens from Farm.
  function withdraw(uint256 _pid, uint256 _amount) internal {
    PoolInfo storage pool = s().poolInfo[_pid];
    UserInfo storage user = s().userInfo[_pid][msg.sender];
    require(
      user.amount >= _amount,
      "withdraw: can't withdraw more than deposit"
    );

    updatePoolAndHarvest(msg.sender, _pid);

    user.amount = user.amount - _amount;
    user.rewardDebt = (user.amount * pool.accERC20PerShare) / 1e18;
    pool.lpToken.safeTransfer(address(msg.sender), _amount);
    emit Withdraw(msg.sender, _pid, _amount);
  }

  // Withdraw without caring about rewards. EMERGENCY ONLY.
  function emergencyWithdraw(uint256 _pid) internal {
    PoolInfo storage pool = s().poolInfo[_pid];
    UserInfo storage user = s().userInfo[_pid][msg.sender];
    pool.lpToken.safeTransfer(address(msg.sender), user.amount);
    emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    user.amount = 0;
    user.rewardDebt = 0;
  }

  // Updates the pool and harvests reward tokens
  function updatePoolAndHarvest(address _to, uint256 _pid) internal {
    PoolInfo storage pool = s().poolInfo[_pid];
    UserInfo storage user = s().userInfo[_pid][_to];
    updatePool(_pid);

    uint256 userReward = (user.amount * pool.accERC20PerShare) / 1e18;

    if (user.amount > 0) {
      uint256 pendingAmount = userReward - user.rewardDebt;
      s().paidOut += pendingAmount;
      user.rewardDebt = userReward;
      s().rewardToken.transfer(_to, pendingAmount);
      emit Harvest(_to, pendingAmount);
    } else {
      user.rewardDebt = userReward;
    }
  }
}