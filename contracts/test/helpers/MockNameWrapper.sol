// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title MockNameWrapper
 * @notice Minimal mock of ENS NameWrapper for testing khaaliSplitSubnames.
 *         Implements only the functions called by our contract:
 *         - setSubnodeRecord(): tracks subnode ownership and records call params
 *         - ownerOf(): returns tracked owner for a node
 *
 * @dev Does NOT implement the full INameWrapper/IERC1155 interface.
 *      Only used in tests where we interact via the concrete mock type
 *      or via the specific function selectors our contract calls.
 */
contract MockNameWrapper {
    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice Tracks subnode ownership: node → owner
    mapping(uint256 => address) public owners;

    /// @notice Records the last setSubnodeRecord call for test assertions
    struct SubnodeRecord {
        bytes32 parentNode;
        string label;
        address owner;
        address resolver;
        uint64 ttl;
        uint32 fuses;
        uint64 expiry;
    }
    SubnodeRecord public lastRecord;

    /// @notice Number of times setSubnodeRecord has been called
    uint256 public registerCount;

    // ──────────────────────────────────────────────
    //  NameWrapper Functions (mocked)
    // ──────────────────────────────────────────────

    /**
     * @notice Mock setSubnodeRecord — records ownership and call params.
     * @dev Computes the child node the same way ENS does:
     *      node = keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))))
     */
    function setSubnodeRecord(
        bytes32 parentNode,
        string calldata label,
        address owner,
        address resolver,
        uint64 ttl,
        uint32 fuses,
        uint64 expiry
    ) external returns (bytes32) {
        bytes32 node = keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))));

        owners[uint256(node)] = owner;

        lastRecord = SubnodeRecord({
            parentNode: parentNode,
            label: label,
            owner: owner,
            resolver: resolver,
            ttl: ttl,
            fuses: fuses,
            expiry: expiry
        });

        registerCount++;

        return node;
    }

    /**
     * @notice Mock ownerOf — returns the tracked owner for a token ID (node).
     * @dev Returns address(0) for unregistered nodes (same behavior as NameWrapper).
     */
    function ownerOf(uint256 id) external view returns (address) {
        return owners[id];
    }

    // ──────────────────────────────────────────────
    //  Test Helpers
    // ──────────────────────────────────────────────

    /// @notice Manually set the owner of a node (for test setup).
    function setOwner(bytes32 node, address owner) external {
        owners[uint256(node)] = owner;
    }
}
