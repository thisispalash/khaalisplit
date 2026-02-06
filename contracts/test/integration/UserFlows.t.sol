// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliSplitFriends} from "../../src/khaaliSplitFriends.sol";
import {khaaliSplitGroups} from "../../src/khaaliSplitGroups.sol";
import {khaaliSplitExpenses} from "../../src/khaaliSplitExpenses.sol";
import {khaaliSplitSettlement} from "../../src/khaaliSplitSettlement.sol";
import {kdioDeployer} from "../../src/kdioDeployer.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";

/**
 * @title UserFlows — Integration Tests
 * @notice End-to-end tests covering full user flows from the khaaliSplit PRD.
 *         Deploys all contracts through ERC1967 proxies, wires them together,
 *         and exercises multi-contract interactions.
 */
contract UserFlowsTest is Test {
    // ── Contracts ──
    khaaliSplitFriends public friends;
    khaaliSplitGroups public groupsContract;
    khaaliSplitExpenses public expensesContract;
    khaaliSplitSettlement public settlement;
    MockUSDC public usdc;

    // ── Accounts ──
    address owner = makeAddr("owner");
    address backend = makeAddr("backend");

    address alice;
    uint256 aliceKey;
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    // ── Constants ──
    bytes alicePubKey = hex"04aabbccdd";
    bytes bobPubKey = hex"04eeff0011";
    bytes charliePubKey = hex"04deadbeef";

    bytes32 groupNameHash = keccak256("Trip to Goa");
    bytes encKeyAlice = hex"aabb";
    bytes encKeyBob = hex"ccdd";
    bytes encKeyCharlie = hex"eeff";

    uint256 constant DEST_CHAIN_ID = 42161;
    uint256 constant SETTLE_AMOUNT = 50e6;

    // ──────────────────────────────────────────────
    //  Setup
    // ──────────────────────────────────────────────

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        _deployAll();
        _registerUsers();
    }

    function _deployAll() internal {
        // ── Friends ──
        khaaliSplitFriends friendsImpl = new khaaliSplitFriends();
        ERC1967Proxy friendsProxy = new ERC1967Proxy(
            address(friendsImpl),
            abi.encodeCall(khaaliSplitFriends.initialize, (backend, owner))
        );
        friends = khaaliSplitFriends(address(friendsProxy));

        // ── Groups ──
        khaaliSplitGroups groupsImpl = new khaaliSplitGroups();
        ERC1967Proxy groupsProxy = new ERC1967Proxy(
            address(groupsImpl),
            abi.encodeCall(khaaliSplitGroups.initialize, (address(friends), owner))
        );
        groupsContract = khaaliSplitGroups(address(groupsProxy));

        // ── Expenses ──
        khaaliSplitExpenses expensesImpl = new khaaliSplitExpenses();
        ERC1967Proxy expensesProxy = new ERC1967Proxy(
            address(expensesImpl),
            abi.encodeCall(khaaliSplitExpenses.initialize, (address(groupsContract), owner))
        );
        expensesContract = khaaliSplitExpenses(address(expensesProxy));

        // ── Settlement + USDC ──
        usdc = new MockUSDC();

        khaaliSplitSettlement settlementImpl = new khaaliSplitSettlement();
        ERC1967Proxy settlementProxy = new ERC1967Proxy(
            address(settlementImpl),
            abi.encodeCall(khaaliSplitSettlement.initialize, (owner))
        );
        settlement = khaaliSplitSettlement(address(settlementProxy));

        vm.prank(owner);
        settlement.addToken(address(usdc));
    }

    function _registerUsers() internal {
        vm.startPrank(backend);
        friends.registerPubKey(alice, alicePubKey);
        friends.registerPubKey(bob, bobPubKey);
        friends.registerPubKey(charlie, charliePubKey);
        vm.stopPrank();
    }

    /// @dev alice↔bob via request+accept, alice↔charlie via mutual auto-accept
    function _makeFriends() internal {
        // alice → bob (standard request + accept)
        vm.prank(alice);
        friends.requestFriend(bob);
        vm.prank(bob);
        friends.acceptFriend(alice);

        // alice ↔ charlie via mutual request auto-accept
        vm.prank(charlie);
        friends.requestFriend(alice);
        vm.prank(alice);
        friends.requestFriend(charlie); // auto-accepts
    }

    /// @dev Creates group, invites and accepts bob + charlie
    function _createGroupWithMembers() internal returns (uint256 groupId) {
        _makeFriends();

        vm.prank(alice);
        groupId = groupsContract.createGroup(groupNameHash, encKeyAlice);

        // Invite bob
        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encKeyBob);
        vm.prank(bob);
        groupsContract.acceptGroupInvite(groupId);

        // Invite charlie (alice↔charlie are friends via auto-accept)
        vm.prank(alice);
        groupsContract.inviteMember(groupId, charlie, encKeyCharlie);
        vm.prank(charlie);
        groupsContract.acceptGroupInvite(groupId);
    }

    function _buildPermitDigest(
        MockUSDC token,
        address permitOwner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, permitOwner, spender, value, nonce, deadline)
        );

        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                structHash
            )
        );
    }

    // ──────────────────────────────────────────────
    //  Flow 1: Onboarding → Friends → Group → Expenses
    // ──────────────────────────────────────────────

    function test_flow_onboarding_friends_group_expense() public {
        // Step 1: Make friends
        // alice↔bob (request+accept), alice↔charlie (mutual auto-accept)
        _makeFriends();

        // Verify friendships
        assertTrue(friends.isFriend(alice, bob));
        assertTrue(friends.isFriend(bob, alice));
        assertTrue(friends.isFriend(alice, charlie));
        assertTrue(friends.isFriend(charlie, alice));
        assertFalse(friends.isFriend(bob, charlie)); // not friends with each other

        // Step 2: Create group + invite members
        vm.prank(alice);
        uint256 groupId = groupsContract.createGroup(groupNameHash, encKeyAlice);

        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encKeyBob);
        vm.prank(bob);
        groupsContract.acceptGroupInvite(groupId);

        vm.prank(alice);
        groupsContract.inviteMember(groupId, charlie, encKeyCharlie);
        vm.prank(charlie);
        groupsContract.acceptGroupInvite(groupId);

        // Verify group state
        assertTrue(groupsContract.isMember(groupId, alice));
        assertTrue(groupsContract.isMember(groupId, bob));
        assertTrue(groupsContract.isMember(groupId, charlie));
        (, , uint256 memberCount) = groupsContract.groups(groupId);
        assertEq(memberCount, 3);
        assertEq(groupsContract.getGroupCreator(groupId), alice);

        address[] memory members = groupsContract.getMembers(groupId);
        assertEq(members.length, 3);
        assertEq(members[0], alice);
        assertEq(members[1], bob);
        assertEq(members[2], charlie);

        // Step 3: Add expenses
        bytes32 hash1 = keccak256("dinner");
        bytes32 hash2 = keccak256("taxi");

        vm.prank(alice);
        uint256 e1 = expensesContract.addExpense(groupId, hash1, hex"aa");

        vm.prank(bob);
        uint256 e2 = expensesContract.addExpense(groupId, hash2, hex"bb");

        // Verify expenses
        assertEq(e1, 1);
        assertEq(e2, 2);
        assertEq(expensesContract.expenseCount(), 2);

        uint256[] memory groupExpenses = expensesContract.getGroupExpenses(groupId);
        assertEq(groupExpenses.length, 2);
        assertEq(groupExpenses[0], 1);
        assertEq(groupExpenses[1], 2);

        (uint256 gId, address creator, bytes32 dHash, ) = expensesContract.getExpense(e1);
        assertEq(gId, groupId);
        assertEq(creator, alice);
        assertEq(dHash, hash1);
    }

    // ──────────────────────────────────────────────
    //  Flow 2: Settlement with Permit
    // ──────────────────────────────────────────────

    function test_flow_settlement_with_permit() public {
        _createGroupWithMembers();

        // Alice wants to settle with bob
        usdc.mint(alice, 1000e6);
        uint256 aliceBalBefore = usdc.balanceOf(alice);

        uint256 deadline = block.timestamp + 1 hours;

        // Build permit signature
        bytes32 permitHash = _buildPermitDigest(
            usdc,
            alice,
            address(settlement),
            SETTLE_AMOUNT,
            usdc.nonces(alice),
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, permitHash);

        // Relayer executes settleWithPermit on behalf of alice
        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit khaaliSplitSettlement.SettlementInitiated(
            alice, bob, DEST_CHAIN_ID, address(usdc), SETTLE_AMOUNT, ""
        );
        settlement.settleWithPermit(
            address(usdc), alice, bob, DEST_CHAIN_ID, SETTLE_AMOUNT, "", deadline, v, r, s
        );

        // Verify balances
        assertEq(usdc.balanceOf(alice), aliceBalBefore - SETTLE_AMOUNT);
        assertEq(usdc.balanceOf(address(settlement)), SETTLE_AMOUNT);
    }

    // ──────────────────────────────────────────────
    //  Flow 3: Leave Group + Update Expense
    // ──────────────────────────────────────────────

    function test_flow_leaveGroup_and_updateExpense() public {
        uint256 groupId = _createGroupWithMembers();

        // Alice and charlie add expenses
        bytes32 aliceHash = keccak256("alice expense");
        vm.prank(alice);
        uint256 aliceExpenseId = expensesContract.addExpense(groupId, aliceHash, hex"aa");

        bytes32 charlieHash = keccak256("charlie expense");
        vm.prank(charlie);
        expensesContract.addExpense(groupId, charlieHash, hex"cc");

        // Charlie leaves the group
        vm.prank(charlie);
        groupsContract.leaveGroup(groupId);

        // Verify charlie is no longer a member
        assertFalse(groupsContract.isMember(groupId, charlie));
        (, , uint256 memberCount) = groupsContract.groups(groupId);
        assertEq(memberCount, 2);
        // Encrypted key cleared
        assertEq(groupsContract.encryptedGroupKey(groupId, charlie), "");

        // Charlie cannot add new expenses (reverts)
        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(
                khaaliSplitExpenses.NotGroupMember.selector,
                groupId,
                charlie
            )
        );
        expensesContract.addExpense(groupId, keccak256("x"), hex"00");

        // Alice updates her expense
        bytes32 updatedHash = keccak256("alice expense updated");
        vm.warp(block.timestamp + 60);
        vm.prank(alice);
        expensesContract.updateExpense(aliceExpenseId, updatedHash, hex"aabb");

        (uint256 gId, address creator, bytes32 dHash, uint256 ts) =
            expensesContract.getExpense(aliceExpenseId);
        assertEq(gId, groupId);
        assertEq(creator, alice);
        assertEq(dHash, updatedHash);
        assertEq(ts, block.timestamp);
    }

    // ──────────────────────────────────────────────
    //  Flow 4: Remove Friend — No Cascade to Groups
    // ──────────────────────────────────────────────

    function test_flow_removeFriend_no_cascade() public {
        uint256 groupId = _createGroupWithMembers();

        // Alice removes bob as friend
        vm.prank(alice);
        friends.removeFriend(bob);

        // Friendship is gone
        assertFalse(friends.isFriend(alice, bob));
        assertFalse(friends.isFriend(bob, alice));

        // But bob is still a group member (no cascade)
        assertTrue(groupsContract.isMember(groupId, bob));

        // Bob can still add expenses
        bytes32 expHash = keccak256("bob expense after unfriend");
        vm.prank(bob);
        uint256 expenseId = expensesContract.addExpense(groupId, expHash, hex"bb");
        assertEq(expenseId, 1);

        (uint256 gId, address creator, bytes32 dHash, ) = expensesContract.getExpense(expenseId);
        assertEq(gId, groupId);
        assertEq(creator, bob);
        assertEq(dHash, expHash);

        // But alice can no longer invite new members who are only friends with
        // the now-unfriended bob (since friendship check is on inviter)
        // This is expected behavior — group membership ≠ friendship
    }

    // ──────────────────────────────────────────────
    //  Flow 5: kdioDeployer End-to-End
    // ──────────────────────────────────────────────

    function test_flow_kdioDeployer_endToEnd() public {
        kdioDeployer deployer = new kdioDeployer();

        // ── Deploy Friends via CREATE2 ──
        khaaliSplitFriends friendsImpl = new khaaliSplitFriends();
        bytes32 friendsSalt = keccak256("khaaliSplitFriends-v1");
        bytes memory friendsInitData = abi.encodeCall(
            khaaliSplitFriends.initialize,
            (backend, owner)
        );

        address predictedFriends = deployer.computeAddress(friendsSalt, address(friendsImpl), friendsInitData);
        address actualFriends = deployer.deploy(friendsSalt, address(friendsImpl), friendsInitData);
        assertEq(actualFriends, predictedFriends);

        khaaliSplitFriends f = khaaliSplitFriends(actualFriends);
        assertEq(f.backend(), backend);
        assertEq(f.owner(), owner);

        // ── Deploy Groups via CREATE2 ──
        khaaliSplitGroups groupsImpl = new khaaliSplitGroups();
        bytes32 groupsSalt = keccak256("khaaliSplitGroups-v1");
        bytes memory groupsInitData = abi.encodeCall(
            khaaliSplitGroups.initialize,
            (actualFriends, owner)
        );

        address actualGroups = deployer.deploy(groupsSalt, address(groupsImpl), groupsInitData);
        khaaliSplitGroups g = khaaliSplitGroups(actualGroups);
        assertEq(address(g.friendRegistry()), actualFriends);

        // ── Deploy Expenses via CREATE2 ──
        khaaliSplitExpenses expensesImpl = new khaaliSplitExpenses();
        bytes32 expensesSalt = keccak256("khaaliSplitExpenses-v1");
        bytes memory expensesInitData = abi.encodeCall(
            khaaliSplitExpenses.initialize,
            (actualGroups, owner)
        );

        address actualExpenses = deployer.deploy(expensesSalt, address(expensesImpl), expensesInitData);
        khaaliSplitExpenses e = khaaliSplitExpenses(actualExpenses);
        assertEq(address(e.groupRegistry()), actualGroups);

        // ── Use the deployed contracts ──

        // Register user
        vm.prank(backend);
        f.registerPubKey(alice, alicePubKey);
        assertTrue(f.registered(alice));

        // Register second user + make friends
        vm.prank(backend);
        f.registerPubKey(bob, bobPubKey);
        vm.prank(alice);
        f.requestFriend(bob);
        vm.prank(bob);
        f.acceptFriend(alice);
        assertTrue(f.isFriend(alice, bob));

        // Create group
        vm.prank(alice);
        uint256 groupId = g.createGroup(groupNameHash, encKeyAlice);
        assertTrue(g.isMember(groupId, alice));

        // Invite bob
        vm.prank(alice);
        g.inviteMember(groupId, bob, encKeyBob);
        vm.prank(bob);
        g.acceptGroupInvite(groupId);
        assertTrue(g.isMember(groupId, bob));

        // Add expense
        bytes32 dHash = keccak256("test expense");
        vm.prank(alice);
        uint256 expenseId = e.addExpense(groupId, dHash, hex"deadbeef");
        assertEq(expenseId, 1);

        (uint256 gId, address creator, bytes32 storedHash, ) = e.getExpense(expenseId);
        assertEq(gId, groupId);
        assertEq(creator, alice);
        assertEq(storedHash, dHash);
    }
}
