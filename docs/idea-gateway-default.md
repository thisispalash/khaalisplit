# Idea: Gateway as Default Settlement Route for Instant Cross-Chain USDC

## The Problem

Cross-chain USDC transfers via CCTP are reliable but slow — they require waiting for attestations from Circle's off-chain attestation service, which can take minutes. For an expense-splitting app where users expect near-instant feedback, that latency feels broken.

## The Insight

Circle's **Gateway** protocol offers an alternative: `depositFor` sends USDC to the Gateway contract on the source chain, and the recipient receives USDC on their preferred destination chain **almost instantly** — because Gateway manages liquidity pools across chains and can front the funds before the underlying bridge settles.

By defaulting all settlements to Gateway routing, khaaliSplit gives users the fastest possible cross-chain experience out of the box.

## How It Works

### Default Flow (Gateway)

1. Settlement is triggered (via EIP-3009 or Gateway mint)
2. `_routeSettlement()` reads the recipient's ENS payment preferences:
   - `text("com.khaalisplit.payment.flow")` → `"gateway"` (default)
   - `text("com.khaalisplit.payment.chain")` → e.g., `"8453"` (Base)
3. Contract calls `IGateway.depositFor(amount, destinationDomain, recipientBytes32)`
4. Gateway handles cross-chain routing — recipient gets USDC on Base near-instantly

### Opt-in CCTP Flow

Users who prefer the direct burn-and-mint model (e.g., for larger amounts where they want on-chain attestation guarantees) can set their payment flow to `"cctp"`:

1. Same settlement trigger
2. `_routeSettlement()` reads `"cctp"` from their ENS records
3. Contract calls `ITokenMessengerV2.depositForBurn(amount, destinationDomain, recipientBytes32, token)`
4. Circle's attestation service validates the burn, then mints on the destination chain (slower, but fully trustless)

### Same-Chain Fast Path

If the recipient's preferred chain matches the source chain, `_routeSettlement()` skips cross-chain routing entirely and transfers USDC directly. No bridge, no latency.

## Why This Is Interesting

- **Instant UX by default** — users don't need to understand bridging. They settle a debt, and the money appears on their preferred chain in seconds.
- **User-controlled routing** — payment preferences are ENS text records, so users can switch between Gateway and CCTP at any time by updating a single record. The settlement contract reads preferences at execution time.
- **Progressive trust model** — Gateway for speed (small casual settlements), CCTP for trustlessness (larger amounts where attestation matters). Users self-select.
- **Chain-agnostic settlements** — the sender doesn't need to know or care which chain the recipient prefers. They sign an EIP-3009 authorization on the source chain, and the contract handles everything.
- **Composable routing** — because preferences are in ENS, a future settlement contract could add new routing options (e.g., Across, Stargate) without changing the identity layer.

## Trade-offs

- Gateway requires trusting Circle's liquidity management and instant settlement guarantees
- Gateway may have lower transfer limits than raw CCTP for very large amounts
- If Gateway is down or unsupported on a chain pair, the settlement reverts rather than falling back to CCTP (could be improved with a fallback mechanism)
- Same-chain detection relies on ENS records being up-to-date — stale preferences could route to the wrong chain
