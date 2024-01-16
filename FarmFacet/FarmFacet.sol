// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../libraries/LibFarm.sol";
import "../abstract/ReentrancyGuard.sol";
import "../abstract/Ownable.sol";

contract FarmFacet is Ownable, ReentrancyGuard {
  // Add a new lp to the pool. Can only be called by the owner.
  // DO NOT add the same LP token more than once. Rewards will be messed up if you do.
  function add(
    uint256 _allocPoint,
    IERC20 _lpToken,
    bool _withUpdate
  ) external onlyOwner {
    LibFarm.add(_allocPoint, _lpToken, _withUpdate);
  }

  // Update the given pool's ERC20 allocation point. Can only be called by the owner.
  function set(
    uint256 _pid,
    uint256 _allocPoint,
    bool _withUpdate
  ) external onlyOwner {
    LibFarm.set(_pid, _allocPoint, _withUpdate);
  }

  // Update reward variables for all pools. Be careful of gas spending!
  function massUpdatePools() external {
    LibFarm.massUpdatePools();
  }

  // Update reward variables of the given pool to be up-to-date.
  function updatePool(uint256 _pid) external {
    LibFarm.updatePool(_pid);
  }

  // Deposit LP tokens to Farm for ERC20 allocation.
  function deposit(uint256 _pid, uint256 _amount)
    external
    nonReentrant
  {
    LibFarm.deposit(_pid, _amount);
  }

  // Withdraw LP tokens from Farm.
  function withdraw(uint256 _pid, uint256 _amount)
    external
    nonReentrant
  {
    LibFarm.withdraw(_pid, _amount);
  }

  // Harvest rewards
  function harvest(uint256 _pid) external nonReentrant {
    LibFarm.updatePoolAndHarvest(msg.sender, _pid);
  }

  // Batch harvest rewards
  function batchHarvest(uint256[] memory _pids)
    external
    nonReentrant
  {
    for (uint256 i = 0; i < _pids.length; ++i) {
      LibFarm.updatePoolAndHarvest(msg.sender, _pids[i]);
    }
  }

  // Withdraw without caring about rewards. EMERGENCY ONLY.
  function emergencyWithdraw(uint256 _pid) external nonReentrant {
    LibFarm.emergencyWithdraw(_pid);
  }

  //////////////////////////////////////////////////////////////////////////////
  // GETTERS
  //////////////////////////////////////////////////////////////////////////////

  // Storage pointer helper
  function s() private pure returns (FarmStorage.Layout storage fs) {
    return FarmStorage.layout();
  }

  // Number of LP pools
  function poolLength() external view returns (uint256) {
    return s().poolInfo.length;
  }

  // View function to see deposited LP for a user.
  function deposited(uint256 _pid, address _user)
    external
    view
    returns (uint256)
  {
    return s().userInfo[_pid][_user].amount;
  }

  // View function to see pending ERC20s for a user.
  function pending(uint256 _pid, address _user)
    public
    view
    returns (uint256)
  {
    PoolInfo storage pool = s().poolInfo[_pid];
    UserInfo storage user = s().userInfo[_pid][_user];
    uint256 accERC20PerShare = pool.accERC20PerShare;
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));

    if (block.number > pool.lastRewardBlock && lpSupply != 0) {
      uint256 nrOfBlocks = block.number - pool.lastRewardBlock;
      uint256 erc20Reward = (LibFarm.sumRewardPerBlock(
        pool.lastRewardBlock,
        nrOfBlocks
      ) * pool.allocPoint) / s().totalAllocPoint;
      accERC20PerShare += (erc20Reward * 1e18) / lpSupply;
    }
    uint256 userReward = (user.amount * accERC20PerShare) / 1e18;
    if (userReward <= user.rewardDebt) return 0;
    else return userReward - user.rewardDebt;
  }

  // View function for total reward the farm has yet to pay out.
  function totalPending()
    external
    view
    returns (uint256 totalPending_)
  {
    uint256 _startBlock = s().startBlock;
    if (block.number <= _startBlock) {
      return 0;
    }

    totalPending_ =
      LibFarm.sumRewardPerBlock(
        _startBlock,
        block.number - _startBlock
      ) -
      s().paidOut;
  }

  struct UserInfoOutput {
    IERC20 lpToken; // LP Token of the pool
    uint256 allocPoint;
    uint256 pending; // Amount of reward pending for this lp token pool
    uint256 userBalance; // Amount user has deposited
    uint256 poolBalance; // Amount of LP tokens in the pool
  }

  function allUserInfo(address _user)
    external
    view
    returns (UserInfoOutput[] memory)
  {
    UserInfoOutput[] memory userInfo_ = new UserInfoOutput[](
      s().poolInfo.length
    );
    for (uint256 i = 0; i < s().poolInfo.length; i++) {
      userInfo_[i] = UserInfoOutput({
        lpToken: s().poolInfo[i].lpToken,
        allocPoint: s().poolInfo[i].allocPoint,
        pending: pending(i, _user),
        userBalance: s().userInfo[i][_user].amount,
        poolBalance: s().poolInfo[i].lpToken.balanceOf(address(this))
      });
    }
    return userInfo_;
  }

  function rewardToken() external view returns (IERC20) {
    return s().rewardToken;
  }

  function paidOut() external view returns (uint256) {
    return s().paidOut;
  }

  // Returns the reward per block for the specified year. 0 is the first year
  function rewardPerBlock(uint256 year)
    external
    pure
    returns (uint256)
  {
    return LibFarm.rewardPerBlock(year);
  }

  function currentRewardPerBlock() external view returns (uint256) {
    if (block.number < s().startBlock) return 0;
    return
      LibFarm.rewardPerBlock(
        (block.number - s().startBlock) / s().decayPeriod
      );
  }

  function poolInfo(uint256 _pid)
    external
    view
    returns (PoolInfo memory pi)
  {
    return s().poolInfo[_pid];
  }

  function poolTokens(address _token) external view returns (bool) {
    return s().poolTokens[_token];
  }

  function poolBalance(uint256 _pid) external view returns (uint256) {
    return s().poolInfo[_pid].lpToken.balanceOf(address(this));
  }

  function userInfo(uint256 _pid, address _user)
    external
    view
    returns (UserInfo memory ui)
  {
    return s().userInfo[_pid][_user];
  }

  function totalAllocPoint() external view returns (uint256) {
    return s().totalAllocPoint;
  }

  function startBlock() external view returns (uint256) {
    return s().startBlock;
  }

  function decayPeriod() external view returns (uint256) {
    return s().decayPeriod;
  }
}