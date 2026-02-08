// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IkhaaliSplitSubnames} from "./interfaces/IkhaaliSplitSubnames.sol";

/**
 * @title khaaliSplitReputation
 * @notice On-chain reputation scoring for khaaliSplit users.
 *         Tracks per-user scores (0–100) and syncs them to ENS text records
 *         via the subname registry automatically.
 *
 * @dev UUPS upgradeable. Score mechanics:
 *        - Default score: 50 (set on the subnames contract during registration)
 *        - Successful settlement: score = min(score + 1, 100)
 *        - Failed settlement: score = score > 5 ? score - 5 : 0
 *
 *      The settlement contract calls recordSettlement() after each settlement.
 *      Users must have a registered ENS subname node (set via setUserNode during
 *      onboarding) before reputation can be recorded.
 *
 *      TODO: revisit what happens in a trustless scenario — users interacting
 *      outside the client won't have a node set and recordSettlement will revert.
 */
contract khaaliSplitReputation is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    uint256 public constant DEFAULT_SCORE = 50;
    uint256 public constant MAX_SCORE = 100;
    uint256 public constant MIN_SCORE = 0;
    uint256 public constant SUCCESS_DELTA = 1;
    uint256 public constant FAILURE_DELTA = 5;

    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice Authorized backend address (can call setUserNode).
    address public backend;

    /// @notice Subname registry for ENS text record syncing.
    IkhaaliSplitSubnames public subnameRegistry;

    /// @notice Settlement contract authorized to call recordSettlement.
    address public settlementContract;

    /// @notice Reputation scores: user → score.
    mapping(address => uint256) public scores;

    /// @notice User → ENS subname node mapping.
    mapping(address => bytes32) public userNodes;

    /// @notice Whether a user has had at least one settlement recorded.
    /// @dev Needed to distinguish "default 50" from "score is exactly 50 after updates".
    ///      We use this instead of checking scores[user] == 0 because a score of 0
    ///      is a valid state (user with many failures).
    mapping(address => bool) private _hasRecord;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event ReputationUpdated(address indexed user, uint256 newScore, bool wasSuccess);
    event UserNodeSet(address indexed user, bytes32 indexed node);
    event BackendUpdated(address indexed newBackend);
    event SubnameRegistryUpdated(address indexed newSubnameRegistry);
    event SettlementContractUpdated(address indexed newSettlementContract);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error Unauthorized();
    error ZeroAddress();
    error UserNodeNotSet();
    error ZeroNode();

    // ──────────────────────────────────────────────
    //  Initializer
    // ──────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the reputation contract.
     * @param _backend             Authorized backend address (for setUserNode).
     * @param _subnameRegistry     Subname registry for ENS text record syncing.
     *                             address(0) is allowed (ENS sync disabled until set).
     * @param _settlementContract  Settlement contract authorized to call recordSettlement.
     *                             address(0) is allowed (wired after settlement is deployed).
     * @param _owner               Owner of this contract (admin).
     */
    function initialize(
        address _backend,
        address _subnameRegistry,
        address _settlementContract,
        address _owner
    ) external initializer {
        if (_backend == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        __Ownable_init(_owner);

        backend = _backend;
        subnameRegistry = IkhaaliSplitSubnames(_subnameRegistry);
        settlementContract = _settlementContract;
    }

    // ──────────────────────────────────────────────
    //  Settlement Integration
    // ──────────────────────────────────────────────

    /**
     * @notice Record a settlement outcome for a user.
     * @dev Only callable by the settlement contract. Reverts if the user
     *      has no ENS subname node set (must complete onboarding first).
     *
     *      On first call for a user, initializes their score to DEFAULT_SCORE
     *      before applying the delta.
     *
     *      After updating the score, syncs to the ENS text record
     *      "com.khaalisplit.reputation" via subnameRegistry.setText().
     *
     * @param user    The user whose reputation is being updated.
     * @param success Whether the settlement was successful.
     */
    function recordSettlement(address user, bool success) external {
        if (msg.sender != settlementContract) revert Unauthorized();
        if (userNodes[user] == bytes32(0)) revert UserNodeNotSet();

        // Auto-initialize to DEFAULT_SCORE on first interaction
        if (!_hasRecord[user]) {
            scores[user] = DEFAULT_SCORE;
            _hasRecord[user] = true;
        }

        uint256 score = scores[user];

        if (success) {
            // Increment, capped at MAX_SCORE
            score = score + SUCCESS_DELTA > MAX_SCORE ? MAX_SCORE : score + SUCCESS_DELTA;
        } else {
            // Decrement, floored at MIN_SCORE
            score = score > FAILURE_DELTA ? score - FAILURE_DELTA : MIN_SCORE;
        }

        scores[user] = score;

        emit ReputationUpdated(user, score, success);

        // Sync to ENS text record if subname registry is configured
        _syncToENS(user, score);
    }

    // ──────────────────────────────────────────────
    //  User Node Management
    // ──────────────────────────────────────────────

    /**
     * @notice Link a user address to their ENS subname node.
     * @dev Backend only. Called during onboarding after subname registration.
     * @param user The user's address.
     * @param node The ENS namehash of the user's subname.
     */
    function setUserNode(address user, bytes32 node) external {
        if (msg.sender != backend) revert Unauthorized();
        if (user == address(0)) revert ZeroAddress();
        if (node == bytes32(0)) revert ZeroNode();

        userNodes[user] = node;

        emit UserNodeSet(user, node);
    }

    // ──────────────────────────────────────────────
    //  Getters
    // ──────────────────────────────────────────────

    /**
     * @notice Get the reputation score for a user.
     * @dev Returns DEFAULT_SCORE (50) if the user has not had any settlements recorded.
     * @param user The user's address.
     * @return The reputation score (0–100).
     */
    function getReputation(address user) external view returns (uint256) {
        if (!_hasRecord[user]) return DEFAULT_SCORE;
        return scores[user];
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /// @notice Update the backend address authorized to call setUserNode.
    function setBackend(address _backend) external onlyOwner {
        if (_backend == address(0)) revert ZeroAddress();
        backend = _backend;
        emit BackendUpdated(_backend);
    }

    /// @notice Update the subname registry used for ENS text record syncing.
    /// @dev address(0) is allowed (disables ENS sync).
    function setSubnameRegistry(address _subnameRegistry) external onlyOwner {
        subnameRegistry = IkhaaliSplitSubnames(_subnameRegistry);
        emit SubnameRegistryUpdated(_subnameRegistry);
    }

    /// @notice Update the settlement contract authorized to call recordSettlement.
    /// @dev address(0) is allowed (disables settlement recording).
    function setSettlementContract(address _settlementContract) external onlyOwner {
        settlementContract = _settlementContract;
        emit SettlementContractUpdated(_settlementContract);
    }

    // ──────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────

    /**
     * @dev Sync the user's reputation score to their ENS text record.
     *      Calls subnameRegistry.setText(node, "com.khaalisplit.reputation", score).
     *      Silently skips if subnameRegistry is not configured (address(0)).
     */
    function _syncToENS(address user, uint256 score) internal {
        if (address(subnameRegistry) == address(0)) return;

        bytes32 node = userNodes[user];
        // userNodes[user] is guaranteed non-zero here (checked in recordSettlement)

        subnameRegistry.setText(
            node,
            "com.khaalisplit.reputation",
            Strings.toString(score)
        );
    }

    // ──────────────────────────────────────────────
    //  UUPS
    // ──────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
