// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {kdioDeployer} from "../src/kdioDeployer.sol";
import {khaaliSplitSettlement} from "../src/khaaliSplitSettlement.sol";

/**
 * @title DeploySettlement
 * @notice Deploys khaaliSplitSettlement to any chain via kdioDeployer (CREATE2).
 *         Uses empty initData for deterministic proxy address, then initializes
 *         separately and adds allowed tokens (USDC, EURC).
 *
 * @dev Required environment variables:
 *   - DEPLOYER_PRIVATE_KEY: Private key for the deployer EOA
 *   - USDC_ADDRESS: USDC token address on the target chain
 *   - EURC_ADDRESS: EURC token address on the target chain
 *   - OWNER_ADDRESS: Contract owner (relayer)
 *
 * Usage:
 *   USDC_ADDRESS=0x... EURC_ADDRESS=0x... \
 *     forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url sepolia --broadcast
 */
contract DeploySettlement is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address eurcAddress = vm.envAddress("EURC_ADDRESS");
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. Deploy kdioDeployer (or reuse existing) ──
        kdioDeployer factory = new kdioDeployer();
        console.log("kdioDeployer:", address(factory));

        // ── 2. Deploy implementation ──
        khaaliSplitSettlement impl = new khaaliSplitSettlement();
        console.log("khaaliSplitSettlement impl:", address(impl));

        // ── 3. Deploy proxy via CREATE2 with EMPTY initData ──
        // This ensures the proxy address is deterministic regardless of
        // chain-specific token addresses.
        bytes32 salt = keccak256("khaaliSplitSettlement-v1");
        address proxyAddr = factory.deploy(salt, address(impl), "");
        console.log("khaaliSplitSettlement proxy:", proxyAddr);

        // ── 4. Initialize ──
        khaaliSplitSettlement proxy = khaaliSplitSettlement(proxyAddr);
        proxy.initialize(ownerAddress);

        // ── 5. Add allowed tokens ──
        proxy.addToken(usdcAddress);
        console.log("Added USDC:", usdcAddress);

        proxy.addToken(eurcAddress);
        console.log("Added EURC:", eurcAddress);

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
