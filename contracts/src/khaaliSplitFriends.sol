// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title khaaliSplitFriends
 * @notice Social graph registry for khaaliSplit — stores ECDH public keys and
 *         manages bidirectional friend relationships.
 * @dev UUPS upgradeable. A trusted `backend` address is authorized to register
 *      wallet public keys on behalf of users (relayed from the PWA).
 */
contract khaaliSplitFriends is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice Authorized backend / relayer that can register public keys.
    address public backend;

    /// @notice ECDH public key for a registered user.
    mapping(address => bytes) public walletPubKey;

    /// @notice Whether an address has been registered (has a pubkey).
    mapping(address => bool) public registered;

    /// @notice Bidirectional friendship status.
    mapping(address => mapping(address => bool)) public isFriend;

    /// @notice Pending (one-way) friend requests: pendingRequest[requester][target] = true.
    mapping(address => mapping(address => bool)) public pendingRequest;

    /// @dev Internal list of friends per user (for off-chain enumeration).
    mapping(address => address[]) private _friendsList;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event PubKeyRegistered(address indexed user, bytes pubKey);
    event FriendRequested(address indexed from, address indexed to);
    event FriendAccepted(address indexed user, address indexed friend);
    event FriendRemoved(address indexed user, address indexed friend);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error NotBackend();
    error NotRegistered(address user);
    error AlreadyRegistered(address user);
    error CannotFriendSelf();
    error AlreadyFriends();
    error AlreadyRequested();
    error NoPendingRequest();
    error NotFriends();

    // ──────────────────────────────────────────────
    //  Initializer
    // ──────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param _backend Address authorized to call `registerPubKey`.
     * @param _owner   Owner of the contract (can upgrade + set backend).
     */
    function initialize(address _backend, address _owner) external initializer {
        __Ownable_init(_owner);
        backend = _backend;
    }

    // ──────────────────────────────────────────────
    //  Public-key registration (backend only)
    // ──────────────────────────────────────────────

    /**
     * @notice Registers an ECDH public key for `user`. Can only be called by the
     *         authorized backend.
     * @param user   The wallet address to register.
     * @param pubKey The uncompressed ECDH public key (65 bytes typically).
     */
    function registerPubKey(address user, bytes calldata pubKey) external {
        if (msg.sender != backend) revert NotBackend();
        if (registered[user]) revert AlreadyRegistered(user);

        walletPubKey[user] = pubKey;
        registered[user] = true;

        emit PubKeyRegistered(user, pubKey);
    }

    // ──────────────────────────────────────────────
    //  Friend request / accept
    // ──────────────────────────────────────────────

    /**
     * @notice Sends a friend request to `friend`. Both parties must be registered.
     * @param friend The address to send the request to.
     */
    function requestFriend(address friend) external {
        if (!registered[msg.sender]) revert NotRegistered(msg.sender);
        if (!registered[friend]) revert NotRegistered(friend);
        if (msg.sender == friend) revert CannotFriendSelf();
        if (isFriend[msg.sender][friend]) revert AlreadyFriends();
        if (pendingRequest[msg.sender][friend]) revert AlreadyRequested();

        // If the other party already requested us, auto-accept
        if (pendingRequest[friend][msg.sender]) {
            isFriend[friend][msg.sender] = true;
            isFriend[msg.sender][friend] = true;
            _friendsList[friend].push(msg.sender);
            _friendsList[msg.sender].push(friend);
            delete pendingRequest[friend][msg.sender];
            emit FriendAccepted(msg.sender, friend);
            return;
        }

        pendingRequest[msg.sender][friend] = true;

        emit FriendRequested(msg.sender, friend);
    }

    /**
     * @notice Accepts a pending friend request from `requester`.
     * @param requester The address that originally sent the request.
     */
    function acceptFriend(address requester) external {
        if (!pendingRequest[requester][msg.sender]) revert NoPendingRequest();

        // Set bidirectional friendship
        isFriend[requester][msg.sender] = true;
        isFriend[msg.sender][requester] = true;

        // Track in lists
        _friendsList[requester].push(msg.sender);
        _friendsList[msg.sender].push(requester);

        // Clean up pending request
        delete pendingRequest[requester][msg.sender];

        emit FriendAccepted(msg.sender, requester);
    }

    // ──────────────────────────────────────────────
    //  Remove friend
    // ──────────────────────────────────────────────

    /**
     * @notice Removes a bidirectional friendship. Soft-delete only — does NOT
     *         remove entries from `_friendsList` (indexer should filter by `isFriend`).
     *         Does NOT cascade to group memberships.
     * @param friend The address to unfriend.
     */
    function removeFriend(address friend) external {
        if (!isFriend[msg.sender][friend]) revert NotFriends();
        isFriend[msg.sender][friend] = false;
        isFriend[friend][msg.sender] = false;
        emit FriendRemoved(msg.sender, friend);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    /**
     * @notice Returns the ECDH public key for `user`.
     */
    function getPubKey(address user) external view returns (bytes memory) {
        return walletPubKey[user];
    }

    /**
     * @notice Returns the list of friends for `user`.
     * @dev WARNING: Returns the full array with no pagination. Gas cost grows
     *      linearly with the number of friends. Use off-chain indexing for large lists.
     */
    function getFriends(address user) external view returns (address[] memory) {
        return _friendsList[user];
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
