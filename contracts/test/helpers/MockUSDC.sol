// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title MockUSDC
 * @notice A mock USDC token with 6 decimals, ERC20Permit, and EIP-3009
 *         receiveWithAuthorization support for testing.
 *
 * @dev The receiveWithAuthorization implementation is simplified for testing:
 *      - Does NOT verify EIP-712 signatures (trusts all calls).
 *      - Enforces msg.sender == to (front-running protection).
 *      - Tracks used nonces to prevent replay.
 *      - Transfers tokens from `from` to `to`.
 */
contract MockUSDC is ERC20, ERC20Permit {
    /// @dev Track used authorization nonces to prevent replay.
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    /// @dev Toggle to force receiveWithAuthorization to revert.
    bool public shouldRevertAuth;

    constructor() ERC20("USD Coin", "USDC") ERC20Permit("USD Coin") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Mock EIP-3009 receiveWithAuthorization.
     * @dev Simplified: does not verify signatures. Enforces msg.sender == to
     *      and nonce uniqueness. Transfers tokens from `from` to `to`.
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata // signature — not verified in mock
    ) external {
        require(!shouldRevertAuth, "MockUSDC: auth reverted");
        require(to == msg.sender, "FiatTokenV2: caller must be the payee");
        require(block.timestamp > validAfter, "FiatTokenV2: auth not yet valid");
        require(block.timestamp < validBefore, "FiatTokenV2: auth expired");
        require(!_authorizationStates[from][nonce], "FiatTokenV2: auth already used");

        _authorizationStates[from][nonce] = true;
        _transfer(from, to, value);
    }

    /// @dev Check if an authorization nonce has been used.
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    /// @dev Test helper: toggle auth revert behavior.
    function setShouldRevertAuth(bool _shouldRevert) external {
        shouldRevertAuth = _shouldRevert;
    }
}
