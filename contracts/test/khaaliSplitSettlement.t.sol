// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {khaaliSplitSettlement} from "../src/khaaliSplitSettlement.sol";
import {MockUSDC} from "./helpers/MockUSDC.sol";

contract khaaliSplitSettlementTest is Test {
    khaaliSplitSettlement public settlement;
    MockUSDC public usdc;

    address owner = makeAddr("owner");
    address alice;
    uint256 aliceKey;
    address bob = makeAddr("bob");
    address relayer = makeAddr("relayer");

    uint256 constant AMOUNT = 100e6; // 100 USDC
    uint256 constant DEST_CHAIN_ID = 42161; // Arbitrum

    function setUp() public {
        // Create alice with known private key for permit signing
        (alice, aliceKey) = makeAddrAndKey("alice");

        // Deploy MockUSDC
        usdc = new MockUSDC();

        // Deploy settlement proxy
        khaaliSplitSettlement impl = new khaaliSplitSettlement();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(khaaliSplitSettlement.initialize, (address(usdc), owner))
        );
        settlement = khaaliSplitSettlement(address(proxy));

        // Mint USDC to alice
        usdc.mint(alice, 1000e6);
    }

    // ──────────────────────────────────────────────
    //  Initialization
    // ──────────────────────────────────────────────

    function test_initialize_setsState() public view {
        assertEq(address(settlement.usdc()), address(usdc));
        assertEq(settlement.owner(), owner);
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert();
        settlement.initialize(address(usdc), owner);
    }

    // ──────────────────────────────────────────────
    //  settle
    // ──────────────────────────────────────────────

    function test_settle_success() public {
        vm.prank(alice);
        usdc.approve(address(settlement), AMOUNT);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit khaaliSplitSettlement.SettlementInitiated(alice, bob, DEST_CHAIN_ID, AMOUNT, "");
        settlement.settle(bob, DEST_CHAIN_ID, AMOUNT, "");

        assertEq(usdc.balanceOf(address(settlement)), AMOUNT);
        assertEq(usdc.balanceOf(alice), 1000e6 - AMOUNT);
    }

    function test_settle_zeroAmount_reverts() public {
        vm.prank(alice);
        vm.expectRevert(khaaliSplitSettlement.ZeroAmount.selector);
        settlement.settle(bob, DEST_CHAIN_ID, 0, "");
    }

    function test_settle_zeroRecipient_reverts() public {
        vm.prank(alice);
        vm.expectRevert(khaaliSplitSettlement.ZeroAddress.selector);
        settlement.settle(address(0), DEST_CHAIN_ID, AMOUNT, "");
    }

    function test_settle_insufficientAllowance_reverts() public {
        vm.prank(alice);
        // No approval
        vm.expectRevert(); // SafeERC20 will revert
        settlement.settle(bob, DEST_CHAIN_ID, AMOUNT, "");
    }

    function test_settle_withNote() public {
        bytes memory note = hex"cafebabe";

        vm.prank(alice);
        usdc.approve(address(settlement), AMOUNT);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit khaaliSplitSettlement.SettlementInitiated(alice, bob, DEST_CHAIN_ID, AMOUNT, note);
        settlement.settle(bob, DEST_CHAIN_ID, AMOUNT, note);
    }

    // ──────────────────────────────────────────────
    //  settleWithPermit
    // ──────────────────────────────────────────────

    function test_settleWithPermit_success() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Build permit signature
        bytes32 permitHash = _buildPermitDigest(
            alice,
            address(settlement),
            AMOUNT,
            usdc.nonces(alice),
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, permitHash);

        // Relayer calls settleWithPermit on behalf of alice
        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit khaaliSplitSettlement.SettlementInitiated(alice, bob, DEST_CHAIN_ID, AMOUNT, "");
        settlement.settleWithPermit(alice, bob, DEST_CHAIN_ID, AMOUNT, "", deadline, v, r, s);

        assertEq(usdc.balanceOf(address(settlement)), AMOUNT);
        assertEq(usdc.balanceOf(alice), 1000e6 - AMOUNT);
    }

    function test_settleWithPermit_zeroAmount_reverts() public {
        vm.prank(relayer);
        vm.expectRevert(khaaliSplitSettlement.ZeroAmount.selector);
        settlement.settleWithPermit(alice, bob, DEST_CHAIN_ID, 0, "", 0, 0, bytes32(0), bytes32(0));
    }

    function test_settleWithPermit_zeroRecipient_reverts() public {
        vm.prank(relayer);
        vm.expectRevert(khaaliSplitSettlement.ZeroAddress.selector);
        settlement.settleWithPermit(alice, address(0), DEST_CHAIN_ID, AMOUNT, "", 0, 0, bytes32(0), bytes32(0));
    }

    // ──────────────────────────────────────────────
    //  withdraw
    // ──────────────────────────────────────────────

    function test_withdraw_byOwner() public {
        // First, settle some USDC into the contract
        vm.prank(alice);
        usdc.approve(address(settlement), AMOUNT);
        vm.prank(alice);
        settlement.settle(bob, DEST_CHAIN_ID, AMOUNT, "");

        // Owner withdraws
        vm.prank(owner);
        settlement.withdraw(address(usdc), relayer, AMOUNT);

        assertEq(usdc.balanceOf(relayer), AMOUNT);
        assertEq(usdc.balanceOf(address(settlement)), 0);
    }

    function test_withdraw_notOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        settlement.withdraw(address(usdc), alice, AMOUNT);
    }

    function test_withdraw_zeroAddress_reverts() public {
        vm.prank(owner);
        vm.expectRevert(khaaliSplitSettlement.ZeroAddress.selector);
        settlement.withdraw(address(usdc), address(0), AMOUNT);
    }

    // ──────────────────────────────────────────────
    //  Upgrade
    // ──────────────────────────────────────────────

    function test_upgrade_onlyOwner() public {
        khaaliSplitSettlement newImpl = new khaaliSplitSettlement();
        vm.prank(owner);
        settlement.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_notOwner_reverts() public {
        khaaliSplitSettlement newImpl = new khaaliSplitSettlement();
        vm.prank(alice);
        vm.expectRevert();
        settlement.upgradeToAndCall(address(newImpl), "");
    }

    // ──────────────────────────────────────────────
    //  Helpers — EIP-2612 permit digest
    // ──────────────────────────────────────────────

    function _buildPermitDigest(
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
                usdc.DOMAIN_SEPARATOR(),
                structHash
            )
        );
    }
}
