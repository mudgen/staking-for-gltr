
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

}