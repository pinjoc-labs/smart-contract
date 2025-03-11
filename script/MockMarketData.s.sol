// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {PinjocLendingRouter} from "../src/PinjocLendingRouter.sol";
import {ILendingCLOB} from "../src/interfaces/ILendingCLOB.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MockMarketData is Script {
    // Struct to hold rate data for a maturity
    struct MaturityRates {
        uint256[] lendRates;   // 6 rates for lending
        uint256[] borrowRates; // 5 rates for borrowing
    }

    // Constants
    uint256 constant RATE_INCREMENT = 0.5e16; // 0.5% increment
    uint256 constant USDC_AMOUNT = 10_000e6;  // 10,000 USDC

    function run() public {
        console2.log(unicode"🚀 Starting Mock Market Data Generation");
        
        // Get private keys
        uint256 lenderKey = vm.envUint("LENDER_PRIVATE_KEY");
        uint256 borrowerKey = vm.envUint("BORROWER_PRIVATE_KEY");
        address lender = vm.addr(lenderKey);
        address borrower = vm.addr(borrowerKey);

        console2.log("Lender Address: %s", lender);
        console2.log("Borrower Address: %s", borrower);

        // Get contract addresses from .env
        PinjocLendingRouter router = PinjocLendingRouter(vm.envAddress("PINJOC_ROUTER"));
        MockToken usdc = MockToken(vm.envAddress("USDC"));
        
        // Get collateral tokens from .env
        address[5] memory collaterals = [
            vm.envAddress("WETH"),  // WETH - lowest rate
            vm.envAddress("WBTC"),  // WBTC - second lowest
            vm.envAddress("WSOL"),  // SOL - medium rate
            vm.envAddress("WLINK"), // LINK - second highest
            vm.envAddress("WAAVE")  // AAVE - highest rate
        ];

        uint256[5] memory baseRates = [
            uint256(3e16),  // 3% for ETH
            uint256(3.5e16), // 3.5% for BTC
            uint256(5e16),   // 5% for SOL
            uint256(5.5e16), // 5.5% for LINK
            uint256(6e16)    // 6% for AAVE
        ];

        uint256[5] memory collateralAmounts = [
            uint256(100e18),    // WETH
            uint256(100e8),     // WBTC
            uint256(1000e18),   // SOL
            uint256(10_000e18), // LINK
            uint256(1000e18)    // AAVE
        ];

        string[5] memory maturityMonths = ["MAY", "AUG", "NOV", "FEB", "MAY"];
        uint256[5] memory maturityYears = [uint256(2025), uint256(2025), uint256(2025), uint256(2026), uint256(2026)];

        console2.log(unicode"📅 Available Maturities:");
        for (uint256 i = 0; i < maturityMonths.length; i++) {
            console2.log("  %s %s", maturityMonths[i], maturityYears[i]);
        }

        console2.log(unicode"\n📊 Starting Order Placement");

        // Place orders for each collateral
        for (uint256 i = 0; i < collaterals.length; i++) {
            string memory collateralSymbol = IERC20Metadata(collaterals[i]).symbol();
            console2.log(unicode"\n🔄 Processing Collateral: %s", collateralSymbol);

            for (uint256 j = 0; j < maturityMonths.length; j++) {
                console2.log(
                    unicode"\n📅 Maturity: %s %s",
                    maturityMonths[j],
                    maturityYears[j]
                );

                // Calculate maturity premium (longer maturity = higher rate)
                uint256 maturityPremium = j * 0.5e16; // 0.5% increase per maturity
                uint256 baseRate = baseRates[i] + maturityPremium;

                // Generate lending rates (6 rates, increasing by 0.5%)
                uint256[] memory lendRates = new uint256[](6);
                for (uint256 k = 0; k < 6; k++) {
                    lendRates[k] = baseRate + (k * RATE_INCREMENT);
                }

                // Generate borrowing rates (5 rates, increasing by 0.5%)
                uint256[] memory borrowRates = new uint256[](5);
                for (uint256 k = 0; k < 5; k++) {
                    borrowRates[k] = baseRate - (RATE_INCREMENT + (k * RATE_INCREMENT));
                }

                // Place lend orders
                console2.log(unicode"\n📈 Placing Lend Orders");
                vm.startBroadcast(lenderKey);
                for (uint256 k = 0; k < lendRates.length; k++) {
                    usdc.approve(address(router), USDC_AMOUNT);
                    router.placeOrder(
                        address(usdc),
                        collaterals[i],
                        USDC_AMOUNT,
                        0, // no collateral for lending
                        lendRates[k],
                        block.timestamp + 365 days,
                        maturityMonths[j],
                        maturityYears[j],
                        ILendingCLOB.Side.LEND
                    );
                    console2.log(
                        "  Rate: %s%%",
                        lendRates[k] / 1e14 / 100
                    );
                }
                vm.stopBroadcast();

                // Place borrow orders
                console2.log(unicode"\n📉 Placing Borrow Orders");
                vm.startBroadcast(borrowerKey);
                for (uint256 k = 0; k < borrowRates.length; k++) {
                    MockToken(collaterals[i]).approve(address(router), collateralAmounts[i]);
                    router.placeOrder(
                        address(usdc),
                        collaterals[i],
                        USDC_AMOUNT,
                        collateralAmounts[i],
                        borrowRates[k],
                        block.timestamp + 365 days,
                        maturityMonths[j],
                        maturityYears[j],
                        ILendingCLOB.Side.BORROW
                    );
                    console2.log(
                        "  Rate: %s%%",
                        borrowRates[k] / 1e14 / 100
                    );
                }
                vm.stopBroadcast();
            }
        }

        console2.log(unicode"\n✅ Mock Market Data Generation Complete!");
    }
} 