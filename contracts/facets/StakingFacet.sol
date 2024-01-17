// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "hardhat/console.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {IERC721, IERC721Errors} from "../interfaces/IERC721.sol";
import {LibReceiptToken, ReceiptTokenStorage, TokenInfo} from "../libraries/LibReceiptToken.sol";
import {LibStaking, GltrToken, StakingContract, StakingStorage, GltrStorageInfo} from "../libraries/LibStaking.sol";
import {IFarmFacet} from "../interfaces/IFarmFacet.sol";
import {GltrStorage} from "../GltrStorage.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {ReentrancyGuard} from "../libraries/ReentrancyGuard.sol";

contract StakingFacet is ReentrancyGuard {

  function addStakingTokens() external {
    StakingStorage storage s = LibStaking.diamondStorage();

    uint256 poolLength = StakingContract.poolLength(); 
        
    for(uint256 i = s.gltrStorageInfo.length; i < poolLength; i++) {
      IERC20 stakingToken = StakingContract.poolInfo(i).lpToken;
      s.gltrStorageInfo.push(GltrStorageInfo(
        {
          gltrStorage: new GltrStorage(i, stakingToken),   
          stakingToken: stakingToken,
          accERC20PerShare: 0,
          lastRewardAmount: 0 
        }
      ));
    }
  }
  
  function gltrStorageRewards(uint256 _gid) external view returns(uint256 rewards_) {
    StakingStorage storage s = LibStaking.diamondStorage();
    require(_gid < s.gltrStorageInfo.length, "Invalid _pid: too large");
    address gltrStorage = address(s.gltrStorageInfo[_gid].gltrStorage);
    rewards_ = StakingContract.pending(_gid, gltrStorage) + GltrToken.balanceOf(gltrStorage);
  }


  function updateGltrStorageInfo(uint256 _gid) internal {
    GltrStorageInfo storage gi = LibStaking.diamondStorage().gltrStorageInfo[_gid];
    address gltrStorage = address(gi.gltrStorage);
    uint256 rewards = StakingContract.pending(_gid, gltrStorage) + GltrToken.balanceOf(gltrStorage);
    uint256 newRewards = rewards - gi.lastRewardAmount;
    if(newRewards == 0) {
      return;
    }
    uint256 stakedAmount = StakingContract.deposited(_gid, gltrStorage);
    if(stakedAmount == 0) {
      return;
    }
    gi.accERC20PerShare += (newRewards * 1e18) / stakedAmount; 
    gi.lastRewardAmount = rewards;    
  }

  function mint(uint256 _pid, uint256 _amount) external nonReentrant {
    require(_amount > 0, "Staked amount must be greater than 0");
    StakingStorage storage s = LibStaking.diamondStorage();
    require(_pid < s.gltrStorageInfo.length, "Invalid _pid: too large");
    GltrStorageInfo storage gi = s.gltrStorageInfo[_pid];
    updateGltrStorageInfo(_pid);
    GltrStorage gltrStorage = gi.gltrStorage;
    SafeERC20.safeTransferFrom(gi.stakingToken, msg.sender, address(gltrStorage), _amount);
    gltrStorage.deposit(_amount);
    
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
    ti.debt = (gi.accERC20PerShare * _amount) / 1e18;    
    ti.gltrStorageId = uint96(_pid);
    LibReceiptToken.checkOnERC721Received(address(0), msg.sender, tokenId, "");
    emit IERC721.Transfer(address(0), msg.sender, tokenId);   
  }

  function receiptTokenRewards(uint256 _tokenId) external view returns(uint256 rewards_) {
    TokenInfo storage ti = LibReceiptToken.diamondStorage().tokenInfo[_tokenId];
    if(ti.owner == address(0)) {
      revert IERC721Errors.ERC721NonexistentToken(_tokenId);
    }
    uint256 gid = ti.gltrStorageId;
    GltrStorageInfo storage gi = LibStaking.diamondStorage().gltrStorageInfo[gid]; 
    address gltrStorage = address(gi.gltrStorage);
    uint256 rewards = StakingContract.pending(gid, gltrStorage) + GltrToken.balanceOf(gltrStorage);
    uint256 newRewards = rewards - gi.lastRewardAmount;
    uint256 stakedAmount = StakingContract.deposited(gid, gltrStorage);    
    if(stakedAmount == 0) {
      return 0;
    }
    uint256 accERC20PerShare = gi.accERC20PerShare + ((newRewards * 1e18) / stakedAmount);
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
    uint256 gid = ti.gltrStorageId;
    updateGltrStorageInfo(gid);
    GltrStorageInfo storage gi = LibStaking.diamondStorage().gltrStorageInfo[gid];    
    GltrStorage gltrStorage = gi.gltrStorage;
    uint256 rewards = ((gi.accERC20PerShare * ti.stakedTokenAmount) / 1e18) - ti.debt;
    gi.lastRewardAmount -= rewards;
    gltrStorage.withdraw(ti.stakedTokenAmount);    
    SafeERC20.safeTransferFrom(gi.stakingToken, address(gltrStorage), owner, ti.stakedTokenAmount);
    SafeERC20.safeTransferFrom(GltrToken, address(gltrStorage), owner, rewards);
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