// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title ITokenMessengerV2
 * @notice Minimal interface for Circle's CCTP TokenMessengerV2 contract.
 *         Only includes depositForBurn — the single function used by
 *         khaaliSplitSettlement for cross-chain USDC transfers.
 *
 * @dev Full contract: https://github.com/circlefin/evm-cctp-contracts
 *      Deployed addresses:
 *        - Testnet: 0x8fe6b999dc680ccfdd5bf7eb0974218be2542daa
 *        - Mainnet: 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d
 */
interface ITokenMessengerV2 {
    /**
     * @notice Burns tokens on the source chain and initiates a cross-chain
     *         mint on the destination domain via CCTP.
     * @param amount            Amount of tokens to burn.
     * @param destinationDomain CCTP domain identifier for the destination chain.
     * @param mintRecipient     Recipient address on the destination chain (as bytes32).
     * @param burnToken         Address of the token to burn on the source chain.
     * @return nonce            The CCTP message nonce.
     */
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 nonce);
}
