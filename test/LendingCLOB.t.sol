// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import {Test} from "forge-std/Test.sol";
import {LendingCLOB} from "../src/LendingCLOB.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

/// @title LendingCLOBTest_Base - Base contract for LendingCLOB tests
/// @notice Contains common setup and helper functions for testing LendingCLOB functionality
contract LendingCLOBTest_Base is Test {
    // Constants for testing
    uint256 internal constant INITIAL_BALANCE = 1000e18;
    uint256 internal constant DEFAULT_AMOUNT = 100e18;
    uint256 internal constant DEFAULT_COLLATERAL = 50e18;
    uint256 internal constant DEFAULT_PRICE = 50e15; // 5% interest rate

    // Test contracts
    LendingCLOB internal book;
    MockToken internal quoteToken;
    MockToken internal baseToken;

    // Test accounts
    address internal owner;
    address internal lender;
    address internal borrower;

    function setUp() public virtual {
        // Deploy mock tokens
        quoteToken = new MockToken("Quote Token", "QUOTE", 18);
        baseToken = new MockToken("Base Token", "BASE", 18);

        // Setup test accounts
        owner = makeAddr("owner");
        lender = makeAddr("lender");
        borrower = makeAddr("borrower");

        // Deploy LendingCLOB
        vm.prank(owner);
        book = new LendingCLOB(owner, address(quoteToken), address(baseToken));

        // Setup initial balances
        _setupBalances();
    }

    /// @notice Sets up initial token balances and approvals for test accounts
    function _setupBalances() internal {
        // Mint tokens to test accounts
        quoteToken.mint(lender, INITIAL_BALANCE);
        baseToken.mint(borrower, INITIAL_BALANCE);

        // Setup approvals
        vm.startPrank(lender);
        quoteToken.approve(address(book), type(uint256).max);
        baseToken.approve(address(book), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower);
        quoteToken.approve(address(book), type(uint256).max);
        baseToken.approve(address(book), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Helper to place a buy (lend) order
    function _placeBuyOrder(
        address trader,
        uint256 amount,
        uint256 price
    ) internal returns (LendingCLOB.MatchedInfo[] memory buyMatches, LendingCLOB.MatchedInfo[] memory sellMatches) {
        vm.prank(owner);
        return book.placeOrder(trader, amount, 0, price, LendingCLOB.Side.LEND);
    }

    /// @notice Helper to place a sell (borrow) order
    function _placeSellOrder(
        address trader,
        uint256 amount,
        uint256 collateralAmount,
        uint256 price
    ) internal returns (LendingCLOB.MatchedInfo[] memory buyMatches, LendingCLOB.MatchedInfo[] memory sellMatches) {
        vm.prank(owner);
        return book.placeOrder(trader, amount, collateralAmount, price, LendingCLOB.Side.BORROW);
    }

    /// @notice Helper to verify order details
    function _verifyOrder(
        LendingCLOB.Order memory order,
        uint256 expectedId,
        address expectedTrader,
        uint256 expectedAmount,
        uint256 expectedCollateral,
        uint256 expectedPrice,
        LendingCLOB.Side expectedSide,
        LendingCLOB.Status expectedStatus
    ) internal pure {
        assertEq(order.id, expectedId);
        assertEq(order.trader, expectedTrader);
        assertEq(order.amount, expectedAmount);
        assertEq(order.collateralAmount, expectedCollateral);
        assertEq(order.price, expectedPrice);
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

    function test_PlaceOrder_Buy() public {
        _placeBuyOrder(lender, DEFAULT_AMOUNT, DEFAULT_PRICE);

        // Verify order placement
        LendingCLOB.Order[] memory orders = book.getUserOrders(lender);
        assertEq(orders.length, 1);
        _verifyOrder(
            orders[0],
            0, // first order ID
            lender,
            DEFAULT_AMOUNT,
            0, // no collateral for buy orders
            DEFAULT_PRICE,
            LendingCLOB.Side.LEND,
            LendingCLOB.Status.OPEN
        );

        // Verify token transfer
        assertEq(quoteToken.balanceOf(address(book)), DEFAULT_AMOUNT);
        assertEq(book.quoteBalances(lender), DEFAULT_AMOUNT);
    }

    function test_PlaceOrder_Sell() public {
        _placeSellOrder(borrower, DEFAULT_AMOUNT, DEFAULT_COLLATERAL, DEFAULT_PRICE);

        // Verify order placement
        LendingCLOB.Order[] memory orders = book.getUserOrders(borrower);
        assertEq(orders.length, 1);
        _verifyOrder(
            orders[0],
            0, // first order ID
            borrower,
            DEFAULT_AMOUNT,
            DEFAULT_COLLATERAL,
            DEFAULT_PRICE,
            LendingCLOB.Side.BORROW,
            LendingCLOB.Status.OPEN
        );

        // Verify token transfer
        assertEq(baseToken.balanceOf(address(book)), DEFAULT_COLLATERAL);
        assertEq(book.baseBalances(borrower), DEFAULT_COLLATERAL);
    }

    function test_PlaceOrder_RevertIf_InsufficientBalance() public {
        // Attempt to place order with more tokens than balance
        uint256 tooMuchAmount = INITIAL_BALANCE + 1;
        
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, lender, INITIAL_BALANCE, tooMuchAmount));
        _placeBuyOrder(lender, tooMuchAmount, DEFAULT_PRICE);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, borrower, INITIAL_BALANCE, tooMuchAmount));
        _placeSellOrder(borrower, DEFAULT_AMOUNT, tooMuchAmount, DEFAULT_PRICE);
    }

    function test_PlaceOrder_RevertIf_NotOwner() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, lender));
        book.placeOrder(lender, DEFAULT_AMOUNT, 0, DEFAULT_PRICE, LendingCLOB.Side.LEND);
        
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, borrower));
        book.placeOrder(borrower, DEFAULT_AMOUNT, DEFAULT_COLLATERAL, DEFAULT_PRICE, LendingCLOB.Side.BORROW);
    }
}

/// @title LendingCLOBTest_OrderMatching - Tests for order matching functionality
/// @notice Tests both happy and unhappy paths for order matching
contract LendingCLOBTest_OrderMatching is LendingCLOBTest_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_OrderMatching_ExactMatch() public {
        // Place buy order
        _placeBuyOrder(lender, DEFAULT_AMOUNT, DEFAULT_PRICE);

        // Place matching sell order
        (LendingCLOB.MatchedInfo[] memory buyMatches, LendingCLOB.MatchedInfo[] memory sellMatches) = 
            _placeSellOrder(borrower, DEFAULT_AMOUNT, DEFAULT_COLLATERAL, DEFAULT_PRICE);

        // Verify matches
        assertEq(buyMatches.length, 1);
        assertEq(sellMatches.length, 1);
        
        // Verify buy match
        assertEq(buyMatches[0].trader, lender);
        assertEq(buyMatches[0].amount, DEFAULT_AMOUNT);
        assertTrue(buyMatches[0].status == LendingCLOB.Status.FILLED);
        
        // Verify sell match
        assertEq(sellMatches[0].trader, borrower);
        assertEq(sellMatches[0].amount, DEFAULT_AMOUNT);
        assertTrue(sellMatches[0].status == LendingCLOB.Status.FILLED);
    }

    function test_OrderMatching_PartialMatch() public {
        // Place larger buy order
        uint256 largerAmount = DEFAULT_AMOUNT * 2;
        _placeBuyOrder(lender, largerAmount, DEFAULT_PRICE);

        // Place smaller sell order
        (LendingCLOB.MatchedInfo[] memory buyMatches, LendingCLOB.MatchedInfo[] memory sellMatches) = 
            _placeSellOrder(borrower, DEFAULT_AMOUNT, DEFAULT_COLLATERAL, DEFAULT_PRICE);

        // Verify matches
        assertEq(buyMatches.length, 1);
        assertEq(sellMatches.length, 1);
        
        // Verify buy match (partially filled)
        assertEq(buyMatches[0].trader, lender);
        assertEq(buyMatches[0].amount, largerAmount);
        assertTrue(buyMatches[0].status == LendingCLOB.Status.PARTIALLY_FILLED);
        
        // Verify sell match (fully filled)
        assertEq(sellMatches[0].trader, borrower);
        assertEq(sellMatches[0].amount, DEFAULT_AMOUNT);
        assertTrue(sellMatches[0].status == LendingCLOB.Status.FILLED);
    }
}

/// @title LendingCLOBTest_CancelOrder - Tests for order cancellation functionality
/// @notice Tests both happy and unhappy paths for cancelling orders
contract LendingCLOBTest_CancelOrder is LendingCLOBTest_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_CancelOrder_Buy() public {
        // Place buy order
        _placeBuyOrder(lender, DEFAULT_AMOUNT, DEFAULT_PRICE);

        // Cancel order
        vm.prank(owner);
        book.cancelOrder(lender, 0);

        // Verify order status
        LendingCLOB.Order[] memory orders = book.getUserOrders(lender);
        assertTrue(orders[0].status == LendingCLOB.Status.CANCELLED);

        // Verify token refund
        assertEq(quoteToken.balanceOf(lender), INITIAL_BALANCE);
        assertEq(book.quoteBalances(lender), 0);
    }

    function test_CancelOrder_Sell() public {
        // Place sell order
        _placeSellOrder(borrower, DEFAULT_AMOUNT, DEFAULT_COLLATERAL, DEFAULT_PRICE);

        // Cancel order
        vm.prank(owner);
        book.cancelOrder(borrower, 0);

        // Verify order status
        LendingCLOB.Order[] memory orders = book.getUserOrders(borrower);
        assertTrue(orders[0].status == LendingCLOB.Status.CANCELLED);

        // Verify token refund
        assertEq(baseToken.balanceOf(borrower), INITIAL_BALANCE);
        assertEq(book.baseBalances(borrower), 0);
    }

    function test_CancelOrder_RevertIf_NotFound() public {
        vm.prank(owner);
        book.cancelOrder(lender, 999); // Non-existent order ID
        
        // Verify no changes
        assertEq(book.getUserOrders(lender).length, 0);
    }

    function test_CancelOrder_RevertIf_NotOwner() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, lender));
        book.cancelOrder(lender, 0);
    }
}

/// @title LendingCLOBTest_BestPrice - Tests for best price tracking functionality
/// @notice Tests both happy and unhappy paths for best price updates
contract LendingCLOBTest_BestPrice is LendingCLOBTest_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_BestPrice_Initial() public view {
        assertEq(book.getBestBuyPrice(), 100e16);
    }

    function test_BestPrice_Update() public {
        // Place buy order at 5%
        _placeBuyOrder(lender, DEFAULT_AMOUNT, 50e15);
        assertEq(book.getBestBuyPrice(), 50e15);

        // Place better buy order at 4%
        _placeBuyOrder(lender, DEFAULT_AMOUNT, 40e15);
        assertEq(book.getBestBuyPrice(), 40e15);
    }

    function test_BestPrice_AfterCancellation() public {
        // Place two buy orders
        _placeBuyOrder(lender, DEFAULT_AMOUNT, 50e15);
        _placeBuyOrder(lender, DEFAULT_AMOUNT, 40e15);
        
        // Cancel better order
        vm.prank(owner);
        book.cancelOrder(lender, 1);

        // Best price should update to next best
        assertEq(book.getBestBuyPrice(), 50e15);
    }
}

/// @title LendingCLOBTest_Transfer - Tests for token transfer functionality
/// @notice Tests both happy and unhappy paths for token transfers
contract LendingCLOBTest_Transfer is LendingCLOBTest_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Transfer_Quote() public {
        // Setup: place buy order to get tokens in escrow
        _placeBuyOrder(lender, DEFAULT_AMOUNT, DEFAULT_PRICE);

        // Transfer quote tokens
        vm.prank(owner);
        book.transferFrom(lender, borrower, DEFAULT_AMOUNT, LendingCLOB.Side.LEND);

        // Verify balances
        assertEq(book.quoteBalances(lender), 0);
        assertEq(quoteToken.balanceOf(borrower), DEFAULT_AMOUNT);
    }

    function test_Transfer_Base() public {
        // Setup: place sell order to get tokens in escrow
        _placeSellOrder(borrower, DEFAULT_AMOUNT, DEFAULT_COLLATERAL, DEFAULT_PRICE);

        // Transfer base tokens
        vm.prank(owner);
        book.transferFrom(borrower, lender, DEFAULT_COLLATERAL, LendingCLOB.Side.BORROW);

        // Verify balances
        assertEq(book.baseBalances(borrower), 0);
        assertEq(baseToken.balanceOf(lender), DEFAULT_COLLATERAL);
    }

    function test_Transfer_RevertIf_NotOwner() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, lender));
        book.transferFrom(lender, borrower, DEFAULT_AMOUNT, LendingCLOB.Side.LEND);
    }

    function test_Transfer_RevertIf_InsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert("Not enough quote escrow");
        book.transferFrom(lender, borrower, DEFAULT_AMOUNT, LendingCLOB.Side.LEND);

        vm.prank(owner);
        vm.expectRevert("Not enough base escrow");
        book.transferFrom(borrower, lender, DEFAULT_AMOUNT, LendingCLOB.Side.BORROW);
    }
}
