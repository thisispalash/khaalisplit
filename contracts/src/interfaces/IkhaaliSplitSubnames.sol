// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IkhaaliSplitSubnames
 * @notice Interface for the on-chain ENS subname registrar + resolver for khaaliSplit.
 *         Manages `{username}.khaalisplit.eth` subnames via NameWrapper,
 *         stores on-chain text and addr records, and supports reputation contract
 *         syncing text records automatically.
 */
interface IkhaaliSplitSubnames {
    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event SubnameRegistered(bytes32 indexed node, string label, address indexed owner);
    event TextRecordSet(bytes32 indexed node, string key, string value);
    event AddrRecordSet(bytes32 indexed node, address addr);
    event BackendUpdated(address indexed newBackend);
    event ReputationContractUpdated(address indexed newReputationContract);

    // ──────────────────────────────────────────────
    //  Registration
    // ──────────────────────────────────────────────

    /// @notice Register a new subname under khaalisplit.eth via NameWrapper.
    /// @param label The subname label (e.g. "alice" for alice.khaalisplit.eth).
    /// @param owner The address that will own the subname.
    function register(string calldata label, address owner) external;

    // ──────────────────────────────────────────────
    //  Record Setters
    // ──────────────────────────────────────────────

    /// @notice Set a text record for a subname node.
    /// @param node The ENS namehash of the subname.
    /// @param key The text record key.
    /// @param value The text record value.
    function setText(bytes32 node, string calldata key, string calldata value) external;

    /// @notice Set the address record for a subname node.
    /// @param node The ENS namehash of the subname.
    /// @param _addr The address to associate with the node.
    function setAddr(bytes32 node, address _addr) external;

    // ──────────────────────────────────────────────
    //  Record Getters (Resolver interface)
    // ──────────────────────────────────────────────

    /// @notice Returns the text record for a node and key.
    function text(bytes32 node, string calldata key) external view returns (string memory);

    /// @notice Returns the address associated with a node.
    function addr(bytes32 node) external view returns (address payable);

    // ──────────────────────────────────────────────
    //  Utilities
    // ──────────────────────────────────────────────

    /// @notice Compute the namehash for a subname label under the parent node.
    /// @param label The subname label.
    /// @return The ENS namehash of `label.khaalisplit.eth`.
    function subnameNode(string calldata label) external view returns (bytes32);

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /// @notice Update the backend address authorized to register + set records.
    function setBackend(address _backend) external;

    /// @notice Set the reputation contract address authorized to call setText.
    function setReputationContract(address _reputationContract) external;
}
