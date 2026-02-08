// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {kdioDeployer} from "../src/kdioDeployer.sol";
import {khaaliSplitFriends} from "../src/khaaliSplitFriends.sol";
import {khaaliSplitGroups} from "../src/khaaliSplitGroups.sol";
import {khaaliSplitExpenses} from "../src/khaaliSplitExpenses.sol";
import {khaaliSplitResolver} from "../src/khaaliSplitResolver.sol";
import {khaaliSplitSubnames} from "../src/khaaliSplitSubnames.sol";
import {khaaliSplitReputation} from "../src/khaaliSplitReputation.sol";

/**
 * @title DeployCore
 * @notice Deploys all khaaliSplit contracts to Sepolia via kdioDeployer (CREATE2):
 *         Friends, Groups, Expenses, Resolver, Subnames, and Reputation.
 *         Writes deployment addresses to `deployments.json` under `<chainId>`.
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

    // ── ENS constants (Sepolia) ──
    // NameWrapper: https://docs.ens.domains/learn/deployments
    address constant NAME_WRAPPER_SEPOLIA = 0x0635513f179D50A207757E05759CbD106d7dFcE8;
    // namehash("khaalisplit.eth")
    bytes32 constant PARENT_NODE = keccak256(
        abi.encodePacked(
            // namehash("eth")
            bytes32(0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae),
            keccak256("khaalisplit")
        )
    );

    struct Deployment {
        address factory;
        // implementations
        address friendsImpl;
        address groupsImpl;
        address expensesImpl;
        address resolverImpl;
        address subnamesImpl;
        address reputationImpl;
        // proxies
        address friendsProxy;
        address groupsProxy;
        address expensesProxy;
        address resolverProxy;
        address subnamesProxy;
        address reputationProxy;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address backendAddress = vm.envAddress("BACKEND_ADDRESS");
        string memory gatewayUrl = vm.envString("GATEWAY_URL");
        address gatewaySigner = vm.envAddress("GATEWAY_SIGNER");
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");

        Deployment memory d;

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. Deploy kdioDeployer ──
        kdioDeployer factory = new kdioDeployer();
        d.factory = address(factory);
        console.log("kdioDeployer:", d.factory);

        // ── 2. Deploy implementations ──
        d.friendsImpl = address(new khaaliSplitFriends());
        console.log("khaaliSplitFriends impl:", d.friendsImpl);

        d.groupsImpl = address(new khaaliSplitGroups());
        console.log("khaaliSplitGroups impl:", d.groupsImpl);

        d.expensesImpl = address(new khaaliSplitExpenses());
        console.log("khaaliSplitExpenses impl:", d.expensesImpl);

        d.resolverImpl = address(new khaaliSplitResolver());
        console.log("khaaliSplitResolver impl:", d.resolverImpl);

        d.subnamesImpl = address(new khaaliSplitSubnames());
        console.log("khaaliSplitSubnames impl:", d.subnamesImpl);

        d.reputationImpl = address(new khaaliSplitReputation());
        console.log("khaaliSplitReputation impl:", d.reputationImpl);

        // ── 3. Deploy proxies via CREATE2 ──

        // Friends proxy
        d.friendsProxy = factory.deploy(
            keccak256("khaaliSplitFriends-v1"),
            d.friendsImpl,
            abi.encodeCall(khaaliSplitFriends.initialize, (backendAddress, ownerAddress))
        );
        console.log("khaaliSplitFriends proxy:", d.friendsProxy);

        // Groups proxy
        d.groupsProxy = factory.deploy(
            keccak256("khaaliSplitGroups-v1"),
            d.groupsImpl,
            abi.encodeCall(khaaliSplitGroups.initialize, (d.friendsProxy, ownerAddress))
        );
        console.log("khaaliSplitGroups proxy:", d.groupsProxy);

        // Expenses proxy
        d.expensesProxy = factory.deploy(
            keccak256("khaaliSplitExpenses-v1"),
            d.expensesImpl,
            abi.encodeCall(khaaliSplitExpenses.initialize, (d.groupsProxy, ownerAddress))
        );
        console.log("khaaliSplitExpenses proxy:", d.expensesProxy);

        // Resolver proxy
        {
            address[] memory resolverSigners = new address[](1);
            resolverSigners[0] = gatewaySigner;
            d.resolverProxy = factory.deploy(
                keccak256("khaaliSplitResolver-v1"),
                d.resolverImpl,
                abi.encodeCall(khaaliSplitResolver.initialize, (gatewayUrl, resolverSigners, ownerAddress))
            );
        }
        console.log("khaaliSplitResolver proxy:", d.resolverProxy);

        // Subnames proxy
        d.subnamesProxy = factory.deploy(
            keccak256("khaaliSplitSubnames-v1"),
            d.subnamesImpl,
            abi.encodeCall(
                khaaliSplitSubnames.initialize,
                (NAME_WRAPPER_SEPOLIA, PARENT_NODE, backendAddress, ownerAddress)
            )
        );
        console.log("khaaliSplitSubnames proxy:", d.subnamesProxy);

        // Reputation proxy (settlementContract = address(0), set later after DeploySettlement)
        d.reputationProxy = factory.deploy(
            keccak256("khaaliSplitReputation-v1"),
            d.reputationImpl,
            abi.encodeCall(
                khaaliSplitReputation.initialize,
                (backendAddress, d.subnamesProxy, address(0), ownerAddress)
            )
        );
        console.log("khaaliSplitReputation proxy:", d.reputationProxy);

        // ── 4. Cross-wire: Subnames <-> Reputation ──
        khaaliSplitSubnames(d.subnamesProxy).setReputationContract(d.reputationProxy);
        console.log("Wired: Subnames -> Reputation");

        vm.stopBroadcast();

        _writeDeployments(d);

        // ── Summary ──
        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:    ", block.chainid);
        console.log("Factory:     ", d.factory);
        console.log("Friends:     ", d.friendsProxy);
        console.log("Groups:      ", d.groupsProxy);
        console.log("Expenses:    ", d.expensesProxy);
        console.log("Resolver:    ", d.resolverProxy);
        console.log("Subnames:    ", d.subnamesProxy);
        console.log("Reputation:  ", d.reputationProxy);
        console.log("\nWritten to deployments.json");
        console.log("NOTE: After deploying Settlement, wire it via:");
        console.log("  reputation.setSettlementContract(settlementProxy)");
        console.log("  settlement.setSubnameRegistry(subnamesProxy)");
        console.log("  settlement.setReputationContract(reputationProxy)");
    }

    function _writeDeployments(Deployment memory d) internal {
        string memory implObj = "impl";
        vm.serializeAddress(implObj, "khaaliSplitFriends", d.friendsImpl);
        vm.serializeAddress(implObj, "khaaliSplitGroups", d.groupsImpl);
        vm.serializeAddress(implObj, "khaaliSplitExpenses", d.expensesImpl);
        vm.serializeAddress(implObj, "khaaliSplitResolver", d.resolverImpl);
        vm.serializeAddress(implObj, "khaaliSplitSubnames", d.subnamesImpl);
        string memory implJson = vm.serializeAddress(implObj, "khaaliSplitReputation", d.reputationImpl);

        string memory proxyObj = "proxy";
        vm.serializeAddress(proxyObj, "khaaliSplitFriends", d.friendsProxy);
        vm.serializeAddress(proxyObj, "khaaliSplitGroups", d.groupsProxy);
        vm.serializeAddress(proxyObj, "khaaliSplitExpenses", d.expensesProxy);
        vm.serializeAddress(proxyObj, "khaaliSplitResolver", d.resolverProxy);
        vm.serializeAddress(proxyObj, "khaaliSplitSubnames", d.subnamesProxy);
        string memory proxyJson = vm.serializeAddress(proxyObj, "khaaliSplitReputation", d.reputationProxy);

        string memory chainObj = "chain";
        vm.serializeAddress(chainObj, "kdioDeployer", d.factory);
        vm.serializeString(chainObj, "impl", implJson);
        string memory chainJson = vm.serializeString(chainObj, "proxy", proxyJson);

        string memory root = "root";
        string memory chainId = vm.toString(block.chainid);
        string memory rootJson = vm.serializeString(root, chainId, chainJson);

        vm.writeJson(rootJson, string.concat(vm.projectRoot(), "/deployments.json"));
    }
}
