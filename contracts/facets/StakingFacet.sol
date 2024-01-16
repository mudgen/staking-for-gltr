//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.23;

import "hardhat/console.sol";

struct UserInfo {
  uint256 lastUpdatedBlock;
  uint256 stakedTokenAmount;
}


struct AppStorage {
  //address owner;
  // mapping(address => UserInfo) userInfo;
}


contract StakingFacet {
  AppStorage internal s;

  constructor(address _owner) {

  }

  function addStakedToken()
}