// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";

/// @title MockToken Base Test Contract
/// @notice Base contract containing common setup for MockToken tests
/// @dev Inherits from Forge's Test contract
contract MockTokenTest_Base is Test {
    MockToken public mockToken;
    address public address1;

    /// @notice Setup function called before each test
    /// @dev Creates a new MockToken instance and sets up test addresses
    function setUp() public {
        mockToken = new MockToken("Mock USDC", "MUSDC", 6);
        address1 = makeAddr("address1");
    }
}

/// @title MockToken Mint Tests
/// @notice Test contract for MockToken minting functionality
/// @dev Inherits from MockTokenTest_Base
contract MockTokenTest_Mint is MockTokenTest_Base {
    /// @notice Test successful token minting
    /// @dev Verifies that tokens can be minted by the owner
    function test_Mint() public {
        mockToken.mint(address(this), 1000);
        assertEq(mockToken.balanceOf(address(this)), 1000);
    }

    /// @notice Test minting restriction to owner
    /// @dev Verifies that non-owners cannot mint tokens
    function test_Mint_RevertIf_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address1)
        );
        vm.prank(address1);
        mockToken.mint(address(this), 1000);
    }
}

/// @title MockToken Burn Tests
/// @notice Test contract for MockToken burning functionality
/// @dev Inherits from MockTokenTest_Base
contract MockTokenTest_Burn is MockTokenTest_Base {
    /// @notice Test successful token burning
    /// @dev Verifies that tokens can be burned by the owner
    function test_Burn() public {
        mockToken.mint(address(this), 1000);
        mockToken.burn(1000);
        assertEq(mockToken.balanceOf(address(this)), 0);
    }

    /// @notice Test burning restriction to owner
    /// @dev Verifies that non-owners cannot burn tokens
    function test_Burn_RevertIf_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address1)
        );
        vm.prank(address1);
        mockToken.burn(1000);
    }
}