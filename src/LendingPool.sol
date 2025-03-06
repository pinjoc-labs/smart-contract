// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract LendingPool is Ownable, ReentrancyGuard {

    address public debtToken; // USDC
    address public collateralToken; // ETH
    address public oracle; // USDC-ETH Oracle
    address public pinjocToken;
    uint256 public borrowRate; // 18 decimals: 10e16 = 10% APY
    uint256 public maturity; // 1 year

    // Supply
    uint256 public totalSupplyAssets;
    uint256 public totalSupplyShares;

    // Borrow
    uint256 public totalBorrowAssets;
    uint256 public totalBorrowShares;
    mapping(address => uint256) public userBorrowShares;
    mapping(address => uint256) public userCollaterals;

    // Interest Calculation
    uint256 public lastAccrued = block.timestamp; // assumpt this contract is deployed after anyone doing supply

    // Collateral Calculation
    uint256 public ltv; // 70% Loan to Value (70% in 18 decimals)

    constructor(
        address router_,
        address debtToken_,
        address collateralToken_,
        address oracle_,
        uint256 borrowRate_,
        uint256 ltv_,
        uint256 maturity_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) Ownable(router_) {
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