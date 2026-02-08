// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {kdioDeployer} from "../src/kdioDeployer.sol";
import {khaaliSplitSettlement} from "../src/khaaliSplitSettlement.sol";
import {khaaliSplitReputation} from "../src/khaaliSplitReputation.sol";

/**
 * @title DeploySettlement
 * @notice Deploys khaaliSplitSettlement to any chain via kdioDeployer (CREATE2).
 *         Reads token addresses from `script/tokens.json` and CCTP / Gateway config
 *         from `script/cctp.json`, both keyed by chain ID.
 *         Reads Subnames/Reputation proxy addresses from `deployments.json` (written by DeployCore).
 *         Writes deployment addresses to `deployments-settlement-tmp.json`;
 *         use `deploy-settlement.sh` to merge into `deployments.json`.
 *
 * @dev Required environment variables:
 *   - DEPLOYER_PRIVATE_KEY: Private key for the deployer EOA
 *   - OWNER_ADDRESS: Contract owner (admin)
 *   - NETWORK_TYPE: "testnet" or "mainnet" (selects CCTP / Gateway addresses)
 *
 *   Reads from deployments.json (Sepolia chain only):
 *   - proxy.khaaliSplitSubnames  -> settlement.setSubnameRegistry()
 *   - proxy.khaaliSplitReputation -> settlement.setReputationContract()
 *   Also wires reputation.setSettlementContract() on Sepolia.
 *
 * Usage (per chain, or use deploy-settlement.sh for all chains):
 *   NETWORK_TYPE=testnet forge script script/DeploySettlement.s.sol:DeploySettlement \
 *     --rpc-url sepolia --broadcast --verify
 */
contract DeploySettlement is Script {

    // Sepolia chain ID - where core contracts (Subnames/Reputation) live
    uint256 constant SEPOLIA_CHAIN_ID = 11155111;

    struct Settlement {
        address factory;
        address impl;
        address proxy;
        address usdc;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");

        Settlement memory s;

        // ── Read token config for current chain ──
        {
            string memory json = vm.readFile("script/tokens.json");
            string memory cid = vm.toString(block.chainid);
            s.usdc = vm.parseJsonAddress(json, string.concat(".", cid, ".tokens.USDC"));
        }

        console.log("Chain ID:", block.chainid);
        console.log("USDC:    ", s.usdc);

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. Deploy kdioDeployer ──
        kdioDeployer factory = new kdioDeployer();
        s.factory = address(factory);
        console.log("kdioDeployer:", s.factory);

        // ── 2. Deploy implementation ──
        s.impl = address(new khaaliSplitSettlement());
        console.log("khaaliSplitSettlement impl:", s.impl);

        // ── 3. Deploy proxy via CREATE2 with EMPTY initData ──
        bytes32 salt = keccak256("khaaliSplitSettlement-v1");
        s.proxy = factory.deploy(salt, s.impl, "");
        console.log("khaaliSplitSettlement proxy:", s.proxy);

        // ── 4. Initialize ──
        khaaliSplitSettlement proxy = khaaliSplitSettlement(s.proxy);
        proxy.initialize(ownerAddress);

        // ── 5. Add allowed token ──
        if (s.usdc != address(0)) {
            proxy.addToken(s.usdc);
            console.log("Added USDC:", s.usdc);
        }

        // ── 6. Configure CCTP, Gateway, domains ──
        _configureSettlement(proxy);

        // ── 7. Wire companion contracts from deployments.json (Sepolia only) ──
        _wireCompanionContracts(proxy);

        vm.stopBroadcast();

        _writeDeployments(s);

        // ── Summary ──
        address predicted = factory.computeAddress(salt, s.impl, "");
        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:   ", block.chainid);
        console.log("Factory:    ", s.factory);
        console.log("Settlement: ", s.proxy);
        console.log("Predicted:  ", predicted);
        console.log("Match:      ", s.proxy == predicted);
        console.log("\nWritten to deployments-settlement-tmp.json");
    }

    /// @dev Read cctp.json and configure CCTP/Gateway addresses + domain mappings.
    function _configureSettlement(khaaliSplitSettlement proxy) internal {
        string memory networkType = vm.envString("NETWORK_TYPE");
        console.log("Network: ", networkType);

        string memory cctpJson = vm.readFile("script/cctp.json");

        // ── TokenMessenger ──
        address tokenMessengerAddr = vm.parseJsonAddress(
            cctpJson,
            string.concat(".tokenMessenger.", networkType)
        );
        if (tokenMessengerAddr != address(0)) {
            proxy.setTokenMessenger(tokenMessengerAddr);
            console.log("Set TokenMessenger:", tokenMessengerAddr);
        }

        // ── GatewayWallet ──
        address gatewayWalletAddr = vm.parseJsonAddress(
            cctpJson,
            string.concat(".gatewayWallet.", networkType)
        );
        if (gatewayWalletAddr != address(0)) {
            proxy.setGatewayWallet(gatewayWalletAddr);
            console.log("Set GatewayWallet:", gatewayWalletAddr);
        }

        // ── GatewayMinter ──
        address gatewayMinterAddr = vm.parseJsonAddress(
            cctpJson,
            string.concat(".gatewayMinter.", networkType)
        );
        if (gatewayMinterAddr != address(0)) {
            proxy.setGatewayMinter(gatewayMinterAddr);
            console.log("Set GatewayMinter:", gatewayMinterAddr);
        }

        // ── CCTP domains ──
        _configureDomains(proxy, cctpJson);
    }

    /// @dev Configure CCTP domain mappings from cctp.json.
    function _configureDomains(khaaliSplitSettlement proxy, string memory cctpJson) internal {
        // All known chain IDs (testnet + mainnet)
        uint256[6] memory chainIds = [
            uint256(11155111), // Sepolia
            84532,            // Base Sepolia
            421614,           // Arbitrum Sepolia
            11155420,         // Optimism Sepolia
            1,                // Ethereum
            8453              // Base
        ];

        for (uint256 i = 0; i < chainIds.length; i++) {
            string memory domainKey = string.concat(
                ".domains.",
                vm.toString(chainIds[i]),
                ".domain"
            );

            try vm.parseJsonUint(cctpJson, domainKey) returns (uint256 domain) {
                proxy.configureDomain(chainIds[i], uint32(domain));
                console.log("Configured domain for chain", chainIds[i], "->", uint32(domain));
            } catch {
                // Domain not configured for this chain, skip
            }
        }
    }

    /// @dev Read Subnames/Reputation proxy addresses from deployments.json and wire them.
    ///      Only applies on Sepolia (where core contracts are deployed).
    function _wireCompanionContracts(khaaliSplitSettlement proxy) internal {
        if (block.chainid != SEPOLIA_CHAIN_ID) {
            console.log("Not Sepolia - skipping companion contract wiring");
            return;
        }

        string memory deploymentsPath = string.concat(vm.projectRoot(), "/deployments.json");

        try vm.readFile(deploymentsPath) returns (string memory json) {
            string memory sepoliaKey = string.concat(".", vm.toString(SEPOLIA_CHAIN_ID));

            // Read Subnames proxy
            try vm.parseJsonAddress(json, string.concat(sepoliaKey, ".proxy.khaaliSplitSubnames")) returns (
                address subnamesProxy
            ) {
                if (subnamesProxy != address(0)) {
                    proxy.setSubnameRegistry(subnamesProxy);
                    console.log("Set SubnameRegistry from deployments.json:", subnamesProxy);
                }
            } catch {
                console.log("WARNING: khaaliSplitSubnames not found in deployments.json");
            }

            // Read Reputation proxy
            try vm.parseJsonAddress(json, string.concat(sepoliaKey, ".proxy.khaaliSplitReputation")) returns (
                address reputationProxy
            ) {
                if (reputationProxy != address(0)) {
                    proxy.setReputationContract(reputationProxy);
                    console.log("Set ReputationContract from deployments.json:", reputationProxy);

                    // Also wire Settlement into Reputation
                    khaaliSplitReputation(reputationProxy).setSettlementContract(address(proxy));
                    console.log("Wired: Reputation -> Settlement");
                }
            } catch {
                console.log("WARNING: khaaliSplitReputation not found in deployments.json");
            }
        } catch {
            console.log("WARNING: deployments.json not found - skipping companion wiring");
            console.log("  Run DeployCore first, then re-deploy Settlement on Sepolia");
        }
    }

    /// @dev Write deployment addresses to temp JSON file for shell script merging.
    function _writeDeployments(Settlement memory s) internal {
        string memory tokensObj = "tokens";
        string memory tokensJson = vm.serializeAddress(tokensObj, "USDC", s.usdc);

        string memory setObj = "settlement";
        vm.serializeAddress(setObj, "kdioDeployer", s.factory);
        vm.serializeAddress(setObj, "impl", s.impl);
        vm.serializeAddress(setObj, "proxy", s.proxy);
        string memory setJson = vm.serializeString(setObj, "tokens", tokensJson);

        string memory chainObj = "chain";
        string memory chainJson = vm.serializeString(chainObj, "settlement", setJson);

        string memory root = "root";
        string memory chainId = vm.toString(block.chainid);
        string memory rootJson = vm.serializeString(root, chainId, chainJson);

        // Write to temp file; deploy-settlement.sh merges into deployments.json via jq
        vm.writeJson(rootJson, string.concat(vm.projectRoot(), "/deployments-settlement-tmp.json"));
    }
}
