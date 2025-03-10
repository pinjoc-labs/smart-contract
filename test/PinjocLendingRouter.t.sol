// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {PinjocLendingRouter} from "../src/PinjocLendingRouter.sol";
import {LendingCLOBManager} from "../src/LendingCLOBManager.sol";
import {LendingPoolManager} from "../src/LendingPoolManager.sol";
import {ILendingCLOB} from "../src/interfaces/ILendingCLOB.sol";
import {LendingCLOB} from "../src/LendingCLOB.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {PinjocToken} from "../src/PinjocToken.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

contract PinjocLendingRouterTest_Base is Test {

    address public debtToken;
    address public collateralToken;
    MockOracle oracle;

    LendingCLOBManager public lendingCLOBManager;
    LendingPoolManager public lendingPoolManager;
    PinjocLendingRouter public pinjocRouter;

    address owner = makeAddr("owner");
    address lender = makeAddr("lender");
    address borrower = makeAddr("borrower");
    uint256 lenderDefaultBalance = 2000e6; // 2000USDC
    uint256 borrowerDefaultCollateral = 1e18; // 1WETH = 2500USDC

    uint256 borrowRate = 5e16; // 5% APY
    uint256 maturity = block.timestamp + 90 days;
    string maturityMonth = "MAY";
    uint256 maturityYear = 2025;

    function setUp() public {
        debtToken = address(new MockToken("Mock USDC", "MUSDC", 6));
        collateralToken = address(new MockToken("Mock ETH", "METH", 18));

        oracle = new MockOracle(debtToken, collateralToken);
        oracle.setPrice(2500e6); // 1 WETH = 2500USDC

        vm.startPrank(owner);
        lendingCLOBManager = new LendingCLOBManager(owner);
        lendingPoolManager = new LendingPoolManager(owner);
        lendingPoolManager.setOracle(address(oracle), address(debtToken), address(collateralToken));

        pinjocRouter = new PinjocLendingRouter(address(lendingCLOBManager), address(lendingPoolManager));
        lendingCLOBManager.transferOwnership(address(pinjocRouter));
        lendingPoolManager.setRouter(address(pinjocRouter));
        vm.stopPrank();

        deal(debtToken, lender, lenderDefaultBalance);
        deal(collateralToken, borrower, borrowerDefaultCollateral);
    }

    function setUp_LendOrder(uint256 lendingAmount) public {
        vm.startPrank(lender);
        IERC20(debtToken).approve(address(pinjocRouter), lendingAmount);
        pinjocRouter.placeOrder(
            debtToken,
            collateralToken,
            lendingAmount,
            0,
            borrowRate,
            maturity,
            maturityMonth,
            maturityYear,
            ILendingCLOB.Side.LEND
        );
        vm.stopPrank();
    }

    function setUp_BorrowOrder(uint256 borrowAmount, uint256 collateralAmount) public {
        vm.startPrank(borrower);
        IERC20(collateralToken).approve(address(pinjocRouter), collateralAmount);
        pinjocRouter.placeOrder(
            debtToken,
            collateralToken,
            borrowAmount,
            collateralAmount,
            borrowRate,
            maturity,
            maturityMonth,
            maturityYear,
            ILendingCLOB.Side.BORROW
        );
        vm.stopPrank();
    }
}

contract PinjocLendingRouterTest_PlaceOrderFlow is PinjocLendingRouterTest_Base {

    function test_LendOrder() public {
        uint256 lendAmount = 1000e6; // 1000USDC
        setUp_LendOrder(lendAmount);

        address orderBook = lendingCLOBManager.getLendingCLOB(debtToken, collateralToken, maturityMonth, maturityYear);
        (, address trader, uint256 amount, , , , ILendingCLOB.Status status) = LendingCLOB(orderBook).orderQueue(5e16, ILendingCLOB.Side.LEND, 0);
        assertEq(trader, lender);
        assertEq(amount, lendAmount);
        assertEq(uint256(status), uint256(ILendingCLOB.Status.OPEN));

        assertEq(IERC20(debtToken).balanceOf(lender), lenderDefaultBalance - lendAmount);
    }

    function test_BorrowOrder() public {
        uint256 borrowAmount = 1000e6; // 1000USDC
        uint256 collateralAmount = 1e18; // 1WETH = 2500USDC
        setUp_BorrowOrder(borrowAmount, collateralAmount);

        address orderBook = lendingCLOBManager.getLendingCLOB(debtToken, collateralToken, maturityMonth, maturityYear); 
        (, address trader, uint256 amount, uint256 collateral, , , ILendingCLOB.Status status) = LendingCLOB(orderBook).orderQueue(5e16, ILendingCLOB.Side.BORROW, 0);
        assertEq(trader, borrower);
        assertEq(amount, borrowAmount);
        assertEq(collateral, collateralAmount);
        assertEq(uint256(status), uint256(ILendingCLOB.Status.OPEN));

        assertEq(IERC20(collateralToken).balanceOf(borrower), borrowerDefaultCollateral - collateralAmount);
    }

    function test_PlaceOrder_BothMatchedFully() public {
        uint256 borrowAmount = 1000e6; // 1000USDC
        uint256 collateralAmount = 1e18; // 1WETH = 2500USDC

        setUp_BorrowOrder(borrowAmount, collateralAmount);
        setUp_LendOrder(borrowAmount);
        
        // Check borrower balance
        assertEq(IERC20(debtToken).balanceOf(borrower), borrowAmount);
        assertEq(IERC20(collateralToken).balanceOf(borrower), borrowerDefaultCollateral - collateralAmount);

        // Check borrower data on lending pool
        LendingPool lendingPool = LendingPool(lendingPoolManager.getLendingPool(debtToken, collateralToken, maturityMonth, maturityYear));
        (
            address pinjocToken,
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares,
            ,
        ) = lendingPool.lendingPoolStates(borrowRate);

        assertEq(totalBorrowAssets, borrowAmount);
        assertEq(totalBorrowShares, borrowAmount);
        assertEq(lendingPool.getUserBorrowShares(borrowRate, borrower), borrowAmount);
        assertEq(lendingPool.getUserCollateral(borrowRate, borrower), collateralAmount);

        // Check lender balance
        assertEq(IERC20(pinjocToken).balanceOf(lender), borrowAmount);
        assertEq(IERC20(debtToken).balanceOf(lender), lenderDefaultBalance - borrowAmount);

        // Check lender data on lending pool
        assertEq(totalSupplyAssets, borrowAmount);
        assertEq(totalSupplyShares, borrowAmount);
    }

    function test_PlaceOrder_OnlyLendMatchedFully() public {
        uint256 borrowAmount = 2000e6; // 2000USDC
        uint256 collateralAmount = 1e18; // 1WETH = 2500USDC
        uint256 supplyAmount = 1000e6; // 1000USDC

        setUp_BorrowOrder(borrowAmount, collateralAmount);
        setUp_LendOrder(supplyAmount);
        
        // Check borrower balance
        assertEq(IERC20(debtToken).balanceOf(borrower), borrowAmount - supplyAmount);
        assertEq(IERC20(collateralToken).balanceOf(borrower), borrowerDefaultCollateral - collateralAmount);

        // Check borrower data on lending pool
        LendingPool lendingPool = LendingPool(lendingPoolManager.getLendingPool(debtToken, collateralToken, maturityMonth, maturityYear));
        (
            address pinjocToken,
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares,
            ,
        ) = lendingPool.lendingPoolStates(borrowRate);

        assertEq(totalBorrowAssets, supplyAmount);
        assertEq(totalBorrowShares, supplyAmount);
        assertEq(lendingPool.getUserBorrowShares(borrowRate, borrower), supplyAmount);
        assertEq(lendingPool.getUserCollateral(borrowRate, borrower), collateralAmount * supplyAmount / borrowAmount);

        // Check borrower order queue
        address orderBook = lendingCLOBManager.getLendingCLOB(debtToken, collateralToken, maturityMonth, maturityYear);
        (, address trader, uint256 amount, uint256 collateral, , , ILendingCLOB.Status status) = LendingCLOB(orderBook).orderQueue(5e16, ILendingCLOB.Side.BORROW, 0);
        assertEq(trader, borrower);
        assertEq(amount, borrowAmount - supplyAmount);
        assertEq(collateral, collateralAmount * supplyAmount / borrowAmount);
        assertEq(uint256(status), uint256(ILendingCLOB.Status.PARTIALLY_FILLED));

        // Check lender balance
        assertEq(IERC20(pinjocToken).balanceOf(lender), supplyAmount);
        assertEq(IERC20(debtToken).balanceOf(lender), lenderDefaultBalance - supplyAmount);

        // Check lender data on lending pool
        assertEq(totalSupplyAssets, supplyAmount);
        assertEq(totalSupplyShares, supplyAmount);
    }

    function test_PlaceOrder_OnlyBorrowMatchedFully() public {
        uint256 borrowAmount = 1000e6; // 1000USDC
        uint256 collateralAmount = 1e18; // 1WETH = 2500USDC
        uint256 supplyAmount = 2000e6; // 2000USDC

        setUp_BorrowOrder(borrowAmount, collateralAmount);
        setUp_LendOrder(supplyAmount);
        
        // Check borrower balance
        assertEq(IERC20(debtToken).balanceOf(borrower), borrowAmount);
        assertEq(IERC20(collateralToken).balanceOf(borrower), borrowerDefaultCollateral - collateralAmount);

        // Check borrower data on lending pool
        LendingPool lendingPool = LendingPool(lendingPoolManager.getLendingPool(debtToken, collateralToken, maturityMonth, maturityYear));
        (
            address pinjocToken,
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares,
            ,
        ) = lendingPool.lendingPoolStates(borrowRate);
        assertEq(totalBorrowAssets, borrowAmount);
        assertEq(totalBorrowShares, borrowAmount);
        assertEq(lendingPool.getUserBorrowShares(borrowRate, borrower), borrowAmount);
        assertEq(lendingPool.getUserCollateral(borrowRate, borrower), collateralAmount);

        // Check lender order queue
        address orderBook = lendingCLOBManager.getLendingCLOB(debtToken, collateralToken, maturityMonth, maturityYear);
        (, address trader, uint256 amount, uint256 collateral, , , ILendingCLOB.Status status) = LendingCLOB(orderBook).orderQueue(5e16, ILendingCLOB.Side.LEND, 0);
        assertEq(trader, lender);
        assertEq(amount, borrowAmount);
        assertEq(collateral, 0);
        assertEq(uint256(status), uint256(ILendingCLOB.Status.PARTIALLY_FILLED));

        // Check lender balance
        assertEq(IERC20(pinjocToken).balanceOf(lender), borrowAmount);
        assertEq(IERC20(debtToken).balanceOf(lender), 0);

        // Check lender data on lending pool
        assertEq(totalSupplyAssets, borrowAmount);
        assertEq(totalSupplyShares, borrowAmount);
    }
}

contract PinjocLendingRouterTest_CancelOrder is PinjocLendingRouterTest_Base {
    
    function test_CancelLendOrder() public {
        uint256 lendAmount = 1000e6; // 1000USDC

        setUp_LendOrder(lendAmount);

        // Check lender order queue
        address orderBook = lendingCLOBManager.getLendingCLOB(debtToken, collateralToken, maturityMonth, maturityYear);
        (, address trader, uint256 amount, uint256 collateral, , , ILendingCLOB.Status status) = LendingCLOB(orderBook).orderQueue(5e16, ILendingCLOB.Side.LEND, 0);
        assertEq(trader, lender);
        assertEq(uint256(status), uint256(ILendingCLOB.Status.OPEN));

        // Check lender orders before cancelling
        LendingCLOB.Order[] memory userOrders = LendingCLOB(orderBook).getUserOrders(lender);
        assertEq(userOrders.length, 1);
        assertEq(userOrders[0].trader, lender);
        assertEq(uint256(userOrders[0].status), uint256(ILendingCLOB.Status.OPEN));
        assertEq(IERC20(debtToken).balanceOf(lender), lenderDefaultBalance - lendAmount);
        
        vm.startPrank(lender);
        pinjocRouter.cancelOrder(debtToken, collateralToken, "MAY", 2025, 0);
        vm.stopPrank();
        
        // Check lender orders after cancelling
        userOrders = LendingCLOB(orderBook).getUserOrders(lender);
        assertEq(userOrders.length, 1);
        assertEq(userOrders[0].trader, lender);
        assertEq(uint256(userOrders[0].status), uint256(ILendingCLOB.Status.CANCELLED));
        assertEq(IERC20(debtToken).balanceOf(lender), lenderDefaultBalance);
    }

    function test_CancelBorrowOrder() public {
        uint256 borrowAmount = 1000e6; // 1000USDC
        uint256 collateralAmount = 1e18; // 1WETH = 2500USDC

        setUp_BorrowOrder(borrowAmount, collateralAmount);

        // Check borrower order queue
        address orderBook = lendingCLOBManager.getLendingCLOB(debtToken, collateralToken, maturityMonth, maturityYear);
        (, address trader, uint256 amount, uint256 collateral, , , ILendingCLOB.Status status) = LendingCLOB(orderBook).orderQueue(5e16, ILendingCLOB.Side.BORROW, 0);
        assertEq(trader, borrower);
        assertEq(uint256(status), uint256(ILendingCLOB.Status.OPEN));

        // Check borrower orders before cancelling
        LendingCLOB.Order[] memory userOrders = LendingCLOB(orderBook).getUserOrders(borrower);
        assertEq(userOrders.length, 1);
        assertEq(userOrders[0].trader, borrower);
        assertEq(uint256(userOrders[0].status), uint256(ILendingCLOB.Status.OPEN));
        assertEq(IERC20(collateralToken).balanceOf(borrower), borrowerDefaultCollateral - collateralAmount);
        
        vm.startPrank(borrower);
        pinjocRouter.cancelOrder(debtToken, collateralToken, "MAY", 2025, 0);
        vm.stopPrank();
        
        // Check borrower orders after cancelling
        userOrders = LendingCLOB(orderBook).getUserOrders(borrower);
        assertEq(userOrders.length, 1);
        assertEq(userOrders[0].trader, borrower);
        assertEq(uint256(userOrders[0].status), uint256(ILendingCLOB.Status.CANCELLED));
        assertEq(IERC20(collateralToken).balanceOf(borrower), borrowerDefaultCollateral);
    }
}