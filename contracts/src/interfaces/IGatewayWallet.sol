// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IGatewayWallet
 * @notice Minimal interface for Circle's Gateway Wallet contract.
 *         Only includes depositFor — used by khaaliSplitSettlement to deposit
 *         USDC into a recipient's unified Gateway balance.
 *
 * @dev Full docs: https://developers.circle.com/gateway/references/contract-interfaces-and-events
 *
 *      WARNING: Do NOT send USDC to the Gateway Wallet via plain ERC-20 transfer.
 *      You MUST call depositFor() or the funds will be lost.
 *
 *      Deployed addresses:
 *        - Testnet: 0x0077777d7EBA4688BDeF3E311b846F25870A19B9
 *        - Mainnet: TBD (uses 0x7777777 prefix)
 */
interface IGatewayWallet {
    /**
     * @notice Deposit tokens into Gateway on behalf of a depositor.
     *         The resulting balance belongs to the `depositor` address,
     *         not the function caller.
     *
     * @dev The caller must have approved this contract for `value` of `token`
     *      before calling. The caller pulls tokens via transferFrom.
     *
     * @param token     The ERC-20 token to deposit (e.g. USDC).
     * @param depositor The address that will receive the Gateway balance.
     * @param value     The amount of tokens to deposit.
     */
    function depositFor(
        address token,
        address depositor,
        uint256 value
    ) external;
}
