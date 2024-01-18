// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IFarmFacet} from "../interfaces/IFarmFacet.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {GltrStorage} from "../GltrStorage.sol";

IERC20 constant GltrToken = IERC20(0x3801C3B3B5c98F88a9c9005966AA96aa440B9Afc);
IFarmFacet constant StakingContract = IFarmFacet(0x1fE64677Ab1397e20A1211AFae2758570fEa1B8c);


struct PoolInfo {
    uint256 rewardStored;    
    IERC20 stakingToken;
    uint256 accERC20PerShare;    
}

struct StakingStorage {
  PoolInfo[] poolInfo;
}


library LibStaking {
  bytes32 constant STAKING_STORAGE_POSITION = keccak256("gltr-receipt-token.storage");
  
  // rt == receipt token
  function diamondStorage() internal pure returns (StakingStorage storage s) {
    bytes32 position = STAKING_STORAGE_POSITION;
    assembly {
      s.slot := position
    }
  }
}