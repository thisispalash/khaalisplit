// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {kdioDeployer} from "../src/kdioDeployer.sol";
import {khaaliSplitSettlement} from "../src/khaaliSplitSettlement.sol";

/**
 * @title DeploySettlement
 * @notice Deploys khaaliSplitSettlement to any chain via kdioDeployer (CREATE2).
 *         Uses empty initData for deterministic proxy address, then initializes
 *         separately with chain-specific USDC address.
 *
 * @dev Required environment variables:
 *   - DEPLOYER_PRIVATE_KEY: Private key for the deployer EOA
 *   - USDC_ADDRESS: USDC token address on the target chain
 *   - OWNER_ADDRESS: Contract owner (relayer)
 *   - DEPLOYER_ADDRESS: Address of the kdioDeployer factory (if already deployed)
 *
 * Usage:
 *   # Deploy factory + settlement on Sepolia
 *   USDC_ADDRESS=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 \
 *     forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url sepolia --broadcast
 *
 *   # Deploy settlement on other chains (reuse factory or deploy new one)
 *   USDC_ADDRESS=0x... forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url base --broadcast
 */
contract DeploySettlement is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. Deploy kdioDeployer (or reuse existing) ──
        // For cross-chain determinism, the same deployer contract must exist at
        // the same address on every chain. In production, you'd use a
        // pre-determined deployer address. For now, we deploy fresh.
        kdioDeployer factory = new kdioDeployer();
        console.log("kdioDeployer:", address(factory));

        // ── 2. Deploy implementation ──
        khaaliSplitSettlement impl = new khaaliSplitSettlement();
        console.log("khaaliSplitSettlement impl:", address(impl));

        // ── 3. Deploy proxy via CREATE2 with EMPTY initData ──
        // This ensures the proxy address is deterministic regardless of chain-specific
        // USDC address. The same salt + same impl bytecode + empty initData
        // → same proxy address on every chain.
        bytes32 salt = keccak256("khaaliSplitSettlement-v1");
        address proxyAddr = factory.deploy(salt, address(impl), "");
        console.log("khaaliSplitSettlement proxy:", proxyAddr);

        // ── 4. Initialize with chain-specific params ──
        khaaliSplitSettlement proxy = khaaliSplitSettlement(proxyAddr);
        proxy.initialize(usdcAddress, ownerAddress);
        console.log("Initialized with USDC:", usdcAddress);

        vm.stopBroadcast();

        // ── Predict address for verification ──
        address predicted = factory.computeAddress(salt, address(impl), "");
        console.log("\n=== Deployment Summary ===");
        console.log("Factory:    ", address(factory));
        console.log("Settlement: ", proxyAddr);
        console.log("Predicted:  ", predicted);
        console.log("Match:      ", proxyAddr == predicted);
    }
}
