// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PinjocToken} from "../src/PinjocToken.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

/// @title Base test contract for PinjocToken
/// @notice Provides the common setup and utilities for all PinjocToken tests
/// @dev Inherits from Forge's Test contract for testing utilities
contract PinjocTokenTest_Base is Test {
    /// @notice Mock USDC token address
    address public debtToken;
    /// @notice Mock ETH token address
    address public collateralToken;
    /// @notice The PinjocToken instance being tested
    PinjocToken public pinjocToken;
    /// @notice Test address for unauthorized operations
    address public address1;

    /// @notice Sets up the test environment before each test
    /// @dev Deploys mock tokens and PinjocToken with initial configuration
    function setUp() public {
        debtToken = address(new MockToken("Mock USDC", "MUSDC", 6));
        collateralToken = address(new MockToken("Mock ETH", "METH", 18));

        PinjocToken.PinjocTokenInfo memory info = PinjocToken.PinjocTokenInfo({
            debtToken: debtToken,
            collateralToken: collateralToken,
            rate: 45e16,
            maturity: 1715280000,
            maturityMonth: "MAY",
            maturityYear: 2025
        });

        pinjocToken = new PinjocToken(
            address(this), // lending pool address
            info
        );
        address1 = makeAddr("address1");
    }
}

/// @title Constructor tests for PinjocToken
/// @notice Tests the initialization and configuration of PinjocToken
/// @dev Inherits from PinjocTokenTest_Base for common setup
contract PinjocTokenTest_Constructor is PinjocTokenTest_Base {
    /// @notice Tests that the constructor properly sets all state variables
    /// @dev Verifies token addresses, rate, maturity, and metadata
    function test_PinjocToken_Constructor() public view {
        console.log("Token Symbol:", IERC20Metadata(pinjocToken).symbol());
        console.log("Token Name:", IERC20Metadata(pinjocToken).name());
        
        (
            address debtToken_,
            address collateralToken_,
            uint256 rate_,
            uint256 maturity_,
            string memory maturityMonth_,
            uint256 maturityYear_
        ) = pinjocToken.info();

        assertEq(debtToken_, debtToken, "Incorrect debt token address");
        assertEq(collateralToken_, collateralToken, "Incorrect collateral token address");
        assertEq(rate_, 45e16, "Incorrect borrow rate");
        assertEq(maturity_, 1715280000, "Incorrect maturity timestamp");
        assertEq(maturityMonth_, "MAY", "Incorrect maturity month");
        assertEq(maturityYear_, 2025, "Incorrect maturity year");
    }
}

/// @title Minting tests for PinjocToken
/// @notice Tests the minting functionality of PinjocToken
/// @dev Inherits from PinjocTokenTest_Base for common setup
contract PinjocTokenTest_Mint is PinjocTokenTest_Base {
    /// @notice Tests successful minting of tokens
    /// @dev Verifies that the owner can mint tokens and balance is updated correctly
    function test_Mint() public {
        pinjocToken.mint(address(this), 1000);
        assertEq(pinjocToken.balanceOf(address(this)), 1000, "Incorrect balance after mint");
    }

    /// @notice Tests that non-owners cannot mint tokens
    /// @dev Verifies that the transaction reverts with OwnableUnauthorizedAccount error
    function test_Mint_RevertIf_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address1)
        );
        vm.prank(address1);
        pinjocToken.mint(address(this), 1000);
    }
}

