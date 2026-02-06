// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliSplitResolver} from "../src/khaaliSplitResolver.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/resolvers/profiles/IExtendedResolver.sol";

contract khaaliSplitResolverTest is Test {
    khaaliSplitResolver public resolver;

    address owner = makeAddr("owner");
    // Use vm.createWallet for signer so we can sign with it
    uint256 signerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address signer;

    string gatewayUrl = "https://gateway.khaalisplit.eth/{sender}/{data}.json";
    bytes dnsName = hex"0b6b6861616c6973706c69740365746800"; // khaalisplit.eth DNS-encoded
    bytes resolveData = hex"3b3b57de"; // addr(bytes32) selector

    function setUp() public {
        signer = vm.addr(signerKey);

        // Deploy implementation + proxy
        khaaliSplitResolver impl = new khaaliSplitResolver();

        address[] memory signerList = new address[](1);
        signerList[0] = signer;

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(khaaliSplitResolver.initialize, (gatewayUrl, signerList, owner))
        );
        resolver = khaaliSplitResolver(address(proxy));
    }

    // ──────────────────────────────────────────────
    //  Initialization
    // ──────────────────────────────────────────────

    function test_initialize_setsState() public view {
        assertEq(resolver.url(), gatewayUrl);
        assertTrue(resolver.signers(signer));
        assertEq(resolver.owner(), owner);
    }

    function test_initialize_cannotReinitialize() public {
        address[] memory s = new address[](0);
        vm.expectRevert();
        resolver.initialize("url", s, owner);
    }

    // ──────────────────────────────────────────────
    //  resolve → OffchainLookup revert
    // ──────────────────────────────────────────────

    function test_resolve_revertsWithOffchainLookup() public {
        // We need to catch the OffchainLookup revert and inspect its data
        try resolver.resolve(dnsName, resolveData) returns (bytes memory) {
            fail(); // Should never reach here
        } catch (bytes memory errorData) {
            // Decode the OffchainLookup error
            // First 4 bytes = selector
            bytes4 selector = bytes4(errorData);
            assertEq(
                selector,
                khaaliSplitResolver.OffchainLookup.selector
            );

            // Decode the rest
            (
                address sender,
                string[] memory urls,
                ,
                bytes4 callbackFunction,
                bytes memory extraData
            ) = abi.decode(
                _sliceBytes(errorData, 4),
                (address, string[], bytes, bytes4, bytes)
            );

            assertEq(sender, address(resolver));
            assertEq(urls.length, 1);
            assertEq(urls[0], gatewayUrl);
            assertEq(callbackFunction, resolver.resolveWithProof.selector);

            // extraData should encode (name, data)
            (bytes memory decodedName, bytes memory decodedData) =
                abi.decode(extraData, (bytes, bytes));
            assertEq(decodedName, dnsName);
            assertEq(decodedData, resolveData);
        }
    }

    // ──────────────────────────────────────────────
    //  resolveWithProof — valid signature
    // ──────────────────────────────────────────────

    function test_resolveWithProof_validSignature() public {
        bytes memory result = abi.encode(address(0x1234)); // simulated addr() result
        uint64 expires = uint64(block.timestamp + 1 hours);

        // Build the message hash the same way the contract does
        bytes memory request = abi.encodeWithSelector(
            IExtendedResolver.resolve.selector,
            dnsName,
            resolveData
        );

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                hex"1900",
                address(resolver),
                expires,
                keccak256(request),
                keccak256(result)
            )
        );

        // Sign with the trusted signer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, messageHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Encode the response
        bytes memory response = abi.encode(result, expires, sig);
        bytes memory extraData = abi.encode(dnsName, resolveData);

        // Call resolveWithProof
        bytes memory returned = resolver.resolveWithProof(response, extraData);
        assertEq(returned, result);
    }

    // ──────────────────────────────────────────────
    //  resolveWithProof — invalid signer
    // ──────────────────────────────────────────────

    function test_resolveWithProof_invalidSigner_reverts() public {
        bytes memory result = abi.encode(address(0x1234));
        uint64 expires = uint64(block.timestamp + 1 hours);

        bytes memory request = abi.encodeWithSelector(
            IExtendedResolver.resolve.selector,
            dnsName,
            resolveData
        );

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                hex"1900",
                address(resolver),
                expires,
                keccak256(request),
                keccak256(result)
            )
        );

        // Sign with a WRONG key
        uint256 wrongKey = 0xdead;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, messageHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        bytes memory response = abi.encode(result, expires, sig);
        bytes memory extraData = abi.encode(dnsName, resolveData);

        vm.expectRevert(khaaliSplitResolver.InvalidSignature.selector);
        resolver.resolveWithProof(response, extraData);
    }

    // ──────────────────────────────────────────────
    //  resolveWithProof — expired signature
    // ──────────────────────────────────────────────

    function test_resolveWithProof_expired_reverts() public {
        bytes memory result = abi.encode(address(0x1234));
        uint64 expires = uint64(block.timestamp - 1); // already expired

        bytes memory request = abi.encodeWithSelector(
            IExtendedResolver.resolve.selector,
            dnsName,
            resolveData
        );

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                hex"1900",
                address(resolver),
                expires,
                keccak256(request),
                keccak256(result)
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, messageHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        bytes memory response = abi.encode(result, expires, sig);
        bytes memory extraData = abi.encode(dnsName, resolveData);

        vm.expectRevert(khaaliSplitResolver.SignatureExpired.selector);
        resolver.resolveWithProof(response, extraData);
    }

    // ──────────────────────────────────────────────
    //  supportsInterface
    // ──────────────────────────────────────────────

    function test_supportsInterface_IExtendedResolver() public view {
        assertTrue(resolver.supportsInterface(type(IExtendedResolver).interfaceId));
    }

    function test_supportsInterface_IERC165() public view {
        assertTrue(resolver.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_random_returnsFalse() public view {
        assertFalse(resolver.supportsInterface(0xdeadbeef));
    }

    // ──────────────────────────────────────────────
    //  Signer management
    // ──────────────────────────────────────────────

    function test_addSigner_onlyOwner() public {
        address newSigner = makeAddr("newSigner");

        vm.prank(owner);
        resolver.addSigner(newSigner);
        assertTrue(resolver.signers(newSigner));
    }

    function test_addSigner_notOwner_reverts() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert();
        resolver.addSigner(makeAddr("x"));
    }

    function test_removeSigner_onlyOwner() public {
        vm.prank(owner);
        resolver.removeSigner(signer);
        assertFalse(resolver.signers(signer));
    }

    function test_removeSigner_notOwner_reverts() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert();
        resolver.removeSigner(signer);
    }

    // ──────────────────────────────────────────────
    //  URL management
    // ──────────────────────────────────────────────

    function test_setUrl_onlyOwner() public {
        string memory newUrl = "https://new-gateway.example.com/{sender}/{data}";
        vm.prank(owner);
        resolver.setUrl(newUrl);
        assertEq(resolver.url(), newUrl);
    }

    function test_setUrl_notOwner_reverts() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert();
        resolver.setUrl("bad");
    }

    // ──────────────────────────────────────────────
    //  Upgrade
    // ──────────────────────────────────────────────

    function test_upgrade_onlyOwner() public {
        khaaliSplitResolver newImpl = new khaaliSplitResolver();
        vm.prank(owner);
        resolver.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_notOwner_reverts() public {
        khaaliSplitResolver newImpl = new khaaliSplitResolver();
        vm.prank(makeAddr("rando"));
        vm.expectRevert();
        resolver.upgradeToAndCall(address(newImpl), "");
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    /// @dev Slice bytes from `start` to end.
    function _sliceBytes(bytes memory data, uint256 start) internal pure returns (bytes memory) {
        require(start <= data.length, "start out of bounds");
        uint256 len = data.length - start;
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = data[start + i];
        }
        return result;
    }
}
