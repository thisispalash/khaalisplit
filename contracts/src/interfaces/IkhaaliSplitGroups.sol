// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IkhaaliSplitGroups {
    function isMember(uint256 groupId, address user) external view returns (bool);
    function getGroupCreator(uint256 groupId) external view returns (address);
}
