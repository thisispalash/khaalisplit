// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliSplitSettlement} from "../src/khaaliSplitSettlement.sol";
import {MockUSDC} from "./helpers/MockUSDC.sol";
import {MockTokenMessengerV2} from "./helpers/MockTokenMessengerV2.sol";
import {MockGatewayWallet} from "./helpers/MockGatewayWallet.sol";

/**
 * @title MockSubnamesForSettlement
 * @notice Mock of khaaliSplitSubnames that implements text(), addr(), and setAddr()
 *         for settlement contract unit testing. Avoids the full NameWrapper dependency.
 */
contract MockSubnamesForSettlement {
    mapping(bytes32 => mapping(string => string)) private _texts;
    mapping(bytes32 => address) private _addresses;

    function setTextRecord(bytes32 node, string calldata key, string calldata value) external {
        _texts[node][key] = value;
    }

    function setAddr(bytes32 node, address addr_) external {
        _addresses[node] = addr_;
    }

    function text(bytes32 node, string calldata key) external view returns (string memory) {
        return _texts[node][key];
    }

    function addr(bytes32 node) external view returns (address payable) {
        return payable(_addresses[node]);
    }

    function setText(bytes32 node, string calldata key, string calldata value) external {
        _texts[node][key] = value;
    }
}

/**
 * @title MockReputationForSettlement
 * @notice Minimal mock of khaaliSplitReputation for settlement tests.
 *         Implements recordSettlement and getReputation with score tracking.
 */
contract MockReputationForSettlement {
    mapping(address => uint256) public scores;
    mapping(address => bool) private _hasRecord;
    uint256 public constant DEFAULT_SCORE = 50;

    struct RecordSettlementCall {
        address user;
        bool success;
    }
    RecordSettlementCall[] public recordCalls;
    bool public shouldRevert;

    function recordSettlement(address user, bool success) external {
        require(!shouldRevert, "MockReputation: reverted");
        if (!_hasRecord[user]) {
            scores[user] = DEFAULT_SCORE;
            _hasRecord[user] = true;
        }
        if (success) {
            scores[user] = scores[user] + 1 > 100 ? 100 : scores[user] + 1;
        } else {
            scores[user] = scores[user] > 5 ? scores[user] - 5 : 0;
        }
        recordCalls.push(RecordSettlementCall({user: user, success: success}));
    }

    function getReputation(address user) external view returns (uint256) {
        if (!_hasRecord[user]) return DEFAULT_SCORE;
        return scores[user];
    }

    function recordCallCount() external view returns (uint256) {
        return recordCalls.length;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}


contract khaaliSplitSettlementTest is Test {
    khaaliSplitSettlement public settlement;
    MockUSDC public usdc;
    MockTokenMessengerV2 public tokenMessenger;
    MockGatewayWallet public gatewayWallet;
    MockSubnamesForSettlement public subnameRegistry;
    MockReputationForSettlement public reputation;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address relayer = makeAddr("relayer");

    bytes32 constant BOB_NODE = keccak256("bob.khaalisplit.eth");
    bytes32 constant CHARLIE_NODE = keccak256("charlie.khaalisplit.eth");

    uint256 constant SETTLE_AMOUNT = 100e6; // 100 USDC

    // ──────────────────────────────────────────────
    //  Setup
    // ──────────────────────────────────────────────

    function setUp() public {
        usdc = new MockUSDC();
        tokenMessenger = new MockTokenMessengerV2();
        gatewayWallet = new MockGatewayWallet();
        subnameRegistry = new MockSubnamesForSettlement();
        reputation = new MockReputationForSettlement();

        khaaliSplitSettlement impl = new khaaliSplitSettlement();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(khaaliSplitSettlement.initialize, (owner))
        );
        settlement = khaaliSplitSettlement(address(proxy));

        vm.startPrank(owner);
        settlement.addToken(address(usdc));
        settlement.setGatewayWallet(address(gatewayWallet));
        settlement.setTokenMessenger(address(tokenMessenger));
        settlement.setSubnameRegistry(address(subnameRegistry));
        settlement.setReputationContract(address(reputation));
        settlement.configureDomain(11155111, 0);
        settlement.configureDomain(84532, 6);
        vm.stopPrank();

        // Register bob with Gateway preferences (default)
        _registerRecipient(bob, BOB_NODE, _addressToHexString(address(usdc)), "8453", "gateway", "");

        // Mint USDC to alice
        usdc.mint(alice, 10_000e6);
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _registerRecipient(
        address recipient, bytes32 node,
        string memory tokenAddr, string memory chain,
        string memory flow, string memory cctpDomain
    ) internal {
        subnameRegistry.setAddr(node, recipient);
        subnameRegistry.setTextRecord(node, "com.khaalisplit.payment.token", tokenAddr);
        subnameRegistry.setTextRecord(node, "com.khaalisplit.payment.chain", chain);
        subnameRegistry.setTextRecord(node, "com.khaalisplit.payment.flow", flow);
        if (bytes(cctpDomain).length > 0) {
            subnameRegistry.setTextRecord(node, "com.khaalisplit.payment.cctp", cctpDomain);
        }
    }

    function _buildAuth(address from) internal view returns (khaaliSplitSettlement.Authorization memory) {
        return khaaliSplitSettlement.Authorization({
            from: from,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: keccak256(abi.encodePacked(block.timestamp, from, gasleft()))
        });
    }

    function _buildAuthWithNonce(address from, bytes32 nonce) internal view returns (khaaliSplitSettlement.Authorization memory) {
        return khaaliSplitSettlement.Authorization({
            from: from,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: nonce
        });
    }

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

    // ══════════════════════════════════════════════
    //  INITIALIZATION
    // ══════════════════════════════════════════════

    function test_initialize_setsOwner() public view {
        assertEq(settlement.owner(), owner);
    }

    function test_initialize_revertsOnReinit() public {
        vm.expectRevert();
        settlement.initialize(owner);
    }

    function test_initialize_revertsZeroOwner() public {
        khaaliSplitSettlement impl = new khaaliSplitSettlement();
        vm.expectRevert(khaaliSplitSettlement.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(khaaliSplitSettlement.initialize, (address(0))));
    }

    function test_implementation_cannotInitialize() public {
        khaaliSplitSettlement impl = new khaaliSplitSettlement();
        vm.expectRevert();
        impl.initialize(owner);
    }

    function test_initialize_state() public view {
        assertTrue(settlement.allowedTokens(address(usdc)));
        assertEq(address(settlement.gatewayWallet()), address(gatewayWallet));
        assertEq(address(settlement.tokenMessenger()), address(tokenMessenger));
        assertEq(address(settlement.subnameRegistry()), address(subnameRegistry));
        assertEq(address(settlement.reputationContract()), address(reputation));
        assertEq(settlement.REPUTATION_NOT_SET(), 500);
    }

    // ══════════════════════════════════════════════
    //  SETTLE() — STUB
    // ══════════════════════════════════════════════

    function test_settle_revertsNotImplemented() public {
        vm.expectRevert(khaaliSplitSettlement.NotImplemented.selector);
        settlement.settle(BOB_NODE, SETTLE_AMOUNT, "");
    }

    // ══════════════════════════════════════════════
    //  SETTLE WITH AUTHORIZATION — GATEWAY FLOW
    // ══════════════════════════════════════════════

    function test_gateway_success() public {
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");

        assertEq(gatewayWallet.callCount(), 1);
        MockGatewayWallet.DepositForCall memory call = gatewayWallet.getCall(0);
        assertEq(call.token, address(usdc));
        assertEq(call.depositor, bob);
        assertEq(call.value, SETTLE_AMOUNT);
    }

    function test_gateway_emitsSettlementCompleted() public {
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit khaaliSplitSettlement.SettlementCompleted(alice, bob, address(usdc), SETTLE_AMOUNT, 51, "");
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");
    }

    function test_gateway_updatesReputation() public {
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");

        assertEq(reputation.recordCallCount(), 1);
        assertEq(reputation.getReputation(alice), 51);
    }

    function test_gateway_withMemo() public {
        bytes memory memo = abi.encodePacked("dinner split");
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit khaaliSplitSettlement.SettlementCompleted(alice, bob, address(usdc), SETTLE_AMOUNT, 51, memo);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, memo, auth, "");
    }

    function test_gateway_movesTokensCorrectly() public {
        uint256 aliceBefore = usdc.balanceOf(alice);
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");

        assertEq(usdc.balanceOf(alice), aliceBefore - SETTLE_AMOUNT);
        assertEq(usdc.balanceOf(address(gatewayWallet)), SETTLE_AMOUNT);
        assertEq(usdc.balanceOf(address(settlement)), 0);
    }

    function test_gateway_defaultIfFlowEmpty() public {
        _registerRecipient(charlie, CHARLIE_NODE, _addressToHexString(address(usdc)), "8453", "", "");
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(CHARLIE_NODE, SETTLE_AMOUNT, "", auth, "");

        assertEq(gatewayWallet.callCount(), 1);
        assertEq(tokenMessenger.callCount(), 0);
    }

    function test_gateway_anyoneCanSubmit() public {
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        address randomSubmitter = makeAddr("random");
        vm.prank(randomSubmitter);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");

        assertEq(gatewayWallet.callCount(), 1);
    }

    function test_gateway_unknownFlowDefaultsToGateway() public {
        _registerRecipient(charlie, CHARLIE_NODE, _addressToHexString(address(usdc)), "8453", "someRandomFlow", "");
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(CHARLIE_NODE, SETTLE_AMOUNT, "", auth, "");

        assertEq(gatewayWallet.callCount(), 1);
        assertEq(tokenMessenger.callCount(), 0);
    }

    // ══════════════════════════════════════════════
    //  SETTLE WITH AUTHORIZATION — CCTP FLOW
    // ══════════════════════════════════════════════

    function test_cctp_success() public {
        _registerRecipient(charlie, CHARLIE_NODE, _addressToHexString(address(usdc)), "84532", "cctp", "6");
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(CHARLIE_NODE, SETTLE_AMOUNT, "", auth, "");

        assertEq(tokenMessenger.callCount(), 1);
        MockTokenMessengerV2.DepositForBurnCall memory call = tokenMessenger.getCall(0);
        assertEq(call.amount, SETTLE_AMOUNT);
        assertEq(call.destinationDomain, 6);
        assertEq(call.mintRecipient, bytes32(uint256(uint160(charlie))));
        assertEq(call.burnToken, address(usdc));
    }

    function test_cctp_emitsEvent() public {
        _registerRecipient(charlie, CHARLIE_NODE, _addressToHexString(address(usdc)), "84532", "cctp", "6");
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit khaaliSplitSettlement.SettlementCompleted(alice, charlie, address(usdc), SETTLE_AMOUNT, 51, "");
        settlement.settleWithAuthorization(CHARLIE_NODE, SETTLE_AMOUNT, "", auth, "");
    }

    function test_cctp_revertsIfNoDomainInTextRecord() public {
        _registerRecipient(charlie, CHARLIE_NODE, _addressToHexString(address(usdc)), "84532", "cctp", "");
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectRevert(khaaliSplitSettlement.CctpDomainNotInTextRecord.selector);
        settlement.settleWithAuthorization(CHARLIE_NODE, SETTLE_AMOUNT, "", auth, "");
    }

    function test_cctp_revertsIfTokenMessengerNotSet() public {
        _registerRecipient(charlie, CHARLIE_NODE, _addressToHexString(address(usdc)), "84532", "cctp", "6");
        vm.prank(owner);
        settlement.setTokenMessenger(address(0));
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectRevert(khaaliSplitSettlement.TokenMessengerNotSet.selector);
        settlement.settleWithAuthorization(CHARLIE_NODE, SETTLE_AMOUNT, "", auth, "");
    }

    function test_cctp_movesTokensCorrectly() public {
        _registerRecipient(charlie, CHARLIE_NODE, _addressToHexString(address(usdc)), "84532", "cctp", "6");
        uint256 aliceBefore = usdc.balanceOf(alice);
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(CHARLIE_NODE, SETTLE_AMOUNT, "", auth, "");

        assertEq(usdc.balanceOf(alice), aliceBefore - SETTLE_AMOUNT);
        assertEq(usdc.balanceOf(address(tokenMessenger)), SETTLE_AMOUNT);
        assertEq(usdc.balanceOf(address(settlement)), 0);
    }

    function test_cctp_domainZeroWorks() public {
        // Domain 0 = Ethereum/Sepolia — valid CCTP domain
        _registerRecipient(charlie, CHARLIE_NODE, _addressToHexString(address(usdc)), "11155111", "cctp", "0");
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(CHARLIE_NODE, SETTLE_AMOUNT, "", auth, "");

        MockTokenMessengerV2.DepositForBurnCall memory call = tokenMessenger.getCall(0);
        assertEq(call.destinationDomain, 0);
    }

    // ══════════════════════════════════════════════
    //  VALIDATION
    // ══════════════════════════════════════════════

    function test_validation_revertsZeroAmount() public {
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectRevert(khaaliSplitSettlement.ZeroAmount.selector);
        settlement.settleWithAuthorization(BOB_NODE, 0, "", auth, "");
    }

    function test_validation_revertsZeroRecipientNode() public {
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectRevert(khaaliSplitSettlement.ZeroAddress.selector);
        settlement.settleWithAuthorization(bytes32(0), SETTLE_AMOUNT, "", auth, "");
    }

    function test_validation_revertsIfSubnameRegistryNotSet() public {
        khaaliSplitSettlement impl = new khaaliSplitSettlement();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(khaaliSplitSettlement.initialize, (owner)));
        khaaliSplitSettlement fresh = khaaliSplitSettlement(address(proxy));
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectRevert(khaaliSplitSettlement.SubnameRegistryNotSet.selector);
        fresh.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");
    }

    function test_validation_revertsIfRecipientNotRegistered() public {
        bytes32 unregisteredNode = keccak256("unregistered.khaalisplit.eth");
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(khaaliSplitSettlement.RecipientNotRegistered.selector, unregisteredNode));
        settlement.settleWithAuthorization(unregisteredNode, SETTLE_AMOUNT, "", auth, "");
    }

    function test_validation_revertsIfTokenNotAllowed() public {
        address fakeToken = makeAddr("fakeToken");
        subnameRegistry.setTextRecord(BOB_NODE, "com.khaalisplit.payment.token", _addressToHexString(fakeToken));
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(khaaliSplitSettlement.TokenNotAllowed.selector, fakeToken));
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");
    }

    function test_validation_revertsIfTokenTextRecordEmpty() public {
        subnameRegistry.setTextRecord(BOB_NODE, "com.khaalisplit.payment.token", "");
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(khaaliSplitSettlement.TokenNotAllowed.selector, address(0)));
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");
    }

    function test_validation_revertsIfGatewayWalletNotSet() public {
        vm.prank(owner);
        settlement.setGatewayWallet(address(0));
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectRevert(khaaliSplitSettlement.GatewayWalletNotSet.selector);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");
    }

    // ══════════════════════════════════════════════
    //  REPUTATION
    // ══════════════════════════════════════════════

    function test_reputation_notSet_emits500() public {
        vm.prank(owner);
        settlement.setReputationContract(address(0));
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit khaaliSplitSettlement.SettlementCompleted(alice, bob, address(usdc), SETTLE_AMOUNT, 500, "");
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");
    }

    function test_reputation_notSet_skipsCall() public {
        vm.prank(owner);
        settlement.setReputationContract(address(0));
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");
        assertEq(reputation.recordCallCount(), 0);
    }

    function test_reputation_multipleSettlements() public {
        khaaliSplitSettlement.Authorization memory auth1 = _buildAuthWithNonce(alice, bytes32(uint256(1)));
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth1, "");
        assertEq(reputation.getReputation(alice), 51);

        khaaliSplitSettlement.Authorization memory auth2 = _buildAuthWithNonce(alice, bytes32(uint256(2)));
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth2, "");
        assertEq(reputation.getReputation(alice), 52);
    }

    // ══════════════════════════════════════════════
    //  TOKEN MANAGEMENT
    // ══════════════════════════════════════════════

    function test_addToken_success() public {
        address newToken = makeAddr("newToken");
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitSettlement.TokenAdded(newToken);
        settlement.addToken(newToken);
        assertTrue(settlement.allowedTokens(newToken));
    }

    function test_addToken_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        settlement.addToken(makeAddr("token"));
    }

    function test_addToken_revertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(khaaliSplitSettlement.ZeroAddress.selector);
        settlement.addToken(address(0));
    }

    function test_removeToken_success() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitSettlement.TokenRemoved(address(usdc));
        settlement.removeToken(address(usdc));
        assertFalse(settlement.allowedTokens(address(usdc)));
    }

    function test_removeToken_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        settlement.removeToken(address(usdc));
    }

    // ══════════════════════════════════════════════
    //  ADMIN SETTERS
    // ══════════════════════════════════════════════

    function test_setTokenMessenger_success() public {
        address newTm = makeAddr("newTM");
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitSettlement.TokenMessengerUpdated(newTm);
        settlement.setTokenMessenger(newTm);
        assertEq(address(settlement.tokenMessenger()), newTm);
    }

    function test_setTokenMessenger_allowsZero() public {
        vm.prank(owner);
        settlement.setTokenMessenger(address(0));
        assertEq(address(settlement.tokenMessenger()), address(0));
    }

    function test_setTokenMessenger_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        settlement.setTokenMessenger(makeAddr("tm"));
    }

    function test_configureDomain_success() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit khaaliSplitSettlement.DomainConfigured(1, 0);
        settlement.configureDomain(1, 0);
        assertEq(settlement.chainIdToDomain(1), 0);
        assertTrue(settlement.domainConfigured(1));
    }

    function test_configureDomain_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        settlement.configureDomain(1, 0);
    }

    function test_setGatewayWallet_success() public {
        address newGw = makeAddr("newGW");
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitSettlement.GatewayWalletUpdated(newGw);
        settlement.setGatewayWallet(newGw);
        assertEq(address(settlement.gatewayWallet()), newGw);
    }

    function test_setGatewayWallet_allowsZero() public {
        vm.prank(owner);
        settlement.setGatewayWallet(address(0));
        assertEq(address(settlement.gatewayWallet()), address(0));
    }

    function test_setGatewayWallet_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        settlement.setGatewayWallet(makeAddr("gw"));
    }

    function test_setSubnameRegistry_success() public {
        address newSr = makeAddr("newSR");
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitSettlement.SubnameRegistryUpdated(newSr);
        settlement.setSubnameRegistry(newSr);
        assertEq(address(settlement.subnameRegistry()), newSr);
    }

    function test_setSubnameRegistry_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        settlement.setSubnameRegistry(makeAddr("sr"));
    }

    function test_setReputationContract_success() public {
        address newRep = makeAddr("newRep");
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit khaaliSplitSettlement.ReputationContractUpdated(newRep);
        settlement.setReputationContract(newRep);
        assertEq(address(settlement.reputationContract()), newRep);
    }

    function test_setReputationContract_allowsZero() public {
        vm.prank(owner);
        settlement.setReputationContract(address(0));
        assertEq(address(settlement.reputationContract()), address(0));
    }

    function test_setReputationContract_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        settlement.setReputationContract(makeAddr("rep"));
    }

    // ══════════════════════════════════════════════
    //  UUPS UPGRADES
    // ══════════════════════════════════════════════

    function test_upgrade_ownerOnly() public {
        khaaliSplitSettlement newImpl = new khaaliSplitSettlement();
        vm.prank(owner);
        settlement.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_revertsNotOwner() public {
        khaaliSplitSettlement newImpl = new khaaliSplitSettlement();
        vm.prank(alice);
        vm.expectRevert();
        settlement.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_preservesState() public {
        khaaliSplitSettlement.Authorization memory auth = _buildAuth(alice);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");

        khaaliSplitSettlement newImpl = new khaaliSplitSettlement();
        vm.prank(owner);
        settlement.upgradeToAndCall(address(newImpl), "");

        assertTrue(settlement.allowedTokens(address(usdc)));
        assertEq(address(settlement.gatewayWallet()), address(gatewayWallet));
        assertEq(address(settlement.tokenMessenger()), address(tokenMessenger));
        assertEq(address(settlement.subnameRegistry()), address(subnameRegistry));
        assertEq(address(settlement.reputationContract()), address(reputation));
        assertEq(settlement.owner(), owner);
    }

    // ══════════════════════════════════════════════
    //  NONCE REPLAY PROTECTION
    // ══════════════════════════════════════════════

    function test_nonceReplay_reverts() public {
        bytes32 nonce = bytes32(uint256(42));
        khaaliSplitSettlement.Authorization memory auth = _buildAuthWithNonce(alice, nonce);
        vm.prank(relayer);
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");

        vm.prank(relayer);
        vm.expectRevert("FiatTokenV2: auth already used");
        settlement.settleWithAuthorization(BOB_NODE, SETTLE_AMOUNT, "", auth, "");
    }
}
