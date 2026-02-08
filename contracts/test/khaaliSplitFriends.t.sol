// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliSplitFriends} from "../src/khaaliSplitFriends.sol";

contract khaaliSplitFriendsTest is Test {
    khaaliSplitFriends public friends;

    address owner = makeAddr("owner");
    address backend = makeAddr("backend");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    bytes alicePubKey = hex"04aabbccdd";
    bytes bobPubKey = hex"04eeff0011";
    bytes charliePubKey = hex"04deadbeef";

    function setUp() public {
        // Deploy implementation
        khaaliSplitFriends impl = new khaaliSplitFriends();

        // Deploy proxy with initializer
        bytes memory initData = abi.encodeCall(
            khaaliSplitFriends.initialize,
            (backend, owner)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        friends = khaaliSplitFriends(address(proxy));
    }

    // ──────────────────────────────────────────────
    //  Initialization
    // ──────────────────────────────────────────────

    function test_initialize_setsState() public view {
        assertEq(friends.backend(), backend);
        assertEq(friends.owner(), owner);
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert();
        friends.initialize(backend, owner);
    }

    // ──────────────────────────────────────────────
    //  PubKey registration
    // ──────────────────────────────────────────────

    function test_registerPubKey_byBackend() public {
        vm.prank(backend);
        friends.registerPubKey(alice, alicePubKey);

        assertTrue(friends.registered(alice));
        assertEq(friends.getPubKey(alice), alicePubKey);
    }

    function test_registerPubKey_emitsEvent() public {
        vm.prank(backend);
        vm.expectEmit(true, false, false, true);
        emit khaaliSplitFriends.PubKeyRegistered(alice, alicePubKey);
        friends.registerPubKey(alice, alicePubKey);
    }

    function test_registerPubKey_notBackend_reverts() public {
        vm.prank(alice);
        vm.expectRevert(khaaliSplitFriends.NotBackend.selector);
        friends.registerPubKey(alice, alicePubKey);
    }

    function test_registerPubKey_alreadyRegistered_reverts() public {
        vm.prank(backend);
        friends.registerPubKey(alice, alicePubKey);

        vm.prank(backend);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitFriends.AlreadyRegistered.selector, alice)
        );
        friends.registerPubKey(alice, alicePubKey);
    }

    // ──────────────────────────────────────────────
    //  Friend requests
    // ──────────────────────────────────────────────

    function _registerAliceAndBob() internal {
        vm.startPrank(backend);
        friends.registerPubKey(alice, alicePubKey);
        friends.registerPubKey(bob, bobPubKey);
        vm.stopPrank();
    }

    function test_requestFriend_success() public {
        _registerAliceAndBob();

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitFriends.FriendRequested(alice, bob);
        friends.requestFriend(bob);

        assertTrue(friends.pendingRequest(alice, bob));
    }

    function test_requestFriend_notRegistered_sender_reverts() public {
        vm.prank(backend);
        friends.registerPubKey(bob, bobPubKey);

        vm.prank(alice); // alice not registered
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitFriends.NotRegistered.selector, alice)
        );
        friends.requestFriend(bob);
    }

    function test_requestFriend_notRegistered_target_reverts() public {
        vm.prank(backend);
        friends.registerPubKey(alice, alicePubKey);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitFriends.NotRegistered.selector, bob)
        );
        friends.requestFriend(bob); // bob not registered
    }

    function test_requestFriend_self_reverts() public {
        vm.prank(backend);
        friends.registerPubKey(alice, alicePubKey);

        vm.prank(alice);
        vm.expectRevert(khaaliSplitFriends.CannotFriendSelf.selector);
        friends.requestFriend(alice);
    }

    function test_requestFriend_alreadyFriends_reverts() public {
        _registerAliceAndBob();

        vm.prank(alice);
        friends.requestFriend(bob);
        vm.prank(bob);
        friends.acceptFriend(alice);

        vm.prank(alice);
        vm.expectRevert(khaaliSplitFriends.AlreadyFriends.selector);
        friends.requestFriend(bob);
    }

    function test_requestFriend_alreadyRequested_reverts() public {
        _registerAliceAndBob();

        vm.prank(alice);
        friends.requestFriend(bob);

        vm.prank(alice);
        vm.expectRevert(khaaliSplitFriends.AlreadyRequested.selector);
        friends.requestFriend(bob);
    }

    // ──────────────────────────────────────────────
    //  Mutual request auto-accept
    // ──────────────────────────────────────────────

    function test_requestFriend_mutualRequest_autoAccepts() public {
        _registerAliceAndBob();

        // Bob requests alice first
        vm.prank(bob);
        friends.requestFriend(alice);
        assertTrue(friends.pendingRequest(bob, alice));

        // Alice requests bob → should auto-accept
        vm.prank(alice);
        friends.requestFriend(bob);

        // Both should be friends now
        assertTrue(friends.isFriend(alice, bob));
        assertTrue(friends.isFriend(bob, alice));
        // Pending request should be cleaned up
        assertFalse(friends.pendingRequest(bob, alice));
        assertFalse(friends.pendingRequest(alice, bob));
        // Both should appear in each other's friend lists
        assertEq(friends.getFriends(alice).length, 1);
        assertEq(friends.getFriends(alice)[0], bob);
        assertEq(friends.getFriends(bob).length, 1);
        assertEq(friends.getFriends(bob)[0], alice);
    }

    function test_requestFriend_mutualRequest_emitsFriendAccepted() public {
        _registerAliceAndBob();

        vm.prank(bob);
        friends.requestFriend(alice);

        // When alice requests bob, expect FriendAccepted (NOT FriendRequested)
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitFriends.FriendAccepted(alice, bob);
        friends.requestFriend(bob);
    }

    function test_requestFriend_mutualRequest_thenAlreadyFriends() public {
        _registerAliceAndBob();

        // Mutual request → auto-accept
        vm.prank(bob);
        friends.requestFriend(alice);
        vm.prank(alice);
        friends.requestFriend(bob);

        // Re-requesting should revert with AlreadyFriends
        vm.prank(alice);
        vm.expectRevert(khaaliSplitFriends.AlreadyFriends.selector);
        friends.requestFriend(bob);
    }

    // ──────────────────────────────────────────────
    //  Accept friend
    // ──────────────────────────────────────────────

    function test_acceptFriend_success() public {
        _registerAliceAndBob();

        vm.prank(alice);
        friends.requestFriend(bob);

        vm.prank(bob);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitFriends.FriendAccepted(bob, alice);
        friends.acceptFriend(alice);

        assertTrue(friends.isFriend(alice, bob));
        assertTrue(friends.isFriend(bob, alice));
        assertFalse(friends.pendingRequest(alice, bob));
    }

    function test_acceptFriend_noPending_reverts() public {
        _registerAliceAndBob();

        vm.prank(bob);
        vm.expectRevert(khaaliSplitFriends.NoPendingRequest.selector);
        friends.acceptFriend(alice);
    }

    // ──────────────────────────────────────────────
    //  Remove friend
    // ──────────────────────────────────────────────

    function _makeFriends() internal {
        _registerAliceAndBob();
        vm.prank(alice);
        friends.requestFriend(bob);
        vm.prank(bob);
        friends.acceptFriend(alice);
    }

    function test_removeFriend_success() public {
        _makeFriends();

        vm.prank(alice);
        friends.removeFriend(bob);

        assertFalse(friends.isFriend(alice, bob));
        assertFalse(friends.isFriend(bob, alice));
    }

    function test_removeFriend_emitsEvent() public {
        _makeFriends();

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitFriends.FriendRemoved(alice, bob);
        friends.removeFriend(bob);
    }

    function test_removeFriend_notFriends_reverts() public {
        _registerAliceAndBob();

        vm.prank(alice);
        vm.expectRevert(khaaliSplitFriends.NotFriends.selector);
        friends.removeFriend(bob);
    }

    function test_removeFriend_canReRequest() public {
        _makeFriends();

        // Remove
        vm.prank(alice);
        friends.removeFriend(bob);

        // Re-request and re-accept
        vm.prank(alice);
        friends.requestFriend(bob);
        vm.prank(bob);
        friends.acceptFriend(alice);

        assertTrue(friends.isFriend(alice, bob));
        assertTrue(friends.isFriend(bob, alice));
    }

    function test_removeFriend_bothDirections() public {
        _makeFriends();

        // Bob removes alice (not just alice removes bob)
        vm.prank(bob);
        friends.removeFriend(alice);

        assertFalse(friends.isFriend(alice, bob));
        assertFalse(friends.isFriend(bob, alice));
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    function test_getFriends_returnsList() public {
        _registerAliceAndBob();
        vm.prank(backend);
        friends.registerPubKey(charlie, charliePubKey);

        // alice -> bob
        vm.prank(alice);
        friends.requestFriend(bob);
        vm.prank(bob);
        friends.acceptFriend(alice);

        // alice -> charlie
        vm.prank(alice);
        friends.requestFriend(charlie);
        vm.prank(charlie);
        friends.acceptFriend(alice);

        address[] memory aliceFriends = friends.getFriends(alice);
        assertEq(aliceFriends.length, 2);
        assertEq(aliceFriends[0], bob);
        assertEq(aliceFriends[1], charlie);

        address[] memory bobFriends = friends.getFriends(bob);
        assertEq(bobFriends.length, 1);
        assertEq(bobFriends[0], alice);
    }

    // ══════════════════════════════════════════════
    //  Backend relay: requestFriendFor
    // ══════════════════════════════════════════════

    function test_requestFriendFor_success() public {
        _registerAliceAndBob();

        vm.prank(backend);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitFriends.FriendRequested(alice, bob);
        friends.requestFriendFor(alice, bob);

        assertTrue(friends.pendingRequest(alice, bob));
    }

    function test_requestFriendFor_notBackend_reverts() public {
        _registerAliceAndBob();

        vm.prank(alice);
        vm.expectRevert(khaaliSplitFriends.NotBackend.selector);
        friends.requestFriendFor(alice, bob);
    }

    function test_requestFriendFor_notRegistered_user_reverts() public {
        vm.prank(backend);
        friends.registerPubKey(bob, bobPubKey);

        vm.prank(backend);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitFriends.NotRegistered.selector, alice)
        );
        friends.requestFriendFor(alice, bob);
    }

    function test_requestFriendFor_notRegistered_friend_reverts() public {
        vm.prank(backend);
        friends.registerPubKey(alice, alicePubKey);

        vm.prank(backend);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitFriends.NotRegistered.selector, bob)
        );
        friends.requestFriendFor(alice, bob);
    }

    function test_requestFriendFor_self_reverts() public {
        vm.prank(backend);
        friends.registerPubKey(alice, alicePubKey);

        vm.prank(backend);
        vm.expectRevert(khaaliSplitFriends.CannotFriendSelf.selector);
        friends.requestFriendFor(alice, alice);
    }

    function test_requestFriendFor_alreadyFriends_reverts() public {
        _registerAliceAndBob();

        vm.startPrank(backend);
        friends.requestFriendFor(alice, bob);
        friends.acceptFriendFor(bob, alice);
        vm.stopPrank();

        vm.prank(backend);
        vm.expectRevert(khaaliSplitFriends.AlreadyFriends.selector);
        friends.requestFriendFor(alice, bob);
    }

    function test_requestFriendFor_alreadyRequested_reverts() public {
        _registerAliceAndBob();

        vm.prank(backend);
        friends.requestFriendFor(alice, bob);

        vm.prank(backend);
        vm.expectRevert(khaaliSplitFriends.AlreadyRequested.selector);
        friends.requestFriendFor(alice, bob);
    }

    function test_requestFriendFor_mutualRequest_autoAccepts() public {
        _registerAliceAndBob();

        vm.startPrank(backend);
        friends.requestFriendFor(bob, alice);
        assertTrue(friends.pendingRequest(bob, alice));

        vm.expectEmit(true, true, false, false);
        emit khaaliSplitFriends.FriendAccepted(alice, bob);
        friends.requestFriendFor(alice, bob);
        vm.stopPrank();

        assertTrue(friends.isFriend(alice, bob));
        assertTrue(friends.isFriend(bob, alice));
        assertFalse(friends.pendingRequest(bob, alice));
        assertFalse(friends.pendingRequest(alice, bob));
        assertEq(friends.getFriends(alice).length, 1);
        assertEq(friends.getFriends(bob).length, 1);
    }

    function test_requestFriendFor_originalStillWorks() public {
        _registerAliceAndBob();

        // User calls directly — should still work
        vm.prank(alice);
        friends.requestFriend(bob);
        assertTrue(friends.pendingRequest(alice, bob));
    }

    // ══════════════════════════════════════════════
    //  Backend relay: acceptFriendFor
    // ══════════════════════════════════════════════

    function test_acceptFriendFor_success() public {
        _registerAliceAndBob();

        vm.prank(alice);
        friends.requestFriend(bob);

        vm.prank(backend);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitFriends.FriendAccepted(bob, alice);
        friends.acceptFriendFor(bob, alice);

        assertTrue(friends.isFriend(alice, bob));
        assertTrue(friends.isFriend(bob, alice));
        assertFalse(friends.pendingRequest(alice, bob));
        assertEq(friends.getFriends(alice).length, 1);
        assertEq(friends.getFriends(bob).length, 1);
    }

    function test_acceptFriendFor_notBackend_reverts() public {
        _registerAliceAndBob();

        vm.prank(alice);
        friends.requestFriend(bob);

        vm.prank(bob);
        vm.expectRevert(khaaliSplitFriends.NotBackend.selector);
        friends.acceptFriendFor(bob, alice);
    }

    function test_acceptFriendFor_noPending_reverts() public {
        _registerAliceAndBob();

        vm.prank(backend);
        vm.expectRevert(khaaliSplitFriends.NoPendingRequest.selector);
        friends.acceptFriendFor(bob, alice);
    }

    function test_acceptFriendFor_originalStillWorks() public {
        _registerAliceAndBob();

        vm.prank(alice);
        friends.requestFriend(bob);

        // User calls directly — should still work
        vm.prank(bob);
        friends.acceptFriend(alice);
        assertTrue(friends.isFriend(alice, bob));
    }

    // ══════════════════════════════════════════════
    //  Backend relay: removeFriendFor
    // ══════════════════════════════════════════════

    function test_removeFriendFor_success() public {
        _makeFriends();

        vm.prank(backend);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitFriends.FriendRemoved(alice, bob);
        friends.removeFriendFor(alice, bob);

        assertFalse(friends.isFriend(alice, bob));
        assertFalse(friends.isFriend(bob, alice));
    }

    function test_removeFriendFor_notBackend_reverts() public {
        _makeFriends();

        vm.prank(alice);
        vm.expectRevert(khaaliSplitFriends.NotBackend.selector);
        friends.removeFriendFor(alice, bob);
    }

    function test_removeFriendFor_notFriends_reverts() public {
        _registerAliceAndBob();

        vm.prank(backend);
        vm.expectRevert(khaaliSplitFriends.NotFriends.selector);
        friends.removeFriendFor(alice, bob);
    }

    function test_removeFriendFor_originalStillWorks() public {
        _makeFriends();

        // User calls directly — should still work
        vm.prank(alice);
        friends.removeFriend(bob);
        assertFalse(friends.isFriend(alice, bob));
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    function test_setBackend_onlyOwner() public {
        address newBackend = makeAddr("newBackend");

        vm.prank(owner);
        friends.setBackend(newBackend);
        assertEq(friends.backend(), newBackend);
    }

    function test_setBackend_notOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        friends.setBackend(alice);
    }

    // ──────────────────────────────────────────────
    //  Upgrade
    // ──────────────────────────────────────────────

    function test_upgrade_onlyOwner() public {
        khaaliSplitFriends newImpl = new khaaliSplitFriends();

        vm.prank(owner);
        friends.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_notOwner_reverts() public {
        khaaliSplitFriends newImpl = new khaaliSplitFriends();

        vm.prank(alice);
        vm.expectRevert();
        friends.upgradeToAndCall(address(newImpl), "");
    }
}
