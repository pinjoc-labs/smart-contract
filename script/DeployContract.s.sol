// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {LendingPoolManager} from "../src/LendingPoolManager.sol";
import {LendingCLOBManager} from "../src/LendingCLOBManager.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {PinjocLendingRouter} from "../src/PinjocLendingRouter.sol";

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployContract is Script {
    function run() public {
        // Get deployer private key from environment
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        console2.log("\n=== DEPLOYMENT STARTED ===");

        // Deploy Mock Tokens
        console2.log("Deploying Mock Tokens...");
        MockToken musdc = new MockToken("Mock USDC", "MUSDC", 6); // USDC
        console2.log("Mock USDC deployed at: %s", address(musdc));

        MockToken[5] memory collaterals = [
            new MockToken("Mock WETH", "MWETH", 18), // WETH
            new MockToken("Mock WBTC", "MWBTC", 8),  // WBTC
            new MockToken("Mock WSOL", "MWSOL", 18), // SOL
            new MockToken("Mock WLINK", "MWLINK", 18), // LINK
            new MockToken("Mock WAAVE", "MWAAVE", 18)  // AAVE
        ];

        for (uint256 i = 0; i < collaterals.length; i++) {
            console2.log(
                "%s deployed at: %s",
                IERC20Metadata(address(collaterals[i])).symbol(),
                address(collaterals[i])
            );
        }

        // Deploy Mock Oracles
        console2.log("\nDeploying Mock Oracles...");
        MockOracle[5] memory oracles;
        uint40[5] memory prices = [2500e6, 90000e6, 200e6, 15e6, 200e6];

        for (uint256 i = 0; i < collaterals.length; i++) {
            oracles[i] = new MockOracle(
                address(collaterals[i]),
                address(musdc)
            );
            oracles[i].setPrice(prices[i]);
            console2.log(
                "MockOracle for %s deployed at: %s",
                collaterals[i].symbol(),
                address(oracles[i])
            );
        }

        // Deploy LendingCLOBManager
        console2.log("\nDeploying LendingCLOBManager...");
        LendingCLOBManager lendingCLOBManager = new LendingCLOBManager(owner);
        console2.log(
            "LendingCLOBManager deployed at: %s",
            address(lendingCLOBManager)
        );

        // Deploy LendingPoolManager
        console2.log("\nDeploying LendingPoolManager...");
        LendingPoolManager lendingPoolManager = new LendingPoolManager(owner);
        console2.log(
            "LendingPoolManager deployed at: %s",
            address(lendingPoolManager)
        );

        // Set Oracle on LendingPoolManager
        console2.log("\nSetting Oracle on LendingPoolManager...");
        for (uint256 i = 0; i < collaterals.length; i++) {
            lendingPoolManager.setOracle(address(oracles[i]), address(musdc), address(collaterals[i]));
            console2.log(
                "Oracle for %s set on LendingPoolManager",
                collaterals[i].symbol()
            );
        }

        // Deploy PinjocLendingRouter
        console2.log("\nDeploying PinjocLendingRouter...");
        PinjocLendingRouter pinjocRouter = new PinjocLendingRouter(address(lendingCLOBManager), address(lendingPoolManager));
        console2.log(
            "PinjocLendingRouter deployed at: %s",
            address(pinjocRouter)
        );

        // Set Router on LendingCLOBManager
        console2.log("\nSetting Router on LendingCLOBManager...");
        lendingCLOBManager.transferOwnership(address(pinjocRouter));
        console2.log("Router set on LendingCLOBManager");

        // Set Router on LendingPoolManager
        console2.log("\nSetting Router on LendingPoolManager...");
        lendingPoolManager.setRouter(address(pinjocRouter));
        console2.log("Router set on LendingPoolManager");

        console2.log("\n=== DEPLOYMENT COMPLETED ===");

        vm.stopBroadcast();

        // Append deployed contract addresses to .env file
        string memory deploymentInfo = string.concat(
            "\n# Deployed contract addresses\n",
            "USDC=", vm.toString(address(musdc)), "\n",
            "WETH=", vm.toString(address(collaterals[0])), "\n",
            "WBTC=", vm.toString(address(collaterals[1])), "\n",
            "WSOL=", vm.toString(address(collaterals[2])), "\n",
            "WLINK=", vm.toString(address(collaterals[3])), "\n",
            "WAAVE=", vm.toString(address(collaterals[4])), "\n",
            "LENDING_CLOB_MANAGER=", vm.toString(address(lendingCLOBManager)), "\n",
            "LENDING_POOL_MANAGER=", vm.toString(address(lendingPoolManager)), "\n",
            "PINJOC_ROUTER=", vm.toString(address(pinjocRouter)), "\n"
        );

        vm.writeFile(".env", string.concat(vm.readFile(".env"), deploymentInfo));
        console2.log("Appended contract addresses to .env file");
    }
}
