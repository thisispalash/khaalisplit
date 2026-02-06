# khaaliSplit Smart Contracts — Implementation Plan

## Scope
**Only smart contracts.** No backend, no frontend, no Envio/HyperIndex. Deployment scripts created but **not executed** — deployment commands go in README.

**Repository:** `/Users/thisispalash/local/___2026-final/hacks/hackmoney2026/src/contracts/`
**Current state:** Empty — PRD.md, README.md, LICENSE, .gitignore, empty `contracts/` subdir. No foundry.toml, no .sol files.

## Key Design Decisions

1. **All contracts are UUPS upgradeable** — inherit `UUPSUpgradeable` + `Initializable` from OZ upgradeable
2. **Contract naming (lowercase k):** `khaaliSplitFriends`, `khaaliSplitGroups`, `khaaliSplitExpenses`, `khaaliSplitResolver`, `khaaliSplitSettlement`, `kdioDeployer`
3. **Custom CREATE2 deployer:** `kdioDeployer` — deploys all contracts deterministically
4. **No `kdioSignatures` library needed** — OZ `ECDSA.recover()` handles CCIP-Read signature verification directly (SignatureChecker doesn't fit the recover-then-check-mapping pattern)
5. **SettlementContract uses initializer** (not constructor args) for same CREATE2 address across all chains
6. **No actual deployments** — scripts + fork tests only
7. **Git commit after every major step** (scaffolding, each contract+test pair, deployer, scripts)

---

## Step 0: Add Plan to Repository

1. Copy this plan file to `src/contracts/PLAN.md`
2. Commit: `"docs: add contract implementation plan"`

---

## Step 1: Foundry Project Scaffolding

1. `forge init --no-git --force` (repo already has git via worktree)
2. Delete placeholder files: `src/Counter.sol`, `test/Counter.t.sol`, `script/Counter.s.sol`
3. Install dependencies:
   ```bash
   forge install openzeppelin/openzeppelin-contracts --no-commit
   forge install openzeppelin/openzeppelin-contracts-upgradeable --no-commit
   forge install ensdomains/ens-contracts --no-commit
   ```
4. Update `.gitignore` to add: `out/`, `cache/`, `broadcast/`, `.env`
5. Write `foundry.toml`:
   - `solc = "0.8.20"`, `evm_version = "paris"`
   - `optimizer = true`, `optimizer_runs = 200`
   - **`bytecode_hash = "none"`, `cbor_metadata = false`** (critical for CREATE2 determinism)
   - Remappings: `@openzeppelin/contracts/`, `@openzeppelin/contracts-upgradeable/`, `@ensdomains/ens-contracts/`
   - RPC endpoints: sepolia, arc_testnet, base, arbitrum (from env vars)

### Final Directory Structure

```
contracts/                              # repo root (worktree)
  foundry.toml
  .gitignore
  lib/
    openzeppelin-contracts/
    openzeppelin-contracts-upgradeable/
    ens-contracts/
  src/
    interfaces/
      IkhaaliSplitFriends.sol
      IkhaaliSplitGroups.sol
    khaaliSplitFriends.sol
    khaaliSplitGroups.sol
    khaaliSplitExpenses.sol
    khaaliSplitResolver.sol
    khaaliSplitSettlement.sol
    kdioDeployer.sol
  test/
    khaaliSplitFriends.t.sol
    khaaliSplitGroups.t.sol
    khaaliSplitExpenses.t.sol
    khaaliSplitResolver.t.sol
    khaaliSplitSettlement.t.sol
    kdioDeployer.t.sol
    helpers/
      MockUSDC.sol
  script/
    DeployCore.s.sol
    DeploySettlement.s.sol
  PLAN.md
  PRD.md
  README.md
  LICENSE
```

> **Git:** Commit after this step: `"chore: scaffold foundry project with dependencies"`

---

## Step 2: Interfaces

### `src/interfaces/IkhaaliSplitFriends.sol`
- `isFriend(address a, address b) -> bool`
- `walletPubKey(address user) -> bytes`
- `registered(address user) -> bool`

### `src/interfaces/IkhaaliSplitGroups.sol`
- `isMember(uint256 groupId, address user) -> bool`
- `getGroupCreator(uint256 groupId) -> address`

> **Git:** Commit: `"feat: add khaaliSplit interfaces"`

---

## Step 3: khaaliSplitFriends.sol

**Chain:** Sepolia | **Pattern:** UUPS Upgradeable

**Inherits:** `Initializable`, `UUPSUpgradeable`, `OwnableUpgradeable`

**Storage:**
- `address public backend` — authorized backend/relayer for pubkey registration
- `mapping(address => bytes) public walletPubKey`
- `mapping(address => mapping(address => bool)) public isFriend`
- `mapping(address => mapping(address => bool)) public pendingRequest`
- `mapping(address => address[]) private _friendsList`
- `mapping(address => bool) public registered`

**Functions:**
| Function | Access | Description |
|----------|--------|-------------|
| `initialize(address _backend, address _owner)` | Initializer | Sets backend + owner |
| `registerPubKey(address user, bytes pubKey)` | Backend only | Store ECDH pubkey |
| `requestFriend(address friend)` | User (msg.sender) | Both registered; sets pendingRequest |
| `acceptFriend(address requester)` | User (msg.sender) | Sets isFriend bidirectionally, clears pending |
| `getPubKey(address user)` | View | Returns walletPubKey |
| `getFriends(address user)` | View | Returns _friendsList |
| `setBackend(address)` | Owner only | Update backend address |
| `_authorizeUpgrade(address)` | Owner only | UUPS upgrade authorization |

**Events:** `PubKeyRegistered`, `FriendRequested`, `FriendAccepted`

## Step 4: khaaliSplitFriends Tests

**File:** `test/khaaliSplitFriends.t.sol`

- Deploy via `ERC1967Proxy` + `initialize()`
- `test_registerPubKey_by_backend` / `test_registerPubKey_not_backend_reverts`
- `test_requestFriend_success` / `test_requestFriend_not_registered_reverts` / `test_requestFriend_self_reverts`
- `test_acceptFriend_success` / `test_acceptFriend_no_pending_reverts`
- `test_getFriends_returns_list`
- `test_upgrade_onlyOwner`

> **Git:** Commit: `"feat: add khaaliSplitFriends contract and tests"`

---

## Step 5: khaaliSplitGroups.sol

**Chain:** Sepolia | **Pattern:** UUPS Upgradeable

**Inherits:** `Initializable`, `UUPSUpgradeable`, `OwnableUpgradeable`

**Storage:**
- `IkhaaliSplitFriends public friendRegistry`
- `uint256 public groupCount`
- `mapping(uint256 => Group) public groups` — struct: nameHash, creator, memberCount
- `mapping(uint256 => address[]) private _memberList`
- `mapping(uint256 => mapping(address => bool)) public isMember`
- `mapping(uint256 => mapping(address => bool)) public isInvited`
- `mapping(uint256 => mapping(address => bytes)) public encryptedGroupKey`

**Functions:**
| Function | Access | Description |
|----------|--------|-------------|
| `initialize(address _friendRegistry, address _owner)` | Initializer | Sets friend registry + owner |
| `createGroup(bytes32 nameHash, bytes encryptedKey)` | Any registered user | Create group, creator is first member |
| `inviteMember(uint256 groupId, address member, bytes encryptedKey)` | Group member | Must be friends (checks FriendRegistry) |
| `acceptGroupInvite(uint256 groupId)` | Invited user | Becomes member |
| `getMembers(uint256 groupId)` | View | Returns member list |
| `_authorizeUpgrade(address)` | Owner only | UUPS upgrade auth |

**Events:** `GroupCreated`, `MemberInvited`, `MemberAccepted`

## Step 6: khaaliSplitGroups Tests

**File:** `test/khaaliSplitGroups.t.sol`

Setup: Deploy khaaliSplitFriends proxy, register pubkeys, establish friendships, deploy khaaliSplitGroups proxy.

Tests: create group, invite (must be friend), invite (not friend reverts), accept, membership checks, encrypted key storage, upgrade auth.

> **Git:** Commit: `"feat: add khaaliSplitGroups contract and tests"`

---

## Step 7: khaaliSplitExpenses.sol

**Chain:** Sepolia | **Pattern:** UUPS Upgradeable

**Inherits:** `Initializable`, `UUPSUpgradeable`, `OwnableUpgradeable`

**Storage:**
- `IkhaaliSplitGroups public groupRegistry`
- `uint256 public expenseCount`
- `mapping(uint256 => Expense) public expenses` — struct: groupId, creator, dataHash, timestamp
- `mapping(uint256 => uint256[]) private _groupExpenses`

**Functions:**
| Function | Access | Description |
|----------|--------|-------------|
| `initialize(address _groupRegistry, address _owner)` | Initializer | Sets group registry + owner |
| `addExpense(uint256 groupId, bytes32 dataHash, bytes encryptedData)` | Group member | Stores hash; emits encrypted blob in event |
| `getExpense(uint256 expenseId)` | View | Returns Expense struct |
| `getGroupExpenses(uint256 groupId)` | View | Returns expense ID list |
| `_authorizeUpgrade(address)` | Owner only | UUPS upgrade auth |

**Events:**
```solidity
event ExpenseAdded(uint256 indexed groupId, uint256 indexed expenseId, address indexed creator, bytes32 dataHash, bytes encryptedData);
```

## Step 8: khaaliSplitExpenses Tests

**File:** `test/khaaliSplitExpenses.t.sol`

Setup: Full stack proxies — Friends + Groups + Expenses.

Tests: member adds expense, non-member reverts, event contains encrypted data, multiple expenses per group.

> **Git:** Commit: `"feat: add khaaliSplitExpenses contract and tests"`

---

## Step 9: khaaliSplitResolver.sol

**Chain:** Sepolia | **Pattern:** UUPS Upgradeable

**Implements:** `IExtendedResolver` (0x9061b923), ERC165

**Inherits:** `Initializable`, `UUPSUpgradeable`, `OwnableUpgradeable`

**Signature verification:** Uses `ECDSA.recover()` from OpenZeppelin directly — no custom library needed. The CCIP-Read pattern requires recovering the signer address from a hash+signature, then checking a mapping. OZ `SignatureChecker` doesn't fit (it validates a *known* signer, but we need to *discover* who signed).

**Storage:**
- `string public url` — gateway URL template
- `mapping(address => bool) public signers` — trusted gateway signers

**Functions:**
| Function | Access | Description |
|----------|--------|-------------|
| `initialize(string url, address[] signers, address _owner)` | Initializer | Sets gateway URL, signers, owner |
| `resolve(bytes name, bytes data)` | View | Reverts with `OffchainLookup(sender, urls, callData, resolveWithProof.selector, extraData)` |
| `resolveWithProof(bytes response, bytes extraData)` | View | Builds EIP-191 hash (`0x1900 \|\| target \|\| expires \|\| keccak256(request) \|\| keccak256(result)`), calls `ECDSA.recover()`, checks `signers[recovered]`, returns result |
| `supportsInterface(bytes4)` | View | True for IExtendedResolver + IERC165 |
| `addSigner(address)` / `removeSigner(address)` | Owner | Manage trusted signers |
| `setUrl(string)` | Owner | Update gateway URL |
| `_authorizeUpgrade(address)` | Owner only | UUPS upgrade auth |

**OffchainLookup error:**
```solidity
error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);
```

## Step 10: khaaliSplitResolver Tests

**File:** `test/khaaliSplitResolver.t.sol`

- `resolve` reverts with correct `OffchainLookup` data
- `resolveWithProof` with valid signature (via `vm.sign()`) returns result
- `resolveWithProof` with invalid signer / expired signature reverts
- `supportsInterface` for IExtendedResolver, IERC165, random
- Signer management (add/remove, onlyOwner)

> **Git:** Commit: `"feat: add khaaliSplitResolver contract and tests"`

---

## Step 11: khaaliSplitSettlement.sol

**Chain:** ALL chains — **DETERMINISTIC ADDRESS via kdioDeployer + CREATE2**

**Pattern:** UUPS Upgradeable (with initializer for CREATE2 determinism)

**Inherits:** `Initializable`, `UUPSUpgradeable`, `OwnableUpgradeable`

**Why initializer:** USDC address differs per chain. Constructor args change init_code hash → different CREATE2 addresses. With UUPS, the **implementation** has no constructor args (identical bytecode), and each **proxy** is initialized with chain-specific USDC.

**Storage:**
- `IERC20 public usdc` — set via initialize (NOT immutable)
- Owner via OwnableUpgradeable

**Functions:**
| Function | Access | Description |
|----------|--------|-------------|
| `initialize(address _usdc, address _owner)` | Initializer | Sets USDC and owner |
| `settle(address recipient, uint256 destChainId, uint256 amount, bytes note)` | Any user | `transferFrom(msg.sender, this, amount)`, emits event |
| `settleWithPermit(sender, recipient, destChainId, amount, note, deadline, v, r, s)` | Any (relayer) | EIP-2612 permit + transferFrom in one call |
| `withdraw(address token, address to, uint256 amount)` | Owner only | Relayer withdraws to bridge via CCTP |
| `_authorizeUpgrade(address)` | Owner only | UUPS upgrade auth |

**Events:**
```solidity
event SettlementInitiated(address indexed sender, address indexed recipient, uint256 indexed destChainId, uint256 amount, bytes note);
```

## Step 12: khaaliSplitSettlement Tests

**File:** `test/khaaliSplitSettlement.t.sol`
**Helper:** `test/helpers/MockUSDC.sol` — ERC20 + ERC20Permit with `mint()` and 6 decimals

Tests:
- Initialize sets state; double-initialize reverts
- `settle` transfers USDC, emits event; insufficient allowance reverts
- `settleWithPermit` with valid permit signature (constructed via `vm.sign()`)
- `withdraw` by owner; non-owner reverts
- Upgrade authorization (onlyOwner)

> **Git:** Commit: `"feat: add khaaliSplitSettlement contract, MockUSDC, and tests"`

---

## Step 13: kdioDeployer.sol

**Purpose:** Custom CREATE2 deployer that deploys UUPS proxy contracts at deterministic addresses across chains.

**How it works:**
- Uses `CREATE2` (via Solidity `new Contract{salt: ...}()`) to deploy ERC1967Proxy instances
- Since all UUPS proxies use the same ERC1967Proxy bytecode (no constructor args in implementation), the proxy addresses are deterministic
- The implementation contract is deployed first (can be at any address), then the proxy is deployed via CREATE2 pointing to that implementation
- `initialize()` is called on the proxy post-deployment with chain-specific params

**Functions:**
| Function | Access | Description |
|----------|--------|-------------|
| `deploy(bytes32 salt, address implementation, bytes initData)` | Anyone | Deploys ERC1967Proxy via CREATE2, calls initialize via initData |
| `computeAddress(bytes32 salt, address implementation, bytes initData)` | View | Predicts the proxy address |

**Key detail:** The ERC1967Proxy constructor takes `(address implementation, bytes data)`. The `data` (initData) is part of the constructor args and WILL affect the CREATE2 address. To get truly deterministic addresses, we need the initData to be empty at deploy time, then call initialize separately. OR we accept that different chains will have different proxy addresses (since initData differs).

**Recommended approach for Settlement:** Deploy the implementation at any address, then deploy the proxy via CREATE2 with empty initData, then call `initialize()` separately. This way proxy bytecode+args are identical across chains.

## Step 14: kdioDeployer Tests

**File:** `test/kdioDeployer.t.sol`

Tests:
- Deploy contract via CREATE2 and verify address matches `computeAddress`
- Same salt + same bytecode → same address
- Deploy + initialize in sequence
- Cannot deploy to same address twice (CREATE2 collision reverts)

> **Git:** Commit: `"feat: add kdioDeployer CREATE2 factory and tests"`

---

## Step 15: Deployment Scripts (scripts only — NOT executed)

### `script/DeployCore.s.sol` — Sepolia
Uses kdioDeployer to deploy all core contracts:
1. Deploy implementations: khaaliSplitFriends, khaaliSplitGroups, khaaliSplitExpenses, khaaliSplitResolver
2. Deploy proxies via kdioDeployer with CREATE2
3. Initialize each proxy with appropriate params

Reads env vars: `BACKEND_ADDRESS`, `GATEWAY_URL`, `GATEWAY_SIGNER`, `DEPLOYER_PRIVATE_KEY`

### `script/DeploySettlement.s.sol` — Multi-chain
1. Deploy khaaliSplitSettlement implementation
2. Deploy proxy via kdioDeployer with CREATE2 (empty initData for determinism)
3. Call `initialize(_usdc, _owner)` on proxy

Reads env vars: `USDC_ADDRESS`, `SETTLEMENT_OWNER`, `DEPLOYER_PRIVATE_KEY`

### README additions
Add deployment commands to README.md:
```bash
# Sepolia core contracts
forge script script/DeployCore.s.sol:DeployCore --rpc-url sepolia --broadcast --verify

# Settlement on each chain
USDC_ADDRESS=0x... forge script script/DeploySettlement.s.sol --rpc-url sepolia --broadcast
USDC_ADDRESS=0x... forge script script/DeploySettlement.s.sol --rpc-url arc_testnet --broadcast
USDC_ADDRESS=0x... forge script script/DeploySettlement.s.sol --rpc-url base --broadcast
USDC_ADDRESS=0x... forge script script/DeploySettlement.s.sol --rpc-url arbitrum --broadcast
```

> **Git:** Commit: `"feat: add deployment scripts and update README"`

---

## Implementation Order

| Step | Task | Depends On | Git Commit |
|------|------|-----------|------------|
| 0 | Add plan to repo | — | `docs: add contract implementation plan` |
| 1 | Foundry scaffolding + deps + foundry.toml | 0 | `chore: scaffold foundry project with dependencies` |
| 2 | Interfaces | 1 | `feat: add khaaliSplit interfaces` |
| 3-4 | khaaliSplitFriends.sol + tests | 2 | `feat: add khaaliSplitFriends contract and tests` |
| 5-6 | khaaliSplitGroups.sol + tests | 3 | `feat: add khaaliSplitGroups contract and tests` |
| 7-8 | khaaliSplitExpenses.sol + tests | 5 | `feat: add khaaliSplitExpenses contract and tests` |
| 9-10 | khaaliSplitResolver.sol + tests | 1 | `feat: add khaaliSplitResolver contract and tests` |
| 11-12 | khaaliSplitSettlement.sol + MockUSDC + tests | 1 | `feat: add khaaliSplitSettlement contract, MockUSDC, and tests` |
| 13-14 | kdioDeployer.sol + tests | 1 | `feat: add kdioDeployer CREATE2 factory and tests` |
| 15 | Deployment scripts + README update | All | `feat: add deployment scripts and update README` |

> Steps 3-8 (social graph), 9-10 (resolver), 11-12 (settlement), and 13-14 (deployer) are independent branches.

## Verification

1. `forge build` — all contracts compile cleanly
2. `forge test -vvv` — all tests pass
3. `forge test --gas-report` — key ops under reasonable gas limits
4. CREATE2 determinism verified in kdioDeployer tests
5. UUPS upgrade tests pass for all contracts
6. Fork tests against Sepolia: `forge test --fork-url $SEPOLIA_RPC_URL`

## Key Risks

| Risk | Mitigation |
|------|-----------|
| ERC1967Proxy constructor args affect CREATE2 address | Deploy proxy with empty initData, call initialize separately |
| OZ upgradeable storage layout conflicts | Follow OZ storage gap pattern; use `@openzeppelin/contracts-upgradeable` consistently |
| ens-contracts import paths vary by version | Pin forge install to specific commit if needed |
| CREATE2 factory not on Arc Testnet | kdioDeployer is self-contained; just deploy it first |
| Unbounded arrays (_friendsList, _memberList) | Acceptable for hackathon; production uses indexer |
