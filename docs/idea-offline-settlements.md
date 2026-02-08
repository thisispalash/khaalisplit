# Idea: Offline Settlements via EIP-3009

## The Problem

Traditional on-chain payments require the sender to be online to submit a transaction. In a group expense-splitting app, this creates friction — you shouldn't need both parties actively online at the same moment to settle a debt.

## The Insight

EIP-3009 (`receiveWithAuthorization`) lets a USDC holder **sign a transfer authorization off-chain**. The signature is a typed data message (EIP-712) that authorizes a specific recipient to pull a specific amount of USDC. Crucially, **anyone** can submit this signature to the chain — not just the sender.

This means: the sender signs while they have connectivity, and the recipient (or a relayer, or the app backend) submits the transaction whenever convenient.

## How It Works in khaaliSplit

1. **Sender signs off-chain**: The PWA presents a settlement, and the sender signs an EIP-3009 `ReceiveWithAuthorization` message. This produces a `(v, r, s)` signature over `(from, to, value, validAfter, validBefore, nonce)`.
2. **Signature is stored**: The signed authorization can be stored locally, sent via any messaging channel, or held by the app.
3. **Anyone submits**: When ready, anyone calls `settleWithAuthorization()` on `khaaliSplitSettlement`, passing the signature. The contract calls `IUSDC.receiveWithAuthorization()` which validates the signature and transfers the USDC.
4. **Routing kicks in**: After the direct transfer, `_routeSettlement()` reads the recipient's ENS payment preferences and routes funds accordingly (keep on current chain, bridge via Gateway, or burn via CCTP).

## Why This Is Interesting

- **True offline capability** — the sender can sign on an airplane, in the subway, anywhere. The settlement executes later.
- **No gas for the sender** — since anyone can submit, a relayer or the recipient themselves can pay gas. This is native gasless UX without a separate meta-transaction layer.
- **Non-custodial** — at no point does khaaliSplit hold user funds. The USDC moves directly from sender to the settlement contract's routing logic.
- **Replay-safe** — EIP-3009 uses unique nonces, so each authorization can only be used once.
- **Time-bounded** — `validAfter` and `validBefore` parameters let senders set expiration windows on their authorizations.

## Trade-offs

- Only works with tokens that implement EIP-3009 (USDC does, most other ERC-20s do not)
- The sender must have sufficient USDC balance **at execution time**, not signing time — a stale signature can fail
- Requires the sender to trust that the signed authorization won't be front-run for a different purpose (mitigated by the specific `to` address in the signature)
