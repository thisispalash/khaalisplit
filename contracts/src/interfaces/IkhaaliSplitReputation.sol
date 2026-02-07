// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IkhaaliSplitReputation
 * @notice Interface for the on-chain reputation scoring contract for khaaliSplit.
 *         Tracks per-user reputation scores (0–100) and syncs them to ENS text
 *         records via the subname registry.
 *
 * @dev Reputation is updated by the settlement contract after each settlement.
 *      Users must have a registered ENS subname (userNode) before reputation
 *      can be recorded — enforced by the client onboarding flow.
 *
 *      Score mechanics:
 *        - Default score: 50 (set during subname registration on the subnames contract)
 *        - Successful settlement: score = min(score + 1, 100)
 *        - Failed settlement: score = score > 5 ? score - 5 : 0
 */
interface IkhaaliSplitReputation {
    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event ReputationUpdated(address indexed user, uint256 newScore, bool wasSuccess);
    event UserNodeSet(address indexed user, bytes32 indexed node);
    event BackendUpdated(address indexed newBackend);
    event SubnameRegistryUpdated(address indexed newSubnameRegistry);
    event SettlementContractUpdated(address indexed newSettlementContract);

    // ──────────────────────────────────────────────
    //  Settlement Integration
    // ──────────────────────────────────────────────

    /// @notice Record a settlement outcome for a user. Called by the settlement contract.
    /// @param user The user whose reputation is being updated.
    /// @param success Whether the settlement was successful.
    function recordSettlement(address user, bool success) external;

    // ──────────────────────────────────────────────
    //  User Node Management
    // ──────────────────────────────────────────────

    /// @notice Link a user address to their ENS subname node. Called by backend during onboarding.
    /// @param user The user's address.
    /// @param node The ENS namehash of the user's subname (e.g. namehash("alice.khaalisplit.eth")).
    function setUserNode(address user, bytes32 node) external;

    // ──────────────────────────────────────────────
    //  Getters
    // ──────────────────────────────────────────────

    /// @notice Get the reputation score for a user.
    /// @dev Returns DEFAULT_SCORE (50) if the user has not had any settlements recorded.
    /// @param user The user's address.
    /// @return The reputation score (0–100).
    function getReputation(address user) external view returns (uint256);

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /// @notice Update the backend address authorized to call setUserNode.
    function setBackend(address _backend) external;

    /// @notice Update the subname registry used for ENS text record syncing.
    function setSubnameRegistry(address _subnameRegistry) external;

    /// @notice Update the settlement contract authorized to call recordSettlement.
    function setSettlementContract(address _settlementContract) external;
}
