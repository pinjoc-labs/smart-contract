// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

contract MockTokenBaseTest is Test {
    MockToken public mockToken;
    address public address1;

    function setUp() public {
        mockToken = new MockToken("Mock USDC", "MUSDC", 6);
        address1 = makeAddr("address1");
    }
}

contract MockTokenMintTest is MockTokenBaseTest {
    function test_Mint() public {
        mockToken.mint(address(this), 1000);
        assertEq(mockToken.balanceOf(address(this)), 1000);
    }

    function test_Mint_RevertIf_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address1)
        );
        vm.prank(address1);
        mockToken.mint(address(this), 1000);
    }
}

contract MockTokenBurnTest is MockTokenBaseTest {
    function test_Burn() public {
        mockToken.mint(address(this), 1000);
        mockToken.burn(1000);
        assertEq(mockToken.balanceOf(address(this)), 0);
    }

    function test_Burn_RevertIf_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address1)
        );
        vm.prank(address1);
        mockToken.burn(1000);
    }
}

