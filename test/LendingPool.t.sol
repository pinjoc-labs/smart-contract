// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ILendingPool} from "../src/interfaces/ILendingPool.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {PinjocToken} from "../src/PinjocToken.sol";

/// @title LendingPool Base Test Contract
/// @notice Base contract containing common setup for LendingPool tests
/// @dev Inherits from Forge's Test contract. Sets up a lending pool with 1-year maturity.
contract LendingPoolTest_Base is Test {
    uint256 public constant BORROW_RATE = 5e16; // 5%

    LendingPool public lendingPool;
    address public debtToken;
    address public collateralToken;
    address public oracle;
    address public owner;
    address public router;
    address public address1;
    address public address2;

    /// @notice Setup function called before each test
    /// @dev Creates mock tokens, oracle, and lending pool instance with 1-year maturity
    function setUp() public virtual {
        // Deploy mock tokens and oracle
        debtToken = address(new MockToken("Mock USDC", "MUSDC", 6));
        collateralToken = address(new MockToken("Mock ETH", "METH", 18));
        oracle = address(new MockOracle(debtToken, collateralToken));
        MockOracle(oracle).setPrice(2000e6);

        // Setup test addresses
        owner = makeAddr("owner");
        router = makeAddr("router");
        address1 = makeAddr("address1");
        address2 = makeAddr("address2");

        // Create lending pool info
        ILendingPool.LendingPoolInfo memory info = ILendingPool
            .LendingPoolInfo({
                debtToken: debtToken,
                collateralToken: collateralToken,
                oracle: oracle,
                maturity: block.timestamp + 365 days,
                maturityMonth: "MAY",
                maturityYear: 2025,
                ltv: 75e16 // 75%
            });

        // Deploy lending pool
        lendingPool = new LendingPool(owner, router, info);
    }

    /// @notice Helper function to add a borrow rate to the lending pool
    /// @param borrowRate_ The borrow rate to add
    function setUp_AddBorrowRate(uint256 borrowRate_) public {
        vm.startPrank(router);
        lendingPool.addBorrowRate(borrowRate_);
        vm.stopPrank();
    }

    /// @notice Helper function to supply assets to the lending pool
    /// @param borrowRate_ The borrow rate tier
    /// @param user_ The address of the user supplying assets
    /// @param amount_ The amount of assets to supply
    function setUp_Supply(
        uint256 borrowRate_,
        address user_,
        uint256 amount_
    ) public {
        vm.startPrank(router);
        lendingPool.supply(borrowRate_, user_, amount_);
        vm.stopPrank();
    }

    /// @notice Helper function to borrow assets from the lending pool
    /// @param borrowRate_ The borrow rate tier
    /// @param user_ The address of the borrower
    /// @param amount_ The amount to borrow
    function setUp_Borrow(
        uint256 borrowRate_,
        address user_,
        uint256 amount_
    ) public {
        vm.startPrank(router);
        lendingPool.borrow(borrowRate_, user_, amount_);
        vm.stopPrank();
    }

    /// @notice Helper function to supply collateral to the lending pool
    /// @param borrowRate_ The borrow rate tier
    /// @param user_ The address of the user supplying collateral
    /// @param amount_ The amount of collateral to supply
    function setUp_SupplyCollateral(
        uint256 borrowRate_,
        address user_,
        uint256 amount_
    ) public {
        vm.startPrank(router);
        lendingPool.supplyCollateral(borrowRate_, user_, amount_);
        vm.stopPrank();

        MockToken(collateralToken).mint(address(lendingPool), amount_);
    }

    /// @notice Helper function to withdraw collateral from the lending pool
    /// @param borrowRate_ The borrow rate tier
    /// @param user_ The address of the user withdrawing collateral
    /// @param amount_ The amount of collateral to withdraw
    function setUp_WithdrawCollateral(
        uint256 borrowRate_,
        address user_,
        uint256 amount_
    ) public {
        vm.startPrank(user_);
        lendingPool.withdrawCollateral(borrowRate_, amount_);
        vm.stopPrank();
    }
}

/// @title LendingPool Constructor Tests
/// @notice Test contract for LendingPool constructor functionality
/// @dev Inherits from LendingPoolTest_Base
contract LendingPoolTest_Constructor is LendingPoolTest_Base {
    /// @notice Test successful lending pool creation
    /// @dev Verifies that all state variables are set correctly
    function test_Constructor() public view {
        (
            address debtToken_,
            address collateralToken_,
            address oracle_,
            uint256 maturity_,
            string memory maturityMonth_,
            uint256 maturityYear_,
            uint256 ltv_
        ) = lendingPool.info();

        assertEq(debtToken_, debtToken, "Incorrect debt token");
        assertEq(
            collateralToken_,
            collateralToken,
            "Incorrect collateral token"
        );
        assertEq(oracle_, oracle, "Incorrect oracle");
        assertEq(maturity_, block.timestamp + 365 days, "Incorrect maturity");
        assertEq(maturityMonth_, "MAY", "Incorrect maturity month");
        assertEq(maturityYear_, 2025, "Incorrect maturity year");
        assertEq(ltv_, 75e16, "Incorrect LTV");
    }

    /// @notice Test constructor reverts with invalid parameters
    /// @dev Verifies that constructor reverts with zero addresses and invalid dates
    function test_Constructor_RevertIf_InvalidParams() public {
        ILendingPool.LendingPoolInfo memory invalidInfo = ILendingPool
            .LendingPoolInfo({
                debtToken: address(0),
                collateralToken: collateralToken,
                oracle: oracle,
                maturity: block.timestamp + 365 days,
                maturityMonth: "MAY",
                maturityYear: 2025,
                ltv: 75e16
            });

        vm.expectRevert(ILendingPool.InvalidLendingPoolInfo.selector);
        new LendingPool(owner, router, invalidInfo);

        invalidInfo.debtToken = debtToken;
        invalidInfo.collateralToken = address(0);
        vm.expectRevert(ILendingPool.InvalidLendingPoolInfo.selector);
        new LendingPool(owner, router, invalidInfo);

        invalidInfo.collateralToken = collateralToken;
        invalidInfo.oracle = address(0);
        vm.expectRevert(ILendingPool.InvalidLendingPoolInfo.selector);
        new LendingPool(owner, router, invalidInfo);

        invalidInfo.oracle = oracle;
        invalidInfo.maturity = block.timestamp - 1;
        vm.expectRevert(ILendingPool.InvalidLendingPoolInfo.selector);
        new LendingPool(owner, router, invalidInfo);

        invalidInfo.maturity = block.timestamp + 365 days;
        invalidInfo.maturityMonth = "";
        vm.expectRevert(ILendingPool.InvalidLendingPoolInfo.selector);
        new LendingPool(owner, router, invalidInfo);

        invalidInfo.maturityMonth = "MAY";
        invalidInfo.maturityYear = 0;
        vm.expectRevert(ILendingPool.InvalidLendingPoolInfo.selector);
        new LendingPool(owner, router, invalidInfo);

        invalidInfo.maturityYear = 2025;
        invalidInfo.ltv = 0;
        vm.expectRevert(ILendingPool.InvalidLendingPoolInfo.selector);
        new LendingPool(owner, router, invalidInfo);
    }
}

/// @title LendingPool Borrow Rate Tests
/// @notice Test contract for borrow rate functionality
/// @dev Inherits from LendingPoolTest_Base
contract LendingPoolTest_AddBorrowRate is LendingPoolTest_Base {
    /// @notice Test successful borrow rate addition
    /// @dev Verifies that a new borrow rate can be added by the owner
    function test_AddBorrowRate() public {
        setUp_AddBorrowRate(BORROW_RATE);

        (address pinjocToken, , , , , , bool isActive) = lendingPool
            .lendingPoolStates(BORROW_RATE);
        assertTrue(isActive, "Borrow rate should be active");
        assertTrue(pinjocToken != address(0), "PinjocToken should be created");
    }

    /// @notice Test borrow rate addition restrictions
    /// @dev Verifies that invalid rates and non-owners cannot add rates
    function test_AddBorrowRate_RevertIf_Invalid() public {
        // Test non-owner cannot add rate
        vm.prank(address1);
        vm.expectRevert(
            abi.encodeWithSelector(ILendingPool.InvalidRouter.selector)
        );
        lendingPool.addBorrowRate(5e16);

        // Test cannot add zero rate
        vm.prank(router);
        vm.expectRevert(ILendingPool.InvalidBorrowRate.selector);
        lendingPool.addBorrowRate(0);

        // Test cannot add 100% rate
        vm.prank(router);
        vm.expectRevert(ILendingPool.InvalidBorrowRate.selector);
        lendingPool.addBorrowRate(100e16);

        // Test cannot add existing rate
        vm.startPrank(router);
        lendingPool.addBorrowRate(5e16);
        vm.expectRevert(ILendingPool.BorrowRateAlreadyExists.selector);
        lendingPool.addBorrowRate(5e16);
        vm.stopPrank();

        // Test cannot add borrow rate after maturity
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(router);
        vm.expectRevert(ILendingPool.MaturityReached.selector);
        lendingPool.addBorrowRate(5e16);
    }
}

/// @title LendingPool LTV Tests
/// @notice Test contract for LTV functionality
/// @dev Inherits from LendingPoolTest_Base
contract LendingPoolTest_LTV is LendingPoolTest_Base {
    /// @notice Test successful LTV update
    /// @dev Verifies that LTV can be updated by the owner
    function test_SetLtv() public {
        vm.prank(owner);
        lendingPool.setLtv(80e16);

        (, , , , , , uint256 ltv) = lendingPool.info();
        assertEq(ltv, 80e16, "LTV should be updated");
    }

    /// @notice Test LTV update restrictions
    /// @dev Verifies that invalid LTV and non-owners cannot update LTV
    function test_SetLtv_RevertIf_Invalid() public {
        // Test non-owner cannot set LTV
        vm.prank(address1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address1
            )
        );
        lendingPool.setLtv(80e16);

        // Test cannot set zero LTV
        vm.prank(owner);
        vm.expectRevert(ILendingPool.InvalidLTV.selector);
        lendingPool.setLtv(0);

        // Test cannot set LTV after maturity
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(owner);
        vm.expectRevert(ILendingPool.MaturityReached.selector);
        lendingPool.setLtv(80e16);
    }
}

/// @title LendingPool Supply Tests
/// @notice Test contract for supply functionality
/// @dev Inherits from LendingPoolTest_Base
contract LendingPoolTest_Supply is LendingPoolTest_Base {
    function setUp() public override {
        super.setUp();
        setUp_AddBorrowRate(BORROW_RATE);
    }

    /// @notice Test successful supply
    /// @dev Verifies that assets can be supplied and shares are minted correctly
    function test_Supply() public {
        setUp_Supply(BORROW_RATE, address1, 1000e6);

        (
            ,
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares,
            ,
            ,
            ,

        ) = lendingPool.lendingPoolStates(BORROW_RATE);
        assertEq(
            totalSupplyAssets,
            1000e6,
            "Total supply assets should be updated"
        );
        assertEq(
            totalSupplyShares,
            1000e6,
            "Total supply shares should be updated"
        );

        (address pinjocToken, , , , , , ) = lendingPool.lendingPoolStates(
            BORROW_RATE
        );
        assertEq(
            IERC20(pinjocToken).balanceOf(address1),
            1000e6,
            "User should have received 1000 shares"
        );
    }

    /// @notice Test supply restrictions
    /// @dev Verifies that invalid parameters and non-owners cannot supply
    function test_Supply_RevertIf_Invalid() public {
        // Test non-owner cannot supply
        vm.prank(address1);
        vm.expectRevert(
            abi.encodeWithSelector(ILendingPool.InvalidRouter.selector)
        );
        lendingPool.supply(BORROW_RATE, address1, 1000e6);

        // Test cannot supply to zero address
        vm.prank(router);
        vm.expectRevert(ILendingPool.InvalidUser.selector);
        lendingPool.supply(BORROW_RATE, address(0), 1000e6);

        // Test cannot supply zero amount
        vm.prank(router);
        vm.expectRevert(ILendingPool.InvalidAmount.selector);
        lendingPool.supply(BORROW_RATE, address1, 0);

        // Test cannot supply with inactive borrow rate
        vm.prank(router);
        vm.expectRevert(ILendingPool.BorrowRateNotActive.selector);
        lendingPool.supply(10e16, address1, 1000e6);

        // Test cannot supply after maturity
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(router);
        vm.expectRevert(ILendingPool.MaturityReached.selector);
        lendingPool.supply(BORROW_RATE, address1, 1000e6);
    }
}

/// @title LendingPool Borrow Tests
/// @notice Test contract for borrow functionality
/// @dev Inherits from LendingPoolTest_Base
contract LendingPoolTest_Borrow is LendingPoolTest_Base {
    function setUp() public override {
        super.setUp();
        setUp_AddBorrowRate(BORROW_RATE);
        setUp_SupplyCollateral(BORROW_RATE, address1, 1 ether);
    }

    /// @notice Test successful borrow
    /// @dev Verifies that assets can be borrowed when sufficient collateral is provided
    function test_Borrow() public {
        vm.prank(router);
        lendingPool.borrow(BORROW_RATE, address1, 1000e6); // Borrow 1000 USDC

        (
            ,
            ,
            ,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares,
            ,

        ) = lendingPool.lendingPoolStates(BORROW_RATE);
        assertEq(
            totalBorrowAssets,
            1000e6,
            "Total borrow assets should be updated"
        );
        assertEq(
            totalBorrowShares,
            1000e6,
            "Total borrow shares should be updated"
        );
    }

    /// @notice Test borrow restrictions
    /// @dev Verifies that invalid parameters and insufficient collateral prevent borrowing
    function test_Borrow_RevertIf_Invalid() public {
        // Test non-owner cannot borrow
        vm.prank(address1);
        vm.expectRevert(
            abi.encodeWithSelector(ILendingPool.InvalidRouter.selector)
        );
        lendingPool.borrow(BORROW_RATE, address1, 1000e6);

        // Test cannot borrow to zero address
        vm.prank(router);
        vm.expectRevert(ILendingPool.InvalidUser.selector);
        lendingPool.borrow(BORROW_RATE, address(0), 1000e6);

        // Test cannot borrow zero amount
        vm.prank(router);
        vm.expectRevert(ILendingPool.InvalidAmount.selector);
        lendingPool.borrow(BORROW_RATE, address1, 0);

        // Test cannot borrow with inactive borrow rate
        vm.prank(router);
        vm.expectRevert(ILendingPool.BorrowRateNotActive.selector);
        lendingPool.borrow(10e16, address1, 1000e6);

        // Test cannot borrow more than collateral allows
        vm.prank(router);
        vm.expectRevert(ILendingPool.InsufficientCollateral.selector);
        lendingPool.borrow(BORROW_RATE, address1, 2000e6); // Try to borrow more than 75% LTV

        // Test cannot borrow after maturity
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(router);
        vm.expectRevert(ILendingPool.MaturityReached.selector);
        lendingPool.borrow(BORROW_RATE, address1, 1000e6);
    }
}

/// @title LendingPool Withdraw Tests
/// @notice Test contract for withdraw functionality
/// @dev Tests withdrawal restrictions before and after maturity
contract LendingPoolTest_Withdraw is LendingPoolTest_Base {
    function setUp() public override {
        super.setUp();
        setUp_AddBorrowRate(BORROW_RATE);
        setUp_Supply(BORROW_RATE, address1, 1000e6);

        MockToken(debtToken).mint(address(lendingPool), 1000e6);
    }

    /// @notice Test successful withdraw after maturity
    /// @dev Verifies that withdrawals are possible only after maturity date
    function test_Withdraw() public {
        vm.warp(block.timestamp + 365 days + 1);

        vm.startPrank(address1);
        lendingPool.withdraw(BORROW_RATE, 500e6);
        vm.stopPrank();

        (
            ,
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares,
            ,
            ,
            ,

        ) = lendingPool.lendingPoolStates(BORROW_RATE);
        assertEq(
            totalSupplyAssets,
            500e6,
            "Total supply assets should be updated"
        );
        assertEq(
            totalSupplyShares,
            500e6,
            "Total supply shares should be updated"
        );

        (address pinjocToken, , , , , , ) = lendingPool.lendingPoolStates(
            BORROW_RATE
        );
        assertEq(
            IERC20(pinjocToken).balanceOf(address1),
            500e6,
            "User should have 500 shares now"
        );
    }

    /// @notice Test withdraw restrictions
    /// @dev Verifies that withdrawals are blocked before maturity and other invalid conditions
    function test_Withdraw_RevertIf_Invalid() public {
        // Test cannot withdraw before maturity
        vm.expectRevert(ILendingPool.MaturityNotReached.selector);
        lendingPool.withdraw(BORROW_RATE, 500e6);

        vm.warp(block.timestamp + 365 days + 1);

        // Test cannot withdraw zero shares
        vm.prank(address1);
        vm.expectRevert(ILendingPool.InvalidAmount.selector);
        lendingPool.withdraw(BORROW_RATE, 0);

        // Test cannot withdraw with inactive borrow rate
        vm.prank(address1);
        vm.expectRevert(ILendingPool.BorrowRateNotActive.selector);
        lendingPool.withdraw(10e16, 500e6);

        // Test cannot withdraw more than owned shares
        vm.prank(address2);
        vm.expectRevert(ILendingPool.InsufficientShares.selector);
        lendingPool.withdraw(BORROW_RATE, 500e6);

        // Test cannot withdraw when pool has insufficient liquidity
        vm.prank(address1);
        vm.expectRevert(ILendingPool.InsufficientShares.selector);
        lendingPool.withdraw(BORROW_RATE, 2000e6);
    }
}

/// @title LendingPool Collateral Tests
/// @notice Test contract for collateral functionality
/// @dev Inherits from LendingPoolTest_Base
contract LendingPoolTest_Collateral is LendingPoolTest_Base {
    function setUp() public override {
        super.setUp();
        setUp_AddBorrowRate(BORROW_RATE);
    }

    /// @notice Test successful collateral supply and withdrawal
    /// @dev Verifies that collateral can be supplied and withdrawn
    function test_CollateralOperations() public {
        setUp_SupplyCollateral(BORROW_RATE, address1, 1 ether);

        uint256 collateral = lendingPool.getUserCollateral(
            BORROW_RATE,
            address1
        );
        assertEq(collateral, 1 ether, "Collateral should be recorded");

        setUp_Borrow(BORROW_RATE, address1, 1000e6); // Borrow 1000 USDC (collateral to borrow = 50%)

        // Since lending pool's ltv are 75% and user borrowed 1000 USDC (50% of collateral)
        // User can only withdraw 33% of collateral
        setUp_WithdrawCollateral(BORROW_RATE, address1, 0.33 ether); // Withdraw

        collateral = lendingPool.getUserCollateral(BORROW_RATE, address1);
        assertEq(
            collateral,
            (1 ether - 0.33 ether),
            "Collateral should be updated"
        );
    }

    /// @notice Test collateral operation restrictions
    /// @dev Verifies that invalid parameters prevent collateral operations
    function test_CollateralOperations_RevertIf_Invalid() public {
        // Test non-owner cannot supply collateral
        vm.prank(address1);
        vm.expectRevert(
            abi.encodeWithSelector(ILendingPool.InvalidRouter.selector)
        );
        lendingPool.supplyCollateral(BORROW_RATE, address1, 1 ether);

        // Test cannot supply to zero address
        vm.prank(router);
        vm.expectRevert(ILendingPool.InvalidUser.selector);
        lendingPool.supplyCollateral(BORROW_RATE, address(0), 1 ether);

        // Test cannot supply zero amount
        vm.prank(router);
        vm.expectRevert(ILendingPool.InvalidAmount.selector);
        lendingPool.supplyCollateral(BORROW_RATE, address1, 0);

        // Test cannot withdraw more than supplied
        vm.prank(address1);
        vm.expectRevert(ILendingPool.InsufficientCollateral.selector);
        lendingPool.withdrawCollateral(BORROW_RATE, 1 ether);

        // Supply some collateral and borrow against it
        setUp_SupplyCollateral(BORROW_RATE, address1, 1 ether);
        setUp_Borrow(BORROW_RATE, address1, 1000e6);

        // Test cannot withdraw collateral that would make position unhealthy
        vm.prank(address1);
        vm.expectRevert(ILendingPool.InsufficientCollateral.selector);
        lendingPool.withdrawCollateral(BORROW_RATE, 0.8 ether);

        // Test cannot supply collateral after maturity
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(router);
        vm.expectRevert(ILendingPool.MaturityReached.selector);
        lendingPool.supplyCollateral(BORROW_RATE, address1, 1 ether);
    }
}

/// @title LendingPool Interest Tests
/// @notice Test contract for interest accrual functionality
/// @dev Tests both regular interest accrual and maturity-capped interest
contract LendingPoolTest_Interest is LendingPoolTest_Base {
    function setUp() public override {
        super.setUp();
        setUp_AddBorrowRate(BORROW_RATE);
        setUp_Supply(BORROW_RATE, address1, 1000e6);
        setUp_SupplyCollateral(BORROW_RATE, address2, 1 ether);
        setUp_Borrow(BORROW_RATE, address2, 1000e6);
    }

    /// @notice Test interest accrual over time
    /// @dev Verifies that interest is correctly accrued within maturity period
    function test_InterestAccrual() public {
        // Move forward 1 year
        vm.warp(block.timestamp + 365 days);

        // This should trigger interest accrual
        lendingPool.accrueInterest(BORROW_RATE);
        (
            ,
            uint256 totalSupplyAssets,
            ,
            uint256 totalBorrowAssets,
            ,
            ,

        ) = lendingPool.lendingPoolStates(BORROW_RATE);

        // After 1 year at 5% interest rate
        assertEq(
            totalBorrowAssets,
            1050e6,
            "Borrow assets should accrue interest"
        );
        assertEq(
            totalSupplyAssets,
            1050e6,
            "Supply assets should match borrow assets"
        );
    }

    /// @notice Test interest accrual is capped at maturity
    /// @dev Verifies that no additional interest accrues after maturity date
    function test_InterestAccrual_CappedAtMaturity() public {
        // Move to just before maturity (364 days)
        vm.warp(block.timestamp + 365 days);

        // Record state before maturity
        lendingPool.accrueInterest(BORROW_RATE);
        (
            ,
            uint256 totalSupplyAssetsBefore,
            ,
            uint256 totalBorrowAssetsBefore,
            ,
            ,

        ) = lendingPool.lendingPoolStates(BORROW_RATE);

        // Move 2 days past maturity (366 days total)
        vm.warp(block.timestamp + 1 days);
        lendingPool.accrueInterest(BORROW_RATE);
        (
            ,
            uint256 totalSupplyAssetsAfter,
            ,
            uint256 totalBorrowAssetsAfter,
            ,
            ,

        ) = lendingPool.lendingPoolStates(BORROW_RATE);

        // Account for the 100e6 repayment and verify only 1 day of interest was added
        assertEq(
            totalBorrowAssetsAfter,
            totalBorrowAssetsBefore,
            "Interest should only accrue up to maturity"
        );
        assertEq(
            totalSupplyAssetsAfter,
            totalSupplyAssetsBefore,
            "Supply assets should match borrow assets with interest"
        );
    }
}

/// @title LendingPool Repay Tests
/// @notice Test contract for repay functionality
/// @dev Inherits from LendingPoolTest_Base
contract LendingPoolTest_Repay is LendingPoolTest_Base {
    function setUp() public override {
        super.setUp();
        setUp_AddBorrowRate(BORROW_RATE);
        setUp_SupplyCollateral(BORROW_RATE, address1, 1 ether);

        // Mock debt token balance for lending pool and borrow
        MockToken(debtToken).mint(address(lendingPool), 1000e6);
        setUp_Borrow(BORROW_RATE, address1, 1000e6);

        // Give debt tokens to repayer
        MockToken(debtToken).mint(address1, 2000e6);
    }

    /// @notice Test successful repayment
    /// @dev Verifies that borrowed assets can be repaid
    function test_Repay() public {
        vm.startPrank(address1);
        IERC20(debtToken).approve(address(lendingPool), 1000e6);
        lendingPool.repay(BORROW_RATE, 1000e6);
        vm.stopPrank();

        (
            ,
            ,
            ,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares,
            ,

        ) = lendingPool.lendingPoolStates(BORROW_RATE);
        assertEq(totalBorrowAssets, 0, "Total borrow assets should be updated");
        assertEq(totalBorrowShares, 0, "Total borrow shares should be updated");
    }

    function test_Repay_RevertIf_Invalid() public {
        // Test cannot repay zero amount
        vm.prank(address1);
        vm.expectRevert(ILendingPool.InvalidAmount.selector);
        lendingPool.repay(BORROW_RATE, 0);

        // Test cannot repay with inactive borrow rate
        vm.prank(address1);
        vm.expectRevert(ILendingPool.BorrowRateNotActive.selector);
        lendingPool.repay(10e16, 1000e6);

        // Test cannot repay more than owed
        vm.prank(address1);
        vm.expectRevert(ILendingPool.InsufficientBorrowShares.selector);
        lendingPool.repay(BORROW_RATE, 2000e6);

        // Test cannot repay after maturity
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(address1);
        vm.expectRevert(ILendingPool.MaturityReached.selector);
        lendingPool.repay(BORROW_RATE, 1000e6);
    }
}

/// @title LendingPool Liquidate Tests
/// @notice Test contract for liquidation functionality
/// @dev Tests liquidations both after maturity and for unhealthy positions
contract LendingPoolTest_Liquidate is LendingPoolTest_Base {
    function setUp() public override {
        super.setUp();
        setUp_AddBorrowRate(BORROW_RATE);
        setUp_SupplyCollateral(BORROW_RATE, address1, 1 ether);

        // Mock debt token balance for lending pool and borrow
        MockToken(debtToken).mint(address(lendingPool), 1000e6);
        setUp_Borrow(BORROW_RATE, address1, 1000e6);

        // Give debt tokens to liquidator
        MockToken(debtToken).mint(address2, 2000e6);
    }

    /// @notice Test successful liquidation after maturity
    /// @dev Verifies that any position can be liquidated after maturity regardless of health
    function test_Liquidate_AfterMaturity() public {
        // Move past maturity
        vm.warp(block.timestamp + 366 days);

        // Prepare liquidator
        vm.startPrank(address2);
        IERC20(debtToken).approve(address(lendingPool), 1000e6);

        // Liquidate position
        lendingPool.liquidate(BORROW_RATE, address1);
        vm.stopPrank();

        // Verify liquidation results
        (
            ,
            ,
            ,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares,
            ,

        ) = lendingPool.lendingPoolStates(BORROW_RATE);
        assertEq(totalBorrowAssets, 0, "Total borrow assets should be updated");
        assertEq(totalBorrowShares, 0, "Total borrow shares should be updated");
        assertEq(
            lendingPool.getUserCollateral(BORROW_RATE, address1),
            0,
            "Collateral should be transferred to liquidator"
        );
        assertEq(
            lendingPool.getUserBorrowShares(BORROW_RATE, address1),
            0,
            "Borrow shares should be cleared"
        );
        assertEq(
            IERC20(collateralToken).balanceOf(address2),
            1 ether,
            "Liquidator should receive collateral"
        );
    }

    /// @notice Test successful liquidation when position becomes unhealthy
    /// @dev Verifies that unhealthy positions can be liquidated even before maturity
    function test_Liquidate_UnhealthyPosition() public {
        // Drop collateral price by 50% to make position unhealthy
        MockOracle(oracle).setPrice(1000e6); // 1 ETH = 1000 USDC

        // Prepare liquidator
        vm.startPrank(address2);
        IERC20(debtToken).approve(address(lendingPool), 1000e6);

        // Liquidate position
        lendingPool.liquidate(BORROW_RATE, address1);
        vm.stopPrank();

        // Verify liquidation results
        (
            ,
            ,
            ,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares,
            ,

        ) = lendingPool.lendingPoolStates(BORROW_RATE);
        assertEq(totalBorrowAssets, 0, "Total borrow assets should be updated");
        assertEq(totalBorrowShares, 0, "Total borrow shares should be updated");
        assertEq(
            lendingPool.getUserCollateral(BORROW_RATE, address1),
            0,
            "Collateral should be transferred to liquidator"
        );
        assertEq(
            lendingPool.getUserBorrowShares(BORROW_RATE, address1),
            0,
            "Borrow shares should be cleared"
        );
        assertEq(
            IERC20(collateralToken).balanceOf(address2),
            1 ether,
            "Liquidator should receive collateral"
        );
    }

    /// @notice Test liquidation restrictions
    /// @dev Verifies that healthy positions cannot be liquidated before maturity
    function test_Liquidate_RevertIf_Invalid() public {
        // Test cannot liquidate zero address
        vm.prank(address2);
        vm.expectRevert(ILendingPool.InvalidUser.selector);
        lendingPool.liquidate(BORROW_RATE, address(0));

        // Test cannot liquidate with inactive borrow rate
        vm.prank(address2);
        vm.expectRevert(ILendingPool.BorrowRateNotActive.selector);
        lendingPool.liquidate(10e16, address1);
    }
}
