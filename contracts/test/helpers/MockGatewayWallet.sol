// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockGatewayWallet
 * @notice Mock for Circle's Gateway Wallet contract. Records depositFor calls
 *         and pulls tokens from the caller for test assertions.
 *
 * @dev Mimics the real GatewayWallet behavior:
 *      - Requires the caller to have approved this contract for the token amount.
 *      - Pulls tokens via transferFrom.
 *      - Credits the balance to the `depositor` address (tracked for assertions).
 */
contract MockGatewayWallet {
    using SafeERC20 for IERC20;

    struct DepositForCall {
        address token;
        address depositor;
        uint256 value;
    }

    DepositForCall[] public calls;

    /// @dev Track depositor balances for assertion.
    mapping(address => mapping(address => uint256)) public balances;

    /// @dev Toggle to force depositFor to revert.
    bool public shouldRevert;

    function depositFor(
        address token,
        address depositor,
        uint256 value
    ) external {
        require(!shouldRevert, "MockGatewayWallet: reverted");

        // Pull tokens from caller (simulates Gateway deposit)
        IERC20(token).safeTransferFrom(msg.sender, address(this), value);

        // Credit depositor balance
        balances[depositor][token] += value;

        calls.push(DepositForCall({
            token: token,
            depositor: depositor,
            value: value
        }));
    }

    /// @dev Get the number of depositFor calls recorded.
    function callCount() external view returns (uint256) {
        return calls.length;
    }

    /// @dev Get a specific depositFor call by index.
    function getCall(uint256 index) external view returns (DepositForCall memory) {
        return calls[index];
    }

    /// @dev Test helper: toggle revert behavior.
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}
