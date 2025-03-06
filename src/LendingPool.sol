// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract LendingPool is Ownable, ReentrancyGuard {

    error InvalidBorrowRate();
    error InvalidLTV();
    error InvalidLendingPoolInfo();

    struct LendingPoolInfo {
        address debtToken;
        address collateralToken;
        address oracle;
        uint256 maturity;
        string maturityMonth;
        uint256 maturityYear;
        uint256 ltv;
    }

    struct LendingPoolState {
        uint256 totalSupplyAssets;
        uint256 totalSupplyShares;
        uint256 totalBorrowAssets;
        uint256 totalBorrowShares;
        mapping(address => uint256) userBorrowShares;
        mapping(address => uint256) userCollaterals;
        uint256 lastAccrued;
        bool isActive;
    }

    LendingPoolInfo public info;
    mapping(uint256 => LendingPoolState) public lendingPoolStates; // borrow rate => lending pool state

    constructor(
        address router_,
        LendingPoolInfo memory info_
    ) Ownable(router_) {
        if (
            info_.debtToken == address(0) ||
            info_.collateralToken == address(0) ||
            info_.oracle == address(0) ||
            info_.maturity <= block.timestamp ||
            bytes(info_.maturityMonth).length == 0 ||
            info_.maturityYear == 0 ||
            info_.ltv == 0
        ) revert InvalidLendingPoolInfo();
        info = info_;
    }

    function addBorrowRate(uint256 borrowRate_) external onlyOwner {
        if (borrowRate_ == 0 || borrowRate_ == 100e16) revert InvalidBorrowRate();
        LendingPoolState storage state = lendingPoolStates[borrowRate_];
        state.isActive = true;
        state.lastAccrued = block.timestamp;
    }
    
    function setLtv(uint256 ltv_) external onlyOwner {
        if (ltv_ == 0) revert InvalidLTV();
        info.ltv = ltv_;
    }

    function supply(uint256 amount) external onlyOwner nonReentrant {
    }

    function borrow(uint256 amount) external onlyOwner nonReentrant {
    }

    function withdraw(uint256 shares) external nonReentrant {
    }

    function supplyCollateral(uint256 amount) external onlyOwner nonReentrant {
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
    }

    function repay(uint256 shares) external nonReentrant {
    }

    function _accrueInterest() internal {
    }

    function _isHealthy(address user) internal view {
    }

}