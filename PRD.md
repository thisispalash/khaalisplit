# PRD: khaaliSplit

**Author:** @thisispalash (using Claude)
**Date:** February 5, 2026
**Status:** Draft
**Last Updated:** February 5, 2026

---

## Overview

khaaliSplit is a mobile-first progressive web app for splitting expenses and settling
balances in USDC cross-chain. It uses ENS subnames for portable identity, ECDH for
end-to-end encrypted friend connections, and Farcaster integration for social graph.
Users sign up with a password (auto-generated username), link their existing blockchain
addresses, and settle debts across any chain via Circle's Arc and CCTP.

**Target:** ETHGlobal HackMoney 2026 (Jan 30 - Feb 11, 2026)
**Prize Categories:** Arc (Chain-Abstracted USDC Apps, Global Payouts) + ENS (Integrate
ENS, Most Creative Use of ENS for DeFi)

---

## Problem Statement

**Problem:** Crypto-native users need a way to split expenses and settle in crypto without
relying on fiat rails or traditional payment apps.

**Who:**
- Conference attendees (ETHDenver, Devcon) who meet strangers and share expenses
- Crypto-native friend groups who want peer-to-peer expense splitting with crypto settlement
- Anyone who prefers settling in USDC without bank accounts or Venmo/Splitwise

**Evidence:**
- Users on different chains with different addresses - manual coordination is painful
- No reputation/trust signal for strangers met at conferences
- No standardized way to publish payment preferences
- Current blockchain solutions expose all financial history when you send someone crypto
- Existing expense-splitting apps (Splitwise) don't support crypto settlement
- Growing demand for crypto-native alternatives to traditional fintech

---

## Goals & Success Metrics

**Goals:**
1. Enable crypto-native expense splitting with cross-chain USDC settlement
2. Provide portable identity via ENS subnames with discoverable payment preferences
3. Protect expense privacy through end-to-end encryption
4. Build reputation system for trust between strangers
5. Win Arc and/or ENS hackathon prizes

**Success Metrics:**

| Metric | Target | Measurement |
|--------|--------|-------------|
| Functional MVP | Complete | All P0 features working |
| ENS integration | Custom code | Resolver, text records, subnames |
| Arc integration | Chain abstraction | Multi-chain USDC settlement |
| Demo | 3-minute video | End-to-end user journey |

---

## User Stories

### Authentication

- **STORY-1:** Sign up with password, receive auto-generated username
- **STORY-2:** Auto-generated username becomes ENS subname (immutable)
- **STORY-3:** Add blockchain address via signature verification during onboarding
- **STORY-4:** Link Farcaster account and import social graph

### Profile Management

- **STORY-5:** Set display name (editable) and avatar
- **STORY-6:** Payment preferences (chain, address, token) stored in ENS text record
- **STORY-7:** View reputation score and history

### Friends

- **STORY-8:** Add friend by searching their subname
- **STORY-9:** ECDH key exchange on-chain when adding friend (encrypted channel)
- **STORY-10:** View friend's payment preferences from ENS
- **STORY-11:** Import Farcaster mutual follows as potential friends

### Groups

- **STORY-12:** Create group with name
- **STORY-13:** Add friends to group (requires their acceptance)
- **STORY-14:** Groups exist on-chain (for future ZK membership proofs)
- **STORY-15:** View net balances within group

### Expenses

- **STORY-16:** Add expense with description, amount (USD), and split
- **STORY-17:** Expenses encrypted with group shared key, stored on-chain
- **STORY-18:** Categorize expenses (food, transport, accommodation, other)
- **STORY-19:** Create expenses offline (queued, synced when online)

### Settlement

- **STORY-20:** View simplified net debts (minimum transactions to settle)
- **STORY-21:** Send funds to app contract on user's chain (no chain switching)
- **STORY-22:** App contract bridges via CCTP to recipient's chain/address
- **STORY-23:** Gasless meta-transactions (relayer pays gas, deducted from amount)

### Reputation

- **STORY-24:** Reputation score stored in ENS text records (portable)
- **STORY-25:** Score updated based on settlement behavior
- **STORY-26:** View others' reputation before adding as friend

### Activity

- **STORY-27:** Chronological activity feed (offline queued actions greyed out)

### Farcaster Integration

- **STORY-28:** Farcaster Frame to add expense directly from cast
- **STORY-29:** Farcaster Frame to view balances
- **STORY-30:** Frame for settlement initiation (Transaction Frame)

---

## Scope

### In Scope (Priority 0 - Must Have)

- Password-based authentication (auto-generated username)
- ENS offchain subnames via CCIP-Read
- Add/link blockchain address(es) to account
- Profile with payment preferences (JSON in ENS text record)
- Add friend by subname
- ECDH key exchange on-chain for friend pairing
- Create group (on-chain)
- Add expense (encrypted on-chain or Arweave)
- Net balance calculation
- Settlement via app contract (handles bridging)
- Activity feed
- Gasless meta-transactions (relayer)

### In Scope (Priority 1 - Should Have)

- Farcaster account linking and social graph import
- Farcaster Frames (add expense, view balances, settle)
- Reputation score in ENS
- IPFS contenthash for frontend
- Expense categorization
- Offline queue for actions

### In Scope (Priority 2 - Nice to Have)

- Signal-style ratcheting for forward secrecy
- QR codes for settlement
- Split by exact amounts or percentages

### Out of Scope (for hackathon)

- Smart contract wallets (ERC-4337)
- Fiat on/off ramp
- Multi-token support beyond USDC/EURC
- Full ZK group membership (Semaphore) - noted for future
- Arc mainnet (testnet only)
- Native mobile app
- Dispute resolution
- Vouch/slash mechanisms

### Future Ideas (Post-Hackathon)

- **Vouching mechanism:** if A vouches for B and B doesn't pay, A's collateral covers it
- **Anti-vouch:** Alice vouches that Bob is untrusted; as Bob's reputation drops, Alice
  gets reward
- **Full decentralization:** client-side only with Arweave/on-chain storage
- **ZK group membership:** shielded payments via Semaphore
- **Privacy-preserving settlement:** ZK-based private pools for shielded payments
  - Shield USDC into private pool
  - Generate ZK proof for spending (without revealing source)
  - Unshield to recipient from unlinkable address
  - Batch payments: settle with multiple recipients privately in one tx
- **Signal-style double ratchet** for forward secrecy in friend encryption

---

## Requirements

### REQ-1: Authentication

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-1-1 | Sign up with password only (auto-generated username becomes subname) | Must have |
| REQ-1-2 | Auto-generate unique subname on signup (stored in Django, served via ENS) | Must have |
| REQ-1-3 | JWT session tokens for API authentication | Must have |
| REQ-1-4 | Add blockchain address (requires signature of challenge message) | Must have |
| REQ-1-5 | Verify signature server-side using `eth_account.Account.recover_message()` | Must have |
| REQ-1-6 | Support multiple addresses per user | Must have |
| REQ-1-7 | Link Farcaster account via Neynar SIWN (Sign In With Neynar) | Should have |

**Onboarding Flow:**
1. Welcome screen displays auto-generated username (e.g., "happy-panda-42")
2. User enters password (username cannot be changed)
3. User sets display name (editable)
4. User sets profile/avatar
5. User selects preferred chain (dropdown)
6. User enters their address on that chain
7. User selects preferred token (USDC or EURC radio button)
8. User signs message to verify address ownership
9. Backend:
   - Creates user with subname (username = subname)
   - Recovers public key from signature (ecrecover)
   - Registers public key on FriendRegistry contract
   - Creates subname on Sepolia via CCIP-Read gateway
   - Transfers subname NFT to user's address

### REQ-2: ENS Subname Registration

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-2-1 | Use offchain subnames via CCIP-Read (EIP-3668) | Must have |
| REQ-2-2 | Django gateway responds to CCIP-Read callbacks | Must have |
| REQ-2-3 | Subnames resolve to user's primary linked address | Must have |
| REQ-2-4 | Support text record resolution | Must have |
| REQ-2-5 | Unique, auto-generated labels (adjective-noun or similar) | Must have |
| REQ-2-6 | Deploy OffchainResolver on Sepolia | Must have |

### REQ-3: Profile & Payment Preferences

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-3-1 | Set display name | Must have |
| REQ-3-2 | Set avatar (URL or IPFS) | Should have |
| REQ-3-3 | Set payment preferences as single JSON text record: `com.khaalisplit.pref` | Must have |
| REQ-3-4 | Support USDC and EURC tokens (both available on Arc) | Must have |
| REQ-3-5 | Use standard ENS keys: `display`, `avatar` | Must have |

**Payment Preferences JSON Schema:**
```json
{
  "vm": "evm",
  "chainId": 42161,
  "address": "0xabc...",
  "token": "usdc",
  "token_addr": "0xabc..."
}
```
- `vm`: "evm" (future-proofed for SVM, etc.)
- `chainId`: numeric chain ID
- `token`: human readable name for the token
- `token_addr`: "usdc" or "eurc" contract address on the preferred chain

### REQ-4: Friends (with ECDH)

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-4-1 | Search by subname | Must have |
| REQ-4-2 | Resolve and display profile (including reputation) | Must have |
| REQ-4-3 | Initiate friend request (ECDH key exchange on-chain) | Must have |
| REQ-4-4 | Bidirectional friendship established once both keys exchanged | Must have |
| REQ-4-5 | Import Farcaster mutual follows as suggested friends (via Neynar API) | Should have |

**ECDH Friend Pairing Flow (using wallet public keys):**
1. During onboarding, user signs message to link address
2. Backend recovers user's public key from signature (ecrecover)
3. Backend registers public key on FriendRegistry contract
4. When Alice wants to add Bob:
   - Alice queries Bob's public key from FriendRegistry
   - Alice computes: `sharedSecret = ECDH(Alice's wallet privKey, Bob's pubKey)`
   - Alice encrypts friend request data with shared secret
   - Alice submits encrypted request on-chain
5. Bob accepts:
   - Bob queries Alice's public key from FriendRegistry
   - Bob computes: `sharedSecret = ECDH(Bob's wallet privKey, Alice's pubKey)`
   - Bob decrypts request, verifies, and submits acceptance on-chain
6. No client-side key generation needed - uses existing wallet keys
7. Shared secret never transmitted, only computed client-side

### REQ-5: Groups (On-Chain)

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-5-1 | Create group via GroupRegistry smart contract | Must have |
| REQ-5-2 | Group stores: creator, name hash, member list | Must have |
| REQ-5-3 | Add friend to group (requires their on-chain acceptance) | Must have |
| REQ-5-4 | Derive group shared key from member ECDH keys | Must have |
| REQ-5-5 | Display expenses, balances, status | Must have |

### REQ-6: Expenses (Encrypted On-Chain)

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-6-1 | Add expense with description, amount (USD), payer, participants | Must have |
| REQ-6-2 | Expense data encrypted with group shared key (AES-256-GCM) | Must have |
| REQ-6-3 | Encrypted blob stored on-chain (or Arweave for cheaper storage) | Must have |
| REQ-6-4 | ExpenseRegistry contract emits event with encrypted data hash | Must have |
| REQ-6-5 | Default equal split | Must have |
| REQ-6-6 | Optional split by amounts/percentages | Nice to have |
| REQ-6-7 | Optional categorization (food, transport, accommodation, other) | Should have |
| REQ-6-8 | Recalculate balances on add (done client-side after decryption) | Must have |

### REQ-7: Settlement (App Contract)

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-7-1 | Show simplified net debts (debt simplification algorithm) | Must have |
| REQ-7-2 | Resolve creditor's payment preferences from ENS | Must have |
| REQ-7-3 | User sends USDC to SettlementContract on their chain | Must have |
| REQ-7-4 | Contract emits event with: amount, recipient, chain ID, note | Must have |
| REQ-7-5 | Backend relayer (or Circle Programmable Wallets) executes CCTP bridge | Must have |
| REQ-7-6 | USDC arrives at recipient's address on their chain | Must have |
| REQ-7-7 | Gasless meta-transaction: user signs EIP-712 message, relayer submits tx | Must have |
| REQ-7-8 | Update reputation on confirmation | Should have |

### REQ-8: Activity Feed

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-8-1 | Show all activity (expenses, settlements, requests, invites) | Must have |
| REQ-8-2 | Timestamp, actor, action, details | Must have |
| REQ-8-3 | Offline queued actions shown greyed out | Should have |
| REQ-8-4 | Pagination | Should have |

### REQ-9: Reputation

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-9-1 | Calculate score from settlement behavior | Should have |
| REQ-9-2 | Store as JSON in ENS text record: `com.khaalisplit.reputation` | Should have |
| REQ-9-3 | Display on profiles with tier badge | Should have |
| REQ-9-4 | Burn mechanism for low reputation or account deletion | Should have |

**Reputation JSON Schema:**
```json
{
  "score": 85,
  "settled": 12,
  "disputes": 1
}
```

**Score Calculation:**
```
reputation = base + bonus - delinquency - disputes

Where:
  base = 50 (everyone starts neutral)
  bonus = min(settlements_confirmed * 5, 40)
  delinquency = overdue_settlements * 10
  disputes = disputes_lost * 15

Score clamped to [0, 100]
```

**Score Tiers:**

| Range | Tier |
|-------|------|
| 80-100 | Trusted |
| 60-79 | Good |
| 40-59 | Neutral |
| 20-39 | Caution |
| 0-19 | Untrusted |

**Burn Mechanism:**
- Triggered when reputation drops below 10 OR user voluntarily deletes account
- Subname transferred to zero address OR back to parent owner (allows reuse)
- Address flagged in BurntAddress table (cannot link to new account)

### REQ-10: Farcaster Frames

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-10-1 | Frame to add expense: shows input field, group selector, amount | Should have |
| REQ-10-2 | Frame to view balances: read-only display of current debts/credits | Should have |
| REQ-10-3 | Frame to initiate settlement: Transaction Frame for USDC | Should have |
| REQ-10-4 | Use `framelib` (Python) or `frog` (TypeScript) for frame server | Should have |
| REQ-10-5 | Validate frame actions via Neynar Hub | Should have |

---

## Non-Functional Requirements

### Performance

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1 | Page load time | < 2 seconds on 4G |
| NFR-2 | ENS resolution latency | < 3 seconds |

### Security

| ID | Requirement |
|----|-------------|
| NFR-3 | Address linking requires signature verification |
| NFR-4 | No private keys stored on server |
| NFR-5 | HTTPS required (PWA requirement) |
| NFR-6 | ECDH shared secrets derived client-side, never transmitted |

### Privacy

| ID | Requirement |
|----|-------------|
| NFR-7 | Expenses encrypted with group shared key (only group members can decrypt) |
| NFR-8 | Groups exist on-chain for future ZK membership proofs |
| NFR-9 | Settlement amounts visible on-chain (unavoidable for USDC transfers) |

### Mobile

| ID | Requirement |
|----|-------------|
| NFR-10 | Mobile-first responsive design (375px+) |
| NFR-11 | PWA installable (manifest, service worker) |
| NFR-12 | Offline queue: actions stored locally, synced when online, shown greyed in activity |

---

## System Architecture

### High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          CLIENT (Mobile PWA)                         │
│  ┌────────────────────────┬────────────────────────────────────────┐ │
│  │ Django Templates + HTMX│ Web3Modal + ethers.js                  │ │
│  │ + Tailwind CSS         │ - Connect wallet (for address linking) │ │
│  │ (HATEOAS principles)   │ - Sign messages (for auth + pubKey)    │ │
│  │                        │ - Send tx (to settlement contract)     │ │
│  │                        │ - ECDH shared secret derivation        │ │
│  └────────────────────────┴────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Local Storage / IndexedDB                                       │ │
│  │ - Offline action queue                                          │ │
│  │ - Cached group shared keys (derived from ECDH)                  │ │
│  │ - Decrypted expense cache                                       │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
                    │ HTTPS/HTMX              │ JSON-RPC
                    ▼                         ▼
┌────────────────────────────┐    ┌─────────────────────────────────────┐
│      DJANGO BACKEND        │    │           BLOCKCHAINS               │
│  ┌──────────────────────┐  │    │  ┌───────────────────────────────┐  │
│  │ Auth (password)      │  │    │  │ Ethereum Sepolia              │  │
│  │ Users, Sessions      │  │    │  │ - OffchainResolver.sol        │  │
│  │ Address links        │  │    │  │ - FriendRegistry.sol (ECDH)   │  │
│  │ Farcaster links      │  │    │  │ - GroupRegistry.sol           │  │
│  └──────────────────────┘  │    │  │ - ExpenseRegistry.sol         │  │
│  ┌──────────────────────┐  │    │  │ - SettlementContract.sol      │  │
│  │ CCIP-Read Gateway    │  │    │  └───────────────────────────────┘  │
│  │ (ENS offchain)       │  │    │  ┌───────────────────────────────┐  │
│  └──────────────────────┘  │    │  │ Arc Testnet (5042002)         │  │
│  ┌──────────────────────┐  │    │  │ - SettlementContract.sol      │  │
│  │ Frame Server         │  │    │  │ - USDC native gas             │  │
│  │ (Farcaster Frames)   │  │    │  └───────────────────────────────┘  │
│  └──────────────────────┘  │    │  ┌───────────────────────────────┐  │
│  ┌──────────────────────┐  │    │  │ Other Chains (Arbitrum, Base) │  │
│  │ Settlement Relayer   │  │    │  │ - SettlementContract.sol      │  │
│  │ (gasless meta-tx,    │  │    │  └───────────────────────────────┘  │
│  │  CCTP bridging)      │  │    └─────────────────────────────────────┘
│  └──────────────────────┘  │
│  ┌──────────────────────┐  │    ┌─────────────────────────────────────┐
│  │ PostgreSQL           │  │    │ Envio HyperIndex                    │
│  └──────────────────────┘  │    │ - Index contract events             │
│  ┌──────────────────────┐  │    │ - Query settlements, expenses       │
│  │ Neynar API           │◄─┼────│ - Verify on-chain confirmations     │
│  │ (Farcaster)          │  │    └─────────────────────────────────────┘
│  └──────────────────────┘  │
└────────────────────────────┘
          │ Docker Compose
          ▼
┌────────────────────────────┐
│       PRIVATE VPS          │
│  - Django + Gunicorn       │
│  - Nginx                   │
│  - PostgreSQL              │
│  - Let's Encrypt SSL       │
└────────────────────────────┘
```

### Data Location Matrix

| Data | Location | Rationale |
|------|----------|-----------|
| User account (subname, password hash) | PostgreSQL | Traditional auth |
| Linked addresses | PostgreSQL | Fast lookup |
| Subname mapping | PostgreSQL + ENS (CCIP-Read) | DB is source, ENS for portability |
| Payment preferences | PostgreSQL + ENS text record | Discoverable via ENS resolution |
| Reputation | PostgreSQL + ENS text record | Portable trust signal |
| ECDH public keys | On-chain (FriendRegistry) | Needed for key exchange |
| Friend relationships | On-chain (FriendRegistry) | ECDH keys establish friendship |
| Groups | On-chain (GroupRegistry) | For future ZK membership |
| Expense details (encrypted) | On-chain or Arweave | Censorship resistant, privacy preserved |
| Settlement transactions | On-chain (user's wallet → contract) | USDC transfers |

### Future Decentralization Path

1. **Frontend:** Deploy to IPFS/Arweave, set ENS contenthash
2. **User accounts:** Replace password with DID or social recovery
3. **All data:** Move to on-chain or Arweave
4. **Compute:** Client-side only (no Django backend needed)
5. **Relayer:** Decentralized relayer network or Circle's programmable wallets

---

## ENS Integration Design

### Use 1: Identity via Offchain Subnames

Every user gets `{username}.khaalisplit.eth` on signup (auto-generated, immutable).

**Implementation:**
1. Deploy `OffchainResolver.sol` on Sepolia
2. Gateway URL: `https://api.khaalisplit.xyz/ens-gateway/{sender}/{data}`
3. Django gateway decodes calldata, looks up user in DB, returns signed response
4. Client verifies signature against trusted signer in resolver

**ENS Code Required:**
- Deploy `OffchainResolver.sol` (Solidity contract inheriting from ENS interfaces)
- Implement CCIP-Read gateway (Django view implementing EIP-3668)
- Call `setResolver` on ENS registry for `khaalisplit.eth`
- Encode/decode calldata per EIP-3668 spec

### Use 2: Payment Preferences via Text Record

Single JSON text record: `com.khaalisplit.pref`

```json
{
  "vm": "evm",
  "chainId": 42161,
  "address": "0xabc...",
  "token": "usdc",
  "token_addr": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
}
```

- `vm`: "evm" (future-proofed for SVM, Fuel, etc.)
- `chainId`: numeric chain ID
- `token`: human-readable token name ("usdc" or "eurc")
- `token_addr`: token contract address on the preferred chain

Standard ENS keys: `display`, `avatar` (follow ENS defaults per ENSIP-5)

### Use 3: Reputation via Text Record

JSON text record: `com.khaalisplit.reputation`

```json
{
  "score": 85,
  "settled": 12,
  "disputes": 1
}
```

Separate numeric text record for quick access: `com.khaalisplit.score` → `"85"`

### Use 4: Content Hash (Decentralized Frontend)

Set `contenthash` on `khaalisplit.eth` to IPFS CID of static frontend build.

---

## Arc / CCTP Integration Design

### Arc Testnet Configuration

| Parameter | Value |
|-----------|-------|
| Chain ID | 5042002 |
| RPC URL | https://rpc.testnet.arc.network |
| Block Explorer | https://testnet.arcscan.app |
| USDC | Native (0x3600...0000) |
| EURC | Available |
| Gas | USDC (no ETH needed) |
| Finality | Sub-second |
| Faucet | https://faucet.circle.com |

### Settlement Flow (App Contract)

```
1. User A taps "Settle Up"
2. App calculates net debt: A owes B $25 USDC
3. App resolves B's payment prefs from ENS (chain ID, address)
4. User A's chain: Base (chain ID 8453)
5. B's preferred chain: Arbitrum (chain ID 42161)

FLOW:
  a. A signs EIP-712 meta-transaction: "settle $25 to B on Arbitrum"
  b. Relayer submits tx to SettlementContract on Base
  c. Contract takes $25 USDC + gas fee from A (via permit)
  d. Relayer triggers CCTP: burn $25 USDC on Base
  e. CCTP mints $25 USDC on Arbitrum (~20 seconds)
  f. Relayer sends to B's address on Arbitrum
  g. Settlement confirmed, reputation updated
```

### BridgeKit Integration (Frontend JS)

```javascript
import { createBridgeKit } from '@circle/bridgekit';

const kit = createBridgeKit({
  // Configuration
});

const result = await kit.bridge({
  from: { adapter: viemAdapter, chain: "base" },
  to: { adapter: viemAdapter, chain: "arbitrum" },
  amount: "25000000", // 25 USDC (6 decimals)
});
```

### Prize Alignment

- **Chain-Abstracted USDC Apps ($5K):** Users on any chain; cross-chain via CCTP
- **Global Payouts & Treasury Systems ($2.5K):** Multi-recipient, multi-chain group settlement

---

## ECDH and Encryption Design

### Friend Pairing (Using Wallet Public Keys)

Public keys are registered during onboarding when user signs a message to link their
address. The backend recovers the public key via ecrecover and registers it on-chain.

```
1. During onboarding, Alice signs message to link her address
2. Backend recovers Alice's public key from signature (ecrecover)
3. Backend calls FriendRegistry.registerPubKey(alice, alicePubKey)
4. (Same happens for Bob during his onboarding)

When Alice wants to add Bob:
5. Alice queries Bob's public key from FriendRegistry
6. Alice computes: sharedSecret = ECDH(Alice's wallet privKey, Bob's pubKey)
7. Alice encrypts friend request data with shared secret
8. Alice calls FriendRegistry.requestFriend(bob)
9. Bob sees request, queries Alice's public key
10. Bob computes: sharedSecret = ECDH(Bob's wallet privKey, Alice's pubKey)
11. Bob decrypts request, verifies, calls FriendRegistry.acceptFriend(alice)
12. Contract marks Alice <-> Bob as friends
13. Shared secret never transmitted, only computed locally
```

### Group Shared Key

For group with N members:
- **MVP (hackathon):** Creator generates group symmetric key, encrypts with each
  member's pairwise shared key, stores on-chain
- **Future:** N-party ECDH, threshold cryptography, or MPC

### Expense Encryption

```
1. User adds expense to group
2. Client encrypts expense JSON with group shared key (AES-256-GCM)
3. Client stores encrypted blob on-chain (ExpenseRegistry) or Arweave
4. Other group members fetch encrypted blob via Envio index
5. Client decrypts with cached group shared key
6. Balance calculations done client-side
```

---

## Smart Contracts

| Contract | Chain | Purpose |
|----------|-------|---------|
| OffchainResolver.sol | Ethereum Sepolia | CCIP-Read resolver for khaalisplit.eth subnames |
| FriendRegistry.sol | Ethereum Sepolia | Store ECDH public keys, friend pairs |
| GroupRegistry.sol | Ethereum Sepolia | Store groups, member lists, encrypted group keys |
| ExpenseRegistry.sol | Ethereum Sepolia | Store encrypted expense hashes |
| SettlementContract.sol | All chains | Receive USDC, emit settlement events for relayer |

### FriendRegistry.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FriendRegistry {
    // User's wallet public key (registered during onboarding)
    mapping(address => bytes) public walletPubKey;

    // Friend relationships
    mapping(address => mapping(address => bool)) public isFriend;
    mapping(address => mapping(address => bool)) public pendingRequest;
    mapping(address => address[]) private friendsList;

    event PubKeyRegistered(address indexed user, bytes pubKey);
    event FriendRequested(address indexed from, address indexed to);
    event FriendAccepted(address indexed from, address indexed to);

    // Called by backend after recovering pubKey from signature
    function registerPubKey(address user, bytes calldata pubKey) external;

    // Alice requests Bob as friend (Bob's pubKey already on-chain)
    function requestFriend(address friend) external;

    // Bob accepts Alice's request
    function acceptFriend(address requester) external;

    function getPubKey(address user) external view returns (bytes memory);
    function getFriends(address user) external view returns (address[] memory);
}
```

### GroupRegistry.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract GroupRegistry {
    struct Group {
        bytes32 nameHash;
        address creator;
        address[] members;
        mapping(address => bytes) encryptedGroupKey; // per-member encrypted key
    }

    mapping(uint256 => Group) public groups;
    uint256 public groupCount;

    event GroupCreated(uint256 indexed groupId, address indexed creator, bytes32 nameHash);
    event MemberInvited(uint256 indexed groupId, address indexed member);
    event MemberAccepted(uint256 indexed groupId, address indexed member);

    function createGroup(bytes32 nameHash, bytes calldata encryptedKey) external returns (uint256);
    function inviteMember(uint256 groupId, address member, bytes calldata encryptedKey) external;
    function acceptGroupInvite(uint256 groupId) external;
}
```

### SettlementContract.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract SettlementContract {
    IERC20 public immutable usdc;

    event SettlementInitiated(
        address indexed sender,
        address indexed recipient,
        uint256 destChainId,
        uint256 amount,
        bytes note
    );

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    function settle(
        address recipient,
        uint256 destChainId,
        uint256 amount,
        bytes calldata note
    ) external {
        usdc.transferFrom(msg.sender, address(this), amount);
        emit SettlementInitiated(msg.sender, recipient, destChainId, amount, note);
    }

    // Gasless meta-tx with EIP-2612 permit
    function settleWithPermit(
        address sender,
        address recipient,
        uint256 destChainId,
        uint256 amount,
        bytes calldata note,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external {
        IERC20Permit(address(usdc)).permit(sender, address(this), amount, deadline, v, r, s);
        usdc.transferFrom(sender, address(this), amount);
        emit SettlementInitiated(sender, recipient, destChainId, amount, note);
    }
}
```

---

## Technical Stack

### Backend
- **Django 5.x:** Web framework, ORM, admin, session management
- **PostgreSQL:** Primary database
- **Gunicorn:** WSGI production server
- **Nginx:** Reverse proxy, SSL termination

### Frontend
- **Django Templates + HTMX:** Server-rendered, HATEOAS principles
- **Tailwind CSS:** Utility-first styling
- **Alpine.js:** Minimal JS for UI interactions (optional)

### Wallet Integration
- **Web3Modal:** Framework-agnostic wallet connection, WalletConnect deep links
- **ethers.js:** Sign messages, send transactions, ECDH key generation

### ENS
- **web3.py:** Server-side ENS resolution and contract interaction
- **CCIP-Read gateway:** Django view implementing EIP-3668

### Blockchain Indexing
- **Envio HyperIndex:** Query contract events, settlement verification

### Farcaster
- **Neynar API:** SIWN, social graph queries, frame validation
- **framelib (Python):** Farcaster frame server

### Deployment
- **Docker + Docker Compose:** Container orchestration
- **Private VPS:** Single server deployment
- **Let's Encrypt:** SSL certificates via Certbot

### Key Packages

| Package | Purpose |
|---------|---------|
| django | Web framework |
| django-htmx | HTMX middleware and helpers |
| django-tailwind | Tailwind CSS integration |
| psycopg2-binary | PostgreSQL adapter |
| web3 | Ethereum interaction (web3.py) |
| eth-account | Signature verification, ECDH |
| gunicorn | Production WSGI server |
| whitenoise | Static file serving (Django middleware for production) |
| django-pwa | PWA manifest and service worker |
| pyjwt | JWT session tokens |
| python-dotenv | Environment variable management |
| framelib | Farcaster frames (Python) |
| requests | Neynar API calls |

---

## Database Schema

```python
# Django Models

class User(AbstractBaseUser):
    # subname is the username (auto-generated, immutable, becomes ENS subname)
    subname = models.CharField(max_length=100, unique=True)
    display_name = models.CharField(max_length=100, blank=True)
    avatar_url = models.URLField(blank=True, null=True)
    reputation_score = models.IntegerField(default=50)
    farcaster_fid = models.IntegerField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = 'subname'

class LinkedAddress(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='addresses')
    address = models.CharField(max_length=42)  # Ethereum address
    is_primary = models.BooleanField(default=False)
    chain_id = models.IntegerField(default=1)  # preferred chain
    token = models.CharField(max_length=10, default='usdc')
    token_addr = models.CharField(max_length=42)  # token contract address on chain
    pub_key = models.CharField(max_length=130, blank=True)  # recovered from signature
    verified_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ['user', 'address']

class BurntAddress(models.Model):
    address = models.CharField(max_length=42, unique=True)
    original_subname = models.CharField(max_length=100)
    burnt_at = models.DateTimeField(auto_now_add=True)

class Activity(models.Model):
    class ActivityType(models.TextChoices):
        EXPENSE_ADDED = 'expense_added'
        SETTLEMENT_INITIATED = 'settlement_initiated'
        SETTLEMENT_CONFIRMED = 'settlement_confirmed'
        FRIEND_REQUEST = 'friend_request'
        FRIEND_ACCEPTED = 'friend_accepted'
        GROUP_INVITE = 'group_invite'
        GROUP_JOINED = 'group_joined'

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='activities')
    activity_type = models.CharField(max_length=50, choices=ActivityType.choices)
    related_type = models.CharField(max_length=50)
    related_id = models.IntegerField()
    message = models.TextField()
    is_synced = models.BooleanField(default=True)  # false if offline queued
    created_at = models.DateTimeField(auto_now_add=True)

# Cached on-chain data (source of truth is blockchain via Envio)

class CachedFriend(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='cached_friends')
    friend_address = models.CharField(max_length=42)
    ecdh_pub_key = models.CharField(max_length=66)
    indexed_at = models.DateTimeField(auto_now=True)

class CachedGroup(models.Model):
    group_id = models.IntegerField(unique=True)  # on-chain ID
    name_hash = models.CharField(max_length=66)
    creator = models.ForeignKey(User, on_delete=models.CASCADE)
    indexed_at = models.DateTimeField(auto_now=True)

class CachedGroupMember(models.Model):
    group = models.ForeignKey(CachedGroup, on_delete=models.CASCADE, related_name='members')
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    encrypted_key = models.TextField()  # encrypted group key for this member
    accepted = models.BooleanField(default=False)
    indexed_at = models.DateTimeField(auto_now=True)

class CachedExpense(models.Model):
    expense_id = models.IntegerField(unique=True)  # on-chain ID
    group = models.ForeignKey(CachedGroup, on_delete=models.CASCADE, related_name='expenses')
    encrypted_data = models.TextField()
    indexed_at = models.DateTimeField(auto_now=True)

class CachedSettlement(models.Model):
    class Status(models.TextChoices):
        PENDING = 'pending'
        BRIDGING = 'bridging'
        CONFIRMED = 'confirmed'
        FAILED = 'failed'

    tx_hash = models.CharField(max_length=66, unique=True)
    from_user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sent_settlements')
    to_address = models.CharField(max_length=42)
    amount = models.DecimalField(max_digits=18, decimal_places=6)
    source_chain = models.IntegerField()
    dest_chain = models.IntegerField()
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    indexed_at = models.DateTimeField(auto_now=True)
```

---

## Edge Cases & Error States

### Authentication

| Scenario | Handling |
|----------|----------|
| User abandons onboarding before linking address | Account not created |
| Signature verification fails | Show error, retry signing |
| Public key recovery fails | Show error, retry with different wallet |
| Burnt address tries to link to new account | Reject with error message |
| User forgets password | Must create new account (no email recovery) |

### ECDH / Friends

| Scenario | Handling |
|----------|----------|
| Friend request not accepted | Request expires after 7 days, can re-request |
| User changes device | Re-derive shared secrets using wallet (keys on-chain) |
| User changes wallet | Must re-link address, new pubKey registered |
| Friend's pubKey not found | User hasn't completed onboarding; cannot add |

### Settlement

| Scenario | Handling |
|----------|----------|
| Settlement contract on recipient's chain not deployed | Show error, suggest alternative chain |
| CCTP bridging fails | Relayer refunds to sender |
| Amount too small for gas | Show minimum settlement amount error |
| Recipient's ENS preferences stale | Resolve at settlement time (not expense time) |

### Offline

| Scenario | Handling |
|----------|----------|
| User adds expense offline | Store in IndexedDB, show greyed in activity |
| User comes online | Sync queue to blockchain; if conflict, show error and let user retry |
| Offline for extended period | Queue may contain stale data; warn user |

### Reputation

| Scenario | Handling |
|----------|----------|
| New user | 50 score, "New User" badge |
| Score drops below 10 | Account flagged, warning shown to potential friends |
| User voluntarily deletes | Burn subname, flag address |

---

## Farcaster Integration

### Linking Flow

1. User clicks "Link Farcaster" button
2. Opens Neynar SIWN (Sign In With Neynar) flow
3. Returns `fid` (Farcaster ID) and `signer_uuid`
4. Store `fid` in User model
5. Optionally request read permission for social graph

### Importing Followers

1. Call Neynar API: `fetchAllFollowing(fid)` and `fetchAllFollowers(fid)`
2. Find mutual follows (bidirectional connections)
3. Check if any mutual follows also have khaaliSplit accounts (via linked addresses or FID)
4. Show as "Suggested Friends" in app

### Frames

- **Frame server:** Django views using `framelib` library
- **Frame validation:** Validate frame actions via Neynar Hub API
- **Transaction Frames:** For settlement (user sends USDC directly from Warpcast)
- **Hosted at:** `https://app.khaalisplit.xyz/frames/{frame-type}`

---

## Open Questions

| # | Question | Status | Answer |
|---|----------|--------|--------|
| 1 | Arc is testnet-only? | Resolved | Yes, testnet. Fine for hackathon. |
| 2 | ENS on L1 vs L2? | Resolved | Offchain subnames via CCIP-Read. Zero gas. |
| 3 | Off-chain data location? | Resolved | PostgreSQL; on-chain is source of truth. |
| 4 | Session mechanism? | Resolved | JWT (platform agnostic). |
| 5 | ECDH key storage? | Resolved | Client-side; re-derivable from on-chain. |

---

## Appendix

### References

- [Circle Arc Documentation](https://docs.arc.network)
- [Circle CCTP Documentation](https://developers.circle.com/cctp)
- [Circle BridgeKit](https://www.circle.com/blog/introducing-bridge-kit)
- [ENS Documentation](https://docs.ens.domains)
- [ENS Offchain Resolvers](https://docs.ens.domains/resolvers/ccip-read)
- [ENS Text Records](https://docs.ens.domains/ens-improvement-proposals/ensip-5-text-records)
- [ENS NameWrapper](https://docs.ens.domains/wrapper/overview)
- [Farcaster Frames](https://docs.farcaster.xyz/reference/frames/spec)
- [Neynar API](https://docs.neynar.com)
- [framelib (Python)](https://github.com/devinaconley/python-framelib)
- [Envio HyperIndex](https://docs.envio.dev/docs/HyperIndex/overview)
- [ETHGlobal HackMoney 2026](https://ethglobal.com/events/hackmoney2026)

### Hackathon Prize Requirements

**Arc ($10,000 total):**
- Chain-Abstracted USDC Apps ($5,000): Build apps treating multiple chains as one liquidity surface
- Global Payouts & Treasury Systems ($2,500): Multi-recipient, multi-chain settlement

**ENS ($5,000 total):**
- Integrate ENS ($3,500): Must write custom ENS code (not just Rainbowkit)
- Most Creative Use of ENS for DeFi ($1,500): ENS must clearly improve the product
