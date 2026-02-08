// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IkhaaliSplitSettlement
 * @notice Interface for the khaaliSplit settlement contract.
 *         Routes USDC payments to recipients based on their ENS text record
 *         preferences (Gateway or CCTP), with EIP-3009 authorization support
 *         for gasless/offline settlements.
 *
 * @dev Settlement flow:
 *        1. User signs an EIP-3009 ReceiveWithAuthorization message.
 *        2. Anyone submits the signature via settleWithAuthorization().
 *        3. Contract pulls USDC from sender, reads recipient's payment
 *           preferences from ENS text records, and routes accordingly:
 *             - Gateway (default): depositFor on Gateway Wallet
 *             - CCTP (opt-in): depositForBurn on TokenMessengerV2
 *        4. Updates sender's reputation score.
 *        5. Emits SettlementCompleted event.
 */
interface IkhaaliSplitSettlement {
    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event SettlementCompleted(
        address indexed sender,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 senderReputation,
        bytes memo
    );

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event TokenMessengerUpdated(address indexed tokenMessenger);
    event GatewayWalletUpdated(address indexed gatewayWallet);
    event DomainConfigured(uint256 indexed chainId, uint32 domain);
    event SubnameRegistryUpdated(address indexed subnameRegistry);
    event ReputationContractUpdated(address indexed reputationContract);

    // ──────────────────────────────────────────────
    //  Settlement
    // ──────────────────────────────────────────────

    /// @notice Placeholder for future approval-based settlement. Currently reverts.
    /// @param recipient The recipient's wallet address.
    /// @param amount The USDC amount to settle.
    /// @param memo Arbitrary data (e.g. encrypted memo for off-chain indexing).
    function settle(address recipient, uint256 amount, bytes calldata memo) external;

    /// @notice EIP-3009 authorization parameters.
    struct Authorization {
        address from;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
    }

    /// @notice Primary settlement function using EIP-3009 authorization.
    ///         Pulls USDC from sender via receiveWithAuthorization, reads recipient's
    ///         payment preferences from ENS text records, routes via Gateway or CCTP,
    ///         and updates the sender's reputation.
    /// @param recipient    The recipient's wallet address.
    /// @param amount       The USDC amount to settle.
    /// @param memo         Arbitrary data (e.g. encrypted memo for off-chain indexing).
    /// @param auth         EIP-3009 authorization parameters.
    /// @param signature    EIP-3009 signature (packed r, s, v).
    function settleWithAuthorization(
        address recipient,
        uint256 amount,
        bytes calldata memo,
        Authorization calldata auth,
        bytes calldata signature
    ) external;

    // ──────────────────────────────────────────────
    //  Token Management
    // ──────────────────────────────────────────────

    /// @notice Add a token to the allowed list.
    function addToken(address token) external;

    /// @notice Remove a token from the allowed list.
    function removeToken(address token) external;

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /// @notice Set the CCTP TokenMessengerV2 address.
    function setTokenMessenger(address _tokenMessenger) external;

    /// @notice Configure a CCTP domain mapping for a chain ID.
    function configureDomain(uint256 chainId, uint32 domain) external;

    /// @notice Set the Circle Gateway Wallet address.
    function setGatewayWallet(address _gatewayWallet) external;

    /// @notice Set the subname registry for reading payment preferences.
    function setSubnameRegistry(address _subnameRegistry) external;

    /// @notice Set the reputation contract for post-settlement score updates.
    function setReputationContract(address _reputationContract) external;
}
