// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {PinjocToken} from "./PinjocToken.sol";
import {IMockOracle} from "./interfaces/IMockOracle.sol";

/// @title LendingPool - A P2P lending pool contract with CLOB (Central Limit Order Book)
/// @notice This contract manages lending and borrowing operations with multiple borrow rates
/// @dev Implements collateralized lending with interest accrual and health factor checks
contract LendingPool is Ownable, ReentrancyGuard {

    /// @notice Emitted when a new borrow rate is added to the lending pool
    /// @param borrowRate The borrow rate that was added
    event BorrowRateAdded(uint256 borrowRate);
    
    /// @notice Emitted when the LTV ratio is updated
    /// @param ltv The new LTV value
    event LTVUpdated(uint256 ltv);
    
    /// @notice Emitted when assets are supplied to the pool
    /// @param borrowRate The borrow rate tier
    /// @param user The supplier's address
    /// @param shares The amount of shares minted
    /// @param amount The amount of assets supplied
    event Supply(uint256 borrowRate, address user, uint256 shares, uint256 amount);
    
    /// @notice Emitted when assets are borrowed from the pool
    /// @param borrowRate The borrow rate tier
    /// @param user The borrower's address
    /// @param shares The amount of borrow shares
    /// @param amount The amount of assets borrowed
    event Borrow(uint256 borrowRate, address user, uint256 shares, uint256 amount);
    
    /// @notice Emitted when a supplier withdraws assets
    /// @param borrowRate The borrow rate tier
    /// @param user The withdrawer's address
    /// @param shares The amount of shares burned
    /// @param amount The amount of assets withdrawn
    event Withdraw(uint256 borrowRate, address user, uint256 shares, uint256 amount);
    
    /// @notice Emitted when collateral is supplied
    /// @param borrowRate The borrow rate tier
    /// @param user The supplier's address
    /// @param amount The amount of collateral supplied
    event SupplyCollateral(uint256 borrowRate, address user, uint256 amount);
    
    /// @notice Emitted when collateral is withdrawn
    /// @param borrowRate The borrow rate tier
    /// @param user The withdrawer's address
    /// @param amount The amount of collateral withdrawn
    event WithdrawCollateral(uint256 borrowRate, address user, uint256 amount);
    
    /// @notice Emitted when a borrower repays their debt
    /// @param borrowRate The borrow rate tier
    /// @param user The repayer's address
    /// @param amount The amount repaid
    event Repay(uint256 borrowRate, address user, uint256 amount);

    /// @notice Thrown when an invalid borrow rate is provided
    error InvalidBorrowRate();
    /// @notice Thrown when an invalid LTV value is provided
    error InvalidLTV();
    /// @notice Thrown when invalid lending pool information is provided
    error InvalidLendingPoolInfo();
    /// @notice Thrown when attempting to add a borrow rate that already exists
    error BorrowRateAlreadyExists();
    /// @notice Thrown when attempting to interact with an inactive borrow rate
    error BorrowRateNotActive();
    /// @notice Thrown when an invalid user address is provided
    error InvalidUser();
    /// @notice Thrown when an invalid amount is provided
    error InvalidAmount();
    /// @notice Thrown when a user has insufficient shares for an operation
    error InsufficientShares();
    /// @notice Thrown when the pool has insufficient liquidity
    error InsufficientLiquidity();
    /// @notice Thrown when a user has insufficient collateral
    error InsufficientCollateral();
    /// @notice Thrown when a user has insufficient borrow shares
    error InsufficientBorrowShares();

    /// @notice Modifier to check if a borrow rate is active
    /// @param borrowRate_ The borrow rate to check
    modifier onlyActiveBorrowRate(uint256 borrowRate_) {
        if (!lendingPoolStates[borrowRate_].isActive) revert BorrowRateNotActive();
        _;
    }

    /// @notice Structure holding the lending pool's configuration
    /// @param debtToken Address of the token that can be borrowed
    /// @param collateralToken Address of the token that can be used as collateral
    /// @param oracle Address of the price oracle for the collateral token
    /// @param maturity Timestamp when the lending pool matures
    /// @param maturityMonth String representation of the maturity month
    /// @param maturityYear Year of maturity
    /// @param ltv Loan-to-Value ratio in 1e18 format
    struct LendingPoolInfo {
        address debtToken;
        address collateralToken;
        address oracle;
        uint256 maturity;
        string maturityMonth;
        uint256 maturityYear;
        uint256 ltv;
    }

    /// @notice Structure holding the state of a lending pool for a specific borrow rate
    /// @param pinjocToken Address of the PinjocToken contract for this borrow rate
    /// @param totalSupplyAssets Total amount of assets supplied
    /// @param totalSupplyShares Total amount of supply shares
    /// @param totalBorrowAssets Total amount of assets borrowed
    /// @param totalBorrowShares Total amount of borrow shares
    /// @param userBorrowShares Mapping of user addresses to their borrow shares
    /// @param userCollaterals Mapping of user addresses to their collateral amounts
    /// @param lastAccrued Timestamp of last interest accrual
    /// @param isActive Whether this borrow rate is active
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

    /// @notice The lending pool's configuration information
    LendingPoolInfo public info;
    /// @notice Mapping of borrow rates to their respective lending pool states
    mapping(uint256 => LendingPoolState) public lendingPoolStates;

    /// @notice Creates a new lending pool with specified parameters
    /// @param router_ Address of the router controlling the lending pool
    /// @param info_ Struct containing pool configuration parameters
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

    /// @notice Adds a new borrow rate tier to the lending pool
    /// @param borrowRate_ The borrow rate to add (in 1e18 format, e.g., 5% = 5e16)
    /// @dev Creates a new PinjocToken contract for this borrow rate tier
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
                rate: borrowRate_,
                maturity: info.maturity,
                maturityMonth: info.maturityMonth,
                maturityYear: info.maturityYear
            })
        ));

        emit BorrowRateAdded(borrowRate_);
    }
    
    /// @notice Updates the Loan-to-Value (LTV) ratio for the lending pool
    /// @param ltv_ The new LTV value (in 1e18 format)
    function setLtv(uint256 ltv_) external onlyOwner {
        if (ltv_ == 0) revert InvalidLTV();
        info.ltv = ltv_;

        emit LTVUpdated(ltv_);
    }

    /// @notice Records a supply of assets to the lending pool
    /// @param borrowRate The borrow rate tier for the supply
    /// @param user Address of the supplier
    /// @param amount Amount of assets being supplied
    /// @dev Only callable by the router contract. Mints PinjocTokens to the supplier.
    function supply(uint256 borrowRate, address user, uint256 amount) external onlyOwner nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (user == address(0)) revert InvalidUser();
        if (amount == 0) revert InvalidAmount();
        _accrueInterest(borrowRate);

        LendingPoolState storage state = lendingPoolStates[borrowRate];

        uint256 shares = 0;
        if (state.totalSupplyShares == 0) {
            shares = amount;
        } else {
            shares = (amount * state.totalSupplyShares) / state.totalSupplyAssets;
        }
        
        state.totalSupplyShares += shares;
        state.totalSupplyAssets += amount;
        
        // mint tokenized bond to the lender
        PinjocToken(state.pinjocToken).mint(user, shares);

        emit Supply(borrowRate, user, shares, amount);
    }

    /// @notice Records a borrow from the lending pool
    /// @param borrowRate The borrow rate tier for the borrow
    /// @param user Address of the borrower
    /// @param amount Amount of assets being borrowed
    /// @dev Only callable by the router contract. Checks borrower's health factor.
    function borrow(uint256 borrowRate, address user, uint256 amount) external onlyOwner nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (user == address(0)) revert InvalidUser();
        if (amount == 0) revert InvalidAmount();
        _accrueInterest(borrowRate);

        LendingPoolState storage state = lendingPoolStates[borrowRate];

        uint256 shares = 0;
        if (state.totalBorrowShares == 0) {
            shares = amount;
        } else {
            shares = (amount * state.totalBorrowShares) / state.totalBorrowAssets;
        }
        
        state.userBorrowShares[user] += shares;
        state.totalBorrowShares += shares;
        state.totalBorrowAssets += amount;
        
        _checkIsHealthy(borrowRate, user);

        emit Borrow(borrowRate, user, shares, amount);
    }

    /// @notice Allows lenders to withdraw their supplied assets
    /// @param borrowRate The borrow rate tier to withdraw from
    /// @param shares Amount of shares to withdraw
    /// @dev Burns PinjocTokens and transfers underlying assets to the withdrawer
    function withdraw(uint256 borrowRate, uint256 shares) external nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (shares == 0) revert InvalidAmount();
        LendingPoolState storage state = lendingPoolStates[borrowRate];
        if (IERC20(state.pinjocToken).balanceOf(msg.sender) < shares) revert InsufficientShares();
        _accrueInterest(borrowRate);

        // this calculates automatically with the interest
        uint256 amount = (shares * state.totalSupplyAssets) / state.totalSupplyShares;

        if (IERC20(info.debtToken).balanceOf(address(this)) < amount) revert InsufficientLiquidity();
        
        state.totalSupplyShares -= shares;
        state.totalSupplyAssets -= amount;

        PinjocToken(state.pinjocToken).burn(msg.sender, shares);
        IERC20(info.debtToken).transfer(msg.sender, amount);
        
        emit Withdraw(borrowRate, msg.sender, shares, amount);
    }

    /// @notice Records collateral supplied to the lending pool
    /// @param borrowRate The borrow rate tier for the collateral
    /// @param user Address of the collateral supplier
    /// @param amount Amount of collateral being supplied
    /// @dev Only callable by the router contract
    function supplyCollateral(uint256 borrowRate, address user, uint256 amount) external onlyOwner nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (user == address(0)) revert InvalidUser();
        if (amount == 0) revert InvalidAmount();
        _accrueInterest(borrowRate);

        LendingPoolState storage state = lendingPoolStates[borrowRate];
        state.userCollaterals[user] += amount;

        emit SupplyCollateral(borrowRate, user, amount);
    }

    /// @notice Allows borrowers to withdraw their collateral
    /// @param borrowRate The borrow rate tier to withdraw collateral from
    /// @param amount Amount of collateral to withdraw
    /// @dev Checks borrower's health factor after withdrawal
    function withdrawCollateral(uint256 borrowRate, uint256 amount) external nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (amount == 0) revert InvalidAmount();

        LendingPoolState storage state = lendingPoolStates[borrowRate];
        if (state.userCollaterals[msg.sender] < amount) revert InsufficientCollateral();
        _accrueInterest(borrowRate);

        state.userCollaterals[msg.sender] -= amount;

        _checkIsHealthy(borrowRate, msg.sender);

        IERC20(info.collateralToken).transfer(msg.sender, amount);

        emit WithdrawCollateral(borrowRate, msg.sender, amount);
    }

    /// @notice Allows borrowers to repay their borrowed assets
    /// @param borrowRate The borrow rate tier to repay
    /// @param amount Amount of borrow shares to repay
    /// @dev Transfers debt tokens from the borrower to the contract
    function repay(uint256 borrowRate, uint256 amount) external nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (amount == 0) revert InvalidAmount();
        _accrueInterest(borrowRate);
        
        LendingPoolState storage state = lendingPoolStates[borrowRate];
        if (state.userBorrowShares[msg.sender] < amount) revert InsufficientBorrowShares();

        uint256 borrowAmount = (amount * state.totalBorrowAssets) / state.totalBorrowShares;

        state.userBorrowShares[msg.sender] -= amount;
        state.totalBorrowShares -= amount;
        state.totalBorrowAssets -= borrowAmount;

        IERC20(info.debtToken).transferFrom(msg.sender, address(this), borrowAmount);

        emit Repay(borrowRate, msg.sender, borrowAmount);
    }

    /// @notice Accrues interest for a specific borrow rate tier
    /// @param borrowRate The borrow rate tier to accrue interest for
    /// @dev Calculates interest based on time elapsed since last accrual
    function _accrueInterest(uint256 borrowRate) internal {
        LendingPoolState storage state = lendingPoolStates[borrowRate];
        uint256 interestPerYear = state.totalBorrowAssets * borrowRate / 1e18;
        uint256 timePassed = block.timestamp - state.lastAccrued;

        uint256 interest = (interestPerYear * timePassed) / 365 days;

        state.totalSupplyAssets += interest;
        state.totalBorrowAssets += interest;
        state.lastAccrued = block.timestamp;
    }

    /// @notice Checks if a user's position is healthy (not subject to liquidation)
    /// @param borrowRate The borrow rate tier to check
    /// @param user Address of the user to check
    /// @dev Compares borrowed value against collateral value * LTV
    function _isHealthy(uint256 borrowRate, address user) internal view returns (bool) {
        uint256 collateralPrice = IMockOracle(info.oracle).price();
        uint256 collateralDecimals = 10 ** IERC20Metadata(info.collateralToken).decimals();

        LendingPoolState storage state = lendingPoolStates[borrowRate];
        uint256 borrowedValue = state.userBorrowShares[user] * state.totalBorrowAssets / state.totalBorrowShares;
        uint256 collateralValue = state.userCollaterals[user] * collateralPrice / collateralDecimals;
        uint256 maxBorrowedValue = collateralValue * info.ltv / 1e18;

        return borrowedValue <= maxBorrowedValue;
    }

    function _checkIsHealthy(uint256 borrowRate, address user) internal view {
        if (!_isHealthy(borrowRate, user)) revert InsufficientCollateral();
    }

    /// @notice Gets the collateral amount for a specific user at a given borrow rate
    /// @param borrowRate The borrow rate tier to check
    /// @param user The address of the user
    /// @return The amount of collateral the user has supplied
    /// @dev This function created because of the limitation of Solidity that does not support dynamic access to mapping from a struct
    function getUserCollateral(uint256 borrowRate, address user) public view returns (uint256) {
        return lendingPoolStates[borrowRate].userCollaterals[user];
    }

    /// @notice Gets the borrow shares for a specific user at a given borrow rate
    /// @param borrowRate The borrow rate tier to check
    /// @param user The address of the user
    /// @return The amount of borrow shares the user has
    /// @dev This function created because of the limitation of Solidity that does not support dynamic access to mapping from a struct
    function getUserBorrowShares(uint256 borrowRate, address user) public view returns (uint256) { 
        return lendingPoolStates[borrowRate].userBorrowShares[user];
    }
}