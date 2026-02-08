// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IkhaaliSplitGroups {
    function isMember(uint256 groupId, address user) external view returns (bool);
    function isInvited(uint256 groupId, address user) external view returns (bool);
    function getGroupCreator(uint256 groupId) external view returns (address);
    function getMembers(uint256 groupId) external view returns (address[] memory);
    function encryptedGroupKey(uint256 groupId, address user) external view returns (bytes memory);
    function groupCount() external view returns (uint256);

    function createGroup(bytes32 nameHash, bytes calldata encryptedKey) external returns (uint256 groupId);
    function inviteMember(uint256 groupId, address member, bytes calldata encryptedKey) external;
    function acceptGroupInvite(uint256 groupId) external;
    function leaveGroup(uint256 groupId) external;

    function createGroupFor(address user, bytes32 nameHash, bytes calldata encryptedKey) external returns (uint256 groupId);
    function inviteMemberFor(address inviter, uint256 groupId, address member, bytes calldata encryptedKey) external;
    function acceptGroupInviteFor(address user, uint256 groupId) external;
    function leaveGroupFor(address user, uint256 groupId) external;

    function setBackend(address _backend) external;
    function backend() external view returns (address);
}
