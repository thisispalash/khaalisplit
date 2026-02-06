// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {kdioDeployer} from "../src/kdioDeployer.sol";
import {khaaliSplitSettlement} from "../src/khaaliSplitSettlement.sol";

/**
 * @title DeploySettlement
 * @notice Deploys khaaliSplitSettlement to any chain via kdioDeployer (CREATE2).
 *         Reads allowed token addresses from `script/tokens.json` keyed by chain ID.
 *
 * @dev Required environment variables:
 *   - DEPLOYER_PRIVATE_KEY: Private key for the deployer EOA
 *   - OWNER_ADDRESS: Contract owner (relayer)
 *
 *   Token config: `script/tokens.json` — keyed by chain ID, e.g.:
 *   {
 *     "11155111": { "name": "sepolia", "tokens": { "USDC": "0x...", "EURC": "0x..." } },
 *     "8453":     { "name": "base",    "tokens": { "USDC": "0x...", "EURC": "0x..." } }
 *   }
 *
 * Usage:
 *   forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url sepolia --broadcast
 *   forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url base --broadcast
 */
contract DeploySettlement is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");

        // ── Read token config for current chain ──
        string memory json = vm.readFile("script/tokens.json");
        string memory chainIdStr = vm.toString(block.chainid);

        string memory usdcKey = string.concat(".", chainIdStr, ".tokens.USDC");
        string memory eurcKey = string.concat(".", chainIdStr, ".tokens.EURC");

        address usdcAddress = vm.parseJsonAddress(json, usdcKey);
        address eurcAddress = vm.parseJsonAddress(json, eurcKey);

        console.log("Chain ID:", block.chainid);
        console.log("USDC:    ", usdcAddress);
        console.log("EURC:    ", eurcAddress);

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. Deploy kdioDeployer ──
        kdioDeployer factory = new kdioDeployer();
        console.log("kdioDeployer:", address(factory));

        // ── 2. Deploy implementation ──
        khaaliSplitSettlement impl = new khaaliSplitSettlement();
        console.log("khaaliSplitSettlement impl:", address(impl));

        // ── 3. Deploy proxy via CREATE2 with EMPTY initData ──
        bytes32 salt = keccak256("khaaliSplitSettlement-v1");
        address proxyAddr = factory.deploy(salt, address(impl), "");
        console.log("khaaliSplitSettlement proxy:", proxyAddr);

        // ── 4. Initialize ──
        khaaliSplitSettlement proxy = khaaliSplitSettlement(proxyAddr);
        proxy.initialize(ownerAddress);

        // ── 5. Add allowed tokens (skip zero addresses) ──
        if (usdcAddress != address(0)) {
            proxy.addToken(usdcAddress);
            console.log("Added USDC:", usdcAddress);
        }

        if (eurcAddress != address(0)) {
            proxy.addToken(eurcAddress);
            console.log("Added EURC:", eurcAddress);
        }

        vm.stopBroadcast();

        // ── Verify ──
        address predicted = factory.computeAddress(salt, address(impl), "");
        console.log("\n=== Deployment Summary ===");
        console.log("Factory:    ", address(factory));
        console.log("Settlement: ", proxyAddr);
        console.log("Predicted:  ", predicted);
        console.log("Match:      ", proxyAddr == predicted);
    }
}
