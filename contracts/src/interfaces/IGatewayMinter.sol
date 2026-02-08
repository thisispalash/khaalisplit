// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IGatewayMinter
 * @notice Minimal interface for Circle's Gateway Minter contract.
 *         Used by khaaliSplitSettlement to mint USDC on the destination chain
 *         from a signed attestation (obtained via Circle's Gateway API).
 *
 * @dev The real GatewayMinter (0x0022222ABE238Cc2C7Bb1f21003F0a260052475B, same
 *      on all chains via CREATE2) mints USDC to the `destinationRecipient` specified
 *      in the attestation payload. It does NOT execute hookData or call back into
 *      the recipient — our settlement contract handles all post-mint logic.
 */
interface IGatewayMinter {
    /// @notice Mint USDC on this chain from a signed attestation.
    /// @param attestationPayload The attestation payload from Circle's Gateway API.
    /// @param signature The attestation signature from Circle's Gateway API.
    function gatewayMint(
        bytes memory attestationPayload,
        bytes memory signature
    ) external;
}
