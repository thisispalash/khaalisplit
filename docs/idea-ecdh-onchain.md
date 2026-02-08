# Idea: On-Chain ECDH Key Exchange

## The Problem

Expense-splitting apps handle sensitive financial data — who owes whom, how much, for what. Storing this in plaintext on-chain is a non-starter. But storing it off-chain in a centralized database defeats the purpose of building on Ethereum.

## The Insight

We can store **ECDH public keys on-chain** and let clients derive pairwise shared secrets entirely client-side. This gives us:

- **No trusted server** — the chain is the key directory
- **No key exchange ceremony** — both parties independently compute the same shared secret from each other's public key and their own private key
- **Three-tier encryption** — pairwise secrets encrypt group AES keys, which encrypt expense data

## How It Works

1. **Registration**: Each user calls `registerPubKey(bytes)` on `khaaliSplitFriends`, storing their ECDH public key on-chain.
2. **Pairwise Secret**: When Alice and Bob become friends, both clients compute `ECDH(myPriv, theirPub)` → identical shared secret, no round-trips needed.
3. **Group Keys**: When Alice creates a group, she generates a random AES-256-GCM key, encrypts a copy for each member using their pairwise secret, and stores those encrypted copies on-chain.
4. **Expense Data**: Expense JSON is encrypted with the group AES key. Only the `keccak256` hash goes on-chain (`dataHash`). The encrypted blob is emitted in the `ExpenseAdded` event for off-chain indexing.

## Why This Is Interesting

- **Fully decentralized E2E encryption** without a key server, certificate authority, or Signal-style ratchet
- **On-chain key directory** means anyone can verify public keys — no TOFU (Trust On First Use) problem
- **Composable** — other dApps could read these public keys and establish encrypted channels with khaaliSplit users
- The contract never sees plaintext. It's a **privacy-preserving social layer** on a public chain.

## Trade-offs

- ECDH keys are **not the same as wallet keys** — users generate a separate keypair, so the private key must be stored client-side (e.g., browser storage, device keychain)
- If a user loses their ECDH private key, they lose access to all their encrypted group keys and expense history
- No forward secrecy — if a pairwise secret is compromised, all past group keys encrypted with it are exposed
