// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title kdioDeployer
 * @notice Custom CREATE2 deployer for khaaliSplit. Deploys ERC1967Proxy
 *         instances at deterministic addresses across chains.
 *
 * @dev How it works:
 *   1. Deploy the implementation contract at any address (not deterministic).
 *   2. Call `deploy(salt, implementation, initData)` on this factory.
 *   3. A new ERC1967Proxy is deployed via CREATE2 with the given salt.
 *   4. If `initData` is provided, it's passed to the proxy constructor
 *      (which delegates to the implementation).
 *
 *   For truly identical addresses across chains (e.g., khaaliSplitSettlement),
 *   deploy with EMPTY initData, then call `initialize()` on the proxy separately.
 *   This ensures the CREATE2 init_code hash is identical regardless of
 *   chain-specific constructor args.
 *
 *   This contract is NOT upgradeable — it's a stateless factory.
 */
contract kdioDeployer {
    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event Deployed(address indexed proxy, bytes32 indexed salt, address indexed implementation);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error DeploymentFailed();

    // ──────────────────────────────────────────────
    //  Deploy
    // ──────────────────────────────────────────────

    /**
     * @notice Deploys an ERC1967Proxy via CREATE2.
     * @param salt           Unique salt for deterministic address.
     * @param implementation The UUPS implementation address.
     * @param initData       Encoded initializer call (can be empty for deferred init).
     * @return proxy         The deployed proxy address.
     */
    function deploy(
        bytes32 salt,
        address implementation,
        bytes memory initData
    ) external returns (address proxy) {
        proxy = address(
            new ERC1967Proxy{salt: salt}(implementation, initData)
        );

        if (proxy == address(0)) revert DeploymentFailed();

        emit Deployed(proxy, salt, implementation);
    }

    // ──────────────────────────────────────────────
    //  Compute address
    // ──────────────────────────────────────────────

    /**
     * @notice Computes the deterministic address for a proxy that would be
     *         deployed with the given parameters.
     * @param salt           Unique salt.
     * @param implementation The UUPS implementation address.
     * @param initData       Encoded initializer call (must match deploy call).
     * @return The predicted proxy address.
     */
    function computeAddress(
        bytes32 salt,
        address implementation,
        bytes memory initData
    ) external view returns (address) {
        bytes memory creationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(creationCode)
            )
        );

        return address(uint160(uint256(hash)));
    }
}
