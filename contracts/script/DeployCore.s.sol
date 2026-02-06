// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {kdioDeployer} from "../src/kdioDeployer.sol";
import {khaaliSplitFriends} from "../src/khaaliSplitFriends.sol";
import {khaaliSplitGroups} from "../src/khaaliSplitGroups.sol";
import {khaaliSplitExpenses} from "../src/khaaliSplitExpenses.sol";
import {khaaliSplitResolver} from "../src/khaaliSplitResolver.sol";

/**
 * @title DeployCore
 * @notice Deploys all core khaaliSplit contracts to Sepolia via kdioDeployer (CREATE2).
 *
 * @dev Required environment variables:
 *   - DEPLOYER_PRIVATE_KEY: Private key for the deployer EOA
 *   - BACKEND_ADDRESS: Backend/relayer address for khaaliSplitFriends
 *   - GATEWAY_URL: CCIP-Read gateway URL template
 *   - GATEWAY_SIGNER: Trusted signer address for the resolver gateway
 *   - OWNER_ADDRESS: Contract owner (for upgrades)
 *
 * Usage:
 *   forge script script/DeployCore.s.sol:DeployCore --rpc-url sepolia --broadcast --verify
 */
contract DeployCore is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address backendAddress = vm.envAddress("BACKEND_ADDRESS");
        string memory gatewayUrl = vm.envString("GATEWAY_URL");
        address gatewaySigner = vm.envAddress("GATEWAY_SIGNER");
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. Deploy kdioDeployer ──
        kdioDeployer factory = new kdioDeployer();
        console.log("kdioDeployer:", address(factory));

        // ── 2. Deploy implementations ──
        khaaliSplitFriends friendsImpl = new khaaliSplitFriends();
        console.log("khaaliSplitFriends impl:", address(friendsImpl));

        khaaliSplitGroups groupsImpl = new khaaliSplitGroups();
        console.log("khaaliSplitGroups impl:", address(groupsImpl));

        khaaliSplitExpenses expensesImpl = new khaaliSplitExpenses();
        console.log("khaaliSplitExpenses impl:", address(expensesImpl));

        khaaliSplitResolver resolverImpl = new khaaliSplitResolver();
        console.log("khaaliSplitResolver impl:", address(resolverImpl));

        // ── 3. Deploy proxies via CREATE2 ──

        // Friends proxy
        bytes memory friendsInitData = abi.encodeCall(
            khaaliSplitFriends.initialize,
            (backendAddress, ownerAddress)
        );
        address friendsProxy = factory.deploy(
            keccak256("khaaliSplitFriends-v1"),
            address(friendsImpl),
            friendsInitData
        );
        console.log("khaaliSplitFriends proxy:", friendsProxy);

        // Groups proxy
        bytes memory groupsInitData = abi.encodeCall(
            khaaliSplitGroups.initialize,
            (friendsProxy, ownerAddress)
        );
        address groupsProxy = factory.deploy(
            keccak256("khaaliSplitGroups-v1"),
            address(groupsImpl),
            groupsInitData
        );
        console.log("khaaliSplitGroups proxy:", groupsProxy);

        // Expenses proxy
        bytes memory expensesInitData = abi.encodeCall(
            khaaliSplitExpenses.initialize,
            (groupsProxy, ownerAddress)
        );
        address expensesProxy = factory.deploy(
            keccak256("khaaliSplitExpenses-v1"),
            address(expensesImpl),
            expensesInitData
        );
        console.log("khaaliSplitExpenses proxy:", expensesProxy);

        // Resolver proxy
        address[] memory resolverSigners = new address[](1);
        resolverSigners[0] = gatewaySigner;
        bytes memory resolverInitData = abi.encodeCall(
            khaaliSplitResolver.initialize,
            (gatewayUrl, resolverSigners, ownerAddress)
        );
        address resolverProxy = factory.deploy(
            keccak256("khaaliSplitResolver-v1"),
            address(resolverImpl),
            resolverInitData
        );
        console.log("khaaliSplitResolver proxy:", resolverProxy);

        vm.stopBroadcast();

        // ── Summary ──
        console.log("\n=== Deployment Summary ===");
        console.log("Factory:   ", address(factory));
        console.log("Friends:   ", friendsProxy);
        console.log("Groups:    ", groupsProxy);
        console.log("Expenses:  ", expensesProxy);
        console.log("Resolver:  ", resolverProxy);
    }
}
