// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IkhaaliSplitFriends {
    function isFriend(address a, address b) external view returns (bool);
    function walletPubKey(address user) external view returns (bytes memory);
    function registered(address user) external view returns (bool);
    function getPubKey(address user) external view returns (bytes memory);
    function getFriends(address user) external view returns (address[] memory);
    function pendingRequest(address requester, address target) external view returns (bool);

    function registerPubKey(address user, bytes calldata pubKey) external;
    function requestFriend(address friend) external;
    function acceptFriend(address requester) external;
    function removeFriend(address friend) external;

    function requestFriendFor(address user, address friend) external;
    function acceptFriendFor(address user, address requester) external;
    function removeFriendFor(address user, address friend) external;

    function setBackend(address _backend) external;
    function backend() external view returns (address);
}
