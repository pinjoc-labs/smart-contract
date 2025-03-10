// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ILendingCLOBManager} from "../src/interfaces/ILendingCLOBManager.sol";
import {LendingCLOBManager} from "../src/LendingCLOBManager.sol";
import {LendingCLOB} from "../src/LendingCLOB.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";

/// @title LendingCLOBManager Base Test Contract
/// @notice Base contract containing common setup and helper functions for LendingCLOBManager tests
/// @dev Provides mock tokens, oracle, test addresses, and helper functions for CLOB creation
contract LendingCLOBManagerTest_Base is Test {
    /// @notice The LendingCLOBManager contract instance being tested
    LendingCLOBManager public manager;
    /// @notice Mock USDC token used as debt token
    address public debtToken;
    /// @notice Mock ETH token used as collateral token
    address public collateralToken;
    /// @notice Address with owner privileges
    address public owner;
    /// @notice Address for testing unauthorized access
    address public user;
    /// @notice Default maturity month string
    string maturityMonth = "MAY";
    /// @notice Default maturity year
    uint256 maturityYear = 2025;

    /// @notice Setup function called before each test
    /// @dev Deploys mock tokens, oracle, and manager contract with initial configuration
    function setUp() public virtual {
        // Deploy mock tokens and oracle
        debtToken = address(new MockToken("Mock USDC", "MUSDC", 6));
        collateralToken = address(new MockToken("Mock ETH", "METH", 18));

        // Setup test addresses
        owner = makeAddr("owner");
        user = makeAddr("user");

        // Deploy manager
        vm.prank(owner);
        manager = new LendingCLOBManager();
    }

    /// @notice Helper function to create a lending CLOB with default parameters
    /// @dev Uses predefined parameters for maturity and tokens
    function setUp_CreateCLOB() public returns (address) {
        return
            manager.createLendingCLOB(
                debtToken,
                collateralToken,
                maturityMonth,
                maturityYear
            );
    }
}

/// @title LendingCLOBManager Creation Tests
/// @notice Test contract for CLOB creation functionality
/// @dev Tests successful CLOB creation and various error cases
contract LendingCLOBManagerTest_Creation is LendingCLOBManagerTest_Base {
    /// @notice Test successful lending CLOB creation
    /// @dev Verifies that a CLOB can be created with valid parameters and all parameters are set correctly
    function test_CreateLendingCLOB() public {
        vm.prank(owner);
        address clobAddress = setUp_CreateCLOB();
        assertTrue(clobAddress != address(0), "CLOB should be created");

        LendingCLOB clob = LendingCLOB(clobAddress);

        assertEq(address(clob.debtToken()), debtToken, "Debt token mismatch");
        assertEq(
            address(clob.collateralToken()),
            collateralToken,
            "Collateral token mismatch"
        );
        assertEq(
            clob.maturityMonth(),
            maturityMonth,
            "Maturity month mismatch"
        );
        assertEq(clob.maturityYear(), maturityYear, "Maturity year mismatch");
    }

    /// @notice Test lending CLOB creation restrictions
    /// @dev Verifies that unauthorized users cannot create CLOB and duplicate CLOB cannot be created
    function test_CreateLendingCLOB_RevertIf_Invalid() public {
        // Test non-owner cannot create CLOB
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        setUp_CreateCLOB();

        // Create initial CLOB
        vm.prank(owner);
        setUp_CreateCLOB();

        // Test cannot create duplicate CLOB
        vm.prank(owner);
        vm.expectRevert(ILendingCLOBManager.LendingCLOBAlreadyExists.selector);
        setUp_CreateCLOB();
    }
}

/// @title LendingCLOBManager Query Tests
/// @notice Test contract for CLOB query functionality
/// @dev Tests successful CLOB retrieval and error cases
contract LendingCLOBManagerTest_GetLendingCLOB is LendingCLOBManagerTest_Base {
    /// @notice Test successful lending CLOB retrieval
    /// @dev Verifies that CLOB addresses can be retrieved and CLOB parameters match creation values
    function test_GetLendingCLOB() public {
        vm.prank(owner);
        setUp_CreateCLOB();
        address retrievedClobAddress = manager.getLendingCLOB(
            debtToken,
            collateralToken,
            maturityMonth,
            maturityYear
        );

        LendingCLOB clob = LendingCLOB(retrievedClobAddress);

        assertEq(address(clob.debtToken()), debtToken, "Debt token mismatch");
        assertEq(
            address(clob.collateralToken()),
            collateralToken,
            "Collateral token mismatch"
        );
        assertEq(
            clob.maturityMonth(),
            maturityMonth,
            "Maturity month mismatch"
        );
        assertEq(clob.maturityYear(), maturityYear, "Maturity year mismatch");
    }

    /// @notice Test getting non-existent lending CLOB
    /// @dev Verifies that attempting to get a non-existent CLOB reverts with appropriate error
    function test_GetLendingCLOB_RevertIf_NotFound() public {
        vm.expectRevert(ILendingCLOBManager.LendingCLOBNotFound.selector);
        manager.getLendingCLOB(debtToken, collateralToken, "MAY", 2025);
    }
}
