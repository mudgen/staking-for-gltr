// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "hardhat/console.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {IERC721, IERC721Errors} from "../interfaces/IERC721.sol";
import {LibReceiptToken, ReceiptTokenStorage, TokenInfo} from "../libraries/LibReceiptToken.sol";
import {LibStaking, GltrToken, StakingContract, StakingStorage, PoolInfo} from "../libraries/LibStaking.sol";
import {IFarmFacet} from "../interfaces/IFarmFacet.sol";
import {GltrStorage} from "../GltrStorage.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {ReentrancyGuard} from "../libraries/ReentrancyGuard.sol";

contract StakingFacet is ReentrancyGuard { 

  function addStakingTokens() external {
    StakingStorage storage s = LibStaking.diamondStorage();

    uint256 poolLength = StakingContract.poolLength(); 
            
    for(uint256 i = s.poolInfo.length; i < poolLength; i++) {
      IERC20 stakingToken = StakingContract.poolInfo(i).lpToken;
      s.poolInfo.push(PoolInfo(
        {
          rewardStored: 0,
          stakingToken: stakingToken,
          accERC20PerShare: 0          
        }
      ));
    } 
  }
  
  function poolRewards(uint256 _pid) external view returns(uint256 rewards_) {
    StakingStorage storage s = LibStaking.diamondStorage();
    require(_pid < s.poolInfo.length, "Invalid _pid: too large");    
    rewards_ = StakingContract.pending(_pid, address(0)) + s.poolInfo[_pid].rewardStored;
  }

  // function updateBonusReward() internal {
  //   StakingStorage storage s = LibStaking.diamondStorage();
  //   uint256 newAllStoredReward = GltrToken.balanceOf(address(0));
  //   uint256 allStoredReward = s.allStoredReward;
  //   uint256 bonus = newAllStoredReward - allStoredReward;
  //   if(bonus < 100000e18) {
  //     return;
  //   }
  //   uint8[] memory bonusPercents = s.bonusPercents;
  //   for(uint256 pid; pid < bonusPercents.length; i++) {
  //     uint256 percent = bonusPercents[pid];
  //     if(percent == 0) {
  //       continue;
  //     }
  //     uint256 reward = s.poolInfo[i]


    




  // }


  function updatePoolInfo(uint256 _pid) internal {
    StakingStorage storage s = LibStaking.diamondStorage();
    PoolInfo storage p = s.poolInfo[_pid];
    uint256 newRewards = StakingContract.pending(_pid, address(this));
    if(newRewards == 0) {
      return;
    }
    uint256 stakedAmount = StakingContract.deposited(_pid, address(this));
    if(stakedAmount == 0) {
      return;
    }
    p.accERC20PerShare += (newRewards * 1e18) / stakedAmount;
    p.rewardStored += newRewards;    
  }

  function mint(uint256 _pid, uint256 _amount) external nonReentrant {
    require(_amount > 0, "Staked amount must be greater than 0");
    StakingStorage storage s = LibStaking.diamondStorage();
    require(_pid < s.poolInfo.length, "Invalid _pid: too large");
    PoolInfo storage p = s.poolInfo[_pid];
    uint256 currentPoolReward = GltrToken.balanceOf(address(this));
    uint256 stakedAmount = StakingContract.deposited(_pid, address(this));
    SafeERC20.safeTransferFrom(p.stakingToken, msg.sender, address(this), _amount);
    StakingContract.deposit(_pid, _amount);

    // calculate rewards info
    uint256 newPoolReward = GltrToken.balanceOf(address(this)) - currentPoolReward;
    p.rewardStored += newPoolReward;  
    if(stakedAmount > 0) {
      p.accERC20PerShare += (newPoolReward * 1e18) / stakedAmount;
    }    
        
    // mint NFT
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();
    uint256 tokenId = rt.tokenIdNum;
    tokenId++;
    rt.tokenIdNum = tokenId;
    TokenInfo storage ti = rt.tokenInfo[tokenId];    
    ti.owner = msg.sender;
    uint256 tokenIndex = rt.ownerTokenIds[msg.sender].length;        
    ti.ownerTokenIdsIndex = tokenIndex;
    rt.ownerTokenIds[msg.sender].push(tokenId);
    ti.stakedTokenAmount = _amount;
    ti.debt = (p.accERC20PerShare * _amount) / 1e18;    
    ti.poolId = uint96(_pid);
    LibReceiptToken.checkOnERC721Received(address(0), msg.sender, tokenId, "");
    emit IERC721.Transfer(address(0), msg.sender, tokenId);   
  }

  function receiptTokenRewards(uint256 _tokenId) external view returns(uint256 rewards_) {
    TokenInfo storage ti = LibReceiptToken.diamondStorage().tokenInfo[_tokenId];
    if(ti.owner == address(0)) {
      revert IERC721Errors.ERC721NonexistentToken(_tokenId);
    }
    uint256 pid = ti.poolId;
    PoolInfo storage p = LibStaking.diamondStorage().poolInfo[pid];     
    uint256 newPoolReward = StakingContract.pending(pid, address(this));
    uint256 stakedAmount = StakingContract.deposited(pid, address(this));    
    if(stakedAmount == 0) {
      return 0;
    }
    uint256 accERC20PerShare = p.accERC20PerShare + ((newPoolReward * 1e18) / stakedAmount);
    if(accERC20PerShare == 0) {
      return 0;
    }  
    rewards_ = ((accERC20PerShare * ti.stakedTokenAmount) / 1e18) - ti.debt;
  }

  function burn(uint256 _tokenId) external nonReentrant {
    TokenInfo storage ti = LibReceiptToken.diamondStorage().tokenInfo[_tokenId];
    address owner = ti.owner;
    if(owner == address(0)) {
      revert IERC721Errors.ERC721NonexistentToken(_tokenId);
    }
    if(!LibReceiptToken.isAuthorized(owner, msg.sender, _tokenId)) {
      revert IERC721Errors.ERC721InsufficientApproval(msg.sender, _tokenId);
    }
    uint256 pid = ti.poolId;
    uint256 currentPoolReward = GltrToken.balanceOf(address(this));
    uint256 stakedAmount = StakingContract.deposited(pid, address(this));    
    StakingContract.withdraw(pid, ti.stakedTokenAmount);
    
     // calculate rewards info
    PoolInfo storage p = LibStaking.diamondStorage().poolInfo[pid];     
    uint256 newPoolReward = GltrToken.balanceOf(address(this)) - currentPoolReward;
    p.rewardStored += newPoolReward; 
    p.accERC20PerShare += (newPoolReward * 1e18) / stakedAmount;    
    uint256 reward = ((p.accERC20PerShare * ti.stakedTokenAmount) / 1e18) - ti.debt;
    p.rewardStored -= reward;

    SafeERC20.safeTransferFrom(p.stakingToken, address(this), owner, ti.stakedTokenAmount);
    SafeERC20.safeTransferFrom(GltrToken, address(this), owner, reward);
    LibReceiptToken.burn(_tokenId);
  }

  

  function rewardToken() external pure returns(address) {
    return address(GltrToken);
  }

  // function totalReward() internal view returns(uint256) {
  //   return RewardToken.balanceOf(address(this));
  // }

  // function deposit(uint256 _amount) external {
  //   uint256 contractBalance = RewardToken.balanceOf(address(this));

  // }

}