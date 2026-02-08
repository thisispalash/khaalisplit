# khaaliSplit Contracts

Smart contracts for khaaliSplit, built with [Foundry](https://getfoundry.sh/).

## Architecture

| Contract | Chain | Description |
|----------|-------|-------------|
| `khaaliSplitFriends` | Sepolia | Social graph — ECDH pubkey registry + friend requests |
| `khaaliSplitGroups` | Sepolia | Group registry with encrypted group keys |
| `khaaliSplitExpenses` | Sepolia | Expense registry (hashes on-chain, encrypted data in events) |
| `khaaliSplitSubnames` | Sepolia | On-chain ENS subname registrar + resolver for `*.khaalisplit.eth` |
| `khaaliSplitReputation` | Sepolia | On-chain reputation scores, synced to ENS text records |
| `khaaliSplitSettlement` | All chains | USDC settlement via EIP-3009, routed through Circle Gateway or CCTP |
| `khaaliSplitResolver` | Sepolia | CCIP-Read (EIP-3668) ENS resolver *(deprecated — replaced by Subnames)* |
| `kdioDeployer` | All chains | CREATE2 factory for deterministic proxy addresses |

All contracts (except `kdioDeployer`) use the **UUPS upgradeable proxy pattern**.

### Approved Chains

| Chain | Chain ID | CCTP Domain |
|-------|----------|-------------|
| Sepolia | 11155111 | 0 |
| Base Sepolia | 84532 | 6 |
| Arc Testnet | 1397 | N/A (no CCTP) |
| Ethereum Mainnet | 1 | 0 |
| Base Mainnet | 8453 | 6 |

**Only approved token: USDC.**

## Settlement

The settlement contract routes USDC payments based on the recipient's ENS text record preferences.

### Flow

```
1. Sender signs an EIP-3009 ReceiveWithAuthorization message off-chain
   (to = settlement contract address, value = amount)
2. Anyone submits the signature via settleWithAuthorization()
   (enables gasless/offline payments — e.g. NFC tap, Bluetooth relay)
3. Contract pulls USDC from sender via receiveWithAuthorization on USDC
4. Reads recipient's payment preferences from ENS text records:
   - com.khaalisplit.payment.flow:  "gateway" (default) or "cctp"
   - com.khaalisplit.payment.token: USDC address on settlement chain
   - com.khaalisplit.payment.cctp:  CCTP domain (required if flow == "cctp")
5. Routes funds:
   - Gateway (default): gatewayWallet.depositFor() → unified USDC balance
   - CCTP (opt-in):     tokenMessenger.depositForBurn() → cross-chain mint
6. Updates sender's reputation score
7. Emits SettlementCompleted event
```

### Routing

| Route | When | What happens |
|-------|------|-------------|
| **Gateway** (default) | `flow` is empty, `"gateway"`, or unknown | Approves + calls `gatewayWallet.depositFor(token, recipient, amount)`. Recipient gets unified Gateway USDC balance across chains. |
| **CCTP** (opt-in) | `flow == "cctp"` | Reads CCTP domain from text records, approves + calls `tokenMessenger.depositForBurn()`. Recipient gets USDC minted on destination chain. |
| **Same-chain** | Sender and recipient on same chain | Handled client-side (direct USDC transfer). Not routed through the contract. |

### ENS Text Records (ENSIP-5)

Payment preferences are stored as on-chain text records on `{username}.khaalisplit.eth` subnames:

| Key | Example | Description |
|-----|---------|-------------|
| `com.khaalisplit.payment.flow` | `"gateway"` | Routing preference: `"gateway"` (default) or `"cctp"` |
| `com.khaalisplit.payment.token` | `"0x1c7D..."` | USDC address on the settlement chain |
| `com.khaalisplit.payment.cctp` | `"6"` | CCTP destination domain (required for CCTP flow) |
| `com.khaalisplit.payment.chain` | `"84532"` | Preferred destination chain ID |

### EIP-3009 Authorization

The settlement contract uses USDC's native `receiveWithAuthorization` (EIP-3009) instead of
the standard approve + transferFrom pattern. Key properties:

- **Gasless**: User signs off-chain, anyone can submit the transaction
- **Front-running protected**: Only the contract (`msg.sender == to`) can execute
- **Random nonces**: Allows concurrent pending authorizations (unlike sequential EIP-2612 nonces)
- **Offline-friendly**: Signatures can be relayed via NFC, Bluetooth, or QR code

## Subnames

The subnames contract manages `{username}.khaalisplit.eth` ENS subnames via NameWrapper (ERC-1155).
It serves as the on-chain resolver, storing text records and address records directly.

- Registration is backend-gated (`register(label, owner)`)
- Supports `setText()` and `setAddr()` by the subname owner, backend, or reputation contract
- `addr(node)` provides forward lookup (ENS namehash → wallet address)
- Implements ERC-165 (`ITextResolver`, `IAddrResolver`)

## Reputation

The reputation contract tracks settlement reliability scores (0–100, default 50):

- `recordSettlement(user, success)` — called by the settlement contract after each payment
- Success: +1 point (capped at 100)
- Failure: -5 points (floored at 0)
- Scores are automatically synced to ENS text records via `com.khaalisplit.reputation`

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
| `test/*.t.sol` | Unit tests — one file per contract |
| `test/integration/UserFlows.t.sol` | Integration tests — full user flows across contracts |
| `test/helpers/MockUSDC.sol` | Mock ERC20 + EIP-3009 `receiveWithAuthorization` |
| `test/helpers/MockTokenMessengerV2.sol` | Mock CCTP TokenMessengerV2 |
| `test/helpers/MockGatewayWallet.sol` | Mock Circle Gateway Wallet |
| `test/helpers/MockNameWrapper.sol` | Mock ENS NameWrapper for subname tests |

### Test Coverage

| Contract | Tests |
|----------|-------|
| `khaaliSplitSettlement` | 52 tests — init, gateway, cctp, validation, reputation, admin, upgrades, nonce replay |
| `khaaliSplitSubnames` | 47 tests — registration, text/addr records, access control, ERC-165, upgrades |
| `khaaliSplitReputation` | 60 tests — scoring, ENS sync, access control, boundary conditions, upgrades |
| `khaaliSplitFriends` | 27 tests |
| `khaaliSplitGroups` | 22 tests |
| `khaaliSplitExpenses` | 15 tests |
| `khaaliSplitResolver` | 17 tests |
| `kdioDeployer` | 6 tests |
| Integration (UserFlows) | 5 tests (1 skipped — old settlement flow) |
| **Total** | **250 passing, 1 skipped** |

## Deployment

### 1. Environment

Set up your `.env` file according to [`.env.example`](./.env.example)

### 2. Config Files

| File | Description |
|------|-------------|
| [`script/tokens.json`](script/tokens.json) | USDC addresses per chain, keyed by chain ID |
| [`script/cctp.json`](script/cctp.json) | TokenMessenger + Gateway addresses (testnet/mainnet), CCTP domain mappings |

### 3. Deploy

```bash
source .env

# Deploy core contracts to Sepolia (Friends, Groups, Expenses, Subnames, Reputation)
forge script script/DeployCore.s.sol:DeployCore --rpc-url sepolia --broadcast --verify

# Deploy settlement to each chain
# Reads USDC addresses from tokens.json and CCTP/Gateway config from cctp.json
NETWORK_TYPE=testnet forge script script/DeploySettlement.s.sol:DeploySettlement \
  --rpc-url sepolia --broadcast

NETWORK_TYPE=testnet forge script script/DeploySettlement.s.sol:DeploySettlement \
  --rpc-url base_sepolia --broadcast

NETWORK_TYPE=testnet forge script script/DeploySettlement.s.sol:DeploySettlement \
  --rpc-url arc_testnet --broadcast

# Optional: set companion contracts after deployment
SUBNAME_REGISTRY=0x... REPUTATION_CONTRACT=0x... \
NETWORK_TYPE=testnet forge script script/DeploySettlement.s.sol:DeploySettlement \
  --rpc-url sepolia --broadcast
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
- **`settle()` stub**: The approval-based settlement flow is not yet implemented — `settle()`
  reverts with `NotImplemented()`. Only `settleWithAuthorization()` is functional.
- **Mainnet Gateway address TBD**: The mainnet Circle Gateway Wallet address is a placeholder
  (`0x0`) in `cctp.json`. Must be verified on Etherscan before mainnet deployment.
- **No integration test for settlement flow**: The old settlement integration test
  (`UserFlows.t.sol` flow 2) is skipped. A new integration test covering the full
  EIP-3009 → Gateway/CCTP flow is a follow-up.
