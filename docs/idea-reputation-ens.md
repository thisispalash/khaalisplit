# Idea: Reputation System & ENS Subnames as Portable Identity

## The Problem

On-chain identity is fragmented. A wallet address tells you nothing about a user's reliability, payment preferences, or social context. And centralized reputation (like Uber ratings) is locked inside one platform — you can't take your score with you.

## The Insight

ENS subnames (`alice.khaalisplit.eth`) are **NFTs under the hood** — they're token IDs in the NameWrapper contract. This means a user's entire identity (reputation score, payment chain preference, payment flow, token address, CCTP domain) is stored as **ENS text records on a token they effectively own**.

Since ENS is a public, permissionless protocol, this identity is readable by any dApp, wallet, or contract — not just khaaliSplit.

## How It Works

### Subname as Identity

- `register("alice", userAddr)` mints `alice.khaalisplit.eth` via NameWrapper
- The Subnames contract is set as the resolver, so it controls all record reads/writes
- Default records set at registration:
  - `text("com.khaalisplit.subname")` → `"alice"`
  - `text("com.khaalisplit.reputation")` → `"50"` (default score)
  - `addr(node)` → user's wallet address

### Reputation Scoring

- Range: **0–100**, default **50**
- Every successful settlement: **+1** (capped at 100)
- Every failed settlement: **-5** (floored at 0)
- The asymmetry is intentional — it's easy to build reputation, hard to recover from bad behavior
- After every score update, `khaaliSplitReputation` calls `subnameRegistry.setText()` to sync the score to ENS automatically

### Payment Preferences as Text Records

The settlement contract reads these ENS records to determine how to route funds:
- `text("com.khaalisplit.payment.flow")` → `"gateway"` or `"cctp"`
- `text("com.khaalisplit.payment.token")` → USDC contract address on preferred chain
- `text("com.khaalisplit.payment.chain")` → target chain ID (e.g., `"8453"` for Base)
- `text("com.khaalisplit.payment.cctp")` → CCTP domain ID for cross-chain burns

### Three-Tier Authorization

Records can be written by:
1. **Backend** — registers subnames, sets initial records
2. **Reputation contract** — writes reputation score after settlements
3. **Subname owner** — updates their own payment preferences

## Why This Is Interesting

- **Portable reputation** — the score lives in ENS, not in a khaaliSplit database. Any dApp can read `text("com.khaalisplit.reputation")` for a given `.eth` name and factor it into their own trust model.
- **Portable payment preferences** — a future app could read a user's preferred chain and token from their ENS records and route payments accordingly, without any khaaliSplit involvement.
- **It's technically a token** — the subname is a NameWrapper token ID. The parent (`khaalisplit.eth`) controls issuance, but the subname owner controls their records. Arguably, the identity could be transferred or composed with other NFT-based identity systems.
- **Self-sovereign with guardrails** — users control their own records, but the reputation contract has write access specifically for score syncing, and the backend handles registration. It's a pragmatic middle ground between full decentralization and usability.
- **ENS-native composability** — wallets like Rainbow, apps like ENS.app, and protocols like Farcaster already resolve ENS records. khaaliSplit users get discoverability for free.

## Trade-offs

- Tied to ENS on Ethereum mainnet — subname registration and record updates require L1 transactions (or NameWrapper on L2 if migrated in the future)
- The reputation score is simplistic (+1/-5) — doesn't account for settlement size, frequency, or context
- If `khaalisplit.eth` is compromised at the parent level, all subnames are at risk
- Users must trust the backend for initial registration and the reputation contract for score integrity
