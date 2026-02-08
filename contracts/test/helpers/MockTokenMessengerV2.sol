// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockTokenMessengerV2
 * @notice Mock for Circle's CCTP TokenMessengerV2. Records depositForBurn calls
 *         and pulls tokens from the caller for test assertions.
 */
contract MockTokenMessengerV2 {
    using SafeERC20 for IERC20;

    struct DepositForBurnCall {
        uint256 amount;
        uint32 destinationDomain;
        bytes32 mintRecipient;
        address burnToken;
    }

    DepositForBurnCall[] public calls;
    uint64 private _nextNonce;

    /// @dev Toggle to force depositForBurn to revert.
    bool public shouldRevert;

    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 nonce) {
        require(!shouldRevert, "MockTokenMessengerV2: reverted");

        // Pull tokens from caller (simulates CCTP burning)
        IERC20(burnToken).safeTransferFrom(msg.sender, address(this), amount);

        calls.push(DepositForBurnCall({
            amount: amount,
            destinationDomain: destinationDomain,
            mintRecipient: mintRecipient,
            burnToken: burnToken
        }));

        nonce = _nextNonce++;
    }

    /// @dev Get the number of depositForBurn calls recorded.
    function callCount() external view returns (uint256) {
        return calls.length;
    }

    /// @dev Get a specific depositForBurn call by index.
    function getCall(uint256 index) external view returns (DepositForBurnCall memory) {
        return calls[index];
    }

    /// @dev Test helper: toggle revert behavior.
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}
