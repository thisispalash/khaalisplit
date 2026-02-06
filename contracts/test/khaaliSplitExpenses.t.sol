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
