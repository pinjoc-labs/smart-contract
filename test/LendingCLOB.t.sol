// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import {ILendingCLOB} from "../src/interfaces/ILendingCLOB.sol";
import {LendingCLOB} from "../src/LendingCLOB.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

/// @title LendingCLOBTest_Base - Base contract for LendingCLOB tests
/// @notice Contains common setup and helper functions for testing LendingCLOB functionality
contract LendingCLOBTest_Base is Test {
    // Constants for testing
    uint256 internal constant INITIAL_BALANCE = 1000e18;
    uint256 internal constant DEFAULT_AMOUNT = 100e18;
    uint256 internal constant DEFAULT_COLLATERAL = 500e18;
    uint256 internal constant DEFAULT_RATE = 50e15; // 5% interest rate

    // Test contracts
    LendingCLOB internal clob;
    MockToken internal debtToken;
    MockToken internal collateralToken;

    // Test accounts
    address internal router;
    address internal lender;
    address internal borrower;

    function setUp() public virtual {
        // Deploy mock tokens
        debtToken = new MockToken("Mock USDC", "MUSDC", 6);
        collateralToken = new MockToken("Mock ETH", "METH", 18);

        // Setup test accounts
        router = makeAddr("router");
        lender = makeAddr("lender");
        borrower = makeAddr("borrower");

        // Deploy LendingCLOB
        vm.prank(router);
        clob = new LendingCLOB(
            router,
            address(debtToken),
            address(collateralToken),
            "MAY",
            2025
        );

        // Setup initial balances
        _setupBalances();
    }

    /// @notice Sets up initial token balances and approvals for test accounts
    function _setupBalances() internal {
        // Mint tokens to test accounts
        debtToken.mint(lender, INITIAL_BALANCE);
        collateralToken.mint(borrower, INITIAL_BALANCE);

        // Setup approvals
        vm.startPrank(lender);
        debtToken.approve(address(clob), type(uint256).max);
        collateralToken.approve(address(clob), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower);
        debtToken.approve(address(clob), type(uint256).max);
        collateralToken.approve(address(clob), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Helper to place a lend order
    function _placeLendOrder(
        address trader,
        uint256 amount,
        uint256 rate
    )
        internal
        returns (
            ILendingCLOB.MatchedInfo[] memory lendMatches,
            ILendingCLOB.MatchedInfo[] memory borrowMatches
        )
    {
        vm.prank(router);
        return clob.placeOrder(trader, amount, 0, rate, ILendingCLOB.Side.LEND);
    }

    /// @notice Helper to place a borrow order
    function _placeBorrowOrder(
        address trader,
        uint256 amount,
        uint256 collateralAmount,
        uint256 rate
    )
        internal
        returns (
            ILendingCLOB.MatchedInfo[] memory lendMatches,
            ILendingCLOB.MatchedInfo[] memory borrowMatches
        )
    {
        vm.prank(router);
        return
            clob.placeOrder(
                trader,
                amount,
                collateralAmount,
                rate,
                ILendingCLOB.Side.BORROW
            );
    }

    /// @notice Helper to verify order details
    function _verifyOrder(
        ILendingCLOB.Order memory order,
        uint256 expectedId,
        address expectedTrader,
        uint256 expectedAmount,
        uint256 expectedCollateral,
        uint256 expectedRate,
        ILendingCLOB.Side expectedSide,
        ILendingCLOB.Status expectedStatus
    ) internal pure {
        assertEq(order.id, expectedId);
        assertEq(order.trader, expectedTrader);
        assertEq(order.amount, expectedAmount);
        assertEq(order.collateralAmount, expectedCollateral);
        assertEq(order.rate, expectedRate);
        assertTrue(order.side == expectedSide);
        assertTrue(order.status == expectedStatus);
    }
}

/// @title LendingCLOBTest_PlaceOrder - Tests for order placement functionality
/// @notice Tests both happy and unhappy paths for placing orders
contract LendingCLOBTest_PlaceOrder is LendingCLOBTest_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_PlaceOrder_Lend() public {
        (
            ILendingCLOB.MatchedInfo[] memory lendMatches,
            ILendingCLOB.MatchedInfo[] memory borrowMatches
        ) = _placeLendOrder(lender, DEFAULT_AMOUNT, DEFAULT_RATE);

        // Verify no matches occurred
        assertEq(lendMatches.length, 0);
        assertEq(borrowMatches.length, 0);

        // Verify order placement
        ILendingCLOB.Order[] memory orders = clob.getUserOrders(lender);
        assertEq(orders.length, 1);
        _verifyOrder(
            orders[0],
            0, // first order ID
            lender,
            DEFAULT_AMOUNT,
            0, // no collateral for lend orders
            DEFAULT_RATE,
            ILendingCLOB.Side.LEND,
            ILendingCLOB.Status.OPEN
        );

        // Verify token transfer
        assertEq(debtToken.balanceOf(address(clob)), DEFAULT_AMOUNT);
        assertEq(clob.debtBalances(lender), DEFAULT_AMOUNT);
    }

    function test_PlaceOrder_Borrow() public {
        (
            ILendingCLOB.MatchedInfo[] memory lendMatches,
            ILendingCLOB.MatchedInfo[] memory borrowMatches
        ) = _placeBorrowOrder(
                borrower,
                DEFAULT_AMOUNT,
                DEFAULT_COLLATERAL,
                DEFAULT_RATE
            );

        // Verify no matches occurred
        assertEq(lendMatches.length, 0);
        assertEq(borrowMatches.length, 0);

        // Verify order placement
        ILendingCLOB.Order[] memory orders = clob.getUserOrders(borrower);
        assertEq(orders.length, 1);
        _verifyOrder(
            orders[0],
            0, // first order ID
            borrower,
            DEFAULT_AMOUNT,
            DEFAULT_COLLATERAL,
            DEFAULT_RATE,
            ILendingCLOB.Side.BORROW,
            ILendingCLOB.Status.OPEN
        );

        // Verify token transfer
        assertEq(collateralToken.balanceOf(address(clob)), DEFAULT_COLLATERAL);
        assertEq(clob.collateralBalances(borrower), DEFAULT_COLLATERAL);
    }

    function test_PlaceOrder_Filled() public {
        // Place lend order
        _placeLendOrder(lender, DEFAULT_AMOUNT, DEFAULT_RATE);
        // Place matching borrow order
        (
            ILendingCLOB.MatchedInfo[] memory lendMatches,
            ILendingCLOB.MatchedInfo[] memory borrowMatches
        ) = _placeBorrowOrder(
                borrower,
                DEFAULT_AMOUNT,
                DEFAULT_COLLATERAL,
                DEFAULT_RATE
            );

        // Verify matches
        assertEq(lendMatches.length, 1);
        assertEq(borrowMatches.length, 1);

        // Verify lend match
        assertEq(lendMatches[0].trader, lender);
        assertEq(lendMatches[0].matchAmount, DEFAULT_AMOUNT);

        // Verify borrow match
        assertEq(borrowMatches[0].trader, borrower);
        assertEq(borrowMatches[0].matchAmount, DEFAULT_AMOUNT);
        assertEq(borrowMatches[0].matchCollateralAmount, DEFAULT_COLLATERAL);

        // Verify order status
        ILendingCLOB.Order[] memory orders = clob.getUserOrders(lender);
        assertTrue(orders[0].status == ILendingCLOB.Status.FILLED);
    }

    function test_PlaceOrder_RevertIf_InsufficientBalance() public {
        // Attempt to place order with more tokens than balance
        uint256 tooMuchAmount = INITIAL_BALANCE + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                lender,
                INITIAL_BALANCE,
                tooMuchAmount
            )
        );
        _placeLendOrder(lender, tooMuchAmount, DEFAULT_RATE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                borrower,
                INITIAL_BALANCE,
                tooMuchAmount
            )
        );
        _placeBorrowOrder(
            borrower,
            DEFAULT_AMOUNT,
            tooMuchAmount,
            DEFAULT_RATE
        );
    }

    function test_PlaceOrder_RevertIf_NoApproval() public {
        address newLender = makeAddr("newLender");
        debtToken.mint(newLender, INITIAL_BALANCE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(clob),
                0,
                DEFAULT_AMOUNT
            )
        );
        _placeLendOrder(newLender, DEFAULT_AMOUNT, DEFAULT_RATE);

        address newBorrower = makeAddr("newBorrower");
        collateralToken.mint(newBorrower, INITIAL_BALANCE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(clob),
                0,
                DEFAULT_COLLATERAL
            )
        );
        _placeBorrowOrder(
            newBorrower,
            DEFAULT_AMOUNT,
            DEFAULT_COLLATERAL,
            DEFAULT_RATE
        );
    }
}

/// @title LendingCLOBTest_OrderMatching - Tests for order matching functionality
/// @notice Tests both happy and unhappy paths for order matching
contract LendingCLOBTest_OrderMatching is LendingCLOBTest_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_OrderMatching_ExactMatch() public {
        // Place lend order
        _placeLendOrder(lender, DEFAULT_AMOUNT, DEFAULT_RATE);

        // Place matching borrow order
        (
            ILendingCLOB.MatchedInfo[] memory lendMatches,
            ILendingCLOB.MatchedInfo[] memory borrowMatches
        ) = _placeBorrowOrder(
                borrower,
                DEFAULT_AMOUNT,
                DEFAULT_COLLATERAL,
                DEFAULT_RATE
            );

        // Verify matches
        assertEq(lendMatches.length, 1);
        assertEq(borrowMatches.length, 1);

        // Verify lend match
        assertEq(lendMatches[0].trader, lender);
        assertEq(lendMatches[0].matchAmount, DEFAULT_AMOUNT);
        assertEq(lendMatches[0].matchCollateralAmount, 0);
        assertTrue(lendMatches[0].status == ILendingCLOB.Status.FILLED);

        // Verify borrow match
        assertEq(borrowMatches[0].trader, borrower);
        assertEq(borrowMatches[0].matchAmount, DEFAULT_AMOUNT);
        assertEq(borrowMatches[0].matchCollateralAmount, DEFAULT_COLLATERAL);
        assertTrue(borrowMatches[0].status == ILendingCLOB.Status.FILLED);
    }

    function test_OrderMatching_PartialMatch() public {
        // Place larger lend order
        uint256 largerAmount = DEFAULT_AMOUNT * 2;
        _placeLendOrder(lender, largerAmount, DEFAULT_RATE);

        // Place smaller borrow order
        (
            ILendingCLOB.MatchedInfo[] memory lendMatches,
            ILendingCLOB.MatchedInfo[] memory borrowMatches
        ) = _placeBorrowOrder(
                borrower,
                DEFAULT_AMOUNT,
                DEFAULT_COLLATERAL,
                DEFAULT_RATE
            );

        // Verify matches
        assertEq(lendMatches.length, 1);
        assertEq(borrowMatches.length, 1);

        // Verify lend match (partially filled)
        assertEq(lendMatches[0].trader, lender);
        assertEq(lendMatches[0].matchAmount, largerAmount - DEFAULT_AMOUNT);
        assertTrue(
            lendMatches[0].status == ILendingCLOB.Status.PARTIALLY_FILLED
        );

        // Verify borrow match (fully filled)
        assertEq(borrowMatches[0].trader, borrower);
        assertEq(borrowMatches[0].matchAmount, DEFAULT_AMOUNT);
        assertEq(borrowMatches[0].matchCollateralAmount, DEFAULT_COLLATERAL);
        assertTrue(borrowMatches[0].status == ILendingCLOB.Status.FILLED);
    }
}

/// @title LendingCLOBTest_CancelOrder - Tests for order cancellation functionality
/// @notice Tests both happy and unhappy paths for cancelling orders
contract LendingCLOBTest_CancelOrder is LendingCLOBTest_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_CancelOrder_Lend() public {
        // Place lend order
        _placeLendOrder(lender, DEFAULT_AMOUNT, DEFAULT_RATE);

        // Cancel order
        vm.prank(router);
        clob.cancelOrder(lender, 0);

        // Verify order status
        ILendingCLOB.Order[] memory orders = clob.getUserOrders(lender);
        assertTrue(orders[0].status == ILendingCLOB.Status.CANCELLED);

        // Verify token refund
        assertEq(debtToken.balanceOf(lender), INITIAL_BALANCE);
        assertEq(clob.debtBalances(lender), 0);
    }

    function test_CancelOrder_Borrow() public {
        // Place borrow order
        _placeBorrowOrder(
            borrower,
            DEFAULT_AMOUNT,
            DEFAULT_COLLATERAL,
            DEFAULT_RATE
        );

        // Cancel order
        vm.prank(router);
        clob.cancelOrder(borrower, 0);

        // Verify order status
        ILendingCLOB.Order[] memory orders = clob.getUserOrders(borrower);
        assertTrue(orders[0].status == ILendingCLOB.Status.CANCELLED);

        // Verify token refund
        assertEq(collateralToken.balanceOf(borrower), INITIAL_BALANCE);
        assertEq(clob.collateralBalances(borrower), 0);
    }

    function test_CancelOrder_PartiallyFilled() public {
        // Place larger lend order
        uint256 largerAmount = DEFAULT_AMOUNT * 2;
        _placeLendOrder(lender, largerAmount, DEFAULT_RATE);

        // Place smaller borrow order
        _placeBorrowOrder(
            borrower,
            DEFAULT_AMOUNT,
            DEFAULT_COLLATERAL,
            DEFAULT_RATE
        );
        // Mock transfer
        vm.startPrank(router);
        clob.transferFrom(
            lender,
            borrower,
            DEFAULT_AMOUNT,
            ILendingCLOB.Side.LEND
        );
        vm.stopPrank();

        // Cancel partially filled lend order
        vm.prank(router);
        clob.cancelOrder(lender, 0);

        // Verify order status
        ILendingCLOB.Order[] memory orders = clob.getUserOrders(lender);
        assertTrue(orders[0].status == ILendingCLOB.Status.CANCELLED);

        // Verify token refund
        assertEq(debtToken.balanceOf(lender), INITIAL_BALANCE - DEFAULT_AMOUNT);
        assertEq(clob.debtBalances(lender), 0);
    }

    function test_CancelOrder_RevertIf_NotFound() public {
        vm.prank(router);
        vm.expectRevert(
            abi.encodeWithSelector(ILendingCLOB.OrderNotFound.selector)
        );
        clob.cancelOrder(lender, 999); // Non-existent order ID

        // Verify no changes
        assertEq(clob.getUserOrders(lender).length, 0);
    }

    function test_CancelOrder_RevertIf_InsufficientBalance() public {
        // Place orders
        _placeLendOrder(lender, DEFAULT_AMOUNT, DEFAULT_RATE);
        _placeBorrowOrder(
            borrower,
            DEFAULT_AMOUNT,
            DEFAULT_COLLATERAL,
            DEFAULT_RATE + 1
        );

        // Simulate balance depletion (through transfer)
        vm.startPrank(router);
        clob.transferFrom(
            lender,
            borrower,
            DEFAULT_AMOUNT,
            ILendingCLOB.Side.LEND
        );
        clob.transferFrom(
            borrower,
            lender,
            DEFAULT_COLLATERAL,
            ILendingCLOB.Side.BORROW
        );
        vm.stopPrank();

        // Try to cancel orders with insufficient balance
        vm.prank(router);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingCLOB.InsufficientBalance.selector,
                lender,
                debtToken,
                0,
                DEFAULT_AMOUNT
            )
        );
        clob.cancelOrder(lender, 0);

        vm.prank(router);
        vm.expectRevert(); // Order status is not OPEN
        clob.cancelOrder(borrower, 1);
    }

    function test_CancelOrder_RevertIf_Filled() public {
        // Place a lend order
        _placeLendOrder(lender, DEFAULT_AMOUNT, DEFAULT_RATE);

        // Place matching borrow order that will fill the lend order
        _placeBorrowOrder(
            borrower,
            DEFAULT_AMOUNT,
            DEFAULT_COLLATERAL,
            DEFAULT_RATE
        );

        // Try to cancel filled orders
        vm.startPrank(router);
        vm.expectRevert(
            abi.encodeWithSelector(ILendingCLOB.OrderNotFound.selector)
        );
        clob.cancelOrder(lender, 0);
        vm.expectRevert(
            abi.encodeWithSelector(ILendingCLOB.OrderNotFound.selector)
        );
        clob.cancelOrder(borrower, 1);
        vm.stopPrank();
    }
}

/// @title LendingCLOBTest_BestRate - Tests for best rate tracking functionality
/// @notice Tests both happy and unhappy paths for best rate updates
contract LendingCLOBTest_BestRate is LendingCLOBTest_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_BestRate_Initial() public view {
        assertEq(clob.getBestLendRate(), 0);
    }

    function test_BestRate_Update() public {
        // Place lend order at 5%
        _placeLendOrder(lender, DEFAULT_AMOUNT, 50e15);
        assertEq(clob.getBestLendRate(), 50e15);

        // Place better lend order at 4%
        _placeLendOrder(lender, DEFAULT_AMOUNT, 40e15);
        assertEq(clob.getBestLendRate(), 40e15);
    }

    function test_BestRate_AfterCancellation() public {
        // Place two lend orders
        _placeLendOrder(lender, DEFAULT_AMOUNT, 50e15);
        _placeLendOrder(lender, DEFAULT_AMOUNT, 40e15);

        // Cancel better order
        vm.prank(router);
        clob.cancelOrder(lender, 1);

        // Best rate should update to next best
        assertEq(clob.getBestLendRate(), 50e15);
    }
}

/// @title LendingCLOBTest_Transfer - Tests for token transfer functionality
/// @notice Tests both happy and unhappy paths for token transfers
contract LendingCLOBTest_Transfer is LendingCLOBTest_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Transfer_Debt() public {
        // Setup: place lend order to get tokens in escrow
        _placeLendOrder(lender, DEFAULT_AMOUNT, DEFAULT_RATE);

        // Transfer debt tokens
        vm.prank(router);
        clob.transferFrom(
            lender,
            borrower,
            DEFAULT_AMOUNT,
            ILendingCLOB.Side.LEND
        );

        // Verify balances
        assertEq(clob.debtBalances(lender), 0);
        assertEq(debtToken.balanceOf(borrower), DEFAULT_AMOUNT);
    }

    function test_Transfer_Collateral() public {
        // Setup: place borrow order to get tokens in escrow
        _placeBorrowOrder(
            borrower,
            DEFAULT_AMOUNT,
            DEFAULT_COLLATERAL,
            DEFAULT_RATE
        );

        // Transfer collateral tokens
        vm.prank(router);
        clob.transferFrom(
            borrower,
            lender,
            DEFAULT_COLLATERAL,
            ILendingCLOB.Side.BORROW
        );

        // Verify balances
        assertEq(clob.collateralBalances(borrower), 0);
        assertEq(collateralToken.balanceOf(lender), DEFAULT_COLLATERAL);
    }

    function test_Transfer_RevertIf_NotOwner() public {
        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                lender
            )
        );
        clob.transferFrom(
            lender,
            borrower,
            DEFAULT_AMOUNT,
            ILendingCLOB.Side.LEND
        );
    }

    function test_Transfer_RevertIf_InsufficientBalance() public {
        vm.prank(router);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingCLOB.InsufficientBalance.selector,
                lender,
                debtToken,
                0,
                DEFAULT_AMOUNT
            )
        );
        clob.transferFrom(
            lender,
            borrower,
            DEFAULT_AMOUNT,
            ILendingCLOB.Side.LEND
        );

        vm.prank(router);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingCLOB.InsufficientBalance.selector,
                borrower,
                collateralToken,
                0,
                DEFAULT_AMOUNT
            )
        );
        clob.transferFrom(
            borrower,
            lender,
            DEFAULT_AMOUNT,
            ILendingCLOB.Side.BORROW
        );
    }
}
