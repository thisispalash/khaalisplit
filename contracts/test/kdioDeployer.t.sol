// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {kdioDeployer} from "../src/kdioDeployer.sol";
import {khaaliSplitFriends} from "../src/khaaliSplitFriends.sol";
import {khaaliSplitSettlement} from "../src/khaaliSplitSettlement.sol";
import {MockUSDC} from "./helpers/MockUSDC.sol";

contract kdioDeployerTest is Test {
    kdioDeployer public deployer;

    address owner = makeAddr("owner");
    address backend = makeAddr("backend");

    function setUp() public {
        deployer = new kdioDeployer();
    }

    // ──────────────────────────────────────────────
    //  Deploy + computeAddress
    // ──────────────────────────────────────────────

    function test_deploy_matchesComputeAddress() public {
        // Deploy a khaaliSplitFriends implementation
        khaaliSplitFriends impl = new khaaliSplitFriends();

        bytes32 salt = keccak256("khaaliSplitFriends-v1");
        bytes memory initData = abi.encodeCall(
            khaaliSplitFriends.initialize,
            (backend, owner)
        );

        // Predict address
        address predicted = deployer.computeAddress(salt, address(impl), initData);

        // Deploy
        address actual = deployer.deploy(salt, address(impl), initData);

        assertEq(actual, predicted);
        assertTrue(actual != address(0));

        // Verify the proxy works
        khaaliSplitFriends proxy = khaaliSplitFriends(actual);
        assertEq(proxy.backend(), backend);
        assertEq(proxy.owner(), owner);
    }

    function test_deploy_emitsEvent() public {
        khaaliSplitFriends impl = new khaaliSplitFriends();
        bytes32 salt = keccak256("test-event");
        bytes memory initData = abi.encodeCall(
            khaaliSplitFriends.initialize,
            (backend, owner)
        );

        address predicted = deployer.computeAddress(salt, address(impl), initData);

        vm.expectEmit(true, true, true, false);
        emit kdioDeployer.Deployed(predicted, salt, address(impl));
        deployer.deploy(salt, address(impl), initData);
    }

    // ──────────────────────────────────────────────
    //  Same salt + same bytecode → same address
    // ──────────────────────────────────────────────

    function test_deploy_sameSaltSameBytecode_sameAddress() public {
        // Deploy two separate deployers to show determinism
        kdioDeployer deployer1 = new kdioDeployer();
        kdioDeployer deployer2 = new kdioDeployer();

        khaaliSplitFriends impl = new khaaliSplitFriends();
        bytes32 salt = keccak256("friends-v1");
        bytes memory initData = abi.encodeCall(
            khaaliSplitFriends.initialize,
            (backend, owner)
        );

        // Same salt + same impl + same initData on same deployer → same predicted address
        address addr1 = deployer1.computeAddress(salt, address(impl), initData);
        address addr2 = deployer1.computeAddress(salt, address(impl), initData);
        assertEq(addr1, addr2);

        // Different deployers → different addresses (deployer address is part of CREATE2)
        address addr3 = deployer2.computeAddress(salt, address(impl), initData);
        assertTrue(addr1 != addr3);
    }

    // ──────────────────────────────────────────────
    //  Deploy + deferred initialize (for cross-chain determinism)
    // ──────────────────────────────────────────────

    function test_deploy_emptyInitData_thenInitialize() public {
        // This is the pattern for khaaliSplitSettlement — deploy proxy with
        // empty initData for deterministic address, then initialize separately.
        MockUSDC usdc = new MockUSDC();
        khaaliSplitSettlement impl = new khaaliSplitSettlement();

        bytes32 salt = keccak256("settlement-v1");
        bytes memory emptyInitData = "";

        // Deploy with empty initData
        address proxyAddr = deployer.deploy(salt, address(impl), emptyInitData);

        // Initialize separately
        khaaliSplitSettlement proxy = khaaliSplitSettlement(proxyAddr);
        proxy.initialize(address(usdc), owner);

        assertEq(address(proxy.usdc()), address(usdc));
        assertEq(proxy.owner(), owner);
    }

    // ──────────────────────────────────────────────
    //  CREATE2 collision — cannot deploy twice to same address
    // ──────────────────────────────────────────────

    function test_deploy_sameSaltTwice_reverts() public {
        khaaliSplitFriends impl = new khaaliSplitFriends();
        bytes32 salt = keccak256("duplicate");
        bytes memory initData = abi.encodeCall(
            khaaliSplitFriends.initialize,
            (backend, owner)
        );

        // First deploy succeeds
        deployer.deploy(salt, address(impl), initData);

        // Second deploy with same salt reverts (CREATE2 collision)
        vm.expectRevert();
        deployer.deploy(salt, address(impl), initData);
    }

    // ──────────────────────────────────────────────
    //  Different salts → different addresses
    // ──────────────────────────────────────────────

    function test_deploy_differentSalts_differentAddresses() public {
        khaaliSplitFriends impl = new khaaliSplitFriends();

        bytes32 salt1 = keccak256("salt-1");
        bytes32 salt2 = keccak256("salt-2");
        bytes memory initData1 = abi.encodeCall(
            khaaliSplitFriends.initialize,
            (backend, owner)
        );
        bytes memory initData2 = abi.encodeCall(
            khaaliSplitFriends.initialize,
            (makeAddr("other-backend"), owner)
        );

        address addr1 = deployer.deploy(salt1, address(impl), initData1);
        address addr2 = deployer.deploy(salt2, address(impl), initData2);

        assertTrue(addr1 != addr2);
    }
}
