# khaaliSplit — Arc Prize Submission

> **Prize Track**: Best Chain Abstracted USDC Apps Using Arc as Liquidity Hub

## TL;DR

khaaliSplit uses Arc (Circle Gateway) as its **default cross-chain settlement route**, enabling instant USDC delivery to recipients on any supported chain. The settlement contract reads each user's payment preferences from ENS text records and routes USDC through Gateway automatically — senders never need to think about which chain the recipient prefers.

---

## How Arc Is Used

### 1. Gateway as Default Settlement Route

Every settlement in khaaliSplit flows through `_routeSettlement()`, which reads the recipient's ENS text records to determine where and how to deliver USDC. **Gateway (`depositFor`) is the default flow**, chosen for its instant cross-chain delivery.

**Key file**: [`contracts/src/khaaliSplitSettlement.sol`](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSettlement.sol)

| Function | Line | Purpose |
|----------|------|---------|
| `_routeSettlement()` | [L397](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSettlement.sol#L397) | Reads ENS payment prefs, decides Gateway vs CCTP vs same-chain |
| `_settleViaGateway()` | [L420](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSettlement.sol#L420) | Calls `IGateway.depositFor()` to route USDC cross-chain |
| `settleWithAuthorization()` | [L188](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSettlement.sol#L188) | EIP-3009 entry point → triggers routing |
| `settleFromGateway()` | [L256](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSettlement.sol#L256) | Receives Gateway attestation mints → triggers routing |

### 2. Multi-Chain, Multi-Recipient Settlement

khaaliSplit is a group expense-splitting app. A single expense can involve multiple participants on different chains. Each recipient's preferred chain and payment flow is stored as ENS text records:

- `text("com.khaalisplit.payment.flow")` → `"gateway"` (default) or `"cctp"`
- `text("com.khaalisplit.payment.chain")` → target chain ID (e.g., `"8453"` for Base)
- `text("com.khaalisplit.payment.token")` → USDC address on target chain

This means a single group settlement can route USDC to Alice on Base, Bob on Arbitrum, and Carol on Ethereum — all in one flow, all via Gateway.

### 3. CCTP as Opt-in Alternative

Users who prefer trustless burn-and-mint can set their flow to `"cctp"`. The contract calls `ITokenMessengerV2.depositForBurn()` instead.

| Function | Line | Purpose |
|----------|------|---------|
| `_settleViaCCTP()` | [L436](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSettlement.sol#L436) | Burns USDC via TokenMessengerV2 for cross-chain mint |

### 4. Gateway Mint as Settlement Entry Point

khaaliSplit also accepts **incoming Gateway mints** as a settlement trigger. When USDC arrives via Gateway attestation, `settleFromGateway()` processes it and routes to the next recipient if needed — enabling **chained cross-chain settlements**.

---

## Architecture Diagram

See [`docs/02-settlement-flows.md`](https://github.com/thisispalash/khaalisplit/blob/docs/docs/02-settlement-flows.md) for full mermaid diagrams of all settlement flows, and [`docs/04-deployment-and-cross-chain.md`](https://github.com/thisispalash/khaalisplit/blob/docs/docs/04-deployment-and-cross-chain.md) for cross-chain topology.

---

## Why This Matters

1. **Chain abstraction for real users** — recipients set their preferred chain once in ENS, and every future settlement auto-routes there. No manual bridging.
2. **Gateway for instant UX** — small casual splits settle in seconds, not minutes. This is critical for a consumer app.
3. **USDC-native throughout** — all settlements are denominated in USDC. No wrapped tokens, no DEX swaps, no slippage.
4. **Non-custodial** — the settlement contract never holds user funds beyond the routing transaction. USDC flows from sender → contract → Gateway/CCTP → recipient in a single transaction.
