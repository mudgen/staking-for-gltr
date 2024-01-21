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

  
  event MintReceiptToken(address indexed _minter, uint256 _tokenId, address indexed _stakingToken, uint256 _stakingAmount);
  event BurnReceiptToken(address indexed _burner, uint256 _tokenId, address indexed _stakingToken, uint256 _stakingAmount, uint256 _gltrAmount);
  // Add staking pools from staking contract
  function addStakingPools() external {
    StakingStorage storage s = LibStaking.diamondStorage();
    uint256 pl = StakingContract.poolLength();           
    for(uint256 i = s.poolInfo.length; i < pl; i++) {
      IERC20 stakingToken = StakingContract.poolInfo(i).lpToken;
      s.poolInfo.push(PoolInfo(
        {
          gltrStored: 0,
          stakingToken: stakingToken,
          accERC20PerShare: 0          
        }
      ));
    } 
  }

  
  // Trade staking tokens for NFT
  // Deposits staking tokens and mints NFT
  // The pid determines which staking token to use with amount
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
      uint256 currentPoolGltr = GltrToken.balanceOf(address(this));
      uint256 totalStakedAmount = StakingContract.deposited(pid, address(this));
      IERC20 stakingToken = p.stakingToken;
      SafeERC20.safeTransferFrom(stakingToken, msg.sender, address(this), amount);
      StakingContract.deposit(pid, amount);

      // calculate gltrs info
      uint256 newPoolGltr = GltrToken.balanceOf(address(this)) - currentPoolGltr;
      p.gltrStored += newPoolGltr;
      uint256 accERC20PerShare = p.accERC20PerShare;
      if(newPoolGltr > 0 && totalStakedAmount > 0) {        
        accERC20PerShare += (newPoolGltr * 1e18) / totalStakedAmount;
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
      emit MintReceiptToken(msg.sender, tokenId, address(stakingToken), amount);
    }
    rt.tokenIdNum = tokenId;
  }


  // Trade NFTs for staking tokens and gltr
  // Withdraws staking tokens and gltr and burn NFTs
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
      uint256 currentPoolGltr = GltrToken.balanceOf(address(this));
      uint256 totalStakedAmount = StakingContract.deposited(pid, address(this));
      uint256 tokenStakedAmount = ti.stakedTokenAmount;
      StakingContract.withdraw(pid, tokenStakedAmount);
      
      // calculate gltrs info
      PoolInfo storage p = s.poolInfo[pid];     
      uint256 newPoolGltr = GltrToken.balanceOf(address(this)) - currentPoolGltr;
      p.gltrStored += newPoolGltr;
      uint256 accERC20PerShare = p.accERC20PerShare;
      if(newPoolGltr > 0) {        
        accERC20PerShare += (newPoolGltr * 1e18) / totalStakedAmount;
        p.accERC20PerShare = accERC20PerShare;
      }      
      uint256 gltrAmount = ((p.accERC20PerShare * tokenStakedAmount) / 1e18) - ti.debt;
      p.gltrStored -= gltrAmount;
      IERC20 stakingToken = p.stakingToken;
      SafeERC20.safeTransferFrom(stakingToken, address(this), owner, tokenStakedAmount);
      SafeERC20.safeTransferFrom(GltrToken, address(this), owner, gltrAmount);
      LibReceiptToken.burn(tokenId);
      emit BurnReceiptToken(msg.sender, tokenId, address(stakingToken), tokenStakedAmount, gltrAmount);
    }
  }

  struct Bonus {
    uint256 pid; // pool id
    uint256 gltrAmount; // GLTR gltr
  }
  // Add bonus GLTR to pools
  function addBonus(Bonus[] calldata _bonuses) external {
    uint256 totalBonus;
    StakingStorage storage s = LibStaking.diamondStorage();
    uint256 pl = s.poolInfo.length;    
    for(uint256 i; i < _bonuses.length; i++) {
      Bonus calldata bonus = _bonuses[i];
      require(bonus.pid < pl, "Invalid _pid: too large");
      totalBonus += bonus.gltrAmount;          
      uint256 stakedAmount = StakingContract.deposited(bonus.pid, address(this));
      require(stakedAmount > 0, "No stakers to give bonus");
      PoolInfo storage p = s.poolInfo[bonus.pid];
      p.gltrStored += bonus.gltrAmount;
      p.accERC20PerShare += (bonus.gltrAmount * 1e18) / stakedAmount; 
    }
    GltrToken.transferFrom(msg.sender, address(this), totalBonus);
  }

  //////////////////////////////////////////////////////////////////////////////
  // GETTERS
  //////////////////////////////////////////////////////////////////////////////

  // Return the total gltr that an NFT can be traded for
  function receiptTokenGltr(uint256 _tokenId) public view returns(uint256 gltrAmount_) {
    TokenInfo storage ti = LibReceiptToken.diamondStorage().tokenInfo[_tokenId];
    if(ti.owner == address(0)) {
      revert IERC721Errors.ERC721NonexistentToken(_tokenId);
    }
    uint256 pid = ti.poolId;
    PoolInfo storage p = LibStaking.diamondStorage().poolInfo[pid];     
    uint256 newPoolGltr = StakingContract.pending(pid, address(this));
    uint256 totalStakedAmount = StakingContract.deposited(pid, address(this));    
    if(totalStakedAmount == 0) {
      return 0;
    }
    uint256 accERC20PerShare = p.accERC20PerShare + ((newPoolGltr * 1e18) / totalStakedAmount);
    if(accERC20PerShare == 0) {
      return 0;
    }  
    gltrAmount_ = ((accERC20PerShare * ti.stakedTokenAmount) / 1e18) - ti.debt;
  }


  struct NftInfo {
    uint256 tokenId;
    uint256 stakedTokenAmount;
    uint256 poolId;
    uint256 gltrAmount;
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
    n_.gltrAmount = receiptTokenGltr(_tokenId);    
    n_.owner = owner;
  }
  
  // Get owner information
  function ownerInfo(address _owner) external view returns(NftInfo[] memory nftInfo_) {
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();    
    uint256[] storage tokenIds = rt.ownerTokenIds[_owner];
    uint256 tokenIdsLength = tokenIds.length;
    nftInfo_ = new NftInfo[](tokenIdsLength);
    for(uint256 i; i < tokenIdsLength; i++) {      
      NftInfo memory n;
      n.tokenId = tokenIds[i];
      TokenInfo storage ti = rt.tokenInfo[n.tokenId];
      n.stakedTokenAmount = ti.stakedTokenAmount;
      n.poolId = ti.poolId;
      n.gltrAmount = receiptTokenGltr(n.tokenId);
      n.owner = _owner;      
    }
  }

  struct PoolData {
    uint256 pid;
    address stakingToken;
    uint256 stakingAmount;
    uint256 gltrAmount;
  }

  function poolData() external view returns(PoolData[] memory pd_) {
    StakingStorage storage s = LibStaking.diamondStorage();
    uint256 pl = s.poolInfo.length;
    pd_ = new PoolData[](pl);
    for(uint256 i; i < pl; i++) {
      pd_[i].pid = 0;
      pd_[i].stakingToken = address(s.poolInfo[i].stakingToken);
      pd_[i].stakingAmount = StakingContract.deposited(i, address(this)); 
      pd_[i].gltrAmount = StakingContract.pending(i, address(this)) + s.poolInfo[i].gltrStored;
    }
  }

  // 
  struct TotalGltr {    
    uint256 bookKeepingTotalStoredGltr;
    uint256 totalStoredGltr;
    uint256 totalPendingGltr;
  }
  // This function is mostly for testing purposes
  // bookKeepingTotalStoredGltr should be equal to totalStoredGltr unless someone transferred GLTR directly into address(this)  
  function totalGltr() external view returns(TotalGltr memory totalGltr_) {
    StakingStorage storage s = LibStaking.diamondStorage();
    uint256 pl = s.poolInfo.length;        
    for(uint256 i; i < pl; i++) {
      uint256 storedGltr = s.poolInfo[i].gltrStored;
      totalGltr_.bookKeepingTotalStoredGltr += storedGltr;      
      totalGltr_.totalPendingGltr += StakingContract.pending(i, address(this));

    }
    totalGltr_.totalStoredGltr = GltrToken.balanceOf(address(this));
  }


  // Return total pool gltr amount.
  function poolGltr(uint256 _pid) external view returns(uint256 gltrAmount_) {
    StakingStorage storage s = LibStaking.diamondStorage();
    require(_pid < s.poolInfo.length, "Invalid _pid: too large");    
    gltrAmount_ = StakingContract.pending(_pid, address(this)) + s.poolInfo[_pid].gltrStored;
  }

  // Return GLTR contract address
  function gltrTokenAddress() external pure returns(address) {
    return address(GltrToken);
  }

  function poolLength() external view returns (uint256) {
    return LibStaking.diamondStorage().poolInfo.length;
  }


}