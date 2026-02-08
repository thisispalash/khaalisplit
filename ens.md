# khaaliSplit — ENS Prize Submission

> **Prize Track**: Most Creative Use of ENS for DeFi

## TL;DR

khaaliSplit uses ENS subnames as the **entire identity and payment preference layer** for a decentralized expense-splitting app. Every user gets `{username}.khaalisplit.eth`, and the subname's text records store reputation scores, preferred settlement chain, payment flow, and USDC token addresses. The settlement contract reads these records at execution time to route USDC cross-chain — ENS is not an afterthought, it's the routing table.

---

## How ENS Is Used

### 1. Subname Registration via NameWrapper

**Key file**: [`contracts/src/khaaliSplitSubnames.sol`](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSubnames.sol)

| Function | Line | Purpose |
|----------|------|---------|
| `register()` | [L116](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSubnames.sol#L116) | Mints `{label}.khaalisplit.eth` via `NameWrapper.setSubnodeRecord()` |
| `setText()` | [L167](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSubnames.sol#L167) | Writes text records (reputation, payment prefs, etc.) |
| `setAddr()` | [L180](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSubnames.sol#L180) | Sets the address record for the subname |
| `text()` | [L195](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSubnames.sol#L195) | Public view — anyone can read records |
| `addr()` | [L203](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSubnames.sol#L203) | Public view — resolves subname to address |
| `_isAuthorized()` | [L262](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSubnames.sol#L262) | Three-tier auth: backend, reputation contract, or subname owner |

The Subnames contract **is the resolver** — it's set as the resolver for all khaaliSplit subnames at registration time, meaning it directly serves `text()` and `addr()` queries.

### 2. Text Records as Payment Routing Table

The settlement contract reads ENS text records to decide how to route each payment:

| Text Record Key | Example Value | Read By |
|----------------|---------------|---------|
| `com.khaalisplit.subname` | `"alice"` | PWA client |
| `com.khaalisplit.reputation` | `"73"` | Any ENS client, settlement events |
| `com.khaalisplit.payment.flow` | `"gateway"` | Settlement contract (`_routeSettlement`) |
| `com.khaalisplit.payment.token` | `"0x833..."` | Settlement contract |
| `com.khaalisplit.payment.chain` | `"8453"` | Settlement contract |
| `com.khaalisplit.payment.cctp` | `"6"` | Settlement contract (CCTP domain) |

**Key file**: [`contracts/src/khaaliSplitSettlement.sol`](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSettlement.sol)

| Function | Line | Purpose |
|----------|------|---------|
| `_routeSettlement()` | [L397](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitSettlement.sol#L397) | Reads `payment.flow`, `payment.chain`, `payment.token` from ENS to decide Gateway vs CCTP vs same-chain |

### 3. Reputation Score Auto-Synced to ENS

The reputation contract writes scores directly to ENS text records after every settlement.

**Key file**: [`contracts/src/khaaliSplitReputation.sol`](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitReputation.sol)

| Function | Line | Purpose |
|----------|------|---------|
| `recordSettlement()` | [L135](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitReputation.sol#L135) | Updates score (+1 success, -5 failure) and auto-syncs to ENS |
| `_syncToENS()` | [L232](https://github.com/thisispalash/khaalisplit/blob/master/contracts/src/khaaliSplitReputation.sol#L232) | Calls `subnameRegistry.setText(node, "com.khaalisplit.reputation", score)` |

This means any ENS-aware app or wallet can read a user's khaaliSplit reputation score — it's not locked inside the app.

### 4. Portable Identity (It's Just a Token)

The subname `alice.khaalisplit.eth` is ultimately a token ID in ENS NameWrapper. This means:
- The identity is **portable** — readable by any ENS client, wallet, or dApp
- The reputation score, payment preferences, and address are all **publicly verifiable** on-chain
- The user's entire financial profile travels with their `.eth` name across the ecosystem
- If NameWrapper subname transfers are enabled, the identity could theoretically be transferred

### 5. Three-Tier Authorization Model

The `_isAuthorized` function implements a nuanced access control:
1. **Backend** → can set any record (registration, initial setup)
2. **Reputation contract** → can write reputation scores (automated after settlements)
3. **Subname owner** → can update their own payment preferences (self-sovereign)

This is a practical middle ground between full decentralization and usability — the user controls their preferences, the protocol controls reputation integrity.

---

## Architecture Diagrams

See [`docs/05-reputation-and-ens.md`](https://github.com/thisispalash/khaalisplit/blob/docs/docs/05-reputation-and-ens.md) for full mermaid diagrams of the ENS identity backbone, reputation mechanics, authorization model, and subname registration sequence.

---

## Why This Is Creative

1. **ENS as a DeFi routing layer** — text records aren't just metadata, they're the **live configuration** that determines how USDC gets routed cross-chain. Change your preferred chain in ENS, and your next settlement auto-routes there.
2. **Reputation as a public good** — the score lives in ENS, not a database. Other DeFi protocols could read `text("com.khaalisplit.reputation")` and factor it into lending decisions, trust scoring, or access control.
3. **Subnames as composable identity** — `alice.khaalisplit.eth` is both a human-readable name and a bundle of machine-readable payment instructions. It's an identity that protocols can program against.
4. **Not an afterthought** — ENS is load-bearing infrastructure in khaaliSplit. Remove it, and the settlement routing, reputation system, and identity layer all break. It's deeply integrated, not bolted on.
