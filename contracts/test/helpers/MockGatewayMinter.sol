// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {MockUSDC} from "./MockUSDC.sol";

/**
 * @title MockGatewayMinter
 * @notice Mock for Circle's Gateway Minter contract. Simulates gatewayMint
 *         by minting a configurable amount of MockUSDC to the caller.
 *
 * @dev The real GatewayMinter (0x0022222ABE238Cc2C7Bb1f21003F0a260052475B) mints
 *      USDC to the `destinationRecipient` from the attestation payload. In our
 *      settlement flow, destinationRecipient = settlement contract address, so
 *      the mock mints to msg.sender (the settlement contract).
 */
contract MockGatewayMinter {
    struct GatewayMintCall {
        bytes attestationPayload;
        bytes signature;
    }

    MockUSDC public token;
    uint256 public mintAmount;
    GatewayMintCall[] public calls;

    bool public shouldRevert;
    bool public shouldMintZero;

    constructor(address _token, uint256 _mintAmount) {
        token = MockUSDC(_token);
        mintAmount = _mintAmount;
    }

    function gatewayMint(
        bytes memory attestationPayload,
        bytes memory signature
    ) external {
        require(!shouldRevert, "MockGatewayMinter: reverted");

        calls.push(GatewayMintCall({
            attestationPayload: attestationPayload,
            signature: signature
        }));

        if (!shouldMintZero) {
            token.mint(msg.sender, mintAmount);
        }
    }

    /// @dev Get the number of gatewayMint calls recorded.
    function callCount() external view returns (uint256) {
        return calls.length;
    }

    /// @dev Set the mint amount for future calls.
    function setMintAmount(uint256 _mintAmount) external {
        mintAmount = _mintAmount;
    }

    /// @dev Toggle revert behavior.
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /// @dev Toggle zero-mint behavior (mint is called but mints 0 tokens).
    function setShouldMintZero(bool _shouldMintZero) external {
        shouldMintZero = _shouldMintZero;
    }
}
