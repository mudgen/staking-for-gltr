
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

interface IFarmFacet {

  function deposit(uint256 _pid, uint256 _amount) external;

  function withdraw(uint256 _pid, uint256 _amount) external;
  function harvest(uint256 _pid) external;
  
  function emergencyWithdraw(uint256 _pid) external;

  function deposited(uint256 _pid, address _user) external view returns (uint256);

  function pending(uint256 _pid, address _user) external view returns (uint256);


  struct UserInfoOutput {
    IERC20 lpToken; // LP Token of the pool
    uint256 allocPoint;
    uint256 pending; // Amount of reward pending for this lp token pool
    uint256 userBalance; // Amount user has deposited
    uint256 poolBalance; // Amount of LP tokens in the pool
  }

  function allUserInfo(address _user) external view returns (UserInfoOutput[] memory);


  function rewardToken() external view returns (IERC20);

  function paidOut() external view returns (uint256);


  function poolLength() external view returns (uint256);


  // Info of each pool.
  struct PoolInfo {
    IERC20 lpToken; // Address of LP token contract.
    uint256 allocPoint; // How many allocation points assigned to this pool. ERC20s to distribute per block.
    uint256 lastRewardBlock; // Last block number that ERC20s distribution occurs.
    uint256 accERC20PerShare; // Accumulated ERC20s per share, times 1e12.
  }

  function poolInfo(uint256 _pid) external view returns (PoolInfo memory);

}