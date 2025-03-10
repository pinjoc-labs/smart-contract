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
    /// @notice Router address for managing pools
    address public router;
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
        router = makeAddr("router");
        user = makeAddr("user");

        // Deploy manager with router and owner
        vm.prank(owner);
        manager = new LendingPoolManager(router);
    }

    /// @notice Helper function to create a lending pool with default parameters
    /// @dev Uses predefined parameters for maturity, LTV, and tokens
    function setUp_CreatePool() public returns (address) {
        return manager.createLendingPool(
            debtToken,
            collateralToken,
            maturity,
            maturityMonth,
            maturityYear,
            ltv
        );
    }
}

/// @title LendingPoolManager Oracle Tests
/// @notice Test contract for oracle management functionality
/// @dev Tests oracle setting and validation
contract LendingPoolManagerTest_SetOracle is LendingPoolManagerTest_Base {
    /// @notice Test successful oracle setting
    /// @dev Verifies that oracle can be set and retrieved correctly
    function test_SetOracle() public {
        vm.prank(owner);
        manager.setOracle(oracle, debtToken, collateralToken);
        
        address retrievedOracle = manager.getOracle(debtToken, collateralToken);
        assertEq(retrievedOracle, oracle, "Oracle address mismatch");
    }

    /// @notice Test oracle setting restrictions
    /// @dev Verifies that only owner can set oracle and invalid parameters are rejected
    function test_SetOracle_RevertIf_Invalid() public {
        // Test non-owner cannot set oracle
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user)
        );
        manager.setOracle(oracle, debtToken, collateralToken);

        // Test cannot set zero address oracle
        vm.prank(owner);
        vm.expectRevert(ILendingPoolManager.InvalidOracle.selector);
        manager.setOracle(address(0), debtToken, collateralToken);
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
        manager.setOracle(oracle, debtToken, collateralToken);
        
        vm.prank(router);
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
        assertEq(poolCollateralToken, collateralToken, "Collateral token mismatch");
        assertEq(poolOracle, oracle, "Oracle mismatch");
        assertEq(poolMaturity, maturity, "Maturity mismatch");
        assertEq(poolMaturityMonth, maturityMonth, "Maturity month mismatch");
        assertEq(poolMaturityYear, maturityYear, "Maturity year mismatch");
        assertEq(poolLtv, ltv, "LTV mismatch");
    }

    /// @notice Test lending pool creation restrictions
    /// @dev Verifies that unauthorized users cannot create pools and duplicate pools cannot be created
    function test_CreateLendingPool_RevertIf_Invalid() public {
        // Test non-router cannot create pool
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ILendingPoolManager.OnlyRouter.selector)
        );
        setUp_CreatePool();

        // Test invalid parameter
        vm.startPrank(router);
        vm.expectRevert(ILendingPoolManager.InvalidCreateLendingPoolParameter.selector);
        manager.createLendingPool(address(0), collateralToken, maturity, maturityMonth, maturityYear, ltv);
        vm.expectRevert(ILendingPoolManager.InvalidCreateLendingPoolParameter.selector);
        manager.createLendingPool(debtToken, address(0), maturity, maturityMonth, maturityYear, ltv);
        vm.expectRevert(ILendingPoolManager.InvalidCreateLendingPoolParameter.selector);
        manager.createLendingPool(debtToken, collateralToken, 0, maturityMonth, maturityYear, ltv);
        vm.expectRevert(ILendingPoolManager.InvalidCreateLendingPoolParameter.selector);
        manager.createLendingPool(debtToken, collateralToken, maturity, "", maturityYear, ltv);
        vm.expectRevert(ILendingPoolManager.InvalidCreateLendingPoolParameter.selector);
        manager.createLendingPool(debtToken, collateralToken, maturity, maturityMonth, 0, ltv);
        vm.expectRevert(ILendingPoolManager.InvalidCreateLendingPoolParameter.selector);
        manager.createLendingPool(debtToken, collateralToken, maturity, maturityMonth, maturityYear, 0);
        vm.stopPrank();

        // Test unset oracle
        vm.prank(router);
        vm.expectRevert(ILendingPoolManager.OracleNotFound.selector);
        setUp_CreatePool();

        // Create initial pool
        vm.prank(owner);
        manager.setOracle(oracle, debtToken, collateralToken);
        vm.prank(router);
        setUp_CreatePool();

        // Test cannot create duplicate pool
        vm.prank(router);
        vm.expectRevert(ILendingPoolManager.LendingPoolAlreadyExists.selector);
        setUp_CreatePool();
    }
}

contract LendingPoolManagerTest_GetOracle is LendingPoolManagerTest_Base {
    /// @notice Test oracle retrieval restrictions
    /// @dev Verifies that only router can retrieve oracle and oracle not found error is thrown if oracle doesn't exist
    function test_GetOracle_RevertIf_OracleNotFound() public {
        vm.expectRevert(ILendingPoolManager.OracleNotFound.selector);
        manager.getOracle(debtToken, collateralToken);
    }
}