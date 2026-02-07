// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {khaaliSplitReputation} from "../src/khaaliSplitReputation.sol";
import {MockSubnames} from "./helpers/MockSubnames.sol";

contract khaaliSplitReputationTest is Test {
    khaaliSplitReputation public reputation;
    MockSubnames public mockSubnames;

    address owner = makeAddr("owner");
    address backend = makeAddr("backend");
    address settlement = makeAddr("settlement");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Deterministic test nodes
    bytes32 constant ALICE_NODE = keccak256("alice.khaalisplit.eth.test");
    bytes32 constant BOB_NODE = keccak256("bob.khaalisplit.eth.test");

    function setUp() public {
        // Deploy mock subnames
        mockSubnames = new MockSubnames();

        // Deploy reputation proxy
        khaaliSplitReputation impl = new khaaliSplitReputation();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitReputation.initialize,
                (backend, address(mockSubnames), settlement, owner)
            )
        );
        reputation = khaaliSplitReputation(address(proxy));
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    /// @dev Set up alice with a user node via backend.
    function _setupAlice() internal {
        vm.prank(backend);
        reputation.setUserNode(alice, ALICE_NODE);
    }

    /// @dev Set up bob with a user node via backend.
    function _setupBob() internal {
        vm.prank(backend);
        reputation.setUserNode(bob, BOB_NODE);
    }

    /// @dev Record a successful settlement for a user.
    function _recordSuccess(address user) internal {
        vm.prank(settlement);
        reputation.recordSettlement(user, true);
    }

    /// @dev Record a failed settlement for a user.
    function _recordFailure(address user) internal {
        vm.prank(settlement);
        reputation.recordSettlement(user, false);
    }

    // ══════════════════════════════════════════════
    //  Initialization
    // ══════════════════════════════════════════════

    function test_initialize_setsState() public view {
        assertEq(reputation.backend(), backend);
        assertEq(address(reputation.subnameRegistry()), address(mockSubnames));
        assertEq(reputation.settlementContract(), settlement);
        assertEq(reputation.owner(), owner);
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert();
        reputation.initialize(backend, address(mockSubnames), settlement, owner);
    }

    function test_initialize_zeroBackend_reverts() public {
        khaaliSplitReputation impl = new khaaliSplitReputation();
        vm.expectRevert(khaaliSplitReputation.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitReputation.initialize,
                (address(0), address(mockSubnames), settlement, owner)
            )
        );
    }

    function test_initialize_zeroOwner_reverts() public {
        khaaliSplitReputation impl = new khaaliSplitReputation();
        vm.expectRevert(khaaliSplitReputation.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitReputation.initialize,
                (backend, address(mockSubnames), settlement, address(0))
            )
        );
    }

    function test_initialize_zeroSubnameRegistry_allowed() public {
        khaaliSplitReputation impl = new khaaliSplitReputation();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitReputation.initialize,
                (backend, address(0), settlement, owner)
            )
        );
        khaaliSplitReputation rep = khaaliSplitReputation(address(proxy));
        assertEq(address(rep.subnameRegistry()), address(0));
    }

    function test_initialize_zeroSettlementContract_allowed() public {
        khaaliSplitReputation impl = new khaaliSplitReputation();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitReputation.initialize,
                (backend, address(mockSubnames), address(0), owner)
            )
        );
        khaaliSplitReputation rep = khaaliSplitReputation(address(proxy));
        assertEq(rep.settlementContract(), address(0));
    }

    // ══════════════════════════════════════════════
    //  Constants
    // ══════════════════════════════════════════════

    function test_constants() public view {
        assertEq(reputation.DEFAULT_SCORE(), 50);
        assertEq(reputation.MAX_SCORE(), 100);
        assertEq(reputation.MIN_SCORE(), 0);
        assertEq(reputation.SUCCESS_DELTA(), 1);
        assertEq(reputation.FAILURE_DELTA(), 5);
    }

    // ══════════════════════════════════════════════
    //  getReputation
    // ══════════════════════════════════════════════

    function test_getReputation_defaultForUnknownUser() public view {
        assertEq(reputation.getReputation(alice), 50);
    }

    function test_getReputation_defaultBeforeAnySettlement() public {
        _setupAlice();
        // Node set but no settlement recorded yet
        assertEq(reputation.getReputation(alice), 50);
    }

    function test_getReputation_afterSuccess() public {
        _setupAlice();
        _recordSuccess(alice);
        // Default 50 + 1 success = 51
        assertEq(reputation.getReputation(alice), 51);
    }

    function test_getReputation_afterFailure() public {
        _setupAlice();
        _recordFailure(alice);
        // Default 50 - 5 failure = 45
        assertEq(reputation.getReputation(alice), 45);
    }

    // ══════════════════════════════════════════════
    //  recordSettlement — Success Path
    // ══════════════════════════════════════════════

    function test_recordSettlement_success_incrementsScore() public {
        _setupAlice();
        _recordSuccess(alice);
        assertEq(reputation.scores(alice), 51);
    }

    function test_recordSettlement_success_emitsEvent() public {
        _setupAlice();

        vm.prank(settlement);
        vm.expectEmit(true, false, false, true);
        emit khaaliSplitReputation.ReputationUpdated(alice, 51, true);
        reputation.recordSettlement(alice, true);
    }

    function test_recordSettlement_multipleSuccesses() public {
        _setupAlice();

        // 10 successes: 50 + 10 = 60
        for (uint256 i = 0; i < 10; i++) {
            _recordSuccess(alice);
        }
        assertEq(reputation.scores(alice), 60);
    }

    function test_recordSettlement_success_cappedAtMax() public {
        _setupAlice();

        // 60 successes: 50 + 60 = 110, capped at 100
        for (uint256 i = 0; i < 60; i++) {
            _recordSuccess(alice);
        }
        assertEq(reputation.scores(alice), 100);
    }

    function test_recordSettlement_success_atMaxStaysAtMax() public {
        _setupAlice();

        // Get to max
        for (uint256 i = 0; i < 60; i++) {
            _recordSuccess(alice);
        }
        assertEq(reputation.scores(alice), 100);

        // One more success should stay at 100
        _recordSuccess(alice);
        assertEq(reputation.scores(alice), 100);
    }

    // ══════════════════════════════════════════════
    //  recordSettlement — Failure Path
    // ══════════════════════════════════════════════

    function test_recordSettlement_failure_decrementsScore() public {
        _setupAlice();
        _recordFailure(alice);
        assertEq(reputation.scores(alice), 45);
    }

    function test_recordSettlement_failure_emitsEvent() public {
        _setupAlice();

        vm.prank(settlement);
        vm.expectEmit(true, false, false, true);
        emit khaaliSplitReputation.ReputationUpdated(alice, 45, false);
        reputation.recordSettlement(alice, false);
    }

    function test_recordSettlement_multipleFailures() public {
        _setupAlice();

        // 5 failures: 50 - 25 = 25
        for (uint256 i = 0; i < 5; i++) {
            _recordFailure(alice);
        }
        assertEq(reputation.scores(alice), 25);
    }

    function test_recordSettlement_failure_flooredAtMin() public {
        _setupAlice();

        // 11 failures: 50 - 55 = floored at 0
        for (uint256 i = 0; i < 11; i++) {
            _recordFailure(alice);
        }
        assertEq(reputation.scores(alice), 0);
    }

    function test_recordSettlement_failure_atMinStaysAtMin() public {
        _setupAlice();

        // Get to min
        for (uint256 i = 0; i < 11; i++) {
            _recordFailure(alice);
        }
        assertEq(reputation.scores(alice), 0);

        // One more failure should stay at 0
        _recordFailure(alice);
        assertEq(reputation.scores(alice), 0);
    }

    // ══════════════════════════════════════════════
    //  recordSettlement — Mixed Outcomes
    // ══════════════════════════════════════════════

    function test_recordSettlement_mixed_successThenFailure() public {
        _setupAlice();

        // 3 successes: 50 + 3 = 53
        for (uint256 i = 0; i < 3; i++) {
            _recordSuccess(alice);
        }
        assertEq(reputation.scores(alice), 53);

        // 1 failure: 53 - 5 = 48
        _recordFailure(alice);
        assertEq(reputation.scores(alice), 48);
    }

    function test_recordSettlement_mixed_failureThenSuccess() public {
        _setupAlice();

        // 2 failures: 50 - 10 = 40
        _recordFailure(alice);
        _recordFailure(alice);
        assertEq(reputation.scores(alice), 40);

        // 5 successes: 40 + 5 = 45
        for (uint256 i = 0; i < 5; i++) {
            _recordSuccess(alice);
        }
        assertEq(reputation.scores(alice), 45);
    }

    // ══════════════════════════════════════════════
    //  recordSettlement — ENS Sync
    // ══════════════════════════════════════════════

    function test_recordSettlement_syncsToENS() public {
        _setupAlice();
        _recordSuccess(alice);

        // Verify MockSubnames.setText was called
        assertEq(mockSubnames.setTextCallCount(), 1);

        (bytes32 node, string memory key, string memory value) = mockSubnames.getSetTextCall(0);
        assertEq(node, ALICE_NODE);
        assertEq(key, "com.khaalisplit.reputation");
        assertEq(value, "51");
    }

    function test_recordSettlement_syncsToENS_multipleUpdates() public {
        _setupAlice();

        _recordSuccess(alice); // 51
        _recordSuccess(alice); // 52
        _recordFailure(alice); // 47

        assertEq(mockSubnames.setTextCallCount(), 3);

        // Verify each sync
        (, , string memory val0) = mockSubnames.getSetTextCall(0);
        assertEq(val0, "51");

        (, , string memory val1) = mockSubnames.getSetTextCall(1);
        assertEq(val1, "52");

        (, , string memory val2) = mockSubnames.getSetTextCall(2);
        assertEq(val2, "47");
    }

    function test_recordSettlement_noENSSync_whenRegistryZero() public {
        // Deploy reputation with no subname registry
        khaaliSplitReputation impl = new khaaliSplitReputation();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                khaaliSplitReputation.initialize,
                (backend, address(0), settlement, owner)
            )
        );
        khaaliSplitReputation rep = khaaliSplitReputation(address(proxy));

        // Set user node
        vm.prank(backend);
        rep.setUserNode(alice, ALICE_NODE);

        // Record settlement — should not revert even without registry
        vm.prank(settlement);
        rep.recordSettlement(alice, true);

        // Score should still be updated
        assertEq(rep.scores(alice), 51);

        // MockSubnames should NOT have been called (no registry configured)
        assertEq(mockSubnames.setTextCallCount(), 0);
    }

    function test_recordSettlement_syncsCorrectNode_perUser() public {
        _setupAlice();
        _setupBob();

        _recordSuccess(alice);
        _recordFailure(bob);

        assertEq(mockSubnames.setTextCallCount(), 2);

        (bytes32 node0, , string memory val0) = mockSubnames.getSetTextCall(0);
        assertEq(node0, ALICE_NODE);
        assertEq(val0, "51");

        (bytes32 node1, , string memory val1) = mockSubnames.getSetTextCall(1);
        assertEq(node1, BOB_NODE);
        assertEq(val1, "45");
    }

    // ══════════════════════════════════════════════
    //  recordSettlement — Authorization
    // ══════════════════════════════════════════════

    function test_recordSettlement_notSettlementContract_reverts() public {
        _setupAlice();

        vm.prank(alice);
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        reputation.recordSettlement(alice, true);
    }

    function test_recordSettlement_byBackend_reverts() public {
        _setupAlice();

        vm.prank(backend);
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        reputation.recordSettlement(alice, true);
    }

    function test_recordSettlement_byOwner_reverts() public {
        _setupAlice();

        vm.prank(owner);
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        reputation.recordSettlement(alice, true);
    }

    function test_recordSettlement_userNodeNotSet_reverts() public {
        // Alice has no node set
        vm.prank(settlement);
        vm.expectRevert(khaaliSplitReputation.UserNodeNotSet.selector);
        reputation.recordSettlement(alice, true);
    }

    // ══════════════════════════════════════════════
    //  setUserNode
    // ══════════════════════════════════════════════

    function test_setUserNode_success() public {
        vm.prank(backend);
        vm.expectEmit(true, true, false, false);
        emit khaaliSplitReputation.UserNodeSet(alice, ALICE_NODE);
        reputation.setUserNode(alice, ALICE_NODE);

        assertEq(reputation.userNodes(alice), ALICE_NODE);
    }

    function test_setUserNode_multipleUsers() public {
        _setupAlice();
        _setupBob();

        assertEq(reputation.userNodes(alice), ALICE_NODE);
        assertEq(reputation.userNodes(bob), BOB_NODE);
    }

    function test_setUserNode_notBackend_reverts() public {
        vm.prank(alice);
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        reputation.setUserNode(alice, ALICE_NODE);
    }

    function test_setUserNode_byOwner_reverts() public {
        vm.prank(owner);
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        reputation.setUserNode(alice, ALICE_NODE);
    }

    function test_setUserNode_bySettlement_reverts() public {
        vm.prank(settlement);
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        reputation.setUserNode(alice, ALICE_NODE);
    }

    function test_setUserNode_zeroUser_reverts() public {
        vm.prank(backend);
        vm.expectRevert(khaaliSplitReputation.ZeroAddress.selector);
        reputation.setUserNode(address(0), ALICE_NODE);
    }

    function test_setUserNode_zeroNode_reverts() public {
        vm.prank(backend);
        vm.expectRevert(khaaliSplitReputation.ZeroNode.selector);
        reputation.setUserNode(alice, bytes32(0));
    }

    // ══════════════════════════════════════════════
    //  Admin — setBackend
    // ══════════════════════════════════════════════

    function test_setBackend_success() public {
        address newBackend = makeAddr("newBackend");

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitReputation.BackendUpdated(newBackend);
        reputation.setBackend(newBackend);

        assertEq(reputation.backend(), newBackend);
    }

    function test_setBackend_notOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        reputation.setBackend(makeAddr("newBackend"));
    }

    function test_setBackend_zeroAddress_reverts() public {
        vm.prank(owner);
        vm.expectRevert(khaaliSplitReputation.ZeroAddress.selector);
        reputation.setBackend(address(0));
    }

    function test_setBackend_oldBackendLosesAuth() public {
        address newBackend = makeAddr("newBackend");

        vm.prank(owner);
        reputation.setBackend(newBackend);

        // Old backend can no longer setUserNode
        vm.prank(backend);
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        reputation.setUserNode(alice, ALICE_NODE);

        // New backend can
        vm.prank(newBackend);
        reputation.setUserNode(alice, ALICE_NODE);
        assertEq(reputation.userNodes(alice), ALICE_NODE);
    }

    // ══════════════════════════════════════════════
    //  Admin — setSubnameRegistry
    // ══════════════════════════════════════════════

    function test_setSubnameRegistry_success() public {
        address newRegistry = makeAddr("newRegistry");

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitReputation.SubnameRegistryUpdated(newRegistry);
        reputation.setSubnameRegistry(newRegistry);

        assertEq(address(reputation.subnameRegistry()), newRegistry);
    }

    function test_setSubnameRegistry_allowsZero() public {
        vm.prank(owner);
        reputation.setSubnameRegistry(address(0));

        assertEq(address(reputation.subnameRegistry()), address(0));
    }

    function test_setSubnameRegistry_notOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        reputation.setSubnameRegistry(makeAddr("newRegistry"));
    }

    // ══════════════════════════════════════════════
    //  Admin — setSettlementContract
    // ══════════════════════════════════════════════

    function test_setSettlementContract_success() public {
        address newSettlement = makeAddr("newSettlement");

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitReputation.SettlementContractUpdated(newSettlement);
        reputation.setSettlementContract(newSettlement);

        assertEq(reputation.settlementContract(), newSettlement);
    }

    function test_setSettlementContract_allowsZero() public {
        vm.prank(owner);
        reputation.setSettlementContract(address(0));

        assertEq(reputation.settlementContract(), address(0));
    }

    function test_setSettlementContract_notOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        reputation.setSettlementContract(makeAddr("newSettlement"));
    }

    function test_setSettlementContract_oldSettlementLosesAuth() public {
        _setupAlice();

        address newSettlement = makeAddr("newSettlement");
        vm.prank(owner);
        reputation.setSettlementContract(newSettlement);

        // Old settlement can no longer record
        vm.prank(settlement);
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        reputation.recordSettlement(alice, true);

        // New settlement can
        vm.prank(newSettlement);
        reputation.recordSettlement(alice, true);
        assertEq(reputation.scores(alice), 51);
    }

    // ══════════════════════════════════════════════
    //  Multi-User Isolation
    // ══════════════════════════════════════════════

    function test_multiUser_scoresAreIndependent() public {
        _setupAlice();
        _setupBob();

        // Alice: 3 successes → 53
        for (uint256 i = 0; i < 3; i++) {
            _recordSuccess(alice);
        }

        // Bob: 2 failures → 40
        _recordFailure(bob);
        _recordFailure(bob);

        assertEq(reputation.scores(alice), 53);
        assertEq(reputation.scores(bob), 40);
        assertEq(reputation.getReputation(alice), 53);
        assertEq(reputation.getReputation(bob), 40);
    }

    // ══════════════════════════════════════════════
    //  Edge Cases
    // ══════════════════════════════════════════════

    function test_recordSettlement_firstCall_initializesToDefault() public {
        _setupAlice();

        // Before any settlement, scores mapping is 0 but getReputation returns 50
        assertEq(reputation.scores(alice), 0);
        assertEq(reputation.getReputation(alice), 50);

        // After first settlement, scores mapping is updated from DEFAULT_SCORE
        _recordSuccess(alice);
        assertEq(reputation.scores(alice), 51);
    }

    function test_recordSettlement_scoreAt5_failureGoesToZero() public {
        _setupAlice();

        // Get score to 5: start at 50, 9 failures = 50 - 45 = 5
        for (uint256 i = 0; i < 9; i++) {
            _recordFailure(alice);
        }
        assertEq(reputation.scores(alice), 5);

        // One more failure: 5 - 5 = 0 (exact boundary)
        _recordFailure(alice);
        assertEq(reputation.scores(alice), 0);
    }

    function test_recordSettlement_scoreAt4_failureGoesToZero() public {
        _setupAlice();

        // Get to 5, then +1 success to get to 6, then -5 failure to get to 1
        // Actually: 50 - 45 (9 failures) = 5, + 1 success = 6, - 5 failure = 1
        for (uint256 i = 0; i < 9; i++) {
            _recordFailure(alice);
        }
        _recordSuccess(alice);
        assertEq(reputation.scores(alice), 6);

        _recordFailure(alice);
        assertEq(reputation.scores(alice), 1);

        // Score at 1, failure should floor to 0 (1 < 5)
        _recordFailure(alice);
        assertEq(reputation.scores(alice), 0);
    }

    function test_recordSettlement_scoreAt99_successGoesTo100() public {
        _setupAlice();

        // 49 successes: 50 + 49 = 99
        for (uint256 i = 0; i < 49; i++) {
            _recordSuccess(alice);
        }
        assertEq(reputation.scores(alice), 99);

        // One more: 99 + 1 = 100 (exact boundary)
        _recordSuccess(alice);
        assertEq(reputation.scores(alice), 100);
    }

    function test_recordSettlement_ensSyncValueIsCorrectString() public {
        _setupAlice();

        // Get to 0, then record — should sync "0"
        for (uint256 i = 0; i < 11; i++) {
            _recordFailure(alice);
        }

        uint256 lastIdx = mockSubnames.setTextCallCount() - 1;
        (, , string memory lastVal) = mockSubnames.getSetTextCall(lastIdx);
        assertEq(lastVal, "0");
    }

    function test_recordSettlement_ensSyncValueAt100() public {
        _setupAlice();

        for (uint256 i = 0; i < 60; i++) {
            _recordSuccess(alice);
        }

        uint256 lastIdx = mockSubnames.setTextCallCount() - 1;
        (, , string memory lastVal) = mockSubnames.getSetTextCall(lastIdx);
        assertEq(lastVal, "100");
    }

    // ══════════════════════════════════════════════
    //  Upgrade
    // ══════════════════════════════════════════════

    function test_upgrade_onlyOwner() public {
        khaaliSplitReputation newImpl = new khaaliSplitReputation();
        vm.prank(owner);
        reputation.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_notOwner_reverts() public {
        khaaliSplitReputation newImpl = new khaaliSplitReputation();
        vm.prank(alice);
        vm.expectRevert();
        reputation.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_preservesState() public {
        _setupAlice();
        _recordSuccess(alice);
        _recordSuccess(alice);
        assertEq(reputation.scores(alice), 52);

        // Upgrade
        khaaliSplitReputation newImpl = new khaaliSplitReputation();
        vm.prank(owner);
        reputation.upgradeToAndCall(address(newImpl), "");

        // State should be preserved
        assertEq(reputation.scores(alice), 52);
        assertEq(reputation.getReputation(alice), 52);
        assertEq(reputation.userNodes(alice), ALICE_NODE);
        assertEq(reputation.backend(), backend);
        assertEq(reputation.settlementContract(), settlement);
        assertEq(address(reputation.subnameRegistry()), address(mockSubnames));
    }

    // ══════════════════════════════════════════════
    //  Implementation Cannot Be Initialized
    // ══════════════════════════════════════════════

    function test_implementation_cannotInitialize() public {
        khaaliSplitReputation impl = new khaaliSplitReputation();
        vm.expectRevert();
        impl.initialize(backend, address(mockSubnames), settlement, owner);
    }
}
