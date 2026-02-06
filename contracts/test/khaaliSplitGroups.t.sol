// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliSplitFriends} from "../src/khaaliSplitFriends.sol";
import {khaaliSplitGroups} from "../src/khaaliSplitGroups.sol";

contract khaaliSplitGroupsTest is Test {
    khaaliSplitFriends public friends;
    khaaliSplitGroups public groupsContract;

    address owner = makeAddr("owner");
    address backend = makeAddr("backend");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    bytes32 nameHash = keccak256("Trip to Goa");
    bytes encryptedKeyAlice = hex"aabbccdd";
    bytes encryptedKeyBob = hex"eeff0011";
    bytes encryptedKeyCharlie = hex"deadbeef";

    function setUp() public {
        // Deploy khaaliSplitFriends proxy
        khaaliSplitFriends friendsImpl = new khaaliSplitFriends();
        ERC1967Proxy friendsProxy = new ERC1967Proxy(
            address(friendsImpl),
            abi.encodeCall(khaaliSplitFriends.initialize, (backend, owner))
        );
        friends = khaaliSplitFriends(address(friendsProxy));

        // Register alice, bob, charlie; make alice<->bob friends
        vm.startPrank(backend);
        friends.registerPubKey(alice, hex"04aa");
        friends.registerPubKey(bob, hex"04bb");
        friends.registerPubKey(charlie, hex"04cc");
        vm.stopPrank();

        vm.prank(alice);
        friends.requestFriend(bob);
        vm.prank(bob);
        friends.acceptFriend(alice);

        // Deploy khaaliSplitGroups proxy
        khaaliSplitGroups groupsImpl = new khaaliSplitGroups();
        ERC1967Proxy groupsProxy = new ERC1967Proxy(
            address(groupsImpl),
            abi.encodeCall(khaaliSplitGroups.initialize, (address(friends), owner))
        );
        groupsContract = khaaliSplitGroups(address(groupsProxy));
    }

    // ──────────────────────────────────────────────
    //  Initialization
    // ──────────────────────────────────────────────

    function test_initialize_setsState() public view {
        assertEq(address(groupsContract.friendRegistry()), address(friends));
        assertEq(groupsContract.owner(), owner);
        assertEq(groupsContract.groupCount(), 0);
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert();
        groupsContract.initialize(address(friends), owner);
    }

    // ──────────────────────────────────────────────
    //  Create group
    // ──────────────────────────────────────────────

    function test_createGroup_success() public {
        vm.prank(alice);
        uint256 groupId = groupsContract.createGroup(nameHash, encryptedKeyAlice);

        assertEq(groupId, 1);
        assertEq(groupsContract.groupCount(), 1);

        (bytes32 storedNameHash, address creator, uint256 memberCount) = groupsContract.groups(groupId);
        assertEq(storedNameHash, nameHash);
        assertEq(creator, alice);
        assertEq(memberCount, 1);

        assertTrue(groupsContract.isMember(groupId, alice));
        assertEq(groupsContract.encryptedGroupKey(groupId, alice), encryptedKeyAlice);
    }

    function test_createGroup_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit khaaliSplitGroups.GroupCreated(1, alice, nameHash);
        groupsContract.createGroup(nameHash, encryptedKeyAlice);
    }

    function test_createGroup_notRegistered_reverts() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitGroups.NotRegistered.selector, stranger)
        );
        groupsContract.createGroup(nameHash, hex"00");
    }

    // ──────────────────────────────────────────────
    //  Invite member
    // ──────────────────────────────────────────────

    function _createGroupAsAlice() internal returns (uint256) {
        vm.prank(alice);
        return groupsContract.createGroup(nameHash, encryptedKeyAlice);
    }

    function test_inviteMember_success() public {
        uint256 groupId = _createGroupAsAlice();

        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit khaaliSplitGroups.MemberInvited(groupId, alice, bob);
        groupsContract.inviteMember(groupId, bob, encryptedKeyBob);

        assertTrue(groupsContract.isInvited(groupId, bob));
        assertEq(groupsContract.encryptedGroupKey(groupId, bob), encryptedKeyBob);
    }

    function test_inviteMember_notFriends_reverts() public {
        uint256 groupId = _createGroupAsAlice();

        // alice and charlie are NOT friends
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitGroups.NotFriends.selector, alice, charlie)
        );
        groupsContract.inviteMember(groupId, charlie, encryptedKeyCharlie);
    }

    function test_inviteMember_notGroupMember_reverts() public {
        uint256 groupId = _createGroupAsAlice();

        // bob is not a member of the group (only alice is)
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitGroups.NotGroupMember.selector, groupId, bob)
        );
        groupsContract.inviteMember(groupId, alice, hex"00");
    }

    function test_inviteMember_alreadyMember_reverts() public {
        uint256 groupId = _createGroupAsAlice();

        // Invite and accept bob first
        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encryptedKeyBob);
        vm.prank(bob);
        groupsContract.acceptGroupInvite(groupId);

        // Try to invite bob again
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitGroups.AlreadyMember.selector, groupId, bob)
        );
        groupsContract.inviteMember(groupId, bob, encryptedKeyBob);
    }

    function test_inviteMember_alreadyInvited_reverts() public {
        uint256 groupId = _createGroupAsAlice();

        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encryptedKeyBob);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitGroups.AlreadyInvited.selector, groupId, bob)
        );
        groupsContract.inviteMember(groupId, bob, encryptedKeyBob);
    }

    function test_inviteMember_groupDoesNotExist_reverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitGroups.GroupDoesNotExist.selector, 999)
        );
        groupsContract.inviteMember(999, bob, encryptedKeyBob);
    }

    // ──────────────────────────────────────────────
    //  Accept group invite
    // ──────────────────────────────────────────────

    function test_acceptGroupInvite_success() public {
        uint256 groupId = _createGroupAsAlice();

        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encryptedKeyBob);

        vm.prank(bob);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitGroups.MemberAccepted(groupId, bob);
        groupsContract.acceptGroupInvite(groupId);

        assertTrue(groupsContract.isMember(groupId, bob));
        assertFalse(groupsContract.isInvited(groupId, bob));

        (, , uint256 memberCount) = groupsContract.groups(groupId);
        assertEq(memberCount, 2);
    }

    function test_acceptGroupInvite_notInvited_reverts() public {
        uint256 groupId = _createGroupAsAlice();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitGroups.NotInvited.selector, groupId, bob)
        );
        groupsContract.acceptGroupInvite(groupId);
    }

    // ──────────────────────────────────────────────
    //  Leave group
    // ──────────────────────────────────────────────

    function _addBobToGroup(uint256 groupId) internal {
        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encryptedKeyBob);
        vm.prank(bob);
        groupsContract.acceptGroupInvite(groupId);
    }

    function test_leaveGroup_success() public {
        uint256 groupId = _createGroupAsAlice();
        _addBobToGroup(groupId);

        vm.prank(bob);
        groupsContract.leaveGroup(groupId);

        assertFalse(groupsContract.isMember(groupId, bob));
        (, , uint256 memberCount) = groupsContract.groups(groupId);
        assertEq(memberCount, 1);
        // Encrypted key should be cleared
        assertEq(groupsContract.encryptedGroupKey(groupId, bob), "");
    }

    function test_leaveGroup_emitsEvent() public {
        uint256 groupId = _createGroupAsAlice();
        _addBobToGroup(groupId);

        vm.prank(bob);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitGroups.MemberLeft(groupId, bob);
        groupsContract.leaveGroup(groupId);
    }

    function test_leaveGroup_creatorCannotLeave() public {
        uint256 groupId = _createGroupAsAlice();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitGroups.CreatorCannotLeave.selector, groupId)
        );
        groupsContract.leaveGroup(groupId);
    }

    function test_leaveGroup_notMember_reverts() public {
        uint256 groupId = _createGroupAsAlice();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitGroups.NotGroupMember.selector, groupId, bob)
        );
        groupsContract.leaveGroup(groupId);
    }

    function test_leaveGroup_canBeReinvited() public {
        uint256 groupId = _createGroupAsAlice();
        _addBobToGroup(groupId);

        // Bob leaves
        vm.prank(bob);
        groupsContract.leaveGroup(groupId);
        assertFalse(groupsContract.isMember(groupId, bob));

        // Bob can be re-invited and re-accept
        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encryptedKeyBob);
        vm.prank(bob);
        groupsContract.acceptGroupInvite(groupId);

        assertTrue(groupsContract.isMember(groupId, bob));
        (, , uint256 memberCount) = groupsContract.groups(groupId);
        assertEq(memberCount, 2);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    function test_getMembers_returnsList() public {
        uint256 groupId = _createGroupAsAlice();

        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encryptedKeyBob);
        vm.prank(bob);
        groupsContract.acceptGroupInvite(groupId);

        address[] memory members = groupsContract.getMembers(groupId);
        assertEq(members.length, 2);
        assertEq(members[0], alice);
        assertEq(members[1], bob);
    }

    function test_getGroupCreator() public {
        uint256 groupId = _createGroupAsAlice();
        assertEq(groupsContract.getGroupCreator(groupId), alice);
    }

    // ──────────────────────────────────────────────
    //  Upgrade
    // ──────────────────────────────────────────────

    function test_upgrade_onlyOwner() public {
        khaaliSplitGroups newImpl = new khaaliSplitGroups();
        vm.prank(owner);
        groupsContract.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_notOwner_reverts() public {
        khaaliSplitGroups newImpl = new khaaliSplitGroups();
        vm.prank(alice);
        vm.expectRevert();
        groupsContract.upgradeToAndCall(address(newImpl), "");
    }
}
