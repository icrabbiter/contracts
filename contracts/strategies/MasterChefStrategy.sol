// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../Policy.sol";
import "./IStrategy.sol";
import "./IAssetAllocator.sol";

import "hardhat/console.sol";

// Info of each user.
struct UserInfo {
    uint256 amount; // How many LP tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.
    //
    // We do some fancy math here. Basically, any point in time, the amount of BEETS
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = (user.amount * pool.accBeetsPerShare) - user.rewardDebt
    //
    // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
    //   1. The pool's `accBeetsPerShare` (and `lastRewardBlock`) gets updated.
    //   2. User receives the pending reward sent to his/her address.
    //   3. User's `amount` gets updated.
    //   4. User's `rewardDebt` gets updated.
}

interface IMasterchef {
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) external;
    function withdrawAndHarvest(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) external;
    function harvest(uint256 _pid, address _to) external;
    function harvestAll(uint256[] calldata _pids, address _to) external;
    function userInfo(uint _pid, address _farmer) external view returns(UserInfo memory);
    function lpTokens(uint _pid) external view returns (address);
    function emergencyWithdraw(uint256 _pid, address _to) external;
}

contract MasterChefStrategy is IStrategy, Policy {
    
    mapping(address => uint) tokenFarmPid;
    mapping(address => uint) public override deposited;
    
    address masterChef;
    address rewardToken;
    address allocator;
    
    constructor(address _masterChef, address _rewardToken, address _allocator){
        masterChef = _masterChef;
        rewardToken = _rewardToken;
        allocator = _allocator;
    }
    
    function getPid(address _token) external view returns(uint){
        return _getPid(_token);
    }
    
    function _getPid(address _token) internal view returns(uint){
        return tokenFarmPid[_token];
    }
    
    function setPid(address _token, uint _pid) external onlyPolicy {
        require(IMasterchef(masterChef).lpTokens(_pid) == _token, "MCS: PID does not match token");
        tokenFarmPid[_token] = _pid;
    }
    
    function deploy(address _token) external override {
        uint pid = _getPid(_token);
        IERC20 token = IERC20(_token);
        uint balance = token.balanceOf(address(this));
        token.approve(masterChef, balance);
        IMasterchef(masterChef).deposit(pid, balance, address(this));
        deposited[_token] += balance;
    }
    
    function withdraw(address _token, uint _amount) external override onlyAssetAllocator returns (uint) {
        uint pid = _getPid(_token);
        IMasterchef(masterChef).withdrawAndHarvest(pid, _amount, address(this));
        _sendToTreasury(rewardToken);
        IERC20(_token).transfer(allocator, _amount);
        deposited[_token] -= _amount;
        return _amount;
    }

    function emergencyWithdraw(address _token) external override returns (uint) {
        IMasterchef(masterChef).emergencyWithdraw(_getPid(_token), address(this));
        uint balance = IERC20(_token).balanceOf(address(this));
        _sendToTreasury(_token, balance);
        deposited[_token] = 0;
        return balance;
    }

    function collectProfits(address _token) external override returns (int){
        // This farm creates yields from the reward token
        return 0;
    }
    
    function collectRewards(address[] calldata _tokens) external {
        for(uint i = 0; i < _tokens.length; i++){
            _collectRewards(_tokens[i]);
        }
    }
    
    function collectRewards(address _token) external override {
        _collectRewards(_token);
    }

    function _collectRewards(address _token) internal {
        uint pid = _getPid(_token);
        IMasterchef(masterChef).harvest(pid, address(this));
        _sendToTreasury(rewardToken);
    }
    
    function balance(address _token) external view override returns(uint256){
        uint pid = _getPid(_token);
        return _balance(pid);
    }
    
    function _balance(uint pid) internal view returns (uint256){
        return IMasterchef(masterChef).userInfo(pid, address(this)).amount;
    }
    
    function sendToTreasury(address _token) external onlyPolicy {
        _sendToTreasury(_token);
    }
    
    function _sendToTreasury(address _token) internal {
        uint balance = IERC20(_token).balanceOf(address(this));
        _sendToTreasury(_token, balance);
    }
    
    function _sendToTreasury(address _token, uint _amount) internal{
        IERC20(_token).approve(allocator, _amount);
        IAssetAllocator(allocator).sendToTreasury(_token, _amount);
    }

    modifier onlyAssetAllocator() {
        require(msg.sender == allocator, "MCS: caller is not allocator");
        _;
    }
    
}
