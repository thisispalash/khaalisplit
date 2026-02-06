// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title khaaliSplitSettlement
 * @notice Settlement contract for khaaliSplit — accepts allowed stablecoins
 *         (e.g., USDC, EURC) and emits settlement intents for cross-chain relay.
 *         Deployed at a deterministic CREATE2 address across all chains via kdioDeployer.
 *
 * @dev UUPS upgradeable. Uses `initialize()` (not constructor args) so the
 *      implementation bytecode is identical across chains, preserving CREATE2
 *      address determinism.
 *
 *      Flow:
 *        1. User calls `settle()` or relayer calls `settleWithPermit()`.
 *        2. Allowed token is transferred to this contract.
 *        3. `SettlementInitiated` event is emitted (indexed by Envio/HyperIndex).
 *        4. Owner (relayer) withdraws tokens to bridge via CCTP.
 */
contract khaaliSplitSettlement is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice Allowed settlement tokens (e.g., USDC, EURC).
    mapping(address => bool) public allowedTokens;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event SettlementInitiated(
        address indexed sender,
        address indexed recipient,
        uint256 indexed destChainId,
        address token,
        uint256 amount,
        bytes note
    );

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error ZeroAmount();
    error ZeroAddress();
    error TokenNotAllowed(address token);

    // ──────────────────────────────────────────────
    //  Initializer
    // ──────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the settlement contract.
     * @param _owner Owner / relayer address.
     */
    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
    }

    // ──────────────────────────────────────────────
    //  Token management (owner only)
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
    //  Settle (user-initiated, requires prior approval)
    // ──────────────────────────────────────────────

    /**
     * @notice Initiates a settlement. The caller must have approved this contract
     *         to spend `amount` of `token` beforehand.
     * @param token       The ERC20 token to settle with (must be allowed).
     * @param recipient   Destination address on the target chain.
     * @param destChainId The chain ID where the recipient should receive funds.
     * @param amount      Token amount (in token decimals, e.g., 6 for USDC).
     * @param note        Arbitrary data (e.g., encrypted memo).
     */
    function settle(
        address token,
        address recipient,
        uint256 destChainId,
        uint256 amount,
        bytes calldata note
    ) external {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (!allowedTokens[token]) revert TokenNotAllowed(token);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit SettlementInitiated(msg.sender, recipient, destChainId, token, amount, note);
    }

    // ──────────────────────────────────────────────
    //  Settle with EIP-2612 Permit (gasless for user)
    // ──────────────────────────────────────────────

    /**
     * @notice Settles using an EIP-2612 permit — a relayer can call this on
     *         behalf of the user without the user needing to send an approve tx.
     * @param token       The ERC20 token to settle with (must be allowed + support EIP-2612).
     * @param sender      The address whose tokens are being settled.
     * @param recipient   Destination address on the target chain.
     * @param destChainId The chain ID where the recipient should receive funds.
     * @param amount      Token amount (in token decimals).
     * @param note        Arbitrary data (e.g., encrypted memo).
     * @param deadline    EIP-2612 permit deadline.
     * @param v           Signature v.
     * @param r           Signature r.
     * @param s           Signature s.
     */
    function settleWithPermit(
        address token,
        address sender,
        address recipient,
        uint256 destChainId,
        uint256 amount,
        bytes calldata note,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (!allowedTokens[token]) revert TokenNotAllowed(token);

        IERC20Permit(token).permit(sender, address(this), amount, deadline, v, r, s);
        IERC20(token).safeTransferFrom(sender, address(this), amount);

        emit SettlementInitiated(sender, recipient, destChainId, token, amount, note);
    }

    // ──────────────────────────────────────────────
    //  Withdraw (owner / relayer)
    // ──────────────────────────────────────────────

    /**
     * @notice Withdraws tokens from the contract. Used by the relayer to move
     *         tokens to a bridge (e.g., CCTP).
     * @param token  The ERC20 token to withdraw.
     * @param to     The recipient address.
     * @param amount The amount to withdraw.
     */
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
    }

    // ──────────────────────────────────────────────
    //  UUPS
    // ──────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
