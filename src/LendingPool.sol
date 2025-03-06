// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {PinjocToken} from "./PinjocToken.sol";
import {IMockOracle} from "./interfaces/IMockOracle.sol";
contract LendingPool is Ownable, ReentrancyGuard {

    event BorrowRateAdded(uint256 borrowRate);
    event LTVUpdated(uint256 ltv);
    event Supply(uint256 borrowRate, address user, uint256 amount, uint256 shares);
    event Borrow(uint256 borrowRate, address user, uint256 amount, uint256 shares);
    event Withdraw(uint256 borrowRate, address user, uint256 shares);
    event SupplyCollateral(uint256 borrowRate, address user, uint256 amount);
    event WithdrawCollateral(uint256 borrowRate, address user, uint256 amount);
    event Repay(uint256 borrowRate, address user, uint256 amount);

    error InvalidBorrowRate();
    error InvalidLTV();
    error InvalidLendingPoolInfo();
    error BorrowRateAlreadyExists();
    error BorrowRateNotActive();
    error InvalidUser();
    error InvalidAmount();
    error InsufficientShares();
    error InsufficientLiquidity();
    error InsufficientCollateral();

    modifier onlyActiveBorrowRate(uint256 borrowRate_) {
        if (!lendingPoolStates[borrowRate_].isActive) revert BorrowRateNotActive();
        _;
    }

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
        address pinjocToken;
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
        address router_, // the one that controlling the lending pool
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
        if (lendingPoolStates[borrowRate_].isActive) revert BorrowRateAlreadyExists();
        if (borrowRate_ == 0 || borrowRate_ == 100e16) revert InvalidBorrowRate();

        LendingPoolState storage state = lendingPoolStates[borrowRate_];
        state.isActive = true;
        state.lastAccrued = block.timestamp;
        state.pinjocToken = address(new PinjocToken(
            address(this), 
            PinjocToken.PinjocTokenInfo({
                debtToken: info.debtToken,
                collateralToken: info.collateralToken,
                oracle: info.oracle,
                maturity: info.maturity,
                maturityMonth: info.maturityMonth,
                maturityYear: info.maturityYear
            })
        ));

        emit BorrowRateAdded(borrowRate_);
    }
    
    function setLtv(uint256 ltv_) external onlyOwner {
        if (ltv_ == 0) revert InvalidLTV();
        info.ltv = ltv_;

        emit LTVUpdated(ltv_);
    }

    // remember this is p2p lending pool via CLOB
    // this function is only for accountability, since router will transfer automatically from the lender to the borrower
    function supply(uint256 borrowRate, address user, uint256 amount) external onlyOwner nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (user == address(0)) revert InvalidUser();
        if (amount == 0) revert InvalidAmount();
        _accrueInterest(borrowRate);

        uint256 storage totalSupplyShares = lendingPoolStates[borrowRate].totalSupplyShares;
        uint256 storage totalSupplyAssets = lendingPoolStates[borrowRate].totalSupplyAssets;

        uint256 shares = 0;
        if (totalSupplyShares == 0) {
            shares = amount;
        } else {
            shares = (amount * totalSupplyShares) / totalSupplyAssets;
        }
        
        totalSupplyShares += shares;
        totalSupplyAssets += amount;
        
        // mint tokenized bond to the lender
        PinjocToken(lendingPoolStates[borrowRate].pinjocToken).mint(user, shares);

        emit Supply(borrowRate, user, amount, shares);
    }

    function borrow(uint256 borrowRate, address user, uint256 amount) external onlyOwner nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (user == address(0)) revert InvalidUser();
        if (amount == 0) revert InvalidAmount();
        _accrueInterest(borrowRate);

        mapping(address => uint256) storage userBorrowShares = lendingPoolStates[borrowRate].userBorrowShares;
        uint256 storage totalBorrowShares = lendingPoolStates[borrowRate].totalBorrowShares;
        uint256 storage totalBorrowAssets = lendingPoolStates[borrowRate].totalBorrowAssets;

        uint256 shares = 0;
        if (totalBorrowShares == 0) {
            shares = amount;
        } else {
            shares = (amount * totalBorrowShares) / totalBorrowAssets;
        }
        
        userBorrowShares[user] += shares;
        totalBorrowShares += shares;
        totalBorrowAssets += amount;
        
        _isHealthy(borrowRate, user);

        emit Borrow(borrowRate, user, amount, shares);
    }

    function withdraw(uint256 borrowRate, uint256 shares) external nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (shares == 0) revert InvalidAmount();
        if (IERC20(lendingPoolStates[borrowRate].pinjocToken).balanceOf(msg.sender) < shares) revert InsufficientShares();
        _accrueInterest(borrowRate);

        uint256 storage totalSupplyShares = lendingPoolStates[borrowRate].totalSupplyShares;
        uint256 storage totalSupplyAssets = lendingPoolStates[borrowRate].totalSupplyAssets;

        // this calculates automatically with the interest
        uint256 amount = (shares * totalSupplyAssets) / totalSupplyShares;

        if (IERC20(debtToken).balanceOf(address(this)) < amount) revert InsufficientLiquidity();
        
        totalSupplyShares -= shares;
        totalSupplyAssets -= amount;

        PinjocToken(lendingPoolStates[borrowRate].pinjocToken).burn(msg.sender, shares);
        IERC20(info.debtToken).transfer(msg.sender, amount);
        
        emit Withdraw(borrowRate, msg.sender, amount, shares);
    }

    function supplyCollateral(uint256 borrowRate, address user, uint256 amount) external onlyOwner nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (user == address(0)) revert InvalidUser();
        if (amount == 0) revert InvalidAmount();
        _accrueInterest(borrowRate);

        lendingPoolStates[borrowRate].userCollaterals[user] += amount;

        emit SupplyCollateral(borrowRate, user, amount);
    }

    function withdrawCollateral(uint256 borrowRate, uint256 amount) external nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (amount == 0) revert InvalidAmount();
        if (lendingPoolStates[borrowRate].userCollaterals[msg.sender] < amount) revert InsufficientCollateral();
        _accrueInterest(borrowRate);

        lendingPoolStates[borrowRate].userCollaterals[msg.sender] -= amount;

        _isHealthy(borrowRate, msg.sender);

        IERC20(info.collateralToken).transfer(msg.sender, amount);

        emit WithdrawCollateral(borrowRate, msg.sender, amount);
    }

    function repay(uint256 borrowRate, uint256 amount) external nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (amount == 0) revert InvalidAmount();
        _accrueInterest(borrowRate);

        uint256 storage totalBorrowShares = lendingPoolStates[borrowRate].totalBorrowShares;
        uint256 storage totalBorrowAssets = lendingPoolStates[borrowRate].totalBorrowAssets;

        uint256 borrowAmount = (amount * totalBorrowAssets) / totalBorrowShares;

        userBorrowShares[msg.sender] -= amount;
        totalBorrowShares -= amount;
        totalBorrowAssets -= borrowAmount;

        IERC20(debtToken).transferFrom(msg.sender, address(this), borrowAmount);

        emit Repay(borrowRate, msg.sender, borrowAmount);
        
    }

    function _accrueInterest(uint256 borrowRate) internal {
        LendingPoolState storage state = lendingPoolStates[borrowRate];
        uint256 interestPerYear = state.totalBorrowAssets * borrowRate / 1e18;
        uint256 timePassed = block.timestamp - state.lastAccrued;

        uint256 interest = (interestPerYear * timePassed) / 365 days;

        state.totalSupplyAssets += interest;
        state.totalBorrowAssets += interest;
        state.lastAccrued = block.timestamp;
    }

    function _isHealthy(uint256 borrowRate, address user) internal view {
        uint256 collateralPrice = IMockOracle(info.oracle).price();
        uint256 collateralDecimals = 10 ** IERC20Metadata(info.collateralToken).decimals();

        uint256 borrowedValue = lendingPoolStates[borrowRate].userBorrowShares[user] * lendingPoolStates[borrowRate].totalBorrowAssets / lendingPoolStates[borrowRate].totalBorrowShares;
        uint256 collateralValue = lendingPoolStates[borrowRate].userCollaterals[user] * collateralPrice / collateralDecimals;
        uint256 maxBorrowedValue = collateralValue * info.ltv / 1e18;

        if (borrowedValue > maxBorrowedValue) revert InsufficientCollateral();
    }
}