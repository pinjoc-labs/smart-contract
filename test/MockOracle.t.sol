// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";

contract MockOracleBaseTest is Test {
    MockOracle public mockOracle;
    address public baseToken;
    address public quoteToken;
    address public address1;

    function setUp() public {
        baseToken = address(new MockToken("Mock USDC", "MUSDC", 6));
        quoteToken = address(new MockToken("Mock ETH", "METH", 18));
        mockOracle = new MockOracle(baseToken, quoteToken);
        address1 = makeAddr("address1");
    }
}

contract MockOracleMintTest is MockOracleBaseTest {
    function test_setPrice() public {
        mockOracle.setPrice(1000);
        assertEq(mockOracle.price(), 1000);
    }

    function test_setPrice_RevertIf_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address1)
        );
        vm.prank(address1);
        mockOracle.setPrice(1000);
    }
}

