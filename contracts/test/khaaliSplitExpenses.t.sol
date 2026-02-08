// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliSplitFriends} from "../src/khaaliSplitFriends.sol";
import {khaaliSplitGroups} from "../src/khaaliSplitGroups.sol";
import {khaaliSplitExpenses} from "../src/khaaliSplitExpenses.sol";

contract khaaliSplitExpensesTest is Test {
    khaaliSplitFriends public friends;
    khaaliSplitGroups public groupsContract;
    khaaliSplitExpenses public expensesContract;

    address owner = makeAddr("owner");
    address backend = makeAddr("backend");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address stranger = makeAddr("stranger");

    uint256 groupId;
    bytes32 dataHash = keccak256("expense data");
    bytes encryptedData = hex"aabbccddee";

    function setUp() public {
        // ── Deploy Friends ──
        khaaliSplitFriends friendsImpl = new khaaliSplitFriends();
        ERC1967Proxy friendsProxy = new ERC1967Proxy(
            address(friendsImpl),
            abi.encodeCall(khaaliSplitFriends.initialize, (backend, owner))
        );
        friends = khaaliSplitFriends(address(friendsProxy));

        // Register & befriend alice <-> bob
        vm.startPrank(backend);
        friends.registerPubKey(alice, hex"04aa");
        friends.registerPubKey(bob, hex"04bb");
        vm.stopPrank();

        vm.prank(alice);
        friends.requestFriend(bob);
        vm.prank(bob);
        friends.acceptFriend(alice);

        // ── Deploy Groups ──
        khaaliSplitGroups groupsImpl = new khaaliSplitGroups();
        ERC1967Proxy groupsProxy = new ERC1967Proxy(
            address(groupsImpl),
            abi.encodeCall(khaaliSplitGroups.initialize, (address(friends), owner))
        );
        groupsContract = khaaliSplitGroups(address(groupsProxy));

        // Create group as alice, invite + accept bob
        vm.prank(alice);
        groupId = groupsContract.createGroup(keccak256("Trip"), hex"aa");

        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, hex"bb");
        vm.prank(bob);
        groupsContract.acceptGroupInvite(groupId);

        // ── Deploy Expenses ──
        khaaliSplitExpenses expensesImpl = new khaaliSplitExpenses();
        ERC1967Proxy expensesProxy = new ERC1967Proxy(
            address(expensesImpl),
            abi.encodeCall(khaaliSplitExpenses.initialize, (address(groupsContract), owner))
        );
        expensesContract = khaaliSplitExpenses(address(expensesProxy));

        // Set backend on Expenses
        vm.prank(owner);
        expensesContract.setBackend(backend);
    }

    // ──────────────────────────────────────────────
    //  Initialization
    // ──────────────────────────────────────────────

    function test_initialize_setsState() public view {
        assertEq(address(expensesContract.groupRegistry()), address(groupsContract));
        assertEq(expensesContract.owner(), owner);
        assertEq(expensesContract.expenseCount(), 0);
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert();
        expensesContract.initialize(address(groupsContract), owner);
    }

    // ──────────────────────────────────────────────
    //  Add expense
    // ──────────────────────────────────────────────

    function test_addExpense_byMember() public {
        vm.prank(alice);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        assertEq(expenseId, 1);
        assertEq(expensesContract.expenseCount(), 1);

        (uint256 gId, address creator, bytes32 dHash, uint256 ts) =
            expensesContract.getExpense(expenseId);

        assertEq(gId, groupId);
        assertEq(creator, alice);
        assertEq(dHash, dataHash);
        assertEq(ts, block.timestamp);
    }

    function test_addExpense_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit khaaliSplitExpenses.ExpenseAdded(groupId, 1, alice, dataHash, encryptedData);
        expensesContract.addExpense(groupId, dataHash, encryptedData);
    }

    function test_addExpense_nonMember_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                khaaliSplitExpenses.NotGroupMember.selector,
                groupId,
                stranger
            )
        );
        expensesContract.addExpense(groupId, dataHash, encryptedData);
    }

    function test_addExpense_multipleExpensesPerGroup() public {
        bytes32 hash1 = keccak256("expense 1");
        bytes32 hash2 = keccak256("expense 2");
        bytes32 hash3 = keccak256("expense 3");

        vm.prank(alice);
        expensesContract.addExpense(groupId, hash1, hex"01");
        vm.prank(bob);
        expensesContract.addExpense(groupId, hash2, hex"02");
        vm.prank(alice);
        expensesContract.addExpense(groupId, hash3, hex"03");

        assertEq(expensesContract.expenseCount(), 3);

        uint256[] memory ids = expensesContract.getGroupExpenses(groupId);
        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(ids[2], 3);
    }

    function test_addExpense_encryptedDataInEvent() public {
        bytes memory longEncData = hex"deadbeefcafebabe0123456789abcdef";

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit khaaliSplitExpenses.ExpenseAdded(groupId, 1, alice, dataHash, longEncData);
        expensesContract.addExpense(groupId, dataHash, longEncData);
    }

    // ──────────────────────────────────────────────
    //  Update expense
    // ──────────────────────────────────────────────

    function test_updateExpense_success() public {
        vm.prank(alice);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        bytes32 newHash = keccak256("updated expense");
        bytes memory newData = hex"ffff";

        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        expensesContract.updateExpense(expenseId, newHash, newData);

        (uint256 gId, address creator, bytes32 dHash, uint256 ts) =
            expensesContract.getExpense(expenseId);

        // groupId and creator unchanged
        assertEq(gId, groupId);
        assertEq(creator, alice);
        // dataHash and timestamp updated
        assertEq(dHash, newHash);
        assertEq(ts, block.timestamp);
    }

    function test_updateExpense_emitsEvent() public {
        vm.prank(alice);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        bytes32 newHash = keccak256("updated expense");
        bytes memory newData = hex"ffff";

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit khaaliSplitExpenses.ExpenseUpdated(groupId, expenseId, alice, newHash, newData);
        expensesContract.updateExpense(expenseId, newHash, newData);
    }

    function test_updateExpense_notCreator_reverts() public {
        vm.prank(alice);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                khaaliSplitExpenses.NotExpenseCreator.selector,
                expenseId,
                bob
            )
        );
        expensesContract.updateExpense(expenseId, keccak256("x"), hex"00");
    }

    function test_updateExpense_doesNotExist_reverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitExpenses.ExpenseDoesNotExist.selector, 999)
        );
        expensesContract.updateExpense(999, keccak256("x"), hex"00");
    }

    function test_updateExpense_notGroupMember_reverts() public {
        // Alice adds expense, bob leaves group, then alice leaves... wait, alice is creator.
        // Let's have bob add expense, then bob leaves group, then tries to update.
        vm.prank(bob);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        // Bob leaves the group
        vm.prank(bob);
        groupsContract.leaveGroup(groupId);

        // Bob tries to update — should revert because he's no longer a member
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                khaaliSplitExpenses.NotGroupMember.selector,
                groupId,
                bob
            )
        );
        expensesContract.updateExpense(expenseId, keccak256("x"), hex"00");
    }

    // ══════════════════════════════════════════════
    //  Backend relay: addExpenseFor
    // ══════════════════════════════════════════════

    function test_addExpenseFor_success() public {
        vm.prank(backend);
        vm.expectEmit(true, true, true, true);
        emit khaaliSplitExpenses.ExpenseAdded(groupId, 1, alice, dataHash, encryptedData);
        uint256 expenseId = expensesContract.addExpenseFor(alice, groupId, dataHash, encryptedData);

        assertEq(expenseId, 1);
        assertEq(expensesContract.expenseCount(), 1);

        (uint256 gId, address creator, bytes32 dHash, uint256 ts) =
            expensesContract.getExpense(expenseId);

        assertEq(gId, groupId);
        assertEq(creator, alice);
        assertEq(dHash, dataHash);
        assertEq(ts, block.timestamp);

        uint256[] memory ids = expensesContract.getGroupExpenses(groupId);
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);
    }

    function test_addExpenseFor_notBackend_reverts() public {
        vm.prank(alice);
        vm.expectRevert(khaaliSplitExpenses.NotBackend.selector);
        expensesContract.addExpenseFor(alice, groupId, dataHash, encryptedData);
    }

    function test_addExpenseFor_notGroupMember_reverts() public {
        vm.prank(backend);
        vm.expectRevert(
            abi.encodeWithSelector(
                khaaliSplitExpenses.NotGroupMember.selector,
                groupId,
                stranger
            )
        );
        expensesContract.addExpenseFor(stranger, groupId, dataHash, encryptedData);
    }

    function test_addExpenseFor_originalStillWorks() public {
        vm.prank(alice);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);
        assertEq(expenseId, 1);
    }

    // ══════════════════════════════════════════════
    //  Backend relay: updateExpenseFor
    // ══════════════════════════════════════════════

    function test_updateExpenseFor_success() public {
        vm.prank(alice);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        bytes32 newHash = keccak256("updated expense");
        bytes memory newData = hex"ffff";

        vm.warp(block.timestamp + 100);
        vm.prank(backend);
        vm.expectEmit(true, true, true, true);
        emit khaaliSplitExpenses.ExpenseUpdated(groupId, expenseId, alice, newHash, newData);
        expensesContract.updateExpenseFor(alice, expenseId, newHash, newData);

        (uint256 gId, address creator, bytes32 dHash, uint256 ts) =
            expensesContract.getExpense(expenseId);

        assertEq(gId, groupId);
        assertEq(creator, alice);
        assertEq(dHash, newHash);
        assertEq(ts, block.timestamp);
    }

    function test_updateExpenseFor_notBackend_reverts() public {
        vm.prank(alice);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        vm.prank(alice);
        vm.expectRevert(khaaliSplitExpenses.NotBackend.selector);
        expensesContract.updateExpenseFor(alice, expenseId, keccak256("x"), hex"00");
    }

    function test_updateExpenseFor_notCreator_reverts() public {
        vm.prank(alice);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        vm.prank(backend);
        vm.expectRevert(
            abi.encodeWithSelector(
                khaaliSplitExpenses.NotExpenseCreator.selector,
                expenseId,
                bob
            )
        );
        expensesContract.updateExpenseFor(bob, expenseId, keccak256("x"), hex"00");
    }

    function test_updateExpenseFor_doesNotExist_reverts() public {
        vm.prank(backend);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitExpenses.ExpenseDoesNotExist.selector, 999)
        );
        expensesContract.updateExpenseFor(alice, 999, keccak256("x"), hex"00");
    }

    function test_updateExpenseFor_notGroupMember_reverts() public {
        // Bob adds expense, then leaves group, then tries to update via relay
        vm.prank(bob);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        vm.prank(bob);
        groupsContract.leaveGroup(groupId);

        vm.prank(backend);
        vm.expectRevert(
            abi.encodeWithSelector(
                khaaliSplitExpenses.NotGroupMember.selector,
                groupId,
                bob
            )
        );
        expensesContract.updateExpenseFor(bob, expenseId, keccak256("x"), hex"00");
    }

    function test_updateExpenseFor_originalStillWorks() public {
        vm.prank(alice);
        uint256 expenseId = expensesContract.addExpense(groupId, dataHash, encryptedData);

        vm.prank(alice);
        expensesContract.updateExpense(expenseId, keccak256("updated"), hex"ff");
        (, , bytes32 dHash, ) = expensesContract.getExpense(expenseId);
        assertEq(dHash, keccak256("updated"));
    }

    // ══════════════════════════════════════════════
    //  Admin (Expenses)
    // ══════════════════════════════════════════════

    function test_setBackend_expenses_success() public {
        address newBackend = makeAddr("newBackend");
        vm.prank(owner);
        expensesContract.setBackend(newBackend);
        assertEq(expensesContract.backend(), newBackend);
    }

    function test_setBackend_expenses_notOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        expensesContract.setBackend(alice);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    function test_getGroupExpenses_empty() public view {
        uint256[] memory ids = expensesContract.getGroupExpenses(999);
        assertEq(ids.length, 0);
    }

    // ──────────────────────────────────────────────
    //  Upgrade
    // ──────────────────────────────────────────────

    function test_upgrade_onlyOwner() public {
        khaaliSplitExpenses newImpl = new khaaliSplitExpenses();
        vm.prank(owner);
        expensesContract.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_notOwner_reverts() public {
        khaaliSplitExpenses newImpl = new khaaliSplitExpenses();
        vm.prank(alice);
        vm.expectRevert();
        expensesContract.upgradeToAndCall(address(newImpl), "");
    }
}
