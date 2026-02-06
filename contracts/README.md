# khaaliSplit Contracts

Smart contracts for khaaliSplit, built with [Foundry](https://getfoundry.sh/).

## Architecture

| Contract | Chain | Description |
|----------|-------|-------------|
| `khaaliSplitFriends` | Sepolia | Social graph — ECDH pubkey registry + friend requests |
| `khaaliSplitGroups` | Sepolia | Group registry with encrypted group keys |
| `khaaliSplitExpenses` | Sepolia | Expense registry (hashes on-chain, encrypted data in events) |
| `khaaliSplitResolver` | Sepolia | CCIP-Read (EIP-3668) ENS resolver for `*.khaalisplit.eth` |
| `khaaliSplitSettlement` | All chains | Multi-token settlement (USDC, EURC) with EIP-2612 permit |
| `kdioDeployer` | All chains | CREATE2 factory for deterministic proxy addresses |

All contracts (except `kdioDeployer`) use the **UUPS upgradeable proxy pattern**.

## Encryption Model

All encryption and decryption happens **client-side**. The contracts serve as a key distribution
and membership management layer.

### 1. Friend Pairing (ECDH)

Wallet ECDH public keys are registered on-chain during onboarding (the backend recovers the key
from a user's signature via `ecrecover` and calls `registerPubKey()`). When two users become
friends, each computes a pairwise shared secret client-side:

```
sharedSecret = ECDH(myPrivateKey, theirPublicKey)
```

Shared secrets are **never transmitted** — they are derived locally and produce identical values
on both sides.

### 2. Group Shared Key (AES-256-GCM)

The group creator generates a random AES-256 symmetric key, then encrypts it separately for each
member using their pairwise ECDH shared secret. Each member's encrypted copy is stored on-chain
in `encryptedGroupKey[groupId][member]`. Members decrypt the group key client-side using their
own shared secret with the inviter.

### 3. Expense Encryption

Expense JSON (amounts, splits, descriptions) is encrypted client-side with the group AES key
using AES-256-GCM. Only the `keccak256` hash of the plaintext data (`dataHash`) is stored
on-chain for integrity verification. The full encrypted blob is emitted in `ExpenseAdded` /
`ExpenseUpdated` events for off-chain indexing by Envio/HyperIndex.

### Key Rotation

When a member leaves a group (`leaveGroup()`), their `encryptedGroupKey` is deleted on-chain
and a `MemberLeft` event is emitted. The client should use this event as a signal to generate
a new group AES key and re-encrypt it for the remaining members. **No ratcheting at the
contract level** — Signal-style double ratchet is a post-hackathon enhancement (PRD Priority 2).

## Build & Test

```bash
# Build
forge build

# Run all tests (unit + integration)
forge test -vvv

# Run only unit tests
forge test --match-path "test/*.t.sol" -vvv

# Run only integration tests
forge test --match-path "test/integration/*.t.sol" -vvv

# Gas report
forge test --gas-report
```

### Test Structure

| Directory | Description |
|-----------|-------------|
| `test/*.t.sol` | Unit tests — one file per contract, covering individual functions |
| `test/integration/UserFlows.t.sol` | Integration tests — full user flows across all contracts |
| `test/helpers/MockUSDC.sol` | Mock ERC20 + ERC20Permit token for settlement tests |

The integration tests deploy all contracts through ERC1967 proxies, wire them together,
and exercise end-to-end flows including: onboarding → friend pairing → group creation →
expense tracking → settlement with EIP-2612 permit → member departure → and CREATE2
deterministic deployment via `kdioDeployer`.

## Deployment

### 1. Environment

Set up your `.env` file according to [`.env.example`](./.env.example)

### 2. Token config

Token addresses per chain are in [`script/tokens.json`](script/tokens.json), keyed by chain ID. 
The settlement deploy script reads this file automatically. Use `address(0)` to skip a token on a 
given chain.

### 3. Deploy

```bash
source .env

# Deploy core contracts to Sepolia
forge script script/DeployCore.s.sol:DeployCore --rpc-url sepolia --broadcast --verify

# Deploy settlement to each chain (reads token addresses from script/tokens.json)
forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url sepolia --broadcast
forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url arc_testnet --broadcast
forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url base --broadcast
forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url arbitrum --broadcast
```

## Known Limitations
> These are acceptable for the hackathon but should be addressed before production.

- **Soft-deletes only**: `removeFriend()`, `leaveGroup()`, and `updateExpense()` exist but use
  soft-deletes — they flip boolean mappings to `false` without removing entries from internal
  arrays (`_friendsList`, `_memberList`). Off-chain indexers should filter by the active status
  mappings (`isFriend`, `isMember`). There is still no `removeMember()` or `deleteExpense()`.
- **Unbounded arrays in views**: `getFriends()`, `getMembers()`, and `getGroupExpenses()`
  return full arrays with no pagination. Gas costs grow linearly with array size.
- **No client-side key rotation in contracts**: When a member leaves a group, the contract
  deletes their encrypted key and emits `MemberLeft`, but key rotation must be handled by
  the client application.
