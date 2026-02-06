// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IkhaaliSplitFriends {
    function isFriend(address a, address b) external view returns (bool);
    function walletPubKey(address user) external view returns (bytes memory);
    function registered(address user) external view returns (bool);
}
