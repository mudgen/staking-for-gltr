// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct UserInfo {
  uint256 amount; // How many LP tokens the user has provided.
  uint256 rewardDebt; // Reward debt.
}

// Info of each pool.
struct PoolInfo {
  IERC20 lpToken; // Address of LP token contract.
  uint256 allocPoint; // How many allocation points assigned to this pool. ERC20s to distribute per block.
  uint256 lastRewardBlock; // Last block number that ERC20s distribution occurs.
  uint256 accERC20PerShare; // Accumulated ERC20s per share, times 1e12.
}

library FarmStorage {
  struct Layout {
    IERC20 rewardToken; // Address of the ERC20 Token contract.
    uint256 totalRewards; // Amount of rewards to be distributed over the lifetime of the contract
    uint256 paidOut; // The total amount of ERC20 that's paid out as reward.
    PoolInfo[] poolInfo; // Info of each pool.
    mapping(address => bool) poolTokens; // Keep track of which LP tokens are assigned to a pool
    mapping(uint256 => mapping(address => UserInfo)) userInfo; // Info of each user that stakes LP tokens.
    uint256 totalAllocPoint; // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 startBlock; // The block number when farming starts.
    uint256 decayPeriod; // # of blocks after which rewards decay.
  }

  bytes32 internal constant STORAGE_SLOT =
    keccak256("aavegotchi.gax.storage.Farm");

  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }
}