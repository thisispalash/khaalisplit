// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {INameWrapper} from "@ensdomains/ens-contracts/wrapper/INameWrapper.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/resolvers/profiles/IAddrResolver.sol";
import {ITextResolver} from "@ensdomains/ens-contracts/resolvers/profiles/ITextResolver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title khaaliSplitSubnames
 * @notice On-chain ENS subname registrar + resolver for khaaliSplit.
 *         Registers `{username}.khaalisplit.eth` subnames via ENS NameWrapper
 *         and stores text + addr records on-chain (no CCIP-Read gateway needed).
 *
 * @dev UUPS upgradeable. Authorized callers for record mutations:
 *      - subname owner (verified via NameWrapper.ownerOf)
 *      - backend address (relayed from the PWA)
 *      - reputationContract (for automated reputation score syncing)
 *
 *      This contract acts as both the registrar (calls NameWrapper.setSubnodeRecord)
 *      and the resolver (implements IAddrResolver + ITextResolver for on-chain reads).
 *      Set this contract as the resolver when registering subnames so that ENS
 *      clients call text() / addr() directly on this contract.
 */
contract khaaliSplitSubnames is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice ENS NameWrapper contract reference.
    INameWrapper public nameWrapper;

    /// @notice Namehash of the parent name (e.g. namehash("khaalisplit.eth")).
    bytes32 public parentNode;

    /// @notice Authorized backend address that can register subnames and set records.
    address public backend;

    /// @notice On-chain addr() records: node → address.
    mapping(bytes32 => address) private _addresses;

    /// @notice On-chain text() records: node → key → value.
    mapping(bytes32 => mapping(string => string)) private _texts;

    /// @notice Reputation contract authorized to call setText for score syncing.
    /// @dev Set to address(0) until the reputation contract is deployed.
    address public reputationContract;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event SubnameRegistered(bytes32 indexed node, string label, address indexed owner);
    event TextRecordSet(bytes32 indexed node, string key, string value);
    event AddrRecordSet(bytes32 indexed node, address addr);
    event BackendUpdated(address indexed newBackend);
    event ReputationContractUpdated(address indexed newReputationContract);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error Unauthorized();
    error ZeroAddress();
    error EmptyLabel();
    error SubnameAlreadyRegistered();

    // ──────────────────────────────────────────────
    //  Initializer
    // ──────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the subname registrar.
     * @param _nameWrapper Address of the ENS NameWrapper contract.
     * @param _parentNode  Namehash of the parent name (e.g. khaalisplit.eth).
     * @param _backend     Authorized backend address.
     * @param _owner       Owner of this contract (admin).
     */
    function initialize(
        address _nameWrapper,
        bytes32 _parentNode,
        address _backend,
        address _owner
    ) external initializer {
        if (_nameWrapper == address(0)) revert ZeroAddress();
        if (_backend == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        __Ownable_init(_owner);

        nameWrapper = INameWrapper(_nameWrapper);
        parentNode = _parentNode;
        backend = _backend;
    }

    // ──────────────────────────────────────────────
    //  Registration
    // ──────────────────────────────────────────────

    /**
     * @notice Register a new subname under khaalisplit.eth.
     * @dev Backend only. Calls NameWrapper.setSubnodeRecord with this contract
     *      as the resolver. No fuses burned (deferred to a later iteration).
     *      Sets default text records on registration.
     * @param label The subname label (e.g. "alice" for alice.khaalisplit.eth).
     * @param owner The address that will own the subname.
     */
    function register(string calldata label, address owner) external {
        if (msg.sender != backend) revert Unauthorized();
        if (bytes(label).length == 0) revert EmptyLabel();
        if (owner == address(0)) revert ZeroAddress();

        bytes32 node = subnameNode(label);

        // Check if the subname is already registered by querying NameWrapper ownership.
        // ownerOf returns address(0) for unregistered/unwrapped nodes.
        try nameWrapper.ownerOf(uint256(node)) returns (address existingOwner) {
            if (existingOwner != address(0)) revert SubnameAlreadyRegistered();
        } catch {
            // ownerOf reverted — node doesn't exist yet, safe to proceed
        }

        // Register the subname via NameWrapper.
        // resolver = address(this) so ENS clients resolve records from this contract.
        // fuses = 0 (no fuses burned — parent retains control, deferred to later iteration).
        // expiry = type(uint64).max (no expiration).
        nameWrapper.setSubnodeRecord(
            parentNode,
            label,
            owner,
            address(this), // this contract is the resolver
            0,             // ttl
            0,             // fuses — none burned for now
            type(uint64).max // expiry — max (no expiration)
        );

        // Set default text records
        _texts[node]["com.khaalisplit.subname"] = label;
        _texts[node]["com.khaalisplit.reputation"] = "50";

        // Set default addr record to the owner
        _addresses[node] = owner;

        emit SubnameRegistered(node, label, owner);
        emit AddrRecordSet(node, owner);
    }

    // ──────────────────────────────────────────────
    //  Record Setters
    // ──────────────────────────────────────────────

    /**
     * @notice Set a text record for a subname node.
     * @dev Authorized callers: subname owner, backend, or reputationContract.
     * @param node The ENS namehash of the subname.
     * @param key  The text record key.
     * @param value The text record value.
     */
    function setText(bytes32 node, string calldata key, string calldata value) external {
        if (!_isAuthorized(node, msg.sender)) revert Unauthorized();

        _texts[node][key] = value;
        emit TextRecordSet(node, key, value);
    }

    /**
     * @notice Set the address record for a subname node.
     * @dev Authorized callers: subname owner, backend, or reputationContract.
     * @param node  The ENS namehash of the subname.
     * @param _addr The address to associate with the node.
     */
    function setAddr(bytes32 node, address _addr) external {
        if (!_isAuthorized(node, msg.sender)) revert Unauthorized();

        _addresses[node] = _addr;
        emit AddrRecordSet(node, _addr);
    }

    // ──────────────────────────────────────────────
    //  Record Getters (ENS Resolver Interface)
    // ──────────────────────────────────────────────

    /**
     * @notice Returns the text record for a node and key.
     * @dev Implements ITextResolver.text().
     */
    function text(bytes32 node, string calldata key) external view returns (string memory) {
        return _texts[node][key];
    }

    /**
     * @notice Returns the address associated with a node.
     * @dev Implements IAddrResolver.addr(). Returns payable per the ENS interface spec.
     */
    function addr(bytes32 node) external view returns (address payable) {
        return payable(_addresses[node]);
    }

    // ──────────────────────────────────────────────
    //  Utilities
    // ──────────────────────────────────────────────

    /**
     * @notice Compute the namehash for a subname label under the parent node.
     * @dev namehash(label.parent) = keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))))
     * @param label The subname label.
     * @return The ENS namehash of `label.khaalisplit.eth`.
     */
    function subnameNode(string calldata label) public view returns (bytes32) {
        return keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))));
    }

    // ──────────────────────────────────────────────
    //  ERC-165
    // ──────────────────────────────────────────────

    /**
     * @notice Returns true for IAddrResolver, ITextResolver, and IERC165.
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IAddrResolver).interfaceId ||  // 0x3b3b57de
            interfaceId == type(ITextResolver).interfaceId ||  // 0x59d1d43c
            interfaceId == type(IERC165).interfaceId;          // 0x01ffc9a7
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /// @notice Update the backend address.
    function setBackend(address _backend) external onlyOwner {
        if (_backend == address(0)) revert ZeroAddress();
        backend = _backend;
        emit BackendUpdated(_backend);
    }

    /// @notice Set the reputation contract address authorized to call setText.
    /// @dev address(0) is allowed (disables reputation syncing).
    function setReputationContract(address _reputationContract) external onlyOwner {
        reputationContract = _reputationContract;
        emit ReputationContractUpdated(_reputationContract);
    }

    // ──────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────

    /**
     * @dev Check if a caller is authorized to modify records for a node.
     *      Authorized callers: backend, reputationContract, or the subname owner
     *      (looked up via NameWrapper.ownerOf).
     */
    function _isAuthorized(bytes32 node, address caller) internal view returns (bool) {
        if (caller == backend) return true;
        if (reputationContract != address(0) && caller == reputationContract) return true;

        // Check if the caller is the subname owner via NameWrapper
        try nameWrapper.ownerOf(uint256(node)) returns (address owner) {
            return caller == owner;
        } catch {
            return false;
        }
    }

    // ──────────────────────────────────────────────
    //  UUPS
    // ──────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
