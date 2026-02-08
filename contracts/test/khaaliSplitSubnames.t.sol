// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliSplitSubnames} from "../src/khaaliSplitSubnames.sol";
import {MockNameWrapper} from "./helpers/MockNameWrapper.sol";

contract khaaliSplitSubnamesTest is Test {
    khaaliSplitSubnames public subnames;
    MockNameWrapper public mockWrapper;

    address owner = makeAddr("owner");
    address backend = makeAddr("backend");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address reputationContract = makeAddr("reputation");

    // Parent node: namehash("khaalisplit.eth")
    // For testing, we use a deterministic value
    bytes32 constant PARENT_NODE = keccak256("khaalisplit.eth.test");

    function setUp() public {
        // Deploy mock NameWrapper
        mockWrapper = new MockNameWrapper();

        // Deploy subnames proxy
        khaaliSplitSubnames impl = new khaaliSplitSubnames();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitSubnames.initialize,
                (address(mockWrapper), PARENT_NODE, backend, owner)
            )
        );
        subnames = khaaliSplitSubnames(address(proxy));
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    /// @dev Compute the expected namehash for a label under PARENT_NODE.
    function _expectedNode(string memory label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PARENT_NODE, keccak256(bytes(label))));
    }

    /// @dev Register a subname via backend and return its node.
    function _registerSubname(string memory label, address subnameOwner) internal returns (bytes32) {
        vm.prank(backend);
        subnames.register(label, subnameOwner);
        return _expectedNode(label);
    }

    // ──────────────────────────────────────────────
    //  Initialization
    // ──────────────────────────────────────────────

    function test_initialize_setsState() public view {
        assertEq(address(subnames.nameWrapper()), address(mockWrapper));
        assertEq(subnames.parentNode(), PARENT_NODE);
        assertEq(subnames.backend(), backend);
        assertEq(subnames.owner(), owner);
        assertEq(subnames.reputationContract(), address(0));
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert();
        subnames.initialize(address(mockWrapper), PARENT_NODE, backend, owner);
    }

    function test_initialize_zeroNameWrapper_reverts() public {
        khaaliSplitSubnames impl = new khaaliSplitSubnames();
        vm.expectRevert(khaaliSplitSubnames.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitSubnames.initialize,
                (address(0), PARENT_NODE, backend, owner)
            )
        );
    }

    function test_initialize_zeroBackend_reverts() public {
        khaaliSplitSubnames impl = new khaaliSplitSubnames();
        vm.expectRevert(khaaliSplitSubnames.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitSubnames.initialize,
                (address(mockWrapper), PARENT_NODE, address(0), owner)
            )
        );
    }

    function test_initialize_zeroOwner_reverts() public {
        khaaliSplitSubnames impl = new khaaliSplitSubnames();
        vm.expectRevert(khaaliSplitSubnames.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitSubnames.initialize,
                (address(mockWrapper), PARENT_NODE, backend, address(0))
            )
        );
    }

    // ──────────────────────────────────────────────
    //  Registration
    // ──────────────────────────────────────────────

    function test_register_success() public {
        bytes32 expectedNode = _expectedNode("alice");

        vm.prank(backend);
        vm.expectEmit(true, true, false, true);
        emit khaaliSplitSubnames.SubnameRegistered(expectedNode, "alice", alice);
        subnames.register("alice", alice);

        // Verify mock NameWrapper was called correctly
        assertEq(mockWrapper.registerCount(), 1);
        (
            bytes32 pNode, , address recOwner, address recResolver,
            uint64 recTtl, uint32 recFuses, uint64 recExpiry
        ) = mockWrapper.lastRecord();
        assertEq(pNode, PARENT_NODE);
        assertEq(recOwner, alice);
        assertEq(recResolver, address(subnames));
        assertEq(recTtl, 0);
        assertEq(recFuses, 0);
        assertEq(recExpiry, type(uint64).max);
    }

    function test_register_setsDefaultTextRecords() public {
        bytes32 node = _registerSubname("alice", alice);

        assertEq(subnames.text(node, "com.khaalisplit.subname"), "alice");
        assertEq(subnames.text(node, "com.khaalisplit.reputation"), "50");
    }

    function test_register_setsDefaultAddrRecord() public {
        bytes32 node = _registerSubname("alice", alice);

        assertEq(subnames.addr(node), alice);
    }

    function test_register_emitsAddrRecordSet() public {
        bytes32 expectedNode = _expectedNode("alice");

        vm.prank(backend);
        vm.expectEmit(true, false, false, true);
        emit khaaliSplitSubnames.AddrRecordSet(expectedNode, alice);
        subnames.register("alice", alice);
    }

    function test_register_multipleSubnames() public {
        bytes32 aliceNode = _registerSubname("alice", alice);
        bytes32 bobNode = _registerSubname("bob", bob);

        // Both should have independent records
        assertEq(subnames.text(aliceNode, "com.khaalisplit.subname"), "alice");
        assertEq(subnames.text(bobNode, "com.khaalisplit.subname"), "bob");
        assertEq(subnames.addr(aliceNode), alice);
        assertEq(subnames.addr(bobNode), bob);
        assertEq(mockWrapper.registerCount(), 2);
    }

    function test_register_notBackend_reverts() public {
        vm.prank(alice);
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.register("alice", alice);
    }

    function test_register_ownerCannotRegister_reverts() public {
        vm.prank(owner);
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.register("alice", alice);
    }

    function test_register_emptyLabel_reverts() public {
        vm.prank(backend);
        vm.expectRevert(khaaliSplitSubnames.EmptyLabel.selector);
        subnames.register("", alice);
    }

    function test_register_zeroAddress_reverts() public {
        vm.prank(backend);
        vm.expectRevert(khaaliSplitSubnames.ZeroAddress.selector);
        subnames.register("alice", address(0));
    }

    function test_register_duplicateLabel_reverts() public {
        _registerSubname("alice", alice);

        vm.prank(backend);
        vm.expectRevert(khaaliSplitSubnames.SubnameAlreadyRegistered.selector);
        subnames.register("alice", bob);
    }

    // ──────────────────────────────────────────────
    //  setText — Owner Authorization
    // ──────────────────────────────────────────────

    function test_setText_bySubnameOwner() public {
        bytes32 node = _registerSubname("alice", alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit khaaliSplitSubnames.TextRecordSet(node, "display", "Alice");
        subnames.setText(node, "display", "Alice");

        assertEq(subnames.text(node, "display"), "Alice");
    }

    function test_setText_overwriteExisting() public {
        bytes32 node = _registerSubname("alice", alice);

        vm.prank(alice);
        subnames.setText(node, "display", "Alice");

        vm.prank(alice);
        subnames.setText(node, "display", "Alice Updated");

        assertEq(subnames.text(node, "display"), "Alice Updated");
    }

    function test_setText_multipleKeys() public {
        bytes32 node = _registerSubname("alice", alice);

        vm.startPrank(alice);
        subnames.setText(node, "display", "Alice");
        subnames.setText(node, "avatar", "https://example.com/alice.png");
        subnames.setText(node, "description", "khaaliSplit user");
        subnames.setText(node, "com.khaalisplit.payment.chain", "8453");
        subnames.setText(node, "com.khaalisplit.payment.token", "USDC");
        vm.stopPrank();

        assertEq(subnames.text(node, "display"), "Alice");
        assertEq(subnames.text(node, "avatar"), "https://example.com/alice.png");
        assertEq(subnames.text(node, "description"), "khaaliSplit user");
        assertEq(subnames.text(node, "com.khaalisplit.payment.chain"), "8453");
        assertEq(subnames.text(node, "com.khaalisplit.payment.token"), "USDC");
    }

    // ──────────────────────────────────────────────
    //  setText — Backend Authorization
    // ──────────────────────────────────────────────

    function test_setText_byBackend() public {
        bytes32 node = _registerSubname("alice", alice);

        vm.prank(backend);
        subnames.setText(node, "display", "Alice via Backend");

        assertEq(subnames.text(node, "display"), "Alice via Backend");
    }

    // ──────────────────────────────────────────────
    //  setText — Reputation Contract Authorization
    // ──────────────────────────────────────────────

    function test_setText_byReputationContract() public {
        bytes32 node = _registerSubname("alice", alice);

        // First, set the reputation contract
        vm.prank(owner);
        subnames.setReputationContract(reputationContract);

        // Reputation contract updates the score
        vm.prank(reputationContract);
        subnames.setText(node, "com.khaalisplit.reputation", "75");

        assertEq(subnames.text(node, "com.khaalisplit.reputation"), "75");
    }

    function test_setText_reputationContractZero_noAuth() public {
        bytes32 node = _registerSubname("alice", alice);

        // reputationContract is address(0) by default, so random addresses shouldn't get auth
        vm.prank(makeAddr("random"));
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.setText(node, "display", "hacked");
    }

    // ──────────────────────────────────────────────
    //  setText — Unauthorized
    // ──────────────────────────────────────────────

    function test_setText_unauthorizedUser_reverts() public {
        bytes32 node = _registerSubname("alice", alice);

        vm.prank(bob);
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.setText(node, "display", "Hacked by Bob");
    }

    function test_setText_cannotModifyOtherSubname() public {
        bytes32 aliceNode = _registerSubname("alice", alice);
        _registerSubname("bob", bob);

        // Bob cannot modify Alice's records
        vm.prank(bob);
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.setText(aliceNode, "display", "Hacked");
    }

    // ──────────────────────────────────────────────
    //  setAddr
    // ──────────────────────────────────────────────

    function test_setAddr_bySubnameOwner() public {
        bytes32 node = _registerSubname("alice", alice);
        address newAddr = makeAddr("aliceNew");

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit khaaliSplitSubnames.AddrRecordSet(node, newAddr);
        subnames.setAddr(node, newAddr);

        assertEq(subnames.addr(node), newAddr);
    }

    function test_setAddr_byBackend() public {
        bytes32 node = _registerSubname("alice", alice);
        address newAddr = makeAddr("aliceNew");

        vm.prank(backend);
        subnames.setAddr(node, newAddr);

        assertEq(subnames.addr(node), newAddr);
    }

    function test_setAddr_unauthorized_reverts() public {
        bytes32 node = _registerSubname("alice", alice);

        vm.prank(bob);
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.setAddr(node, bob);
    }

    // ──────────────────────────────────────────────
    //  Record Getters
    // ──────────────────────────────────────────────

    function test_text_unregisteredNode_returnsEmpty() public view {
        bytes32 fakeNode = keccak256("nonexistent");
        assertEq(subnames.text(fakeNode, "display"), "");
    }

    function test_text_unsetKey_returnsEmpty() public {
        bytes32 node = _registerSubname("alice", alice);
        assertEq(subnames.text(node, "unset_key"), "");
    }

    function test_addr_unregisteredNode_returnsZero() public view {
        bytes32 fakeNode = keccak256("nonexistent");
        assertEq(subnames.addr(fakeNode), address(0));
    }

    // ──────────────────────────────────────────────
    //  subnameNode Utility
    // ──────────────────────────────────────────────

    function test_subnameNode_computation() public view {
        bytes32 expected = keccak256(abi.encodePacked(PARENT_NODE, keccak256(bytes("alice"))));
        assertEq(subnames.subnameNode("alice"), expected);
    }

    function test_subnameNode_differentLabels() public view {
        bytes32 aliceNode = subnames.subnameNode("alice");
        bytes32 bobNode = subnames.subnameNode("bob");
        assertTrue(aliceNode != bobNode);
    }

    function test_subnameNode_consistency() public view {
        // Same label should always produce the same node
        assertEq(subnames.subnameNode("test"), subnames.subnameNode("test"));
    }

    // ──────────────────────────────────────────────
    //  ERC-165
    // ──────────────────────────────────────────────

    function test_supportsInterface_IAddrResolver() public view {
        assertTrue(subnames.supportsInterface(0x3b3b57de));
    }

    function test_supportsInterface_ITextResolver() public view {
        assertTrue(subnames.supportsInterface(0x59d1d43c));
    }

    function test_supportsInterface_IERC165() public view {
        assertTrue(subnames.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_unsupported() public view {
        assertFalse(subnames.supportsInterface(0xdeadbeef));
    }

    // ──────────────────────────────────────────────
    //  Admin — setBackend
    // ──────────────────────────────────────────────

    function test_setBackend_success() public {
        address newBackend = makeAddr("newBackend");

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitSubnames.BackendUpdated(newBackend);
        subnames.setBackend(newBackend);

        assertEq(subnames.backend(), newBackend);
    }

    function test_setBackend_notOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        subnames.setBackend(makeAddr("newBackend"));
    }

    function test_setBackend_zeroAddress_reverts() public {
        vm.prank(owner);
        vm.expectRevert(khaaliSplitSubnames.ZeroAddress.selector);
        subnames.setBackend(address(0));
    }

    function test_setBackend_newBackendCanRegister() public {
        address newBackend = makeAddr("newBackend");

        vm.prank(owner);
        subnames.setBackend(newBackend);

        // Old backend can no longer register
        vm.prank(backend);
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.register("alice", alice);

        // New backend can register
        vm.prank(newBackend);
        subnames.register("alice", alice);
    }

    // ──────────────────────────────────────────────
    //  Admin — setReputationContract
    // ──────────────────────────────────────────────

    function test_setReputationContract_success() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitSubnames.ReputationContractUpdated(reputationContract);
        subnames.setReputationContract(reputationContract);

        assertEq(subnames.reputationContract(), reputationContract);
    }

    function test_setReputationContract_allowsZero() public {
        // First set it
        vm.prank(owner);
        subnames.setReputationContract(reputationContract);

        // Then disable by setting to zero
        vm.prank(owner);
        subnames.setReputationContract(address(0));

        assertEq(subnames.reputationContract(), address(0));
    }

    function test_setReputationContract_notOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        subnames.setReputationContract(reputationContract);
    }

    // ──────────────────────────────────────────────
    //  Upgrade
    // ──────────────────────────────────────────────

    function test_upgrade_onlyOwner() public {
        khaaliSplitSubnames newImpl = new khaaliSplitSubnames();
        vm.prank(owner);
        subnames.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_notOwner_reverts() public {
        khaaliSplitSubnames newImpl = new khaaliSplitSubnames();
        vm.prank(alice);
        vm.expectRevert();
        subnames.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_preservesState() public {
        // Register a subname first
        bytes32 node = _registerSubname("alice", alice);

        // Set some custom records
        vm.prank(alice);
        subnames.setText(node, "display", "Alice");

        // Upgrade
        khaaliSplitSubnames newImpl = new khaaliSplitSubnames();
        vm.prank(owner);
        subnames.upgradeToAndCall(address(newImpl), "");

        // State should be preserved
        assertEq(subnames.text(node, "display"), "Alice");
        assertEq(subnames.text(node, "com.khaalisplit.subname"), "alice");
        assertEq(subnames.addr(node), alice);
        assertEq(subnames.backend(), backend);
        assertEq(subnames.parentNode(), PARENT_NODE);
    }

    // ──────────────────────────────────────────────
    //  Implementation Cannot Be Initialized
    // ──────────────────────────────────────────────

    function test_implementation_cannotInitialize() public {
        khaaliSplitSubnames impl = new khaaliSplitSubnames();
        vm.expectRevert();
        impl.initialize(address(mockWrapper), PARENT_NODE, backend, owner);
    }
}
