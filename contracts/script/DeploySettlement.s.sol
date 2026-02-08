// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {kdioDeployer} from "../src/kdioDeployer.sol";
import {khaaliSplitSettlement} from "../src/khaaliSplitSettlement.sol";

/**
 * @title DeploySettlement
 * @notice Deploys khaaliSplitSettlement to any chain via kdioDeployer (CREATE2).
 *         Reads token addresses from `script/tokens.json` and CCTP / Gateway config
 *         from `script/cctp.json`, both keyed by chain ID.
 *
 * @dev Required environment variables:
 *   - DEPLOYER_PRIVATE_KEY: Private key for the deployer EOA
 *   - OWNER_ADDRESS: Contract owner (admin)
 *   - NETWORK_TYPE: "testnet" or "mainnet" (selects CCTP / Gateway addresses)
 *
 *   Optional environment variables:
 *   - SUBNAME_REGISTRY: Address of the deployed khaaliSplitSubnames contract
 *   - REPUTATION_CONTRACT: Address of the deployed khaaliSplitReputation contract
 *
 * Usage:
 *   NETWORK_TYPE=testnet forge script script/DeploySettlement.s.sol:DeploySettlement \
 *     --rpc-url sepolia --broadcast
 */
contract DeploySettlement is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // ── 1. Deploy factory + implementation + proxy ──
        (kdioDeployer factory, address proxyAddr) = _deployProxy();
        khaaliSplitSettlement proxy = khaaliSplitSettlement(proxyAddr);

        // ── 2. Initialize ──
        proxy.initialize(ownerAddress);

        // ── 3. Configure token, CCTP, Gateway, domains ──
        _configureSettlement(proxy);

        // ── 4. Set optional companion contracts ──
        _setCompanionContracts(proxy);

        vm.stopBroadcast();

        // ── Verify ──
        bytes32 salt = keccak256("khaaliSplitSettlement-v1");
        address predicted = factory.computeAddress(salt, address(khaaliSplitSettlement(proxyAddr)), "");
        console.log("\n=== Deployment Summary ===");
        console.log("Factory:    ", address(factory));
        console.log("Settlement: ", proxyAddr);
        console.log("Predicted:  ", predicted);
        console.log("Match:      ", proxyAddr == predicted);
    }

    /// @dev Deploy kdioDeployer, implementation, and CREATE2 proxy.
    function _deployProxy() internal returns (kdioDeployer factory, address proxyAddr) {
        factory = new kdioDeployer();
        console.log("kdioDeployer:", address(factory));

        khaaliSplitSettlement impl = new khaaliSplitSettlement();
        console.log("khaaliSplitSettlement impl:", address(impl));

        bytes32 salt = keccak256("khaaliSplitSettlement-v1");
        proxyAddr = factory.deploy(salt, address(impl), "");
        console.log("khaaliSplitSettlement proxy:", proxyAddr);
    }

    /// @dev Read config files and configure token + CCTP/Gateway.
    function _configureSettlement(khaaliSplitSettlement proxy) internal {
        string memory networkType = vm.envString("NETWORK_TYPE");
        console.log("Chain ID:", block.chainid);
        console.log("Network: ", networkType);

        // ── Token ──
        string memory tokensJson = vm.readFile("script/tokens.json");
        string memory usdcKey = string.concat(".", vm.toString(block.chainid), ".tokens.USDC");
        address usdcAddress = vm.parseJsonAddress(tokensJson, usdcKey);

        if (usdcAddress != address(0)) {
            proxy.addToken(usdcAddress);
            console.log("Added USDC:", usdcAddress);
        }

        // ── CCTP + Gateway ──
        string memory cctpJson = vm.readFile("script/cctp.json");

        address tokenMessengerAddr = vm.parseJsonAddress(
            cctpJson,
            string.concat(".tokenMessenger.", networkType)
        );
        if (tokenMessengerAddr != address(0)) {
            proxy.setTokenMessenger(tokenMessengerAddr);
            console.log("Set TokenMessenger:", tokenMessengerAddr);
        }

        address gatewayWalletAddr = vm.parseJsonAddress(
            cctpJson,
            string.concat(".gatewayWallet.", networkType)
        );
        if (gatewayWalletAddr != address(0)) {
            proxy.setGatewayWallet(gatewayWalletAddr);
            console.log("Set GatewayWallet:", gatewayWalletAddr);
        }

        // ── CCTP domains ──
        _configureDomains(proxy, cctpJson);
    }

    /// @dev Configure CCTP domain mappings from cctp.json.
    function _configureDomains(khaaliSplitSettlement proxy, string memory cctpJson) internal {
        uint256[4] memory chainIds = [uint256(11155111), 84532, 1, 8453];

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

    /// @dev Set optional companion contracts (subnames, reputation) from env vars.
    function _setCompanionContracts(khaaliSplitSettlement proxy) internal {
        address subnameRegistry = vm.envOr("SUBNAME_REGISTRY", address(0));
        if (subnameRegistry != address(0)) {
            proxy.setSubnameRegistry(subnameRegistry);
            console.log("Set SubnameRegistry:", subnameRegistry);
        }

        address reputationContract = vm.envOr("REPUTATION_CONTRACT", address(0));
        if (reputationContract != address(0)) {
            proxy.setReputationContract(reputationContract);
            console.log("Set ReputationContract:", reputationContract);
        }
    }
}
