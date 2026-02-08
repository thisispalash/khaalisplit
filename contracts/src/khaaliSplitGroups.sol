// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IkhaaliSplitFriends} from "./interfaces/IkhaaliSplitFriends.sol";

/**
 * @title khaaliSplitGroups
 * @notice Group registry for khaaliSplit — manages expense-splitting groups with
 *         encrypted group keys. Members can only be invited if they are friends.
 * @dev UUPS upgradeable. References khaaliSplitFriends for friendship checks.
 */
contract khaaliSplitGroups is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────

    struct Group {
        bytes32 nameHash;
        address creator;
        uint256 memberCount;
    }

    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice Reference to the friend registry.
    IkhaaliSplitFriends public friendRegistry;

    /// @notice Auto-incrementing group counter.
    uint256 public groupCount;

    /// @notice Group metadata by ID.
    mapping(uint256 => Group) public groups;

    /// @notice Ordered list of members per group.
    mapping(uint256 => address[]) private _memberList;

    /// @notice Membership check: isMember[groupId][user].
    mapping(uint256 => mapping(address => bool)) public isMember;

    /// @notice Pending invitations: isInvited[groupId][user].
    mapping(uint256 => mapping(address => bool)) public isInvited;

    /// @notice Encrypted group AES key per member: encryptedGroupKey[groupId][user].
    mapping(uint256 => mapping(address => bytes)) public encryptedGroupKey;

    /// @notice Authorized backend / relayer address.
    address public backend;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event GroupCreated(uint256 indexed groupId, address indexed creator, bytes32 nameHash);
    event MemberInvited(uint256 indexed groupId, address indexed inviter, address indexed invitee);
    event MemberAccepted(uint256 indexed groupId, address indexed member);
    event MemberLeft(uint256 indexed groupId, address indexed member);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error NotRegistered(address user);
    error NotGroupMember(uint256 groupId, address user);
    error NotFriends(address a, address b);
    error AlreadyMember(uint256 groupId, address user);
    error AlreadyInvited(uint256 groupId, address user);
    error NotInvited(uint256 groupId, address user);
    error GroupDoesNotExist(uint256 groupId);
    error CreatorCannotLeave(uint256 groupId);
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
     * @param _friendRegistry Address of the khaaliSplitFriends proxy.
     * @param _owner          Owner of the contract (can upgrade).
     */
    function initialize(address _friendRegistry, address _owner) external initializer {
        __Ownable_init(_owner);
        friendRegistry = IkhaaliSplitFriends(_friendRegistry);
    }

    // ──────────────────────────────────────────────
    //  Group creation
    // ──────────────────────────────────────────────

    /**
     * @notice Creates a new group. Caller becomes the first member.
     * @param nameHash     Keccak256 of the group name (stored on-chain for verification).
     * @param encryptedKey The group AES key encrypted for the creator's ECDH pubkey.
     * @return groupId     The newly created group's ID.
     */
    function createGroup(bytes32 nameHash, bytes calldata encryptedKey) external returns (uint256 groupId) {
        if (!friendRegistry.registered(msg.sender)) revert NotRegistered(msg.sender);

        groupId = ++groupCount;

        groups[groupId] = Group({
            nameHash: nameHash,
            creator: msg.sender,
            memberCount: 1
        });

        isMember[groupId][msg.sender] = true;
        _memberList[groupId].push(msg.sender);
        encryptedGroupKey[groupId][msg.sender] = encryptedKey;

        emit GroupCreated(groupId, msg.sender, nameHash);
    }

    // ──────────────────────────────────────────────
    //  Invite / Accept
    // ──────────────────────────────────────────────

    /**
     * @notice Invites a friend to a group. Caller must be a group member and
     *         friends with the invitee.
     * @param groupId      The group to invite into.
     * @param member       The address to invite.
     * @param encryptedKey The group AES key encrypted for the invitee's ECDH pubkey.
     */
    function inviteMember(uint256 groupId, address member, bytes calldata encryptedKey) external {
        if (groups[groupId].creator == address(0)) revert GroupDoesNotExist(groupId);
        if (!isMember[groupId][msg.sender]) revert NotGroupMember(groupId, msg.sender);
        if (!friendRegistry.isFriend(msg.sender, member)) revert NotFriends(msg.sender, member);
        if (isMember[groupId][member]) revert AlreadyMember(groupId, member);
        if (isInvited[groupId][member]) revert AlreadyInvited(groupId, member);

        isInvited[groupId][member] = true;
        encryptedGroupKey[groupId][member] = encryptedKey;

        emit MemberInvited(groupId, msg.sender, member);
    }

    /**
     * @notice Accepts a pending group invitation.
     * @param groupId The group to accept the invite for.
     */
    function acceptGroupInvite(uint256 groupId) external {
        if (!isInvited[groupId][msg.sender]) revert NotInvited(groupId, msg.sender);

        isInvited[groupId][msg.sender] = false;
        isMember[groupId][msg.sender] = true;
        _memberList[groupId].push(msg.sender);
        groups[groupId].memberCount++;

        emit MemberAccepted(groupId, msg.sender);
    }

    // ──────────────────────────────────────────────
    //  Leave group
    // ──────────────────────────────────────────────

    /**
     * @notice Leaves a group. Soft-delete only — does NOT remove the member from
     *         `_memberList` (indexer should filter by `isMember`). Clears the
     *         member's encrypted group key. The group creator cannot leave.
     * @param groupId The group to leave.
     */
    function leaveGroup(uint256 groupId) external {
        if (!isMember[groupId][msg.sender]) revert NotGroupMember(groupId, msg.sender);
        if (groups[groupId].creator == msg.sender) revert CreatorCannotLeave(groupId);

        isMember[groupId][msg.sender] = false;
        groups[groupId].memberCount--;
        delete encryptedGroupKey[groupId][msg.sender];

        emit MemberLeft(groupId, msg.sender);
    }

    // ──────────────────────────────────────────────
    //  Backend relay: group operations
    // ──────────────────────────────────────────────

    /**
     * @notice Backend relay: create a group on behalf of `user`.
     * @param user         The address creating the group.
     * @param nameHash     Keccak256 of the group name.
     * @param encryptedKey The group AES key encrypted for the creator's ECDH pubkey.
     * @return groupId     The newly created group's ID.
     */
    function createGroupFor(address user, bytes32 nameHash, bytes calldata encryptedKey) external returns (uint256 groupId) {
        if (msg.sender != backend) revert NotBackend();
        if (!friendRegistry.registered(user)) revert NotRegistered(user);

        groupId = ++groupCount;
        groups[groupId] = Group({ nameHash: nameHash, creator: user, memberCount: 1 });
        isMember[groupId][user] = true;
        _memberList[groupId].push(user);
        encryptedGroupKey[groupId][user] = encryptedKey;

        emit GroupCreated(groupId, user, nameHash);
    }

    /**
     * @notice Backend relay: invite a member on behalf of `inviter`.
     * @param inviter      The address doing the inviting (must be a group member).
     * @param groupId      The group to invite into.
     * @param member       The address to invite.
     * @param encryptedKey The group AES key encrypted for the invitee's ECDH pubkey.
     */
    function inviteMemberFor(address inviter, uint256 groupId, address member, bytes calldata encryptedKey) external {
        if (msg.sender != backend) revert NotBackend();
        if (groups[groupId].creator == address(0)) revert GroupDoesNotExist(groupId);
        if (!isMember[groupId][inviter]) revert NotGroupMember(groupId, inviter);
        if (!friendRegistry.isFriend(inviter, member)) revert NotFriends(inviter, member);
        if (isMember[groupId][member]) revert AlreadyMember(groupId, member);
        if (isInvited[groupId][member]) revert AlreadyInvited(groupId, member);

        isInvited[groupId][member] = true;
        encryptedGroupKey[groupId][member] = encryptedKey;

        emit MemberInvited(groupId, inviter, member);
    }

    /**
     * @notice Backend relay: accept a group invite on behalf of `user`.
     * @param user    The address accepting the invite.
     * @param groupId The group to accept the invite for.
     */
    function acceptGroupInviteFor(address user, uint256 groupId) external {
        if (msg.sender != backend) revert NotBackend();
        if (!isInvited[groupId][user]) revert NotInvited(groupId, user);

        isInvited[groupId][user] = false;
        isMember[groupId][user] = true;
        _memberList[groupId].push(user);
        groups[groupId].memberCount++;

        emit MemberAccepted(groupId, user);
    }

    /**
     * @notice Backend relay: leave a group on behalf of `user`.
     * @param user    The address leaving the group.
     * @param groupId The group to leave.
     */
    function leaveGroupFor(address user, uint256 groupId) external {
        if (msg.sender != backend) revert NotBackend();
        if (!isMember[groupId][user]) revert NotGroupMember(groupId, user);
        if (groups[groupId].creator == user) revert CreatorCannotLeave(groupId);

        isMember[groupId][user] = false;
        groups[groupId].memberCount--;
        delete encryptedGroupKey[groupId][user];

        emit MemberLeft(groupId, user);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    /**
     * @notice Returns the ordered list of members in a group.
     * @dev WARNING: Returns the full array with no pagination. Gas cost grows
     *      linearly with the number of members. Use off-chain indexing for large lists.
     */
    function getMembers(uint256 groupId) external view returns (address[] memory) {
        return _memberList[groupId];
    }

    /**
     * @notice Returns the group creator.
     */
    function getGroupCreator(uint256 groupId) external view returns (address) {
        return groups[groupId].creator;
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
