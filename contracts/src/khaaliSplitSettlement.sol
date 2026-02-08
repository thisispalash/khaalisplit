// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenMessengerV2} from "./interfaces/ITokenMessengerV2.sol";
import {IGatewayWallet} from "./interfaces/IGatewayWallet.sol";
import {IERC20Receive} from "./interfaces/IERC20Receive.sol";
import {IkhaaliSplitSubnames} from "./interfaces/IkhaaliSplitSubnames.sol";
import {IkhaaliSplitReputation} from "./interfaces/IkhaaliSplitReputation.sol";

/**
 * @title khaaliSplitSettlement
 * @notice Settlement contract for khaaliSplit — routes USDC payments to recipients
 *         based on their ENS text record preferences (Gateway or CCTP).
 *         Deployed at a deterministic CREATE2 address across all chains via kdioDeployer.
 *
 * @dev UUPS upgradeable. Uses `initialize(address _owner)` (not constructor args)
 *      so the implementation bytecode is identical across chains, preserving CREATE2
 *      address determinism.
 *
 *      Flow:
 *        1. User signs an EIP-3009 ReceiveWithAuthorization message off-chain.
 *        2. Anyone submits the signature via settleWithAuthorization().
 *        3. Contract pulls USDC from sender via receiveWithAuthorization on USDC.
 *        4. Reads recipient's payment preferences from ENS text records:
 *             - com.khaalisplit.payment.flow: "gateway" (default) or "cctp"
 *             - com.khaalisplit.payment.token: token address on destination chain
 *             - com.khaalisplit.payment.chain: destination chain ID
 *             - com.khaalisplit.payment.cctp: CCTP domain (required if flow == "cctp")
 *        5. Routes funds: Gateway → depositFor, CCTP → depositForBurn.
 *        6. Updates sender's reputation score via reputation contract.
 *        7. Emits SettlementCompleted event.
 *
 *      settle() is a stub that reverts — reserved for a future approval-based flow.
 */
contract khaaliSplitSettlement is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    /// @notice Sentinel value emitted in SettlementCompleted when reputation contract
    ///         is not configured. Distinguishable from valid scores (0–100).
    uint256 public constant REPUTATION_NOT_SET = 500;

    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice Allowed settlement tokens (e.g. USDC).
    mapping(address => bool) public allowedTokens;

    /// @notice CCTP TokenMessengerV2 address for cross-chain burns.
    ITokenMessengerV2 public tokenMessenger;

    /// @notice EVM chain ID → CCTP domain mapping.
    mapping(uint256 => uint32) public chainIdToDomain;

    /// @notice Whether a CCTP domain has been configured for a given chain ID.
    mapping(uint256 => bool) public domainConfigured;

    /// @notice Circle Gateway Wallet address for Gateway deposits.
    IGatewayWallet public gatewayWallet;

    /// @notice Subname registry for reading payment preferences from ENS text records.
    IkhaaliSplitSubnames public subnameRegistry;

    /// @notice Reputation contract for post-settlement score updates.
    IkhaaliSplitReputation public reputationContract;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event SettlementCompleted(
        address indexed sender,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 senderReputation,
        bytes memo
    );

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event TokenMessengerUpdated(address indexed newTokenMessenger);
    event GatewayWalletUpdated(address indexed newGatewayWallet);
    event DomainConfigured(uint256 indexed chainId, uint32 domain);
    event SubnameRegistryUpdated(address indexed newSubnameRegistry);
    event ReputationContractUpdated(address indexed newReputationContract);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error NotImplemented();
    error ZeroAmount();
    error ZeroAddress();
    error TokenNotAllowed(address token);
    error RecipientNotRegistered(bytes32 node);
    error SubnameRegistryNotSet();
    error GatewayWalletNotSet();
    error TokenMessengerNotSet();
    error CctpDomainNotInTextRecord();

    // ──────────────────────────────────────────────
    //  Structs
    // ──────────────────────────────────────────────

    /// @notice EIP-3009 authorization parameters for settleWithAuthorization.
    struct Authorization {
        address from;         // Sender (token holder who signed)
        uint256 validAfter;   // Unix timestamp — authorization valid after
        uint256 validBefore;  // Unix timestamp — authorization valid before
        bytes32 nonce;        // Random nonce for replay protection
    }

    // ──────────────────────────────────────────────
    //  Initializer
    // ──────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the settlement contract.
     * @dev Signature MUST remain `initialize(address)` to preserve CREATE2
     *      determinism with empty init data across all chains.
     *      All CCTP/Gateway/subname/reputation config via post-init setters.
     * @param _owner Owner address (admin).
     */
    function initialize(address _owner) external initializer {
        if (_owner == address(0)) revert ZeroAddress();
        __Ownable_init(_owner);
    }

    // ──────────────────────────────────────────────
    //  Settlement — Stub (future approval-based flow)
    // ──────────────────────────────────────────────

    /**
     * @notice Placeholder for future approval-based settlement.
     * @dev Currently reverts with NotImplemented(). Reserved for when
     *      the approval-based flow is implemented in a future iteration.
     */
    function settle(bytes32, uint256, bytes calldata) external pure {
        revert NotImplemented();
    }

    // ──────────────────────────────────────────────
    //  Settlement — EIP-3009 Authorization
    // ──────────────────────────────────────────────

    /**
     * @notice Primary settlement function using EIP-3009 authorization.
     *
     * @dev Flow:
     *      1. Validates inputs (amount, recipientNode, subname registry).
     *      2. Resolves the recipient's wallet address from the ENS node.
     *      3. Resolves the token from recipient's text records.
     *      4. Calls receiveWithAuthorization on the USDC contract to pull tokens.
     *      5. Routes: Gateway (default) or CCTP (opt-in).
     *      6. Updates sender reputation.
     *      7. Emits SettlementCompleted.
     *
     *      The sender signs a ReceiveWithAuthorization message with `to` = this contract.
     *      Anyone can submit the signature (enables offline/relayed settlements).
     *
     * @param recipientNode The ENS namehash of the recipient's subname.
     * @param amount        The USDC amount to settle (in token decimals, e.g. 6 for USDC).
     * @param memo          Arbitrary data (e.g. encrypted memo for off-chain indexing).
     * @param auth          EIP-3009 authorization parameters (from, validAfter, validBefore, nonce).
     * @param signature     EIP-3009 signature (packed r, s, v for EOA wallets).
     */
    function settleWithAuthorization(
        bytes32 recipientNode,
        uint256 amount,
        bytes calldata memo,
        Authorization calldata auth,
        bytes calldata signature
    ) external {
        if (amount == 0) revert ZeroAmount();
        if (recipientNode == bytes32(0)) revert ZeroAddress();
        if (address(subnameRegistry) == address(0)) revert SubnameRegistryNotSet();

        // Resolve the recipient's wallet address from their ENS node
        address recipient = subnameRegistry.addr(recipientNode);
        if (recipient == address(0)) revert RecipientNotRegistered(recipientNode);

        // Determine the token on the current chain from recipient's preferences
        address token = _resolveToken(recipientNode);
        if (!allowedTokens[token]) revert TokenNotAllowed(token);

        // Pull USDC from sender via EIP-3009 receiveWithAuthorization.
        // The sender signed: ReceiveWithAuthorization(from, to=this, value, validAfter, validBefore, nonce)
        // Only this contract (msg.sender == to) can execute this on the USDC contract.
        IERC20Receive(token).receiveWithAuthorization(
            auth.from,
            address(this),
            amount,
            auth.validAfter,
            auth.validBefore,
            auth.nonce,
            signature
        );

        // Route settlement based on recipient's payment flow preference
        _routeSettlement(recipientNode, recipient, token, amount);

        // Update sender reputation
        uint256 senderReputation = _updateReputation(auth.from);

        emit SettlementCompleted(auth.from, recipient, token, amount, senderReputation, memo);
    }

    // ──────────────────────────────────────────────
    //  Token Management (owner only)
    // ──────────────────────────────────────────────

    /**
     * @notice Adds a token to the allowed list.
     * @param token The ERC20 token address to allow.
     */
    function addToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        allowedTokens[token] = true;
        emit TokenAdded(token);
    }

    /**
     * @notice Removes a token from the allowed list.
     * @param token The ERC20 token address to disallow.
     */
    function removeToken(address token) external onlyOwner {
        allowedTokens[token] = false;
        emit TokenRemoved(token);
    }

    // ──────────────────────────────────────────────
    //  Admin (owner only)
    // ──────────────────────────────────────────────

    /// @notice Set the CCTP TokenMessengerV2 address.
    /// @dev address(0) is allowed (disables CCTP routing).
    function setTokenMessenger(address _tokenMessenger) external onlyOwner {
        tokenMessenger = ITokenMessengerV2(_tokenMessenger);
        emit TokenMessengerUpdated(_tokenMessenger);
    }

    /// @notice Configure a CCTP domain mapping for a chain ID.
    /// @param chainId The EVM chain ID.
    /// @param domain  The CCTP domain identifier.
    function configureDomain(uint256 chainId, uint32 domain) external onlyOwner {
        chainIdToDomain[chainId] = domain;
        domainConfigured[chainId] = true;
        emit DomainConfigured(chainId, domain);
    }

    /// @notice Set the Circle Gateway Wallet address.
    /// @dev address(0) is allowed (disables Gateway routing).
    function setGatewayWallet(address _gatewayWallet) external onlyOwner {
        gatewayWallet = IGatewayWallet(_gatewayWallet);
        emit GatewayWalletUpdated(_gatewayWallet);
    }

    /// @notice Set the subname registry for reading payment preferences.
    /// @dev address(0) is allowed (disables ENS lookups — settlements will revert).
    function setSubnameRegistry(address _subnameRegistry) external onlyOwner {
        subnameRegistry = IkhaaliSplitSubnames(_subnameRegistry);
        emit SubnameRegistryUpdated(_subnameRegistry);
    }

    /// @notice Set the reputation contract for post-settlement score updates.
    /// @dev address(0) is allowed (disables reputation updates, emits 500 sentinel).
    function setReputationContract(address _reputationContract) external onlyOwner {
        reputationContract = IkhaaliSplitReputation(_reputationContract);
        emit ReputationContractUpdated(_reputationContract);
    }

    // ──────────────────────────────────────────────
    //  Internal — Token Resolution
    // ──────────────────────────────────────────────

    /**
     * @dev Resolve which token to use for settlement on the current chain.
     *      Reads com.khaalisplit.payment.token from the recipient's text records.
     *      If the text record is empty, returns address(0) — caller validates
     *      against allowedTokens and will revert with TokenNotAllowed(address(0)).
     */
    function _resolveToken(bytes32 recipientNode) internal view returns (address) {
        string memory tokenStr = subnameRegistry.text(
            recipientNode,
            "com.khaalisplit.payment.token"
        );

        if (bytes(tokenStr).length == 0) {
            return address(0);
        }

        return _parseAddress(tokenStr);
    }

    // ──────────────────────────────────────────────
    //  Internal — Settlement Routing
    // ──────────────────────────────────────────────

    /**
     * @dev Route the settlement based on the recipient's payment.flow preference.
     *      - "" or "gateway" → Gateway deposit (default)
     *      - "cctp" → CCTP cross-chain burn
     *      - anything else → Gateway deposit (fallback)
     */
    function _routeSettlement(
        bytes32 recipientNode,
        address recipient,
        address token,
        uint256 amount
    ) internal {
        string memory flow = subnameRegistry.text(
            recipientNode,
            "com.khaalisplit.payment.flow"
        );

        if (_strEq(flow, "cctp")) {
            _settleViaCCTP(recipientNode, recipient, token, amount);
        } else {
            // Default: gateway (includes empty string, "gateway", or unknown values)
            _settleViaGateway(recipient, token, amount);
        }
    }

    /**
     * @dev Execute Gateway settlement: approve GatewayWallet, then depositFor.
     *      The recipient gets a unified Gateway USDC balance.
     */
    function _settleViaGateway(
        address recipient,
        address token,
        uint256 amount
    ) internal {
        if (address(gatewayWallet) == address(0)) revert GatewayWalletNotSet();

        IERC20(token).forceApprove(address(gatewayWallet), amount);
        gatewayWallet.depositFor(token, recipient, amount);
    }

    /**
     * @dev Execute CCTP settlement: approve TokenMessenger, then depositForBurn.
     *      Reads the CCTP domain from the recipient's text records.
     *      Reverts if the CCTP domain text record is not set.
     */
    function _settleViaCCTP(
        bytes32 recipientNode,
        address recipient,
        address token,
        uint256 amount
    ) internal {
        if (address(tokenMessenger) == address(0)) revert TokenMessengerNotSet();

        string memory cctpDomainStr = subnameRegistry.text(
            recipientNode,
            "com.khaalisplit.payment.cctp"
        );
        if (bytes(cctpDomainStr).length == 0) revert CctpDomainNotInTextRecord();

        uint32 domain = _parseUint32(cctpDomainStr);

        IERC20(token).forceApprove(address(tokenMessenger), amount);
        tokenMessenger.depositForBurn(
            amount,
            domain,
            bytes32(uint256(uint160(recipient))),
            token
        );
    }

    // ──────────────────────────────────────────────
    //  Internal — Reputation
    // ──────────────────────────────────────────────

    /**
     * @dev Update the sender's reputation after a successful settlement.
     *      Returns the new reputation score, or REPUTATION_NOT_SET (500)
     *      if the reputation contract is not configured.
     */
    function _updateReputation(address sender) internal returns (uint256) {
        if (address(reputationContract) == address(0)) {
            return REPUTATION_NOT_SET;
        }

        reputationContract.recordSettlement(sender, true);
        return reputationContract.getReputation(sender);
    }

    // ──────────────────────────────────────────────
    //  Internal — String Utilities
    // ──────────────────────────────────────────────

    /// @dev Compare two strings for equality.
    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @dev Parse a hex address string (with or without 0x prefix) into an address.
     *      Expects exactly 40 hex characters after optional prefix.
     */
    function _parseAddress(string memory str) internal pure returns (address) {
        bytes memory b = bytes(str);
        uint256 offset = 0;

        if (b.length >= 2 && b[0] == "0" && (b[1] == "x" || b[1] == "X")) {
            offset = 2;
        }

        require(b.length - offset == 40, "Invalid address length");

        uint160 addr = 0;
        for (uint256 i = offset; i < b.length; i++) {
            addr = addr * 16 + uint160(_hexCharToUint8(uint8(b[i])));
        }

        return address(addr);
    }

    /**
     * @dev Parse a decimal string into a uint32. Reverts on invalid input.
     */
    function _parseUint32(string memory str) internal pure returns (uint32) {
        bytes memory b = bytes(str);
        require(b.length > 0, "Empty string");

        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            require(c >= 48 && c <= 57, "Invalid digit");
            result = result * 10 + (c - 48);
            require(result <= type(uint32).max, "Overflow");
        }

        return uint32(result);
    }

    /// @dev Convert a single hex character to its numeric value (0–15).
    function _hexCharToUint8(uint8 c) internal pure returns (uint8) {
        if (c >= 48 && c <= 57) return c - 48;        // '0'-'9'
        if (c >= 65 && c <= 70) return c - 55;        // 'A'-'F'
        if (c >= 97 && c <= 102) return c - 87;       // 'a'-'f'
        revert("Invalid hex char");
    }

    // ──────────────────────────────────────────────
    //  UUPS
    // ──────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
