// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IMockOracle} from "./interfaces/IMockOracle.sol";
import {ILendingCLOBManager} from "./interfaces/ILendingCLOBManager.sol";
import {ILendingPoolManager} from "./interfaces/ILendingPoolManager.sol";
import {ILendingCLOB} from "./interfaces/ILendingCLOB.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {LendingPool} from "./LendingPool.sol";

/// @title PinjocLendingRouter - Router contract for managing lending orders and pool interactions
/// @notice Handles order placement, matching, and execution in the lending protocol
/// @dev Implements order book management, pool interactions, and collateral health checks
contract PinjocLendingRouter is Ownable, ReentrancyGuard {
    /// @notice Error thrown when an invalid lending CLOB manager address is provided
    error InvalidLendingCLOBManager();

    /// @notice Error thrown when an invalid lending pool manager address is provided
    error InvalidLendingPoolManager();

    /// @notice Error thrown when the oracle for a token pair is not found
    error OracleNotFound();

    /// @notice Error thrown when invalid parameters are provided for order placement
    error InvalidPlaceOrderParameter();

    /// @notice Error thrown when user's token balance is insufficient
    /// @param token The token address with insufficient balance
    /// @param balance The current balance of the token
    /// @param amount The required amount
    error BalanceNotEnough(address token, uint256 balance, uint256 amount);

    /// @notice Error thrown when collateral is insufficient for the requested borrow amount
    error InsufficientCollateral();

    /// @notice The lending CLOB manager contract that handles order book creation and management
    ILendingCLOBManager public lendingCLOBManager;

    /// @notice The lending pool manager contract that handles pool creation and management
    ILendingPoolManager public lendingPoolManager;

    /// @notice Initializes the router with lending CLOB and pool managers
    /// @param _lendingCLOBManager Address of the lending CLOB manager contract
    /// @param _lendingPoolManager Address of the lending pool manager contract
    constructor(
        address _lendingCLOBManager,
        address _lendingPoolManager
    ) Ownable(msg.sender) {
        setLendingCLOBManager(_lendingCLOBManager);
        setLendingPoolManager(_lendingPoolManager);
    }

    /// @notice Sets the lending CLOB manager address
    /// @dev Only callable by the owner
    /// @param _lendingCLOBManager The new lending CLOB manager address
    function setLendingCLOBManager(
        address _lendingCLOBManager
    ) public onlyOwner {
        if (_lendingCLOBManager == address(0)) revert InvalidLendingCLOBManager();
        lendingCLOBManager = ILendingCLOBManager(_lendingCLOBManager);
    }

    /// @notice Sets the lending pool manager address
    /// @dev Only callable by the owner
    /// @param _lendingPoolManager The new lending pool manager address
    function setLendingPoolManager(
        address _lendingPoolManager
    ) public onlyOwner {
        if (_lendingPoolManager == address(0)) revert InvalidLendingPoolManager();
        lendingPoolManager = ILendingPoolManager(_lendingPoolManager);
    }

    /// @notice Checks if a borrow position is healthy based on collateral value
    /// @dev Reverts if collateral is insufficient or user's balance is too low
    /// @param _debtToken The token being borrowed
    /// @param _collateralToken The token being used as collateral
    /// @param _maturity The maturity timestamp of the position
    /// @param _maturityMonth The maturity month (e.g., "MAR")
    /// @param _maturityYear The maturity year
    /// @param _borrowedAmount The amount being borrowed
    /// @param _collateralAmount The amount of collateral being provided
    function _isHealthy(
        address _debtToken,
        address _collateralToken,
        uint256 _maturity,
        string calldata _maturityMonth,
        uint256 _maturityYear,
        uint256 _borrowedAmount,
        uint256 _collateralAmount
    ) internal {
        if (IERC20(_collateralToken).balanceOf(msg.sender) < _collateralAmount)
            revert BalanceNotEnough(
                _collateralToken,
                IERC20(_collateralToken).balanceOf(msg.sender),
                _collateralAmount
            );
        address lendingPoolAddress = _getLendingPoolAddress(
            _debtToken,
            _collateralToken,
            _maturity,
            _maturityMonth,
            _maturityYear
        );

        (,, address oracle,,,, uint256 ltv) = LendingPool(lendingPoolAddress).info();
        uint256 collateralPrice = IMockOracle(oracle).price();
        uint256 collateralDecimals = 10 ** IERC20Metadata(_collateralToken).decimals();

        uint256 collateralValue = (_collateralAmount * collateralPrice) / collateralDecimals;
        uint256 maxBorrowValue = (collateralValue * ltv) / 1e18;

        if (_borrowedAmount > maxBorrowValue) revert InsufficientCollateral();
    }

    /// @notice Gets or creates the order book address for a token pair
    /// @dev Creates a new order book if one doesn't exist
    /// @param _debtToken The debt token address
    /// @param _collateralToken The collateral token address
    /// @param _maturityMonth The maturity month
    /// @param _maturityYear The maturity year
    /// @return The order book address
    function _getOrderBookAddress(
        address _debtToken,
        address _collateralToken,
        string calldata _maturityMonth,
        uint256 _maturityYear
    ) internal returns (address) {
        address orderBookAddr = lendingCLOBManager.getLendingCLOB(
            _debtToken,
            _collateralToken,
            _maturityMonth,
            _maturityYear
        );

        if (orderBookAddr == address(0)) {
            return
                lendingCLOBManager.createLendingCLOB(
                    _debtToken,
                    _collateralToken,
                    _maturityMonth,
                    _maturityYear
                );
        } else {
            return orderBookAddr;
        }
    }

    /// @notice Gets or creates the lending pool address for a token pair
    /// @dev Creates a new lending pool if one doesn't exist
    /// @param _debtToken The debt token address
    /// @param _collateralToken The collateral token address
    /// @param _maturity The maturity timestamp
    /// @param _maturityMonth The maturity month
    /// @param _maturityYear The maturity year
    /// @return The lending pool address
    function _getLendingPoolAddress(
        address _debtToken,
        address _collateralToken,
        uint256 _maturity,
        string calldata _maturityMonth,
        uint256 _maturityYear
    ) internal returns (address) {
        address lendingPoolAddr = lendingPoolManager.getLendingPool(
            _debtToken,
            _collateralToken,
            _maturityMonth,
            _maturityYear
        );

        if (lendingPoolAddr == address(0)) {
            return
                lendingPoolManager.createLendingPool(
                    _debtToken,
                    _collateralToken,
                    _maturity,
                    _maturityMonth,
                    _maturityYear
                );
        } else {
            return lendingPoolAddr;
        }
    }

    /// @notice Places a new lending or borrowing order
    /// @dev Handles token transfers, order matching, and pool interactions
    /// @param _debtToken The token being borrowed (e.g., USDC)
    /// @param _collateralToken The token being used as collateral (e.g., ETH)
    /// @param _amount The amount of debt token to borrow/lend
    /// @param _collateralAmount The amount of collateral token to provide
    /// @param _rate The annual percentage rate (APY) in 1e18 format (e.g., 5% = 5e16)
    /// @param _maturity The maturity timestamp
    /// @param _maturityMonth The maturity month (e.g., "MAR")
    /// @param _maturityYear The maturity year
    /// @param _side The side of the order (LEND or BORROW)
    function placeOrder(
        address _debtToken,
        address _collateralToken,
        uint256 _amount,
        uint256 _collateralAmount,
        uint256 _rate,
        uint256 _maturity,
        string calldata _maturityMonth,
        uint256 _maturityYear,
        ILendingCLOB.Side _side
    ) external nonReentrant {
        if (
            _debtToken == address(0) ||
            _collateralToken == address(0) ||
            _amount == 0 ||
            _rate == 0 ||
            _maturity == 0 ||
            bytes(_maturityMonth).length == 0 ||
            _maturityYear == 0
        ) revert InvalidPlaceOrderParameter();

        address orderBookAddr = _getOrderBookAddress(_debtToken, _collateralToken, _maturityMonth, _maturityYear);

        // Handle token transfers and approvals
        if (_side == ILendingCLOB.Side.LEND) {
            // Check balance and approve router first
            if (IERC20(_debtToken).balanceOf(msg.sender) < _amount)
                revert BalanceNotEnough(
                    _debtToken,
                    IERC20(_debtToken).balanceOf(msg.sender),
                    _amount
                );
            
            // Transfer from user to router
            IERC20(_debtToken).transferFrom(msg.sender, address(this), _amount);
            
            // Approve CLOB to spend router's tokens
            IERC20(_debtToken).approve(orderBookAddr, _amount);
        } else {
            _isHealthy(
                _debtToken,
                _collateralToken,
                _maturity,
                _maturityMonth,
                _maturityYear,
                _amount,
                _collateralAmount
            );

            // Transfer collateral from user to router
            IERC20(_collateralToken).transferFrom(msg.sender, address(this), _collateralAmount);
            
            // Approve CLOB to spend router's collateral
            IERC20(_collateralToken).approve(orderBookAddr, _collateralAmount);
        }

        // Place order in CLOB
        ILendingCLOB orderBook = ILendingCLOB(orderBookAddr);
        (
            ILendingCLOB.MatchedInfo[] memory matchedLendOrders,
            ILendingCLOB.MatchedInfo[] memory matchedBorrowOrders
        ) = orderBook.placeOrder(
            msg.sender,
            _amount,
            _collateralAmount,
            _rate,
            _side
        );

        address lendingPoolAddress = _getLendingPoolAddress(
            _debtToken,
            _collateralToken,
            _maturity,
            _maturityMonth,
            _maturityYear
        );

        // Add borrow rate if it doesn't exist
        if (matchedLendOrders.length > 0 || matchedBorrowOrders.length > 0) {
            (,,,,,,bool active) = LendingPool(lendingPoolAddress).lendingPoolStates(_rate);
            if (!active) {
                LendingPool(lendingPoolAddress).addBorrowRate(_rate);
            }
        }

        // Handle matched orders
        if (_side == ILendingCLOB.Side.LEND && matchedLendOrders.length > 0) {
            // Handle lender's matched order
            ILendingPool(lendingPoolAddress).supply(
                _rate,
                matchedLendOrders[0].trader,
                matchedLendOrders[0].matchAmount
            );

            // Handle borrower's matched orders
            for (uint256 i = 0; i < matchedBorrowOrders.length; i++) {
                uint256 partialCollat = matchedBorrowOrders[i].matchCollateralAmount;
                uint256 portionOfDebt = matchedBorrowOrders[i].matchAmount;

                ILendingPool(lendingPoolAddress).supplyCollateral(
                    _rate,
                    matchedBorrowOrders[i].trader,
                    partialCollat
                );
                ILendingPool(lendingPoolAddress).borrow(
                    _rate,
                    matchedBorrowOrders[i].trader,
                    portionOfDebt
                );

                // Transfer matched amounts between parties
                orderBook.transferFrom(
                    matchedBorrowOrders[i].trader,
                    lendingPoolAddress,
                    partialCollat,
                    ILendingCLOB.Side.BORROW
                );
                orderBook.transferFrom(
                    matchedLendOrders[0].trader,
                    matchedBorrowOrders[i].trader,
                    portionOfDebt,
                    ILendingCLOB.Side.LEND
                );
            }
        } else if (_side == ILendingCLOB.Side.BORROW && matchedBorrowOrders.length > 0) {
            uint256 partialCollat = matchedBorrowOrders[0].matchCollateralAmount;
            uint256 portionOfDebt = matchedBorrowOrders[0].matchAmount;

            // Handle borrower's matched order
            ILendingPool(lendingPoolAddress).supplyCollateral(
                _rate,
                matchedBorrowOrders[0].trader,
                partialCollat
            );

            // Handle lender's matched orders
            for (uint256 i = 0; i < matchedLendOrders.length; i++) {
                uint256 portionOfDebtLend = matchedLendOrders[i].matchAmount;

                ILendingPool(lendingPoolAddress).supply(
                    _rate,
                    matchedLendOrders[i].trader,
                    portionOfDebtLend
                );

                // Transfer matched amounts between parties
                orderBook.transferFrom(
                    matchedLendOrders[i].trader,
                    matchedBorrowOrders[0].trader,
                    portionOfDebtLend,
                    ILendingCLOB.Side.LEND
                );
            }

            // Complete borrower's transaction
            ILendingPool(lendingPoolAddress).borrow(
                _rate,
                matchedBorrowOrders[0].trader,
                portionOfDebt
            );
            orderBook.transferFrom(
                matchedBorrowOrders[0].trader,
                lendingPoolAddress,
                partialCollat,
                ILendingCLOB.Side.BORROW
            );
        }
    }

    /// @notice Cancels an existing order
    /// @dev Only the order creator can cancel their order
    /// @param _debtToken The debt token address
    /// @param _collateralToken The collateral token address
    /// @param _maturityMonth The maturity month
    /// @param _maturityYear The maturity year
    /// @param _orderId The ID of the order to cancel
    function cancelOrder(
        address _debtToken,
        address _collateralToken,
        string calldata _maturityMonth,
        uint256 _maturityYear,
        uint256 _orderId
    ) external nonReentrant {
        address orderBookAddr = _getOrderBookAddress(_debtToken, _collateralToken, _maturityMonth, _maturityYear);
        ILendingCLOB orderBook = ILendingCLOB(orderBookAddr);
        orderBook.cancelOrder(msg.sender, _orderId);
    }
}
