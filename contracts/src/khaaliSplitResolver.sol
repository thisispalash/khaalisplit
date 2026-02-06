// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/resolvers/profiles/IExtendedResolver.sol";

/**
 * @title khaaliSplitResolver
 * @notice CCIP-Read (EIP-3668) off-chain resolver for khaaliSplit ENS subnames.
 *         Implements IExtendedResolver (0x9061b923) to handle wildcard resolution
 *         of `{username}.khaalisplit.eth` subnames via an off-chain gateway.
 *
 * @dev Flow:
 *   1. Client calls `resolve(name, data)` → reverts with `OffchainLookup`
 *   2. Client fetches result from gateway URL
 *   3. Client calls `resolveWithProof(response, extraData)` → verifies signature, returns result
 *
 *   Uses OZ ECDSA.recover() to recover the signer from the gateway response,
 *   then checks the recovered address against the trusted `signers` mapping.
 */
contract khaaliSplitResolver is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using ECDSA for bytes32;

    // ──────────────────────────────────────────────
    //  EIP-3668 Error
    // ──────────────────────────────────────────────

    error OffchainLookup(
        address sender,
        string[] urls,
        bytes callData,
        bytes4 callbackFunction,
        bytes extraData
    );

    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice Gateway URL template (EIP-3668 format with `{sender}` and `{data}`).
    string public url;

    /// @notice Trusted gateway signer addresses.
    mapping(address => bool) public signers;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event UrlUpdated(string newUrl);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error InvalidSignature();
    error SignatureExpired();
    error ResponseTooShort();

    // ──────────────────────────────────────────────
    //  Initializer
    // ──────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the resolver.
     * @param _url     Gateway URL template.
     * @param _signers Initial set of trusted gateway signers.
     * @param _owner   Owner of the contract.
     */
    function initialize(
        string calldata _url,
        address[] calldata _signers,
        address _owner
    ) external initializer {
        __Ownable_init(_owner);
        url = _url;

        for (uint256 i = 0; i < _signers.length; i++) {
            signers[_signers[i]] = true;
            emit SignerAdded(_signers[i]);
        }
    }

    // ──────────────────────────────────────────────
    //  IExtendedResolver — resolve (Step 1: revert with OffchainLookup)
    // ──────────────────────────────────────────────

    /**
     * @notice Resolves an ENS name by reverting with OffchainLookup to trigger
     *         CCIP-Read flow. The client will fetch the result from the gateway
     *         and call `resolveWithProof`.
     * @param name DNS-encoded ENS name.
     * @param data ABI-encoded resolver call (e.g., addr(bytes32)).
     */
    function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory) {
        string[] memory urls = new string[](1);
        urls[0] = url;

        bytes memory callData = abi.encodeWithSelector(
            IExtendedResolver.resolve.selector,
            name,
            data
        );

        revert OffchainLookup(
            address(this),
            urls,
            callData,
            this.resolveWithProof.selector,
            abi.encode(name, data)
        );
    }

    // ──────────────────────────────────────────────
    //  IExtendedResolver callback — resolveWithProof (Step 3: verify + return)
    // ──────────────────────────────────────────────

    /**
     * @notice Callback for CCIP-Read. Verifies the gateway's signed response.
     * @param response ABI-encoded (bytes result, uint64 expires, bytes signature).
     * @param extraData ABI-encoded (bytes name, bytes data) from the original resolve call.
     * @return The verified result bytes.
     *
     * @dev Signature is over EIP-191 hash:
     *      keccak256(0x1900 || target || expires || keccak256(request) || keccak256(result))
     */
    function resolveWithProof(
        bytes calldata response,
        bytes calldata extraData
    ) external view returns (bytes memory) {
        (bytes memory result, uint64 expires, bytes memory sig) =
            abi.decode(response, (bytes, uint64, bytes));

        if (block.timestamp > expires) revert SignatureExpired();

        // Reconstruct request from extraData
        (bytes memory name, bytes memory data) = abi.decode(extraData, (bytes, bytes));
        bytes memory request = abi.encodeWithSelector(
            IExtendedResolver.resolve.selector,
            name,
            data
        );

        // Build EIP-191 signed message hash
        // Format: 0x1900 || target || expires || keccak256(request) || keccak256(result)
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                hex"1900",
                address(this),
                expires,
                keccak256(request),
                keccak256(result)
            )
        );

        // Recover signer and check trust
        address recovered = messageHash.recover(sig);
        if (!signers[recovered]) revert InvalidSignature();

        return result;
    }

    // ──────────────────────────────────────────────
    //  ERC165
    // ──────────────────────────────────────────────

    /**
     * @notice Returns true for IExtendedResolver (0x9061b923) and IERC165 (0x01ffc9a7).
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IExtendedResolver).interfaceId || // 0x9061b923
            interfaceId == 0x01ffc9a7; // IERC165
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    function addSigner(address signer) external onlyOwner {
        signers[signer] = true;
        emit SignerAdded(signer);
    }

    function removeSigner(address signer) external onlyOwner {
        signers[signer] = false;
        emit SignerRemoved(signer);
    }

    function setUrl(string calldata _url) external onlyOwner {
        url = _url;
        emit UrlUpdated(_url);
    }

    // ──────────────────────────────────────────────
    //  UUPS
    // ──────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
