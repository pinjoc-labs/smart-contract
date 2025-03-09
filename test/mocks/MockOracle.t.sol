// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {MockOracle} from "../../src/mocks/MockOracle.sol";

/// @title MockOracle Base Test Contract
/// @notice Base contract containing common setup for MockOracle tests
/// @dev Inherits from Forge's Test contract
contract MockOracleTest_Base is Test {
    MockOracle public mockOracle;
    address public baseToken;
    address public quoteToken;
    address public address1;

    /// @notice Setup function called before each test
    /// @dev Creates mock tokens and oracle instance, and sets up test addresses
    function setUp() public {
        baseToken = address(new MockToken("Mock USDC", "MUSDC", 6));
        quoteToken = address(new MockToken("Mock ETH", "METH", 18));
        mockOracle = new MockOracle(baseToken, quoteToken);
        address1 = makeAddr("address1");
    }
}

/// @title MockOracle Price Setting Tests
/// @notice Test contract for MockOracle price setting functionality
/// @dev Inherits from MockOracleTest_Base
contract MockOracleTest_SetPrice is MockOracleTest_Base {
    /// @notice Test successful price setting
    /// @dev Verifies that price can be set by the owner
    function test_setPrice() public {
        mockOracle.setPrice(1000);
        assertEq(mockOracle.price(), 1000);
    }

    /// @notice Test price setting restriction to owner
    /// @dev Verifies that non-owners cannot set the price
    function test_setPrice_RevertIf_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address1)
        );
        vm.prank(address1);
        mockOracle.setPrice(1000);
    }
}

