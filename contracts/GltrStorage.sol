// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;


import {IFarmFacet} from "./interfaces/IFarmFacet.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract GltrStorage {
  address internal immutable GltrTradeStakingDiamond;
  IERC20 internal immutable StakingToken;
  uint256 internal immutable Pid;
  IERC20 internal constant GLTRToken = IERC20(0x3801C3B3B5c98F88a9c9005966AA96aa440B9Afc);
  IFarmFacet internal constant StakingContract = IFarmFacet(0x1fE64677Ab1397e20A1211AFae2758570fEa1B8c);

  constructor(uint256 _pid, IERC20 _stakingToken) {
    GltrTradeStakingDiamond = msg.sender;
    StakingToken = IERC20(_stakingToken);
    Pid = _pid;
    GLTRToken.approve(address(StakingContract), type(uint256).max);
    GLTRToken.approve(GltrTradeStakingDiamond, type(uint256).max);
    StakingToken.approve(address(StakingContract), type(uint256).max);
    StakingToken.approve(GltrTradeStakingDiamond, type(uint256).max);     
  }


  function deposit(uint256 _amount) external {
    require(msg.sender == GltrTradeStakingDiamond, "Not authorized");
    StakingContract.deposit(Pid, _amount);
  }


  function withdraw(uint256 _amount) external {
    require(msg.sender == GltrTradeStakingDiamond, "Not authorized");
    StakingContract.withdraw(Pid, _amount);
  }
   
}