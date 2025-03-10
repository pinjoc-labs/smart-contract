// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title ILendingPool - Interface for P2P lending pool
/// @notice Interface for managing lending and borrowing operations with multiple borrow rates
interface ILendingPool {
    /// @notice Structure holding the lending pool's configuration
    /// @param debtToken Address of the token that can be borrowed
    /// @param collateralToken Address of the token that can be used as collateral
    /// @param oracle Address of the price oracle for the collateral token
    /// @param maturity Timestamp when the lending pool matures (after this, no new positions can be opened)
    /// @param maturityMonth String representation of the maturity month (e.g., "MAY")
    /// @param maturityYear Year when the lending pool matures
    /// @param ltv Loan-to-Value ratio in 1e18 format (e.g., 75% = 75e16)
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

    /// @notice Thrown when an invalid borrow rate is provided
    error InvalidBorrowRate();
    /// @notice Thrown when an invalid LTV value is provided
    error InvalidLTV();
    /// @notice Thrown when invalid lending pool information is provided
    error InvalidLendingPoolInfo();
    /// @notice Thrown when an operation is attempted after maturity date
    error MaturityReached();
    /// @notice Thrown when a withdrawal is attempted before maturity date
    error MaturityNotReached();
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

    /// @notice Emitted when a new borrow rate is added to the lending pool
    /// @param borrowRate The borrow rate that was added
    event BorrowRateAdded(uint256 borrowRate);

    /// @notice Emitted when a new PinjocToken is created
    /// @param pinjocToken The address of the new PinjocToken
    /// @param borrowRate The borrow rate that was added
    event PinjocTokenCreated(address pinjocToken, uint256 borrowRate);

    /// @notice Emitted when the LTV ratio is updated
    /// @param ltv The new LTV value
    event LTVUpdated(uint256 ltv);

    /// @notice Emitted when assets are supplied to the pool
    /// @param borrowRate The borrow rate tier
    /// @param user The supplier's address
    /// @param shares The amount of shares minted
    /// @param amount The amount of assets supplied
    event Supply(
        uint256 borrowRate,
        address user,
        uint256 shares,
        uint256 amount
    );

    /// @notice Emitted when assets are borrowed from the pool
    /// @param borrowRate The borrow rate tier
    /// @param user The borrower's address
    /// @param shares The amount of borrow shares
    /// @param amount The amount of assets borrowed
    event Borrow(
        uint256 borrowRate,
        address user,
        uint256 shares,
        uint256 amount
    );

    /// @notice Emitted when a supplier withdraws assets
    /// @param borrowRate The borrow rate tier
    /// @param user The withdrawer's address
    /// @param shares The amount of shares burned
    /// @param amount The amount of assets withdrawn
    event Withdraw(
        uint256 borrowRate,
        address user,
        uint256 shares,
        uint256 amount
    );

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

    /// @notice Emitted when a user's position is liquidated
    /// @param borrowRate The borrow rate tier
    /// @param liquidator The liquidator's address
    /// @param user The user's address
    /// @param amount The amount of debt tokens liquidated
    /// @param collateral The amount of collateral tokens liquidated
    event Liquidate(
        uint256 borrowRate,
        address liquidator,
        address user,
        uint256 amount,
        uint256 collateral
    );

    /// @notice Adds a new borrow rate tier to the lending pool
    /// @param borrowRate_ The borrow rate to add (in 1e18 format, e.g., 5% = 5e16)
    /// @dev Creates a new PinjocToken contract for this borrow rate tier
    function addBorrowRate(uint256 borrowRate_) external;

    /// @notice Updates the Loan-to-Value (LTV) ratio for the lending pool
    /// @param ltv_ The new LTV value (in 1e18 format)
    function setLtv(uint256 ltv_) external;

    /// @notice Records a supply of assets to the lending pool
    /// @param borrowRate The borrow rate tier for the supply
    /// @param user Address of the supplier
    /// @param amount Amount of assets being supplied
    /// @dev Only callable by the router contract. Mints PinjocTokens to the supplier.
    function supply(uint256 borrowRate, address user, uint256 amount) external;

    /// @notice Records a borrow from the lending pool
    /// @param borrowRate The borrow rate tier for the borrow
    /// @param user Address of the borrower
    /// @param amount Amount of assets being borrowed
    /// @dev Only callable by the router contract. Checks borrower's health factor.
    function borrow(uint256 borrowRate, address user, uint256 amount) external;

    /// @notice Allows lenders to withdraw their supplied assets
    /// @param borrowRate The borrow rate tier to withdraw from
    /// @param shares Amount of shares to withdraw
    /// @dev Only callable after maturity. Burns PinjocTokens and transfers underlying assets.
    function withdraw(uint256 borrowRate, uint256 shares) external;

    /// @notice Records collateral supplied to the lending pool
    /// @param borrowRate The borrow rate tier for the collateral
    /// @param user Address of the collateral supplier
    /// @param amount Amount of collateral being supplied
    /// @dev Only callable by the router contract
    function supplyCollateral(
        uint256 borrowRate,
        address user,
        uint256 amount
    ) external;

    /// @notice Allows borrowers to withdraw their collateral
    /// @param borrowRate The borrow rate tier to withdraw collateral from
    /// @param amount Amount of collateral to withdraw
    /// @dev Checks borrower's health factor after withdrawal
    function withdrawCollateral(uint256 borrowRate, uint256 amount) external;

    /// @notice Allows borrowers to repay their borrowed assets
    /// @param borrowRate The borrow rate tier to repay
    /// @param amount Amount of borrow shares to repay
    /// @dev Transfers debt tokens from the borrower to the contract
    function repay(uint256 borrowRate, uint256 amount) external;

    /// @notice Accrues interest for a specific borrow rate tier, capped at maturity
    /// @param borrowRate The borrow rate tier to accrue interest for
    /// @dev Interest only accrues up to maturity date, even if called after maturity
    function accrueInterest(uint256 borrowRate) external;

    /// @notice Gets the collateral amount for a specific user at a given borrow rate
    /// @param borrowRate The borrow rate tier to check
    /// @param user The address of the user
    /// @return The amount of collateral the user has supplied
    /// @dev This function created because of the limitation of Solidity that does not support dynamic access to mapping from a struct
    function getUserCollateral(
        uint256 borrowRate,
        address user
    ) external view returns (uint256);

    /// @notice Gets the borrow shares for a specific user at a given borrow rate
    /// @param borrowRate The borrow rate tier to check
    /// @param user The address of the user
    /// @return The amount of borrow shares the user has
    /// @dev This function created because of the limitation of Solidity that does not support dynamic access to mapping from a struct
    function getUserBorrowShares(
        uint256 borrowRate,
        address user
    ) external view returns (uint256);

    /// @notice Liquidates a user's position if it is unhealthy or after maturity
    /// @param borrowRate The borrow rate tier to liquidate
    /// @param user The address of the user to liquidate
    /// @dev Position can be liquidated if either: 1) It's past maturity, or 2) Position is unhealthy
    function liquidate(uint256 borrowRate, address user) external;
}
