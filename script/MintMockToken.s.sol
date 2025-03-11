// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract MintMockToken is Script {
    using Strings for string;

    function run() public {
        // Get private keys from environment
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 lenderKey = vm.envUint("LENDER_PRIVATE_KEY");
        uint256 borrowerKey = vm.envUint("BORROWER_PRIVATE_KEY");

        // Derive addresses from private keys
        address owner = vm.addr(deployerKey);
        address lender = vm.addr(lenderKey);
        address borrower = vm.addr(borrowerKey);

        vm.startBroadcast(deployerKey);

        console2.log("\n=== DATA DISTRIBUTION STARTED ===");
        console2.log("Owner Address: %s", owner);
        console2.log("Lender Address: %s", lender);
        console2.log("Borrower Address: %s", borrower);

        // Get addresses from .env
        address usdcAddress = vm.envAddress("USDC");
        address[5] memory collateralAddresses = [
            vm.envAddress("WETH"),
            vm.envAddress("WBTC"),
            vm.envAddress("WSOL"),
            vm.envAddress("WLINK"),
            vm.envAddress("WAAVE")
        ];

        // Initialize Mock Tokens
        console2.log("\nInitializing Mock Tokens...");
        MockToken musdc = MockToken(usdcAddress);
        MockToken[5] memory collaterals = [
            MockToken(collateralAddresses[0]), // WETH
            MockToken(collateralAddresses[1]), // WBTC
            MockToken(collateralAddresses[2]), // SOL
            MockToken(collateralAddresses[3]), // LINK
            MockToken(collateralAddresses[4])  // AAVE
        ];

        // Minting to owner
        console2.log("\nMinting to owner...");
        musdc.mint(owner, 10_000_000e6);
        console2.log("Minted 10_000_000e6 USDC to owner");

        uint256[5] memory amounts = [
            uint256(1_000_000e18), // WETH
            uint256(10_000e8),     // WBTC
            uint256(1_000_000e18), // SOL
            uint256(1_000_000e18), // LINK
            uint256(1_000_000e18)  // AAVE
        ];
        
        for (uint256 i = 0; i < collaterals.length; i++) {
            collaterals[i].mint(owner, amounts[i]);
            console2.log(
                "Minted %s %s to owner",
                amounts[i] / (10 ** collaterals[i].decimals()),
                IERC20Metadata(address(collaterals[i])).symbol()
            );
        }

        // Minting to lender and borrower
        address[2] memory users = [lender, borrower];
        string[2] memory userTypes = ["lender", "borrower"];
        
        console2.log("\nMinting to lender and borrower...");
        for (uint256 i = 0; i < users.length; i++) {
            musdc.mint(users[i], 10_000_000e6);
            console2.log(
                "Minted %s USDC to %s",
                10_000_000,
                userTypes[i]
            );
            
            for (uint256 j = 0; j < collaterals.length; j++) {
                collaterals[j].mint(users[i], amounts[j]);
                console2.log(
                    "Minted %s %s to %s",
                    amounts[j] / (10 ** collaterals[j].decimals()),
                    IERC20Metadata(address(collaterals[j])).symbol(),
                    userTypes[i]
                );
            }
        }

        console2.log("\n=== DATA DISTRIBUTION COMPLETED ===");

        vm.stopBroadcast();
    }
}