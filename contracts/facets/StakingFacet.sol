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

  // Add staking pools from staking contract
  function addStakingPools() external {
    StakingStorage storage s = LibStaking.diamondStorage();
    uint256 pl = StakingContract.poolLength();           
    for(uint256 i = s.poolInfo.length; i < pl; i++) {
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

  
  // Trade staking tokens for NFT
  // Deposits staking tokens and mints NFT
  function mint(uint256[] calldata _pids, uint256[] calldata _amounts) public nonReentrant {
    require(_pids.length == _amounts.length, "_pids length not equal to amounts length");
    StakingStorage storage s = LibStaking.diamondStorage();
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();
    uint256 pl = s.poolInfo.length;
    uint256 tokenId = rt.tokenIdNum;
    for(uint256 i; i < _amounts.length; i++) {
      uint256 pid = _pids[i];
      uint256 amount = _amounts[i];
      require(amount > 0, "Staked amount must be greater than 0");      
      require(pid < pl, "Invalid _pid: too large");
      PoolInfo storage p = s.poolInfo[pid];
      uint256 currentPoolReward = GltrToken.balanceOf(address(this));
      uint256 stakedAmount = StakingContract.deposited(pid, address(this));
      SafeERC20.safeTransferFrom(p.stakingToken, msg.sender, address(this), amount);
      StakingContract.deposit(pid, amount);

      // calculate rewards info
      uint256 newPoolReward = GltrToken.balanceOf(address(this)) - currentPoolReward;
      p.rewardStored += newPoolReward;
      uint256 accERC20PerShare = p.accERC20PerShare;
      if(newPoolReward > 0 && stakedAmount > 0) {        
        accERC20PerShare += (newPoolReward * 1e18) / stakedAmount;
        p.accERC20PerShare = accERC20PerShare;
      }              
      // mint NFT           
      tokenId++;      
      TokenInfo storage ti = rt.tokenInfo[tokenId];    
      ti.owner = msg.sender;
      uint256 tokenIndex = rt.ownerTokenIds[msg.sender].length;        
      ti.ownerTokenIdsIndex = tokenIndex;
      rt.ownerTokenIds[msg.sender].push(tokenId);
      ti.stakedTokenAmount = amount;
      ti.debt = (accERC20PerShare * amount) / 1e18;    
      ti.poolId = uint96(pid);
      LibReceiptToken.checkOnERC721Received(address(0), msg.sender, tokenId, "");
      emit IERC721.Transfer(address(0), msg.sender, tokenId); 
    }
    rt.tokenIdNum = tokenId;
  }


  // Trade NFT for staking tokens and reward
  // Withdraws staking tokens and reward and buns NFT
  function burn(uint256[] calldata _tokenIds) external nonReentrant {
    StakingStorage storage s = LibStaking.diamondStorage();
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();
    for(uint256 i; i < _tokenIds.length; i++) {
      uint256 tokenId = _tokenIds[i];
      TokenInfo storage ti = rt.tokenInfo[tokenId];
      address owner = ti.owner;
      if(owner == address(0)) {
        revert IERC721Errors.ERC721NonexistentToken(tokenId);
      }
      if(!LibReceiptToken.isAuthorized(owner, msg.sender, tokenId)) {
        revert IERC721Errors.ERC721InsufficientApproval(msg.sender, tokenId);
      }
      uint256 pid = ti.poolId;
      uint256 currentPoolReward = GltrToken.balanceOf(address(this));
      uint256 stakedAmount = StakingContract.deposited(pid, address(this));    
      StakingContract.withdraw(pid, ti.stakedTokenAmount);
      
      // calculate rewards info
      PoolInfo storage p = s.poolInfo[pid];     
      uint256 newPoolReward = GltrToken.balanceOf(address(this)) - currentPoolReward;
      p.rewardStored += newPoolReward;
      uint256 accERC20PerShare = p.accERC20PerShare;
      if(newPoolReward > 0) {        
        accERC20PerShare += (newPoolReward * 1e18) / stakedAmount;
        p.accERC20PerShare = accERC20PerShare;
      }      
      uint256 reward = ((p.accERC20PerShare * ti.stakedTokenAmount) / 1e18) - ti.debt;
      p.rewardStored -= reward;

      SafeERC20.safeTransferFrom(p.stakingToken, address(this), owner, ti.stakedTokenAmount);
      SafeERC20.safeTransferFrom(GltrToken, address(this), owner, reward);
      LibReceiptToken.burn(tokenId);
    }
  }

  struct Bonus {
    uint256 pid; // pool id
    uint256 reward; // GLTR reward
  }
  // Add bonus GLTR to pools
  function addBonus(Bonus[] calldata _bonuses) external {
    uint256 totalBonus;
    StakingStorage storage s = LibStaking.diamondStorage();
    uint256 pl = s.poolInfo.length;    
    for(uint256 i; i < _bonuses.length; i++) {
      Bonus calldata bonus = _bonuses[i];
      require(bonus.pid < pl, "Invalid _pid: too large");
      totalBonus += bonus.reward;          
      uint256 stakedAmount = StakingContract.deposited(bonus.pid, address(this));
      require(stakedAmount > 0, "No stakers to give bonus");
      PoolInfo storage p = s.poolInfo[bonus.pid];
      p.rewardStored += bonus.reward;
      p.accERC20PerShare += (bonus.reward * 1e18) / stakedAmount; 
    }
    GltrToken.transferFrom(msg.sender, address(this), totalBonus);
  }

  //////////////////////////////////////////////////////////////////////////////
  // GETTERS
  //////////////////////////////////////////////////////////////////////////////

  // Return the total reward that an NFT can be traded for
  function receiptTokenReward(uint256 _tokenId) public view returns(uint256 rewards_) {
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


  struct NftInfo {
    uint256 tokenId;
    uint256 stakedTokenAmount;
    uint256 poolId;
    uint256 reward;
    address owner;
  }

  function tokenInfo(uint256 _tokenId) external view returns(NftInfo memory n_) {    
    TokenInfo storage ti = LibReceiptToken.diamondStorage().tokenInfo[_tokenId];
    address owner = ti.owner;
    if (owner == address(0)) {
        revert IERC721Errors.ERC721NonexistentToken(_tokenId);
    }
    n_.tokenId = _tokenId;    
    n_.stakedTokenAmount = ti.stakedTokenAmount;
    n_.poolId = ti.poolId;
    n_.reward = receiptTokenReward(_tokenId);    
    n_.owner = owner;
  }

  struct OwnerInfo {
    uint256 totalReward; // Total GLTR rewards from all NFTs owned by user
    NftInfo[] nftInfo; // Info about all tokens owned by user
  }
  // Get owner information
  function ownerInfo(address _owner) external view returns(OwnerInfo memory ownerInfo_) {
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();    
    uint256[] storage tokenIds = rt.ownerTokenIds[_owner];
    uint256 tokenIdsLength = tokenIds.length;
    ownerInfo_.nftInfo = new NftInfo[](tokenIdsLength);
    for(uint256 i; i < tokenIdsLength; i++) {      
      NftInfo memory n;
      n.tokenId = tokenIds[i];
      TokenInfo storage ti = rt.tokenInfo[n.tokenId];
      n.stakedTokenAmount = ti.stakedTokenAmount;
      n.poolId = ti.poolId;
      n.reward = receiptTokenReward(n.tokenId);
      ownerInfo_.totalReward += n.reward;
      n.owner = _owner;      
    }
  }

  struct PoolData {
    uint256 pid;
    address stakingToken;
    uint256 stakingAmount;
    uint256 reward;
  }

  function poolData() external view returns(PoolData[] memory pd_) {
    StakingStorage storage s = LibStaking.diamondStorage();
    uint256 pl = s.poolInfo.length;
    pd_ = new PoolData[](pl);
    for(uint256 i; i < pl; i++) {
      pd_[i].pid = 0;
      pd_[i].stakingToken = address(s.poolInfo[i].stakingToken);
      pd_[i].stakingAmount = StakingContract.deposited(i, address(this)); 
      pd_[i].reward = StakingContract.pending(i, address(this)) + s.poolInfo[i].rewardStored;
    }
  }

  // Return total pool rewards.
  function poolRewards(uint256 _pid) external view returns(uint256 rewards_) {
    StakingStorage storage s = LibStaking.diamondStorage();
    require(_pid < s.poolInfo.length, "Invalid _pid: too large");    
    rewards_ = StakingContract.pending(_pid, address(this)) + s.poolInfo[_pid].rewardStored;
  }

  // Return GLTR contract address
  function rewardToken() external pure returns(address) {
    return address(GltrToken);
  }

  function poolLength() external view returns (uint256) {
    return LibStaking.diamondStorage().poolInfo.length;
  }


}