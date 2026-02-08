// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IkhaaliSplitGroups} from "./interfaces/IkhaaliSplitGroups.sol";

/**
 * @title khaaliSplitExpenses
 * @notice Expense registry for khaaliSplit — stores expense hashes on-chain and
 *         emits encrypted expense data in events for off-chain indexing.
 * @dev UUPS upgradeable. References khaaliSplitGroups for membership checks.
 *      Actual expense details (amounts, splits, descriptions) are encrypted
 *      client-side and only the hash is stored on-chain.
 */
contract khaaliSplitExpenses is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────

    struct Expense {
        uint256 groupId;
        address creator;
        bytes32 dataHash;
        uint256 timestamp;
    }

    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice Reference to the group registry.
    IkhaaliSplitGroups public groupRegistry;

    /// @notice Auto-incrementing expense counter.
    uint256 public expenseCount;

    /// @notice Expense metadata by ID.
    mapping(uint256 => Expense) public expenses;

    /// @notice List of expense IDs per group.
    mapping(uint256 => uint256[]) private _groupExpenses;

    /// @notice Authorized backend / relayer address.
    address public backend;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    /**
     * @notice Emitted when a new expense is added. The `encryptedData` blob contains
     *         the full expense details encrypted with the group's AES key.
     */
    event ExpenseAdded(
        uint256 indexed groupId,
        uint256 indexed expenseId,
        address indexed creator,
        bytes32 dataHash,
        bytes encryptedData
    );

    /**
     * @notice Emitted when an existing expense is updated by its creator.
     */
    event ExpenseUpdated(
        uint256 indexed groupId,
        uint256 indexed expenseId,
        address indexed creator,
        bytes32 dataHash,
        bytes encryptedData
    );

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error NotGroupMember(uint256 groupId, address user);
    error NotExpenseCreator(uint256 expenseId, address user);
    error ExpenseDoesNotExist(uint256 expenseId);
    error NotBackend();

    // ──────────────────────────────────────────────
    //  Initializer
    // ──────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param _groupRegistry Address of the khaaliSplitGroups proxy.
     * @param _owner         Owner of the contract (can upgrade).
     */
    function initialize(address _groupRegistry, address _owner) external initializer {
        __Ownable_init(_owner);
        groupRegistry = IkhaaliSplitGroups(_groupRegistry);
    }

    // ──────────────────────────────────────────────
    //  Add expense
    // ──────────────────────────────────────────────

    /**
     * @notice Adds an expense to a group. Only group members may add expenses.
     * @param groupId       The group this expense belongs to.
     * @param dataHash      Keccak256 of the plaintext expense data (for integrity).
     * @param encryptedData AES-encrypted expense blob (emitted in event for indexer).
     * @return expenseId    The newly created expense's ID.
     */
    function addExpense(
        uint256 groupId,
        bytes32 dataHash,
        bytes calldata encryptedData
    ) external returns (uint256 expenseId) {
        if (!groupRegistry.isMember(groupId, msg.sender)) {
            revert NotGroupMember(groupId, msg.sender);
        }

        expenseId = ++expenseCount;

        expenses[expenseId] = Expense({
            groupId: groupId,
            creator: msg.sender,
            dataHash: dataHash,
            timestamp: block.timestamp
        });

        _groupExpenses[groupId].push(expenseId);

        emit ExpenseAdded(groupId, expenseId, msg.sender, dataHash, encryptedData);
    }

    // ──────────────────────────────────────────────
    //  Update expense
    // ──────────────────────────────────────────────

    /**
     * @notice Updates an existing expense. Only the original creator may update,
     *         and they must still be a member of the expense's group.
     * @param expenseId        The expense to update.
     * @param newDataHash      New keccak256 of the updated expense data.
     * @param newEncryptedData New AES-encrypted expense blob (emitted in event).
     */
    function updateExpense(
        uint256 expenseId,
        bytes32 newDataHash,
        bytes calldata newEncryptedData
    ) external {
        Expense storage e = expenses[expenseId];
        if (e.creator == address(0)) revert ExpenseDoesNotExist(expenseId);
        if (e.creator != msg.sender) revert NotExpenseCreator(expenseId, msg.sender);
        if (!groupRegistry.isMember(e.groupId, msg.sender)) {
            revert NotGroupMember(e.groupId, msg.sender);
        }

        e.dataHash = newDataHash;
        e.timestamp = block.timestamp;

        emit ExpenseUpdated(e.groupId, expenseId, msg.sender, newDataHash, newEncryptedData);
    }

    // ──────────────────────────────────────────────
    //  Backend relay: expense operations
    // ──────────────────────────────────────────────

    /**
     * @notice Backend relay: add an expense on behalf of `creator`.
     * @param creator       The address adding the expense.
     * @param groupId       The group this expense belongs to.
     * @param dataHash      Keccak256 of the plaintext expense data.
     * @param encryptedData AES-encrypted expense blob (emitted in event for indexer).
     * @return expenseId    The newly created expense's ID.
     */
    function addExpenseFor(
        address creator,
        uint256 groupId,
        bytes32 dataHash,
        bytes calldata encryptedData
    ) external returns (uint256 expenseId) {
        if (msg.sender != backend) revert NotBackend();
        if (!groupRegistry.isMember(groupId, creator)) {
            revert NotGroupMember(groupId, creator);
        }

        expenseId = ++expenseCount;

        expenses[expenseId] = Expense({
            groupId: groupId,
            creator: creator,
            dataHash: dataHash,
            timestamp: block.timestamp
        });

        _groupExpenses[groupId].push(expenseId);

        emit ExpenseAdded(groupId, expenseId, creator, dataHash, encryptedData);
    }

    /**
     * @notice Backend relay: update an expense on behalf of `creator`.
     * @param creator          The address updating the expense (must be original creator).
     * @param expenseId        The expense to update.
     * @param newDataHash      New keccak256 of the updated expense data.
     * @param newEncryptedData New AES-encrypted expense blob (emitted in event).
     */
    function updateExpenseFor(
        address creator,
        uint256 expenseId,
        bytes32 newDataHash,
        bytes calldata newEncryptedData
    ) external {
        if (msg.sender != backend) revert NotBackend();
        Expense storage e = expenses[expenseId];
        if (e.creator == address(0)) revert ExpenseDoesNotExist(expenseId);
        if (e.creator != creator) revert NotExpenseCreator(expenseId, creator);
        if (!groupRegistry.isMember(e.groupId, creator)) {
            revert NotGroupMember(e.groupId, creator);
        }

        e.dataHash = newDataHash;
        e.timestamp = block.timestamp;

        emit ExpenseUpdated(e.groupId, expenseId, creator, newDataHash, newEncryptedData);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    /**
     * @notice Returns expense metadata.
     */
    function getExpense(uint256 expenseId)
        external
        view
        returns (uint256 groupId, address creator, bytes32 dataHash, uint256 timestamp)
    {
        Expense storage e = expenses[expenseId];
        return (e.groupId, e.creator, e.dataHash, e.timestamp);
    }

    /**
     * @notice Returns the list of expense IDs for a group.
     * @dev WARNING: Returns the full array with no pagination. Gas cost grows
     *      linearly with the number of expenses. Use off-chain indexing for large lists.
     */
    function getGroupExpenses(uint256 groupId) external view returns (uint256[] memory) {
        return _groupExpenses[groupId];
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /**
     * @notice Updates the authorized backend address.
     */
    function setBackend(address _backend) external onlyOwner {
        backend = _backend;
    }

    // ──────────────────────────────────────────────
    //  UUPS
    // ──────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
