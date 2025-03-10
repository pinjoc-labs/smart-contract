// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ILendingPoolManager} from "../src/interfaces/ILendingPoolManager.sol";
import {LendingPoolManager} from "../src/LendingPoolManager.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";

/// @title LendingPoolManager Base Test Contract
/// @notice Base contract containing common setup and helper functions for LendingPoolManager tests
/// @dev Provides mock tokens, oracle, test addresses, and helper functions for pool creation
contract LendingPoolManagerTest_Base is Test {
    /// @notice The LendingPoolManager contract instance being tested
    LendingPoolManager public manager;
    /// @notice Mock USDC token used as debt token
    address public debtToken;
    /// @notice Mock ETH token used as collateral token
    address public collateralToken;
    /// @notice Mock price oracle for ETH/USDC pair
    address public oracle;
    /// @notice Address with owner privileges
    address public owner;
    /// @notice Address for testing unauthorized access
    address public user;
    /// @notice Default maturity timestamp (1 year from deployment)
    uint256 maturity = block.timestamp + 365 days;
    /// @notice Default maturity month string
    string maturityMonth = "MAY";
    /// @notice Default maturity year
    uint256 maturityYear = 2025;
    /// @notice Default loan-to-value ratio (75%)
    uint256 ltv = 75e16;

    /// @notice Setup function called before each test
    /// @dev Deploys mock tokens, oracle, and manager contract with initial configuration
    function setUp() public virtual {
        // Deploy mock tokens and oracle
        debtToken = address(new MockToken("Mock USDC", "MUSDC", 6));
        collateralToken = address(new MockToken("Mock ETH", "METH", 18));
        oracle = address(new MockOracle(debtToken, collateralToken));
        MockOracle(oracle).setPrice(2000e6); // 1 ETH = 2000 USDC

        // Setup test addresses
        owner = makeAddr("owner");
        user = makeAddr("user");

        // Deploy manager
        vm.prank(owner);
        manager = new LendingPoolManager();
    }

    /// @notice Helper function to create a lending pool with default parameters
    /// @dev Uses predefined parameters for maturity, LTV, and tokens
    function setUp_CreatePool() public returns (address) {
        return
            manager.createLendingPool(
                debtToken,
                collateralToken,
                oracle,
                maturity,
                maturityMonth,
                maturityYear,
                ltv
            );
    }
}

/// @title LendingPoolManager Creation Tests
/// @notice Test contract for pool creation functionality
/// @dev Tests successful pool creation and various error cases
contract LendingPoolManagerTest_Creation is LendingPoolManagerTest_Base {
    /// @notice Test successful lending pool creation
    /// @dev Verifies that a pool can be created with valid parameters and all parameters are set correctly
    function test_CreateLendingPool() public {
        vm.prank(owner);
        address poolAddress = setUp_CreatePool();
        assertTrue(poolAddress != address(0), "Pool should be created");

        LendingPool pool = LendingPool(poolAddress);
        (
            address poolDebtToken,
            address poolCollateralToken,
            address poolOracle,
            uint256 poolMaturity,
            string memory poolMaturityMonth,
            uint256 poolMaturityYear,
            uint256 poolLtv
        ) = pool.info();

        assertEq(poolDebtToken, debtToken, "Debt token mismatch");
        assertEq(
            poolCollateralToken,
            collateralToken,
            "Collateral token mismatch"
        );
        assertEq(poolOracle, oracle, "Oracle mismatch");
        assertEq(poolMaturity, maturity, "Maturity mismatch");
        assertEq(poolMaturityMonth, maturityMonth, "Maturity month mismatch");
        assertEq(poolMaturityYear, maturityYear, "Maturity year mismatch");
        assertEq(poolLtv, ltv, "LTV mismatch");
    }

    /// @notice Test lending pool creation restrictions
    /// @dev Verifies that unauthorized users cannot create pools and duplicate pools cannot be created
    function test_CreateLendingPool_RevertIf_Invalid() public {
        // Test non-owner cannot create pool
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        setUp_CreatePool();

        // Create initial pool
        vm.prank(owner);
        setUp_CreatePool();

        // Test cannot create duplicate pool
        vm.prank(owner);
        vm.expectRevert(ILendingPoolManager.LendingPoolAlreadyExists.selector);
        setUp_CreatePool();
    }
}

/// @title LendingPoolManager Query Tests
/// @notice Test contract for pool query functionality
/// @dev Tests successful pool retrieval and error cases
contract LendingPoolManagerTest_GetLendingPool is LendingPoolManagerTest_Base {
    /// @notice Test successful lending pool retrieval
    /// @dev Verifies that pool addresses can be retrieved and pool parameters match creation values
    function test_GetLendingPool() public {
        vm.prank(owner);
        address poolAddress = setUp_CreatePool();

        LendingPool pool = LendingPool(poolAddress);
        (
            address poolDebtToken,
            address poolCollateralToken,
            address poolOracle,
            uint256 poolMaturity,
            string memory poolMaturityMonth,
            uint256 poolMaturityYear,
            uint256 poolLtv
        ) = pool.info();

        assertEq(poolDebtToken, debtToken, "Debt token mismatch");
        assertEq(
            poolCollateralToken,
            collateralToken,
            "Collateral token mismatch"
        );
        assertEq(poolOracle, oracle, "Oracle mismatch");
        assertEq(poolMaturity, maturity, "Maturity mismatch");
        assertEq(poolMaturityMonth, maturityMonth, "Maturity month mismatch");
        assertEq(poolMaturityYear, maturityYear, "Maturity year mismatch");
        assertEq(poolLtv, ltv, "LTV mismatch");
    }

    /// @notice Test getting non-existent lending pool
    /// @dev Verifies that attempting to get a non-existent pool reverts with appropriate error
    function test_GetLendingPool_RevertIf_NotFound() public {
        vm.expectRevert(ILendingPoolManager.LendingPoolNotFound.selector);
        manager.getLendingPool(debtToken, collateralToken, "MAY", 2025);
    }
}
