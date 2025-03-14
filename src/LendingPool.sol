// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {PinjocToken} from "./PinjocToken.sol";
import {IMockOracle} from "./interfaces/IMockOracle.sol";

/// @title LendingPool - A P2P lending pool contract with CLOB (Central Limit Order Book)
/// @notice This contract manages lending and borrowing operations with multiple borrow rates and maturity-based restrictions
/// @dev Implements collateralized lending with interest accrual, health factor checks, and maturity-based access control
contract LendingPool is ILendingPool, Ownable, ReentrancyGuard {
    /// @notice Modifier to check if a borrow rate is active
    /// @param borrowRate_ The borrow rate to check
    modifier onlyActiveBorrowRate(uint256 borrowRate_) {
        if (!lendingPoolStates[borrowRate_].isActive)
            revert BorrowRateNotActive();
        _;
    }

    /// @notice Modifier to check if the current timestamp is before maturity
    /// @dev Reverts with MaturityReached if the current time is past maturity
    modifier onlyBeforeMaturity() {
        if (block.timestamp > info.maturity) revert MaturityReached();
        _;
    }

    modifier onlyRouter() {
        if (msg.sender != router) revert InvalidRouter();
        _;
    }

    address public router;
    /// @notice The lending pool's configuration information
    LendingPoolInfo public info;
    /// @notice Mapping of borrow rates to their respective lending pool states
    mapping(uint256 => LendingPoolState) public lendingPoolStates;

    /// @notice Creates a new lending pool with specified parameters
    /// @param owner_ Address of the owner of the lending pool
    /// @param router_ Address of the router controlling the lending pool
    /// @param info_ Struct containing pool configuration parameters
    constructor(
        address owner_,
        address router_,
        LendingPoolInfo memory info_
    ) Ownable(owner_) {
        if (router_ == address(0)) revert InvalidRouter();
        if (
            info_.debtToken == address(0) ||
            info_.collateralToken == address(0) ||
            info_.oracle == address(0) ||
            info_.maturity <= block.timestamp ||
            bytes(info_.maturityMonth).length == 0 ||
            info_.maturityYear == 0 ||
            info_.ltv == 0
        ) revert InvalidLendingPoolInfo();
        router = router_;
        info = info_;
    }

    /// @notice Sets the router address
    /// @dev Only callable by the current router
    /// @param router_ The new router address
    function setRouter(address router_) external onlyOwner {
        if (router_ == address(0)) revert InvalidRouter();
        router = router_;
    }

    /// @notice Adds a new borrow rate tier to the lending pool
    /// @param borrowRate_ The borrow rate to add (in 1e18 format, e.g., 5% = 5e16)
    /// @dev Creates a new PinjocToken contract for this borrow rate tier
    function addBorrowRate(
        uint256 borrowRate_
    ) external onlyRouter onlyBeforeMaturity {
        if (lendingPoolStates[borrowRate_].isActive)
            revert BorrowRateAlreadyExists();
        if (borrowRate_ == 0 || borrowRate_ == 100e16)
            revert InvalidBorrowRate();

        LendingPoolState storage state = lendingPoolStates[borrowRate_];
        state.isActive = true;
        state.lastAccrued = block.timestamp;
        state.pinjocToken = address(
            new PinjocToken(
                address(this),
                PinjocToken.PinjocTokenInfo({
                    debtToken: info.debtToken,
                    collateralToken: info.collateralToken,
                    rate: borrowRate_,
                    maturity: info.maturity,
                    maturityMonth: info.maturityMonth,
                    maturityYear: info.maturityYear
                })
            )
        );

        emit BorrowRateAdded(borrowRate_);
        emit PinjocTokenCreated(address(state.pinjocToken), borrowRate_);
    }

    /// @notice Updates the Loan-to-Value (LTV) ratio for the lending pool
    /// @param ltv_ The new LTV value (in 1e18 format)
    function setLtv(uint256 ltv_) external onlyOwner onlyBeforeMaturity {
        if (ltv_ == 0) revert InvalidLTV();
        info.ltv = ltv_;

        emit LTVUpdated(ltv_);
    }

    /// @notice Records a supply of assets to the lending pool
    /// @param borrowRate The borrow rate tier for the supply
    /// @param user Address of the supplier
    /// @param amount Amount of assets being supplied
    /// @dev Only callable by the router contract. Mints PinjocTokens to the supplier.
    function supply(
        uint256 borrowRate,
        address user,
        uint256 amount
    )
        external
        onlyRouter
        nonReentrant
        onlyActiveBorrowRate(borrowRate)
        onlyBeforeMaturity
    {
        if (user == address(0)) revert InvalidUser();
        if (amount == 0) revert InvalidAmount();
        accrueInterest(borrowRate);

        LendingPoolState storage state = lendingPoolStates[borrowRate];

        uint256 shares = 0;
        if (state.totalSupplyShares == 0) {
            shares = amount;
        } else {
            shares =
                (amount * state.totalSupplyShares) /
                state.totalSupplyAssets;
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
    function borrow(
        uint256 borrowRate,
        address user,
        uint256 amount
    )
        external
        onlyRouter
        nonReentrant
        onlyActiveBorrowRate(borrowRate)
        onlyBeforeMaturity
    {
        if (user == address(0)) revert InvalidUser();
        if (amount == 0) revert InvalidAmount();
        accrueInterest(borrowRate);

        LendingPoolState storage state = lendingPoolStates[borrowRate];

        uint256 shares = 0;
        if (state.totalBorrowShares == 0) {
            shares = amount;
        } else {
            shares =
                (amount * state.totalBorrowShares) /
                state.totalBorrowAssets;
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
    /// @dev Only callable after maturity. Burns PinjocTokens and transfers underlying assets.
    function withdraw(
        uint256 borrowRate,
        uint256 shares
    ) external nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (shares == 0) revert InvalidAmount();
        if (block.timestamp < info.maturity) revert MaturityNotReached();

        LendingPoolState storage state = lendingPoolStates[borrowRate];
        if (IERC20(state.pinjocToken).balanceOf(msg.sender) < shares)
            revert InsufficientShares();
        accrueInterest(borrowRate);

        // this calculates automatically with the interest
        uint256 amount = (shares * state.totalSupplyAssets) /
            state.totalSupplyShares;

        if (IERC20(info.debtToken).balanceOf(address(this)) < amount)
            revert InsufficientLiquidity();

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
    function supplyCollateral(
        uint256 borrowRate,
        address user,
        uint256 amount
    )
        external
        onlyRouter
        nonReentrant
        onlyActiveBorrowRate(borrowRate)
        onlyBeforeMaturity
    {
        if (user == address(0)) revert InvalidUser();
        if (amount == 0) revert InvalidAmount();
        accrueInterest(borrowRate);

        LendingPoolState storage state = lendingPoolStates[borrowRate];
        state.userCollaterals[user] += amount;

        emit SupplyCollateral(borrowRate, user, amount);
    }

    /// @notice Allows borrowers to withdraw their collateral
    /// @param borrowRate The borrow rate tier to withdraw collateral from
    /// @param amount Amount of collateral to withdraw
    /// @dev Checks borrower's health factor after withdrawal
    function withdrawCollateral(
        uint256 borrowRate,
        uint256 amount
    ) external nonReentrant onlyActiveBorrowRate(borrowRate) {
        if (amount == 0) revert InvalidAmount();

        LendingPoolState storage state = lendingPoolStates[borrowRate];
        if (state.userCollaterals[msg.sender] < amount)
            revert InsufficientCollateral();
        accrueInterest(borrowRate);

        state.userCollaterals[msg.sender] -= amount;

        _checkIsHealthy(borrowRate, msg.sender);

        IERC20(info.collateralToken).transfer(msg.sender, amount);

        emit WithdrawCollateral(borrowRate, msg.sender, amount);
    }

    /// @notice Allows borrowers to repay their borrowed assets
    /// @param borrowRate The borrow rate tier to repay
    /// @param amount Amount of borrow shares to repay
    /// @dev Transfers debt tokens from the borrower to the contract
    function repay(
        uint256 borrowRate,
        uint256 amount
    )
        external
        nonReentrant
        onlyActiveBorrowRate(borrowRate)
        onlyBeforeMaturity
    {
        if (amount == 0) revert InvalidAmount();
        accrueInterest(borrowRate);

        LendingPoolState storage state = lendingPoolStates[borrowRate];
        if (state.userBorrowShares[msg.sender] < amount)
            revert InsufficientBorrowShares();

        uint256 borrowAmount = (amount * state.totalBorrowAssets) /
            state.totalBorrowShares;

        state.userBorrowShares[msg.sender] -= amount;
        state.totalBorrowShares -= amount;
        state.totalBorrowAssets -= borrowAmount;

        IERC20(info.debtToken).transferFrom(
            msg.sender,
            address(this),
            borrowAmount
        );

        emit Repay(borrowRate, msg.sender, borrowAmount);
    }

    /// @notice Accrues interest for a specific borrow rate tier, capped at maturity
    /// @param borrowRate The borrow rate tier to accrue interest for
    /// @dev Interest only accrues up to maturity date, even if called after maturity
    function accrueInterest(uint256 borrowRate) public {
        LendingPoolState storage state = lendingPoolStates[borrowRate];
        uint256 interestPerYear = (state.totalBorrowAssets * borrowRate) / 1e18;

        // Cap time passed at maturity
        uint256 timePassed;
        uint256 maxLastTimestamp;
        if (block.timestamp > info.maturity) {
            timePassed = info.maturity - state.lastAccrued;
            maxLastTimestamp = info.maturity;
        } else {
            timePassed = block.timestamp - state.lastAccrued;
            maxLastTimestamp = block.timestamp;
        }

        uint256 interest = (interestPerYear * timePassed) / 365 days;

        state.totalSupplyAssets += interest;
        state.totalBorrowAssets += interest;
        state.lastAccrued = maxLastTimestamp;
    }

    /// @notice Checks if a user's position is healthy (not subject to liquidation)
    /// @param borrowRate The borrow rate tier to check
    /// @param user Address of the user to check
    /// @dev Compares borrowed value against collateral value * LTV
    function _isHealthy(
        uint256 borrowRate,
        address user
    ) internal view returns (bool) {
        uint256 collateralPrice = IMockOracle(info.oracle).price();
        uint256 collateralDecimals = 10 **
            IERC20Metadata(info.collateralToken).decimals();

        LendingPoolState storage state = lendingPoolStates[borrowRate];
        uint256 borrowedValue = (state.userBorrowShares[user] *
            state.totalBorrowAssets) / state.totalBorrowShares;
        uint256 collateralValue = (state.userCollaterals[user] *
            collateralPrice) / collateralDecimals;
        uint256 maxBorrowedValue = (collateralValue * info.ltv) / 1e18;

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
    function getUserCollateral(
        uint256 borrowRate,
        address user
    ) public view returns (uint256) {
        return lendingPoolStates[borrowRate].userCollaterals[user];
    }

    /// @notice Gets the borrow shares for a specific user at a given borrow rate
    /// @param borrowRate The borrow rate tier to check
    /// @param user The address of the user
    /// @return The amount of borrow shares the user has
    /// @dev This function created because of the limitation of Solidity that does not support dynamic access to mapping from a struct
    function getUserBorrowShares(
        uint256 borrowRate,
        address user
    ) public view returns (uint256) {
        return lendingPoolStates[borrowRate].userBorrowShares[user];
    }

    /// @notice Liquidates a user's position if it is unhealthy or after maturity
    /// @param borrowRate The borrow rate tier to liquidate
    /// @param user The address of the user to liquidate
    /// @dev Position can be liquidated if either: 1) It's past maturity, or 2) Position is unhealthy
    function liquidate(
        uint256 borrowRate,
        address user
    ) external onlyActiveBorrowRate(borrowRate) {
        if (user == address(0)) revert InvalidUser();
        if (block.timestamp > info.maturity || !_isHealthy(borrowRate, user)) {
            LendingPoolState storage state = lendingPoolStates[borrowRate];
            uint256 debt = (state.userBorrowShares[user] *
                state.totalBorrowAssets) / state.totalBorrowShares;
            uint256 collateral = state.userCollaterals[user];

            state.totalBorrowShares -= state.userBorrowShares[user];
            state.totalBorrowAssets -= debt;
            state.userBorrowShares[user] = 0;
            state.userCollaterals[user] = 0;

            IERC20(info.debtToken).transferFrom(
                msg.sender,
                address(this),
                debt
            );
            IERC20(info.collateralToken).transfer(msg.sender, collateral);

            emit Liquidate(
                borrowRate,
                msg.sender,
                user,
                lendingPoolStates[borrowRate].userBorrowShares[user],
                lendingPoolStates[borrowRate].userCollaterals[user]
            );
        }
    }
}
