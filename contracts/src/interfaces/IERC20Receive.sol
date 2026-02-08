// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IERC20Receive
 * @notice Minimal interface for EIP-3009 receiveWithAuthorization.
 *         Used by khaaliSplitSettlement to pull USDC from a sender
 *         using an off-chain signature (gasless for the sender).
 *
 * @dev EIP-3009: https://eips.ethereum.org/EIPS/eip-3009
 *
 *      Key properties:
 *        - Atomic transfer: no prior approval needed (unlike EIP-2612 permit).
 *        - Random nonces: supports concurrent, independent authorizations.
 *        - Front-running protection: enforces msg.sender == to.
 *        - USDC FiatTokenV2_2 uses `bytes memory signature` (packed r,s,v).
 *
 *      The user signs an EIP-712 typed message:
 *        ReceiveWithAuthorization(
 *            address from,
 *            address to,           // must be the settlement contract
 *            uint256 value,
 *            uint256 validAfter,
 *            uint256 validBefore,
 *            bytes32 nonce
 *        )
 *
 *      Only the `to` address (our settlement contract) can call this function
 *      on the USDC contract, preventing front-running attacks.
 */
interface IERC20Receive {
    /**
     * @notice Execute a transfer with a signed authorization from the payer.
     *         Can only be called by the `to` address (front-running protection).
     *
     * @param from        Payer's address (the token holder).
     * @param to          Payee's address (must be msg.sender).
     * @param value       Amount to be transferred.
     * @param validAfter  Unix timestamp after which the authorization is valid.
     * @param validBefore Unix timestamp before which the authorization is valid.
     * @param nonce       Unique random nonce (bytes32) to prevent replay.
     * @param signature   Signature bytes (packed r, s, v for EOA wallets).
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external;
}
