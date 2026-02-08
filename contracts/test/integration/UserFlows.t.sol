// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliSplitFriends} from "../../src/khaaliSplitFriends.sol";
import {khaaliSplitGroups} from "../../src/khaaliSplitGroups.sol";
import {khaaliSplitExpenses} from "../../src/khaaliSplitExpenses.sol";
import {khaaliSplitSettlement} from "../../src/khaaliSplitSettlement.sol";
import {khaaliSplitSubnames} from "../../src/khaaliSplitSubnames.sol";
import {khaaliSplitReputation} from "../../src/khaaliSplitReputation.sol";
import {kdioDeployer} from "../../src/kdioDeployer.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {MockNameWrapper} from "../helpers/MockNameWrapper.sol";
import {MockTokenMessengerV2} from "../helpers/MockTokenMessengerV2.sol";
import {MockGatewayWallet} from "../helpers/MockGatewayWallet.sol";
import {MockGatewayMinter} from "../helpers/MockGatewayMinter.sol";

/**
 * @title UserFlows — Integration Tests
 * @notice End-to-end tests covering full user flows from the khaaliSplit PRD.
 *         Deploys all contracts through ERC1967 proxies, wires them together,
 *         and exercises multi-contract interactions.
 *
 *         Uses REAL contracts for all khaaliSplit contracts (friends, groups,
 *         expenses, settlement, subnames, reputation) and MOCKS only for
 *         external dependencies (NameWrapper, USDC, CCTP, Gateway).
 */
contract UserFlowsTest is Test {
    // ── Contracts (real, via UUPS proxies) ──
    khaaliSplitFriends public friends;
    khaaliSplitGroups public groupsContract;
    khaaliSplitExpenses public expensesContract;
    khaaliSplitSettlement public settlement;
    khaaliSplitSubnames public subnames;
    khaaliSplitReputation public reputation;

    // ── Mocks (external deps) ──
    MockUSDC public usdc;
    MockNameWrapper public nameWrapper;
    MockTokenMessengerV2 public tokenMessenger;
    MockGatewayWallet public gatewayWallet;
    MockGatewayMinter public gatewayMinter;

    // ── Accounts ──
    address owner = makeAddr("owner");
    address backend = makeAddr("backend");

    address alice;
    uint256 aliceKey;
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address relayer = makeAddr("relayer");

    // ── Constants ──
    bytes alicePubKey = hex"04aabbccdd";
    bytes bobPubKey = hex"04eeff0011";
    bytes charliePubKey = hex"04deadbeef";

    bytes32 groupNameHash = keccak256("Trip to Goa");
    bytes encKeyAlice = hex"aabb";
    bytes encKeyBob = hex"ccdd";
    bytes encKeyCharlie = hex"eeff";

    bytes32 constant PARENT_NODE = keccak256("khaalisplit.eth");
    uint256 constant SETTLE_AMOUNT = 100e6; // 100 USDC
    uint256 constant GATEWAY_MINT_AMOUNT = 75e6; // 75 USDC (after fees)

    // ── Computed subname nodes (must match subnameNode logic) ──
    // node = keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))))
    bytes32 ALICE_NODE;
    bytes32 BOB_NODE;
    bytes32 CHARLIE_NODE;

    // ──────────────────────────────────────────────
    //  Setup
    // ──────────────────────────────────────────────

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");

        // Compute subname nodes
        ALICE_NODE = keccak256(abi.encodePacked(PARENT_NODE, keccak256(bytes("alice"))));
        BOB_NODE = keccak256(abi.encodePacked(PARENT_NODE, keccak256(bytes("bob"))));
        CHARLIE_NODE = keccak256(abi.encodePacked(PARENT_NODE, keccak256(bytes("charlie"))));

        _deployAll();
    }

    function _deployAll() internal {
        // ── External mocks ──
        usdc = new MockUSDC();
        nameWrapper = new MockNameWrapper();
        tokenMessenger = new MockTokenMessengerV2();
        gatewayWallet = new MockGatewayWallet();
        gatewayMinter = new MockGatewayMinter(address(usdc), GATEWAY_MINT_AMOUNT);

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

        // ── Subnames ──
        khaaliSplitSubnames subnamesImpl = new khaaliSplitSubnames();
        ERC1967Proxy subnamesProxy = new ERC1967Proxy(
            address(subnamesImpl),
            abi.encodeCall(khaaliSplitSubnames.initialize, (
                address(nameWrapper),
                PARENT_NODE,
                backend,
                owner
            ))
        );
        subnames = khaaliSplitSubnames(address(subnamesProxy));

        // ── Settlement ──
        khaaliSplitSettlement settlementImpl = new khaaliSplitSettlement();
        ERC1967Proxy settlementProxy = new ERC1967Proxy(
            address(settlementImpl),
            abi.encodeCall(khaaliSplitSettlement.initialize, (owner))
        );
        settlement = khaaliSplitSettlement(address(settlementProxy));

        // ── Reputation ──
        khaaliSplitReputation reputationImpl = new khaaliSplitReputation();
        ERC1967Proxy reputationProxy = new ERC1967Proxy(
            address(reputationImpl),
            abi.encodeCall(khaaliSplitReputation.initialize, (
                backend,
                address(subnames),
                address(settlement),
                owner
            ))
        );
        reputation = khaaliSplitReputation(address(reputationProxy));

        // ── Wire contracts together ──
        vm.startPrank(owner);

        // Settlement config
        settlement.addToken(address(usdc));
        settlement.setGatewayWallet(address(gatewayWallet));
        settlement.setGatewayMinter(address(gatewayMinter));
        settlement.setTokenMessenger(address(tokenMessenger));
        settlement.setSubnameRegistry(address(subnames));
        settlement.setReputationContract(address(reputation));
        settlement.configureDomain(11155111, 0);  // Sepolia
        settlement.configureDomain(84532, 6);     // Base Sepolia

        // Subnames: authorize the reputation contract to call setText
        subnames.setReputationContract(address(reputation));

        vm.stopPrank();
    }

    // ──────────────────────────────────────────────
    //  Onboarding Helpers
    // ──────────────────────────────────────────────

    /// @dev Full onboarding for a user: register pubkey + register subname + set user node on reputation
    function _onboardUser(
        address user,
        bytes memory pubKey,
        string memory label,
        bytes32 node
    ) internal {
        vm.startPrank(backend);

        // 1. Register ECDH public key on friends contract
        friends.registerPubKey(user, pubKey);

        // 2. Register ENS subname (sets default text records + addr)
        subnames.register(label, user);

        // 3. Link user address to ENS node on reputation contract
        reputation.setUserNode(user, node);

        vm.stopPrank();
    }

    /// @dev Set payment preferences for a user on their subname
    function _setPaymentPrefs(
        bytes32 node,
        string memory tokenAddr,
        string memory chain,
        string memory flow,
        string memory cctpDomain
    ) internal {
        vm.startPrank(backend);
        subnames.setText(node, "com.khaalisplit.payment.token", tokenAddr);
        subnames.setText(node, "com.khaalisplit.payment.chain", chain);
        subnames.setText(node, "com.khaalisplit.payment.flow", flow);
        if (bytes(cctpDomain).length > 0) {
            subnames.setText(node, "com.khaalisplit.payment.cctp", cctpDomain);
        }
        vm.stopPrank();
    }

    /// @dev Build an EIP-3009 authorization for settlement
    function _buildAuth(address from) internal view returns (khaaliSplitSettlement.Authorization memory) {
        return khaaliSplitSettlement.Authorization({
            from: from,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: keccak256(abi.encodePacked(block.timestamp, from, gasleft()))
        });
    }

    /// @dev Build an EIP-3009 authorization with a specific nonce
    function _buildAuthWithNonce(address from, bytes32 nonce) internal view returns (khaaliSplitSettlement.Authorization memory) {
        return khaaliSplitSettlement.Authorization({
            from: from,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: nonce
        });
    }

    /// @dev Convert address to hex string for text records
    function _addressToHexString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i)) >> 4) & 0xf];
            str[3 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i))) & 0xf];
        }
        return string(str);
    }

    /// @dev Make two users friends (request + accept)
    function _makeFriends(address a, address b) internal {
        vm.prank(a);
        friends.requestFriend(b);
        vm.prank(b);
        friends.acceptFriend(a);
    }

    // ══════════════════════════════════════════════
    //  Flow 1: Onboarding → Friends → Group → Expenses
    // ══════════════════════════════════════════════

    function test_flow_onboarding_friends_group_expense() public {
        // Step 1: Onboard all three users
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);
        _onboardUser(charlie, charliePubKey, "charlie", CHARLIE_NODE);

        // Verify registration
        assertTrue(friends.registered(alice));
        assertTrue(friends.registered(bob));
        assertTrue(friends.registered(charlie));

        // Verify subname defaults
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.subname"), "alice");
        assertEq(subnames.text(BOB_NODE, "com.khaalisplit.subname"), "bob");
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "50");
        assertEq(subnames.addr(ALICE_NODE), alice);
        assertEq(subnames.addr(BOB_NODE), bob);

        // Step 2: Make friends
        // alice↔bob via standard request+accept
        _makeFriends(alice, bob);
        // alice↔charlie via mutual request auto-accept
        vm.prank(charlie);
        friends.requestFriend(alice);
        vm.prank(alice);
        friends.requestFriend(charlie); // auto-accepts

        assertTrue(friends.isFriend(alice, bob));
        assertTrue(friends.isFriend(alice, charlie));
        assertFalse(friends.isFriend(bob, charlie));

        // Step 3: Create group + invite members
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

        assertTrue(groupsContract.isMember(groupId, alice));
        assertTrue(groupsContract.isMember(groupId, bob));
        assertTrue(groupsContract.isMember(groupId, charlie));
        (, , uint256 memberCount) = groupsContract.groups(groupId);
        assertEq(memberCount, 3);

        // Step 4: Add expenses
        bytes32 hash1 = keccak256("dinner");
        bytes32 hash2 = keccak256("taxi");

        vm.prank(alice);
        uint256 e1 = expensesContract.addExpense(groupId, hash1, hex"aa");
        vm.prank(bob);
        uint256 e2 = expensesContract.addExpense(groupId, hash2, hex"bb");

        assertEq(e1, 1);
        assertEq(e2, 2);
        assertEq(expensesContract.expenseCount(), 2);

        uint256[] memory groupExpenses = expensesContract.getGroupExpenses(groupId);
        assertEq(groupExpenses.length, 2);
    }

    // ══════════════════════════════════════════════
    //  Flow 2: Onboarding → Settle → Reputation (Gateway Routing)
    // ══════════════════════════════════════════════

    function test_flow_onboarding_settle_reputation_gateway() public {
        // Onboard alice (sender) and bob (recipient)
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);

        // Set bob's payment preferences to gateway (default)
        _setPaymentPrefs(BOB_NODE, _addressToHexString(address(usdc)), "8453", "gateway", "");

        // Mint USDC to alice
        usdc.mint(alice, 10_000e6);

        // Verify pre-settlement reputation
        assertEq(reputation.getReputation(alice), 50); // default

        // Alice settles to bob via EIP-3009 authorization
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);

        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "dinner split", auth, "");

        // Verify: Gateway received the deposit
        assertEq(gatewayWallet.callCount(), 1);
        MockGatewayWallet.DepositForCall memory call = gatewayWallet.getCall(0);
        assertEq(call.token, address(usdc));
        assertEq(call.depositor, bob);
        assertEq(call.value, SETTLE_AMOUNT);

        // Verify: alice's reputation updated (50 + 1 = 51)
        assertEq(reputation.getReputation(alice), 51);

        // Verify: ENS text record synced
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "51");

        // Verify: alice's USDC decreased
        assertEq(usdc.balanceOf(alice), 10_000e6 - SETTLE_AMOUNT);
    }

    // ══════════════════════════════════════════════
    //  Flow 3: settleWithAuthorization — CCTP Routing
    // ══════════════════════════════════════════════

    function test_flow_settle_cctp_routing() public {
        // Onboard alice and bob
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);

        // Set bob's payment preferences to CCTP with domain 6 (Base Sepolia)
        _setPaymentPrefs(BOB_NODE, _addressToHexString(address(usdc)), "84532", "cctp", "6");

        // Mint USDC to alice
        usdc.mint(alice, 10_000e6);

        // Settle
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "cctp test", auth, "");

        // Verify: CCTP TokenMessenger received depositForBurn
        assertEq(tokenMessenger.callCount(), 1);
        MockTokenMessengerV2.DepositForBurnCall memory call = tokenMessenger.getCall(0);
        assertEq(call.amount, SETTLE_AMOUNT);
        assertEq(call.destinationDomain, 6);
        assertEq(call.mintRecipient, bytes32(uint256(uint160(bob))));
        assertEq(call.burnToken, address(usdc));

        // Verify: Gateway was NOT called
        assertEq(gatewayWallet.callCount(), 0);

        // Verify: reputation updated
        assertEq(reputation.getReputation(alice), 51);
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "51");
    }

    // ══════════════════════════════════════════════
    //  Flow 4: settleFromGateway End-to-End
    // ══════════════════════════════════════════════

    function test_flow_settleFromGateway() public {
        // Onboard alice (sender) and bob (recipient)
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);

        // Set bob's payment preferences to gateway
        _setPaymentPrefs(BOB_NODE, _addressToHexString(address(usdc)), "8453", "gateway", "");

        // settleFromGateway: mock minter mints USDC to settlement contract
        bytes memory attestation = hex"deadbeef";
        bytes memory sig = hex"cafebabe";

        vm.prank(relayer);
        settlement.settleFromGateway(attestation, sig, BOB_NODE, alice, "gateway mint test");

        // Verify: gateway minter was called
        assertEq(gatewayMinter.callCount(), 1);

        // Verify: Gateway wallet received the deposit (routed via gateway flow)
        assertEq(gatewayWallet.callCount(), 1);
        MockGatewayWallet.DepositForCall memory call = gatewayWallet.getCall(0);
        assertEq(call.token, address(usdc));
        assertEq(call.depositor, bob);
        assertEq(call.value, GATEWAY_MINT_AMOUNT);

        // Verify: reputation updated for alice (the sender)
        assertEq(reputation.getReputation(alice), 51);
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "51");
    }

    // ══════════════════════════════════════════════
    //  Flow 5: Subname Registration + ENS Defaults + Custom Records
    // ══════════════════════════════════════════════

    function test_flow_subname_registration_and_records() public {
        // Register alice's subname
        vm.prank(backend);
        subnames.register("alice", alice);

        bytes32 node = subnames.subnameNode("alice");
        assertEq(node, ALICE_NODE);

        // Verify defaults set during registration
        assertEq(subnames.text(node, "com.khaalisplit.subname"), "alice");
        assertEq(subnames.text(node, "com.khaalisplit.reputation"), "50");
        assertEq(subnames.addr(node), alice);

        // Verify NameWrapper was called correctly
        (
            bytes32 parentNode_,
            string memory label_,
            address owner_,
            address resolver_,
            ,
            ,
        ) = nameWrapper.lastRecord();
        assertEq(parentNode_, PARENT_NODE);
        assertEq(label_, "alice");
        assertEq(owner_, alice);
        assertEq(resolver_, address(subnames)); // subnames contract is the resolver

        // Owner sets custom text records
        vm.startPrank(alice);
        subnames.setText(node, "display", "Alice Wonderland");
        subnames.setText(node, "avatar", "ipfs://QmAliceAvatar");
        subnames.setText(node, "com.khaalisplit.payment.chain", "8453");
        subnames.setText(node, "com.khaalisplit.payment.token", _addressToHexString(address(usdc)));
        vm.stopPrank();

        // Verify custom records readable
        assertEq(subnames.text(node, "display"), "Alice Wonderland");
        assertEq(subnames.text(node, "avatar"), "ipfs://QmAliceAvatar");
        assertEq(subnames.text(node, "com.khaalisplit.payment.chain"), "8453");

        // Owner updates addr
        address newAddr = makeAddr("aliceNewAddr");
        vm.prank(alice);
        subnames.setAddr(node, newAddr);
        assertEq(subnames.addr(node), newAddr);
    }

    // ══════════════════════════════════════════════
    //  Flow 6: Reputation Sync — Settlement Updates ENS Text Records
    // ══════════════════════════════════════════════

    function test_flow_reputation_sync_via_settlement() public {
        // Full onboarding for alice and bob
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);

        // Set bob's payment preferences
        _setPaymentPrefs(BOB_NODE, _addressToHexString(address(usdc)), "8453", "gateway", "");

        // Mint USDC to alice
        usdc.mint(alice, 10_000e6);

        // Initial state: ENS shows default "50"
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "50");

        // Settlement 1: success → 51
        khaaliSplitSettlement.Authorization memory auth1 = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, 10e6, "settle 1", auth1, "");
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "51");

        // Settlement 2: success → 52
        khaaliSplitSettlement.Authorization memory auth2 = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, 10e6, "settle 2", auth2, "");
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "52");

        // Settlement 3: success → 53
        khaaliSplitSettlement.Authorization memory auth3 = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, 10e6, "settle 3", auth3, "");
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "53");

        // Verify on-chain score matches ENS
        assertEq(reputation.getReputation(alice), 53);
    }

    // ══════════════════════════════════════════════
    //  Flow 7: Multi-User Isolation
    // ══════════════════════════════════════════════

    function test_flow_multiUser_isolation() public {
        // Onboard all three users
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);
        _onboardUser(charlie, charliePubKey, "charlie", CHARLIE_NODE);

        // Bob: gateway preferences
        _setPaymentPrefs(BOB_NODE, _addressToHexString(address(usdc)), "8453", "gateway", "");
        // Charlie: CCTP preferences
        _setPaymentPrefs(CHARLIE_NODE, _addressToHexString(address(usdc)), "84532", "cctp", "6");

        // Mint USDC to alice
        usdc.mint(alice, 10_000e6);

        // Settle to bob (gateway)
        khaaliSplitSettlement.Authorization memory auth1 = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, 50e6, "to bob", auth1, "");

        // Settle to charlie (CCTP)
        khaaliSplitSettlement.Authorization memory auth2 = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(CHARLIE_NODE, 30e6, "to charlie", auth2, "");

        // Verify routing: bob went through gateway
        assertEq(gatewayWallet.callCount(), 1);
        MockGatewayWallet.DepositForCall memory gwCall = gatewayWallet.getCall(0);
        assertEq(gwCall.depositor, bob);
        assertEq(gwCall.value, 50e6);

        // Verify routing: charlie went through CCTP
        assertEq(tokenMessenger.callCount(), 1);
        MockTokenMessengerV2.DepositForBurnCall memory cctpCall = tokenMessenger.getCall(0);
        assertEq(cctpCall.mintRecipient, bytes32(uint256(uint160(charlie))));
        assertEq(cctpCall.amount, 30e6);
        assertEq(cctpCall.destinationDomain, 6);

        // Verify independent reputations: alice settled twice → 52
        assertEq(reputation.getReputation(alice), 52);
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "52");

        // Bob and charlie haven't settled (still default 50)
        assertEq(reputation.getReputation(bob), 50);
        assertEq(reputation.getReputation(charlie), 50);
        assertEq(subnames.text(BOB_NODE, "com.khaalisplit.reputation"), "50"); // default from registration
        assertEq(subnames.text(CHARLIE_NODE, "com.khaalisplit.reputation"), "50");
    }

    // ══════════════════════════════════════════════
    //  Flow 8: Authorization Replay Protection
    // ══════════════════════════════════════════════

    function test_flow_authorization_replay_protection() public {
        // Onboard alice and bob
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);
        _setPaymentPrefs(BOB_NODE, _addressToHexString(address(usdc)), "8453", "gateway", "");

        usdc.mint(alice, 10_000e6);

        // Build auth with a specific nonce
        bytes32 nonce = keccak256("unique-nonce-1");
        khaaliSplitSettlement.Authorization memory auth = _buildAuthWithNonce(alice, nonce);

        // First settlement: success
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "first", auth, "");

        // Verify it worked
        assertEq(gatewayWallet.callCount(), 1);

        // Second settlement with SAME nonce: should revert
        // The MockUSDC enforces nonce uniqueness in receiveWithAuthorization
        vm.prank(relayer);
        vm.expectRevert("FiatTokenV2: auth already used");
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "replay", auth, "");

        // Verify only one settlement went through
        assertEq(gatewayWallet.callCount(), 1);
        assertEq(reputation.getReputation(alice), 51); // only one success
    }

    // ══════════════════════════════════════════════
    //  Flow 9: Offline Settlement (Different Submitter)
    // ══════════════════════════════════════════════

    function test_flow_offline_settlement_different_submitter() public {
        // Onboard alice and bob
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);
        _setPaymentPrefs(BOB_NODE, _addressToHexString(address(usdc)), "8453", "gateway", "");

        usdc.mint(alice, 10_000e6);

        // Alice signs the authorization (auth.from = alice)
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);

        // Bob submits the settlement (not alice, not the relayer — anyone can submit!)
        vm.prank(bob);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "offline payment", auth, "");

        // Verify: funds moved from alice to gateway for bob
        assertEq(usdc.balanceOf(alice), 10_000e6 - SETTLE_AMOUNT);
        assertEq(gatewayWallet.callCount(), 1);
        MockGatewayWallet.DepositForCall memory call = gatewayWallet.getCall(0);
        assertEq(call.depositor, bob);
        assertEq(call.value, SETTLE_AMOUNT);

        // Verify: alice's reputation updated (she's the sender in auth.from)
        assertEq(reputation.getReputation(alice), 51);

        // Charlie submits another settlement on behalf of alice
        khaaliSplitSettlement.Authorization memory auth2 = _buildAuth(alice);
        vm.prank(charlie);
        settlement.settleWithAuthorization(BOB_NODE, 20e6, "charlie submitted", auth2, "");

        // Alice reputation updated again
        assertEq(reputation.getReputation(alice), 52);
    }

    // ══════════════════════════════════════════════
    //  Flow 10: Golden Path — Full Lifecycle
    // ══════════════════════════════════════════════

    function test_flow_golden_path_full_lifecycle() public {
        // ════════════════════════════════════════════
        // Phase 1: Onboarding
        // ════════════════════════════════════════════
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);
        _onboardUser(charlie, charliePubKey, "charlie", CHARLIE_NODE);

        // Verify all three are registered and have subnames
        assertTrue(friends.registered(alice));
        assertTrue(friends.registered(bob));
        assertTrue(friends.registered(charlie));
        assertEq(subnames.addr(ALICE_NODE), alice);
        assertEq(subnames.addr(BOB_NODE), bob);
        assertEq(subnames.addr(CHARLIE_NODE), charlie);

        // ════════════════════════════════════════════
        // Phase 2: Social Graph
        // ════════════════════════════════════════════
        _makeFriends(alice, bob);
        _makeFriends(alice, charlie);

        assertTrue(friends.isFriend(alice, bob));
        assertTrue(friends.isFriend(alice, charlie));

        // ════════════════════════════════════════════
        // Phase 3: Group + Expenses
        // ════════════════════════════════════════════
        vm.prank(alice);
        uint256 groupId = groupsContract.createGroup(groupNameHash, encKeyAlice);

        // Invite and accept bob
        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encKeyBob);
        vm.prank(bob);
        groupsContract.acceptGroupInvite(groupId);

        // Invite and accept charlie
        vm.prank(alice);
        groupsContract.inviteMember(groupId, charlie, encKeyCharlie);
        vm.prank(charlie);
        groupsContract.acceptGroupInvite(groupId);

        // All three are members
        assertTrue(groupsContract.isMember(groupId, alice));
        assertTrue(groupsContract.isMember(groupId, bob));
        assertTrue(groupsContract.isMember(groupId, charlie));

        // Add expenses
        vm.prank(alice);
        uint256 e1 = expensesContract.addExpense(groupId, keccak256("dinner"), hex"aa");
        vm.prank(bob);
        uint256 e2 = expensesContract.addExpense(groupId, keccak256("drinks"), hex"bb");

        assertEq(e1, 1);
        assertEq(e2, 2);

        // ════════════════════════════════════════════
        // Phase 4: Settlement
        // ════════════════════════════════════════════

        // Set payment preferences
        _setPaymentPrefs(BOB_NODE, _addressToHexString(address(usdc)), "8453", "gateway", "");
        _setPaymentPrefs(CHARLIE_NODE, _addressToHexString(address(usdc)), "84532", "cctp", "6");

        // Mint USDC to alice (she owes bob and charlie)
        usdc.mint(alice, 10_000e6);

        // Settle alice → bob (gateway)
        khaaliSplitSettlement.Authorization memory auth1 = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, 50e6, "alice pays bob", auth1, "");

        // Settle alice → charlie (CCTP)
        khaaliSplitSettlement.Authorization memory auth2 = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(CHARLIE_NODE, 30e6, "alice pays charlie", auth2, "");

        // ════════════════════════════════════════════
        // Phase 5: Verify Final State
        // ════════════════════════════════════════════

        // Alice's USDC spent
        assertEq(usdc.balanceOf(alice), 10_000e6 - 50e6 - 30e6);

        // Bob received via gateway
        assertEq(gatewayWallet.callCount(), 1);
        MockGatewayWallet.DepositForCall memory gwCall = gatewayWallet.getCall(0);
        assertEq(gwCall.depositor, bob);
        assertEq(gwCall.value, 50e6);

        // Charlie received via CCTP
        assertEq(tokenMessenger.callCount(), 1);
        MockTokenMessengerV2.DepositForBurnCall memory cctpCall = tokenMessenger.getCall(0);
        assertEq(cctpCall.mintRecipient, bytes32(uint256(uint160(charlie))));
        assertEq(cctpCall.amount, 30e6);

        // Alice's reputation: 50 + 1 + 1 = 52 (two successful settlements)
        assertEq(reputation.getReputation(alice), 52);
        assertEq(subnames.text(ALICE_NODE, "com.khaalisplit.reputation"), "52");

        // Bob and charlie unchanged (they didn't settle, still default)
        assertEq(reputation.getReputation(bob), 50);
        assertEq(reputation.getReputation(charlie), 50);

        // All subname defaults still intact
        assertEq(subnames.text(BOB_NODE, "com.khaalisplit.subname"), "bob");
        assertEq(subnames.text(CHARLIE_NODE, "com.khaalisplit.subname"), "charlie");
    }

    // ══════════════════════════════════════════════
    //  Flow 11: Authorization Boundaries
    // ══════════════════════════════════════════════

    function test_flow_authorization_boundaries_cross_user_records() public {
        // Onboard alice and bob
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);

        // Alice CANNOT modify bob's text records
        vm.prank(alice);
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.setText(BOB_NODE, "display", "hacked");

        // Bob CANNOT modify alice's text records
        vm.prank(bob);
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.setText(ALICE_NODE, "display", "hacked");

        // Alice CANNOT modify bob's addr record
        vm.prank(alice);
        vm.expectRevert(khaaliSplitSubnames.Unauthorized.selector);
        subnames.setAddr(BOB_NODE, alice);

        // Backend CAN modify both
        vm.startPrank(backend);
        subnames.setText(ALICE_NODE, "display", "Alice via Backend");
        subnames.setText(BOB_NODE, "display", "Bob via Backend");
        vm.stopPrank();

        assertEq(subnames.text(ALICE_NODE, "display"), "Alice via Backend");
        assertEq(subnames.text(BOB_NODE, "display"), "Bob via Backend");

        // Each owner can still modify their own
        vm.prank(alice);
        subnames.setText(ALICE_NODE, "display", "Alice Updated");
        vm.prank(bob);
        subnames.setText(BOB_NODE, "display", "Bob Updated");

        assertEq(subnames.text(ALICE_NODE, "display"), "Alice Updated");
        assertEq(subnames.text(BOB_NODE, "display"), "Bob Updated");
    }

    function test_flow_wiring_verification_reputation_requires_settlement() public {
        // Deploy a fresh subnames for this isolated test
        khaaliSplitSubnames subnamesImpl2 = new khaaliSplitSubnames();
        MockNameWrapper nw2 = new MockNameWrapper();
        ERC1967Proxy subnamesProxy2 = new ERC1967Proxy(
            address(subnamesImpl2),
            abi.encodeCall(khaaliSplitSubnames.initialize, (address(nw2), PARENT_NODE, backend, owner))
        );
        khaaliSplitSubnames sub2 = khaaliSplitSubnames(address(subnamesProxy2));

        // Deploy reputation with settlementContract = address(0), wired to sub2
        khaaliSplitReputation reputationImpl2 = new khaaliSplitReputation();
        ERC1967Proxy reputationProxy2 = new ERC1967Proxy(
            address(reputationImpl2),
            abi.encodeCall(khaaliSplitReputation.initialize, (
                backend,
                address(sub2),
                address(0), // no settlement contract
                owner
            ))
        );
        khaaliSplitReputation rep2 = khaaliSplitReputation(address(reputationProxy2));

        // Authorize rep2 on sub2
        vm.prank(owner);
        sub2.setReputationContract(address(rep2));

        // Register a user and set node
        vm.prank(backend);
        sub2.register("dave", makeAddr("dave"));
        bytes32 daveNode = sub2.subnameNode("dave");
        vm.prank(backend);
        rep2.setUserNode(makeAddr("dave"), daveNode);

        // Anyone calling recordSettlement should revert (no authorized settlement contract)
        vm.prank(makeAddr("anyone"));
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        rep2.recordSettlement(makeAddr("dave"), true);

        // Even the owner can't call recordSettlement
        vm.prank(owner);
        vm.expectRevert(khaaliSplitReputation.Unauthorized.selector);
        rep2.recordSettlement(makeAddr("dave"), true);

        // Wire it up: owner sets settlement contract
        vm.prank(owner);
        rep2.setSettlementContract(address(settlement));

        // Now the settlement contract CAN call it
        vm.prank(address(settlement));
        rep2.recordSettlement(makeAddr("dave"), true);

        // Verify score updated
        assertEq(rep2.getReputation(makeAddr("dave")), 51);

        // Verify ENS text record was synced on the fresh subnames
        assertEq(sub2.text(daveNode, "com.khaalisplit.reputation"), "51");
    }

    // ══════════════════════════════════════════════
    //  Flow 12: Leave Group + Update Expense
    // ══════════════════════════════════════════════

    function test_flow_leaveGroup_and_updateExpense() public {
        // Onboard users and create group
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);
        _onboardUser(charlie, charliePubKey, "charlie", CHARLIE_NODE);

        _makeFriends(alice, bob);
        _makeFriends(alice, charlie);

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

        // Add expenses
        vm.prank(alice);
        uint256 aliceExpenseId = expensesContract.addExpense(groupId, keccak256("alice expense"), hex"aa");
        vm.prank(charlie);
        expensesContract.addExpense(groupId, keccak256("charlie expense"), hex"cc");

        // Charlie leaves
        vm.prank(charlie);
        groupsContract.leaveGroup(groupId);

        assertFalse(groupsContract.isMember(groupId, charlie));
        (, , uint256 memberCount) = groupsContract.groups(groupId);
        assertEq(memberCount, 2);

        // Charlie can't add expenses anymore
        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(khaaliSplitExpenses.NotGroupMember.selector, groupId, charlie)
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

    // ══════════════════════════════════════════════
    //  Flow 13: Remove Friend — No Cascade to Groups
    // ══════════════════════════════════════════════

    function test_flow_removeFriend_no_cascade() public {
        // Onboard and set up group
        _onboardUser(alice, alicePubKey, "alice", ALICE_NODE);
        _onboardUser(bob, bobPubKey, "bob", BOB_NODE);
        _onboardUser(charlie, charliePubKey, "charlie", CHARLIE_NODE);

        _makeFriends(alice, bob);
        _makeFriends(alice, charlie);

        vm.prank(alice);
        uint256 groupId = groupsContract.createGroup(groupNameHash, encKeyAlice);

        vm.prank(alice);
        groupsContract.inviteMember(groupId, bob, encKeyBob);
        vm.prank(bob);
        groupsContract.acceptGroupInvite(groupId);

        // Alice removes bob as friend
        vm.prank(alice);
        friends.removeFriend(bob);

        // Friendship gone
        assertFalse(friends.isFriend(alice, bob));
        assertFalse(friends.isFriend(bob, alice));

        // But bob is still a group member (no cascade)
        assertTrue(groupsContract.isMember(groupId, bob));

        // Bob can still add expenses
        vm.prank(bob);
        uint256 expenseId = expensesContract.addExpense(groupId, keccak256("bob expense"), hex"bb");
        assertEq(expenseId, 1);
    }

    // ══════════════════════════════════════════════
    //  Flow 14: kdioDeployer End-to-End with All Contracts
    // ══════════════════════════════════════════════

    /// @dev Helper struct to hold deployed addresses across stack frames
    struct DeployedAddresses {
        address friends;
        address groups;
        address subnames;
        address settlement;
        address reputation;
    }

    function _deployViaCreate2(
        kdioDeployer deployer
    ) internal returns (DeployedAddresses memory addrs) {
        // Friends
        addrs.friends = deployer.deploy(
            keccak256("khaaliSplitFriends-v1"),
            address(new khaaliSplitFriends()),
            abi.encodeCall(khaaliSplitFriends.initialize, (backend, owner))
        );

        // Groups (depends on friends)
        addrs.groups = deployer.deploy(
            keccak256("khaaliSplitGroups-v1"),
            address(new khaaliSplitGroups()),
            abi.encodeCall(khaaliSplitGroups.initialize, (addrs.friends, owner))
        );

        // Subnames
        addrs.subnames = deployer.deploy(
            keccak256("khaaliSplitSubnames-v1"),
            address(new khaaliSplitSubnames()),
            abi.encodeCall(khaaliSplitSubnames.initialize, (address(new MockNameWrapper()), PARENT_NODE, backend, owner))
        );

        // Settlement
        addrs.settlement = deployer.deploy(
            keccak256("khaaliSplitSettlement-v1"),
            address(new khaaliSplitSettlement()),
            abi.encodeCall(khaaliSplitSettlement.initialize, (owner))
        );

        // Reputation (depends on subnames + settlement)
        addrs.reputation = deployer.deploy(
            keccak256("khaaliSplitReputation-v1"),
            address(new khaaliSplitReputation()),
            abi.encodeCall(khaaliSplitReputation.initialize, (backend, addrs.subnames, addrs.settlement, owner))
        );
    }

    function test_flow_kdioDeployer_fullStack() public {
        kdioDeployer deployer = new kdioDeployer();

        // Verify computeAddress matches deploy for Friends
        address friendsImpl = address(new khaaliSplitFriends());
        bytes memory friendsInit = abi.encodeCall(khaaliSplitFriends.initialize, (backend, owner));
        bytes32 friendsSalt = keccak256("khaaliSplitFriends-v1-predict");
        address predicted = deployer.computeAddress(friendsSalt, friendsImpl, friendsInit);
        address actual = deployer.deploy(friendsSalt, friendsImpl, friendsInit);
        assertEq(actual, predicted);

        // Deploy full stack via CREATE2
        DeployedAddresses memory addrs = _deployViaCreate2(deployer);

        // Verify all deployed contracts are functional
        assertEq(khaaliSplitFriends(addrs.friends).backend(), backend);
        assertEq(khaaliSplitFriends(addrs.friends).owner(), owner);
        assertEq(address(khaaliSplitGroups(addrs.groups).friendRegistry()), addrs.friends);
        assertEq(khaaliSplitSubnames(addrs.subnames).parentNode(), PARENT_NODE);
        assertEq(khaaliSplitSettlement(addrs.settlement).owner(), owner);
        assertEq(khaaliSplitReputation(addrs.reputation).backend(), backend);
        assertEq(address(khaaliSplitReputation(addrs.reputation).subnameRegistry()), addrs.subnames);
        assertEq(khaaliSplitReputation(addrs.reputation).settlementContract(), addrs.settlement);

        // Wire reputation on subnames
        vm.prank(owner);
        khaaliSplitSubnames(addrs.subnames).setReputationContract(addrs.reputation);

        // Quick functional test: register a user
        vm.prank(backend);
        khaaliSplitFriends(addrs.friends).registerPubKey(alice, alicePubKey);
        assertTrue(khaaliSplitFriends(addrs.friends).registered(alice));

        vm.prank(backend);
        khaaliSplitSubnames(addrs.subnames).register("alice", alice);
        bytes32 node = khaaliSplitSubnames(addrs.subnames).subnameNode("alice");
        assertEq(khaaliSplitSubnames(addrs.subnames).addr(node), alice);
        assertEq(khaaliSplitSubnames(addrs.subnames).text(node, "com.khaalisplit.subname"), "alice");
    }
}
