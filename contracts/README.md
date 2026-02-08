# khaaliSplit Contracts

Smart contracts for khaaliSplit, a censorship-resistant payment splitting app. Built with [Foundry](https://getfoundry.sh/).

<details>
<summary><strong>Deployed Addresses</strong></summary>

### Sepolia (Chain ID: 11155111) — Core Contracts

| Contract | Proxy | Implementation |
|----------|-------|----------------|
| `khaaliSplitFriends` | [`0xc6513216d6Bc6498De9E37e00478F0Cb802b2561`](https://sepolia.etherscan.io/address/0xc6513216d6Bc6498De9E37e00478F0Cb802b2561) | [`0xee47547be03F5D53Be908c226d2271d0f4D54643`](https://sepolia.etherscan.io/address/0xee47547be03F5D53Be908c226d2271d0f4D54643) |
| `khaaliSplitGroups` | [`0xf6f07Bdc4f14b1FB1374A1d821A9E50547EcE820`](https://sepolia.etherscan.io/address/0xf6f07Bdc4f14b1FB1374A1d821A9E50547EcE820) | [`0x3b12bFDedFAcFC65deA612aB7291404b06214CF3`](https://sepolia.etherscan.io/address/0x3b12bFDedFAcFC65deA612aB7291404b06214CF3) |
| `khaaliSplitExpenses` | [`0x0058f47e98DF066d34f70EF231AdD634C9857605`](https://sepolia.etherscan.io/address/0x0058f47e98DF066d34f70EF231AdD634C9857605) | [`0x187eb3155ef1FaF4CD72DEdd7586674bF775daF3`](https://sepolia.etherscan.io/address/0x187eb3155ef1FaF4CD72DEdd7586674bF775daF3) |
| `khaaliSplitSubnames` | [`0xE7F20a2c7461cAF3FdCD672E273326fAeCE5Be4F`](https://sepolia.etherscan.io/address/0xE7F20a2c7461cAF3FdCD672E273326fAeCE5Be4F) | [`0x9C8531B1afdd1e19f0A1ebb005360D0deB91F8DE`](https://sepolia.etherscan.io/address/0x9C8531B1afdd1e19f0A1ebb005360D0deB91F8DE) |
| `khaaliSplitReputation` | [`0x3a916C1cb55352860FA46084EBA5A032dB50312f`](https://sepolia.etherscan.io/address/0x3a916C1cb55352860FA46084EBA5A032dB50312f) | [`0x1A728640de3C2d100d3526e710E4D1eF79bc27eC`](https://sepolia.etherscan.io/address/0x1A728640de3C2d100d3526e710E4D1eF79bc27eC) |
| `khaaliSplitResolver` | [`0x7403caAFB6d87d3DFF00ddDA3Ef02ACA13C8364A`](https://sepolia.etherscan.io/address/0x7403caAFB6d87d3DFF00ddDA3Ef02ACA13C8364A) | [`0x4c39c4d2a0FD2B9138dFFd8435aaAdA40b22af51`](https://sepolia.etherscan.io/address/0x4c39c4d2a0FD2B9138dFFd8435aaAdA40b22af51) |
| `kdioDeployer` | — | [`0x0f04784d0BFaEeFB4bc15C8EbDe4e483ccE2154f`](https://sepolia.etherscan.io/address/0x0f04784d0BFaEeFB4bc15C8EbDe4e483ccE2154f) |

### Settlement Contracts (multi-chain)

| Chain | Proxy | Implementation | USDC |
|-------|-------|----------------|------|
| Sepolia (11155111) | [`0xd038e9CD05a71765657Fd3943d41820F5035A6C1`](https://sepolia.etherscan.io/address/0xd038e9CD05a71765657Fd3943d41820F5035A6C1) | `0xc095dc0280B947B593b90Ae5Ac1c77bfEc48268A` | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| Base Sepolia (84532) | [`0xacDbabeDc22BE4eD68D9084Dd3157c27D7154baa`](https://sepolia.basescan.org/address/0xacDbabeDc22BE4eD68D9084Dd3157c27D7154baa) | `0x6587Cafe8457FE9AC743cb547245f43b29D5b69d` | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| Arbitrum Sepolia (421614) | [`0x8A20a346a00f809fbd279c1E8B56883998867254`](https://sepolia.arbiscan.io/address/0x8A20a346a00f809fbd279c1E8B56883998867254) | `0x3e9fF12636c36e9a27e0b07F758426F5723b7976` | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` |
| OP Sepolia (11155420) | [`0x8A20a346a00f809fbd279c1E8B56883998867254`](https://sepolia-optimism.etherscan.io/address/0x8A20a346a00f809fbd279c1E8B56883998867254) | `0x3e9fF12636c36e9a27e0b07F758426F5723b7976` | `0x5fd84259d66Cd46123540766Be93DFE6D43130D7` |
| Meld Kanazawa (5042002) | `0xeB75548245A9C5a31ABF6Eda7CA16977f3Af3690` | `0x1ae0487F652f6d639516c0210aBC71ed8103aE97` | `0x3600000000000000000000000000000000000000` |

> All addresses are also stored in [`deployments.json`](./deployments.json).

</details>

## Architecture

| Contract | Chain | Description |
|----------|-------|-------------|
| `khaaliSplitFriends` | Sepolia | Social graph — ECDH pubkey registry, friend requests, backend relay |
| `khaaliSplitGroups` | Sepolia | Group registry with encrypted group keys, backend relay |
| `khaaliSplitExpenses` | Sepolia | Expense registry (hashes on-chain, encrypted data in events), backend relay |
| `khaaliSplitSubnames` | Sepolia | On-chain ENS subname registrar + resolver for `*.khaalisplit.eth` |
| `khaaliSplitReputation` | Sepolia | On-chain reputation scores, synced to ENS text records |
| `khaaliSplitSettlement` | All chains | USDC settlement via EIP-3009 or Gateway mint, routed through Circle Gateway or CCTP |
| `khaaliSplitResolver` | Sepolia | CCIP-Read (EIP-3668) ENS resolver *(deprecated — replaced by Subnames)* |
| `kdioDeployer` | All chains | CREATE2 factory for deterministic proxy addresses |

All contracts (except `kdioDeployer`) use the **UUPS upgradeable proxy pattern**.

### Approved Chains

| Chain | Chain ID | CCTP Domain |
|-------|----------|-------------|
| Sepolia | 11155111 | 0 |
| Base Sepolia | 84532 | 6 |
| Arbitrum Sepolia | 421614 | 3 |
| OP Sepolia | 11155420 | 2 |
| Meld Kanazawa | 5042002 | N/A (no CCTP) |

**Only approved token: USDC.**

## Backend Relay Pattern

The khaaliSplit architecture requires that **the backend sends all on-chain transactions** on behalf of users. Users only sign messages client-side — they never submit transactions directly. This enables:

1. **Gasless UX** — users don't need ETH for gas
2. **PWA compatibility** — no wallet popups for transaction approval, only signing
3. **Offline settlement** — EIP-3009 signatures can be relayed later by anyone

Every state-changing function has a corresponding `*For` relay variant that accepts a `user` parameter and checks `msg.sender == backend`:

| Original (user calls directly) | Relay (backend calls on behalf of user) |
|---|---|
| `requestFriend(friend)` | `requestFriendFor(user, friend)` |
| `acceptFriend(requester)` | `acceptFriendFor(user, requester)` |
| `removeFriend(friend)` | `removeFriendFor(user, friend)` |
| `createGroup(nameHash, key)` | `createGroupFor(user, nameHash, key)` |
| `inviteMember(groupId, member, key)` | `inviteMemberFor(inviter, groupId, member, key)` |
| `acceptGroupInvite(groupId)` | `acceptGroupInviteFor(user, groupId)` |
| `leaveGroup(groupId)` | `leaveGroupFor(user, groupId)` |
| `addExpense(groupId, hash, data)` | `addExpenseFor(creator, groupId, hash, data)` |
| `updateExpense(id, hash, data)` | `updateExpenseFor(creator, id, hash, data)` |

Both versions emit **the same events**, so the indexer (Envio/HyperIndex) doesn't need changes. The `registerPubKey`, `register` (subnames), `setText`, `setAddr`, and settlement functions already followed this pattern — Friends, Groups, and Expenses were the last contracts to be upgraded.

## Settlement

The settlement contract routes USDC payments based on the recipient's ENS text record preferences.
Two settlement flows are supported: **direct** (EIP-3009) and **Gateway mint** (Circle Gateway attestation).

### Flow 1: Direct Settlement (`settleWithAuthorization`)

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
   - Gateway (default): gatewayWallet.depositFor() -> unified USDC balance
   - CCTP (opt-in):     tokenMessenger.depositForBurn() -> cross-chain mint
6. Updates sender's reputation score
7. Emits SettlementCompleted event
```

### Flow 2: Gateway Mint Settlement (`settleFromGateway`)

For cross-chain payments via Circle's Gateway API. The sender pays from their Gateway USDC
balance, and the backend orchestrates the mint + settlement atomically.

```
1. Sender signs a BurnIntent (EIP-712) off-chain
   (destinationRecipient = settlement contract address)
2. Backend submits signed BurnIntent to Circle Gateway API
   -> receives attestationPayload + attestationSignature
3. Backend calls settleFromGateway(attestation, sig, recipientNode, sender, memo)
4. Contract calls gatewayMinter.gatewayMint() -> USDC minted to settlement contract
5. Balance-diff pattern: balanceAfter - balanceBefore = actual minted amount
   (naturally handles Gateway fees without knowing the fee structure)
6. Routes to recipient via Gateway or CCTP (same routing as Flow 1)
7. Updates sender's reputation score
8. Emits SettlementCompleted event
9. All atomic — if any step reverts, the mint reverts too
```

### Key Contracts (Circle Infrastructure)

| Contract | Address | Role |
|----------|---------|------|
| GatewayWallet | `0x0077777d7EBA4688BDeF3E311b846F25870A19B9` | Holds deposited USDC, manages Gateway balances |
| GatewayMinter | `0x0022222ABE238Cc2C7Bb1f21003F0a260052475B` | Mints USDC on destination chain from attestation |

Both are deployed at the same address on all chains via CREATE2.

### Routing

Both settlement flows use the same routing logic based on the recipient's ENS text records:

| Route | When | What happens |
|-------|------|-------------|
| **Gateway** (default) | `flow` is empty, `"gateway"`, or unknown | Approves + calls `gatewayWallet.depositFor(token, recipient, amount)`. Recipient gets unified Gateway USDC balance across chains. |
| **CCTP** (opt-in) | `flow == "cctp"` | Reads CCTP domain from text records, approves + calls `tokenMessenger.depositForBurn()`. Recipient gets USDC minted on destination chain. |
| **Same-chain** | Sender and recipient on same chain | Handled client-side (direct USDC transfer). Not routed through the contract. |

### NFC/Bluetooth UX

The client differentiates flows via a `type` field in the NFC/Bluetooth payload:
- `type: "direct"` -> EIP-3009 flow -> `settleWithAuthorization`
- `type: "gateway"` -> BurnIntent flow -> backend -> Circle API -> `settleFromGateway`

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

### Design Decisions

- **`bytes32 recipientNode` as primary parameter**: All settlement functions take the ENS namehash instead of a wallet address. The contract resolves the address internally via `subnameRegistry.addr(node)`. The ENS node is the canonical identifier — addresses can change (via `setAddr`), but the node is permanent.
- **Sender passed explicitly in `settleFromGateway`**: Rather than parsing the sender from the attestation payload bytes (gas-expensive offset math), the sender address is passed as a parameter. Since the attestation is verified by Circle's GatewayMinter (signature check), and the sender is only used for reputation tracking, this is a pragmatic hackathon tradeoff. On-chain attestation parsing can be added later.
- **Balance-diff pattern for minted amount**: `settleFromGateway` records `balanceOf(this)` before and after the `gatewayMint` call, using the difference as the actual amount. This naturally handles Gateway fees without needing to know the fee structure or parse fee data from the attestation.
- **`initialize(address _owner)` signature preserved**: All post-deployment configuration (tokens, CCTP, Gateway, subnames, reputation) is done via admin setters rather than constructor/initializer args. This keeps the implementation bytecode identical across chains for CREATE2 address determinism.
- **No access control on settlement functions**: Both `settleWithAuthorization` and `settleFromGateway` are callable by anyone. Authorization comes from the EIP-3009 signature (Flow 1) or Circle's attestation signature (Flow 2), not from `msg.sender`.

### Offline Payments

A key design goal of khaaliSplit is enabling payments without requiring the sender to be online
at the time of settlement. The contract architecture supports this through signature-based
authorization — the sender signs a message off-chain, and anyone can submit it later.

**How it works:**

1. **Sender goes offline** after signing. The signature is the authorization — no further
   interaction is needed from the sender.
2. **Signature is transmitted** via local channels that don't require internet:
   - **NFC tap**: Sender holds phone near recipient's phone, signature transfers instantly
   - **Bluetooth**: Nearby devices exchange signature data over BLE
   - **QR code**: Sender displays QR, recipient scans it
3. **Anyone submits** the signature to the blockchain. The recipient, a friend, a backend
   relayer, or any third party can call `settleWithAuthorization()`. The contract validates
   the signature, not `msg.sender`.

**Why this matters:**

- **No internet for sender**: Pay at a restaurant with no wifi — tap your phone, walk away
- **No gas for sender**: The submitter pays gas, not the signer
- **No front-running**: EIP-3009's `receiveWithAuthorization` ensures only the settlement
  contract (`to == address(this)`) can execute the transfer
- **Concurrent payments**: EIP-3009 uses random nonces (not sequential like EIP-2612), so
  multiple pending payments don't block each other

The Gateway mint flow (`settleFromGateway`) also supports offline senders — the sender signs
a BurnIntent off-chain, and the backend handles the rest (Circle API call + contract submission).
The sender never needs to be online after signing.

## Subnames

The subnames contract manages `{username}.khaalisplit.eth` ENS subnames via NameWrapper (ERC-1155).
It serves as the on-chain resolver, storing text records and address records directly.

- Registration is backend-gated (`register(label, owner)`)
- Supports `setText()` and `setAddr()` by the subname owner, backend, or reputation contract
- `addr(node)` provides forward lookup (ENS namehash -> wallet address)
- Implements ERC-165 (`ITextResolver`, `IAddrResolver`)

## Reputation

The reputation contract tracks settlement reliability scores (0-100, default 50):

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
| `test/helpers/MockGatewayMinter.sol` | Mock Circle Gateway Minter (mints configurable USDC to caller) |
| `test/helpers/MockNameWrapper.sol` | Mock ENS NameWrapper for subname tests |

### Test Coverage

| Contract | Tests |
|----------|-------|
| `khaaliSplitSettlement` | 70 tests — init, gateway routing, CCTP routing, settleFromGateway, validation, reputation, admin setters, upgrades, nonce replay |
| `khaaliSplitReputation` | 60 tests — scoring, ENS sync, access control, boundary conditions, upgrades |
| `khaaliSplitSubnames` | 47 tests — registration, text/addr records, access control, ERC-165, upgrades |
| `khaaliSplitGroups` | 45 tests — group CRUD, invites, membership, backend relay (`*For`), admin |
| `khaaliSplitFriends` | 44 tests — pubkey registration, friend requests, mutual auto-accept, backend relay (`*For`), admin |
| `khaaliSplitExpenses` | 27 tests — add/update expenses, backend relay (`*For`), admin |
| `khaaliSplitResolver` | 17 tests |
| Integration (UserFlows) | 15 tests |
| `kdioDeployer` | 6 tests |
| **Total** | **331 passing** |

## Deployment

### 1. Environment

Set up your `.env` file according to [`.env.example`](./.env.example)

### 2. Config Files

| File | Description |
|------|-------------|
| [`script/tokens.json`](script/tokens.json) | USDC addresses per chain, keyed by chain ID |
| [`script/cctp.json`](script/cctp.json) | TokenMessenger, GatewayWallet, GatewayMinter addresses (testnet/mainnet), CCTP domain mappings |

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
  --rpc-url op_sepolia --broadcast

NETWORK_TYPE=testnet forge script script/DeploySettlement.s.sol:DeploySettlement \
  --rpc-url arb_sepolia --broadcast
```

### 4. Upgrade (UUPS)

To upgrade core contracts to new implementations (e.g. after adding relay functions):

```bash
source .env

# Reads proxy addresses from deployments.json, deploys new impls, upgrades, sets backend
forge script script/UpgradeCore.s.sol:UpgradeCore --rpc-url sepolia --broadcast --verify
```

The upgrade script reads proxy addresses from `deployments.json` automatically and writes back updated implementation addresses after upgrade.

### 5. Post-deployment Wiring

```bash
# Wire companion contracts after both Core and Settlement are deployed
reputation.setSettlementContract(settlementProxy)
settlement.setSubnameRegistry(subnamesProxy)
settlement.setReputationContract(reputationProxy)
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
  reverts with `NotImplemented()`. Use `settleWithAuthorization()` (EIP-3009) or
  `settleFromGateway()` (Gateway mint) instead.
- **Mainnet Gateway address TBD**: The mainnet Circle Gateway Wallet address is a placeholder
  (`0x0`) in `cctp.json`. Must be verified on Etherscan before mainnet deployment.
- **Backend is a trusted relayer**: The `*For` relay functions trust the backend to act on
  behalf of the correct user. A compromised backend wallet could manipulate the social graph
  and expenses. Acceptable for hackathon; production would add EIP-712 user signatures.
