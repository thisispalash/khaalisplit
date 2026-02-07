# khaaliSplit: Settlement + Subnames + Reputation Implementation Plan

## Overview

Three major contract changes:
1. **Settlement** — Remove relayer, integrate CCTP V2 directly, add Gateway opt-in
2. **Subnames** — New on-chain ENS subname registrar with ERC-1155 + on-chain text records (replaces CCIP-Read resolver)
3. **Reputation** — New on-chain reputation contract, syncs to ENS text records automatically

All contracts: Solidity ^0.8.22, UUPS upgradeable, deployed via `kdioDeployer` CREATE2.

Base path: `/Users/thisispalash/local/___2026-final/hacks/hackmoney2026/src/contracts/contracts/`

### Approved Chains & Token Policy

**Only approved token: USDC** (EURC and other tokens removed from config).

**Approved chains only:**

| Chain | Chain ID | USDC Address | CCTP Domain |
|-------|----------|-------------|-------------|
| Sepolia | 11155111 | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` | 0 |
| Base Sepolia | 84532 | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | 6 |
| Arc Testnet | 1397 | `0x3600000000000000000000000000000000000000` | N/A (no CCTP) |
| Ethereum Mainnet | 1 | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | 0 |
| Base Mainnet | 8453 | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 6 |

**CCTP TokenMessengerV2 addresses:**
- Testnet: `0x8fe6b999dc680ccfdd5bf7eb0974218be2542daa`
- Mainnet: `0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d`

**Circle Gateway Wallet addresses:**
- Testnet: `0x0077777d7EBA4688BDeF3E311b846F25870A19B9`
- Mainnet: TBD (uses `0x7777777` prefix — verify on Etherscan before mainnet deploy)

**`script/tokens.json` must be rewritten** to reflect this (USDC only, approved chains only).

---

## Implementation Order

```
1. Interfaces (all 5 new interface files)
2. khaaliSplitSettlement.sol (rewrite — standalone, depends only on CCTP interface)
3. khaaliSplitSubnames.sol (new — depends on NameWrapper interface)
4. khaaliSplitReputation.sol (new — depends on IkhaaliSplitSubnames)
5. Mock helpers for tests
6. Tests for all 3 contracts
7. Deployment scripts
8. Deprecation note on old resolver
```

---

## Change 1: Settlement — Direct CCTP + Gateway

### Files

| Action | File |
|--------|------|
| CREATE | `src/interfaces/IkhaaliSplitSettlement.sol` |
| CREATE | `src/interfaces/ITokenMessengerV2.sol` |
| REWRITE | `src/khaaliSplitSettlement.sol` |
| REWRITE | `test/khaaliSplitSettlement.t.sol` |
| CREATE | `test/helpers/MockTokenMessengerV2.sol` |
| CREATE | `script/cctp.json` |
| REWRITE | `script/tokens.json` (USDC only, approved chains only) |
| MODIFY | `script/DeploySettlement.s.sol` |

### `ITokenMessengerV2.sol` — Minimal CCTP interface

```solidity
interface ITokenMessengerV2 {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 nonce);
}
```

### `khaaliSplitSettlement.sol` — Storage

| Variable | Type | Description |
|----------|------|-------------|
| `allowedTokens` | `mapping(address => bool)` | Preserved |
| `tokenMessenger` | `ITokenMessengerV2` | CCTP TokenMessengerV2 address |
| `chainIdToDomain` | `mapping(uint256 => uint32)` | EVM chain ID → CCTP domain |
| `domainConfigured` | `mapping(uint256 => bool)` | Whether domain is set |
| `gatewayWallet` | `address` | Circle Gateway wallet (optional) |

### Key Design

- **`initialize(address _owner)`** — Signature UNCHANGED (preserves CREATE2 determinism with empty init data). CCTP config via post-init setters.
- **`settle()`** — Pulls tokens, then:
  - Same chain (`destChainId == block.chainid`): direct `safeTransfer` to recipient
  - Cross chain: `forceApprove(tokenMessenger, amount)` → `depositForBurn(amount, domain, bytes32(recipient), token)`
- **`settleWithPermit()`** — EIP-2612 permit, then same logic as settle
- **`settleViaGateway(token, amount, note)`** — Separate function. Transfers tokens to `gatewayWallet`. Backend handles BurnIntent off-chain.
- **`settleViaGatewayWithPermit(...)`** — Gasless variant
- **`withdraw()` REMOVED** — No more relayer custody
- **Internal `_executeSettlement()`** — Shared logic for settle + settleWithPermit
- **Internal `_executeGatewaySettlement()`** — Shared logic for gateway variants

### Events

- `SettlementInitiated` (preserved, still emitted for indexing)
- `SameChainSettlement(sender, recipient, token, amount)`
- `GatewaySettlement(sender, recipient, token, amount)`
- `DomainConfigured(chainId, domain)`
- `TokenMessengerUpdated(tokenMessenger)`
- `GatewayWalletUpdated(gatewayWallet)`

### Admin Functions (owner only)

- `addToken()` / `removeToken()` (preserved)
- `setTokenMessenger(address)`
- `configureDomain(uint256 chainId, uint32 domain)`
- `setGatewayWallet(address)`

### CCTP Config (`script/cctp.json`)

```json
{
  "testnet": {
    "tokenMessenger": "0x8fe6b999dc680ccfdd5bf7eb0974218be2542daa",
    "gatewayWallet": "0x0077777d7EBA4688BDeF3E311b846F25870A19B9",
    "domains": {
      "11155111": 0,
      "84532": 6
    }
  },
  "mainnet": {
    "tokenMessenger": "0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d",
    "gatewayWallet": "0x0000000000000000000000000000000000000000",
    "domains": {
      "1": 0,
      "8453": 6
    }
  }
}
```

Note: Arc Testnet (chain ID 1397) does NOT support CCTP — settlements to/from Arc use Gateway or same-chain transfer only.

### Updated `script/tokens.json` (USDC only, approved chains only)

```json
{
  "11155111": {
    "name": "sepolia",
    "tokens": {
      "USDC": "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
    }
  },
  "84532": {
    "name": "baseSepolia",
    "tokens": {
      "USDC": "0x036CbD53842c5426634e7929541eC2318f3dCF7e"
    }
  },
  "1397": {
    "name": "arc_testnet",
    "tokens": {
      "USDC": "0x3600000000000000000000000000000000000000"
    }
  },
  "1": {
    "name": "ethereum",
    "tokens": {
      "USDC": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    }
  },
  "8453": {
    "name": "base",
    "tokens": {
      "USDC": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
    }
  }
}
```

Removed: Arbitrum Sepolia, Avalanche Fuji, Optimism Sepolia, and all EURC entries.

Note: The `DeploySettlement.s.sol` script currently reads EURC keys from tokens.json. The EURC parsing logic should be removed; only USDC should be read and added via `addToken()`.

### DeploySettlement.s.sol Changes

After `proxy.initialize(ownerAddress)` and `addToken()` calls, add:
- Read `script/cctp.json` for TokenMessenger address and domain mappings
- Call `proxy.setTokenMessenger(tokenMessengerAddress)`
- Loop through domain config: `proxy.configureDomain(chainId, domain)` for each pair
- Optionally: `proxy.setGatewayWallet(gatewayWalletAddress)`

---

## Change 2: ENS Subnames — On-Chain Registrar + Resolver

### Files

| Action | File |
|--------|------|
| CREATE | `src/interfaces/INameWrapperMinimal.sol` |
| CREATE | `src/interfaces/IkhaaliSplitSubnames.sol` |
| CREATE | `src/khaaliSplitSubnames.sol` |
| CREATE | `test/khaaliSplitSubnames.t.sol` |
| CREATE | `test/helpers/MockNameWrapper.sol` |
| MODIFY | `src/khaaliSplitResolver.sol` (add deprecation NatSpec) |

### `INameWrapperMinimal.sol` — Local minimal interface

Avoids importing full ENS `INameWrapper.sol` (which is in `deny_paths` and has transitive deps). Only the functions we call:

```solidity
interface INameWrapperMinimal {
    function setSubnodeRecord(
        bytes32 parentNode, string calldata label, address owner,
        address resolver, uint64 ttl, uint32 fuses, uint64 expiry
    ) external returns (bytes32);
    function ownerOf(uint256 id) external view returns (address);
}
```

### `khaaliSplitSubnames.sol` — Storage

| Variable | Type | Description |
|----------|------|-------------|
| `nameWrapper` | `INameWrapperMinimal` | NameWrapper contract reference |
| `parentNode` | `bytes32` | `namehash("khaalisplit.eth")` |
| `backend` | `address` | Authorized to register + set records |
| `_addresses` | `mapping(bytes32 => address)` | addr() records |
| `_texts` | `mapping(bytes32 => mapping(string => string))` | text() records |
| `reputationContract` | `address` | Authorized to call setText for reputation syncing |

### Key Design

- **`initialize(address _nameWrapper, bytes32 _parentNode, address _backend, address _owner)`**
- **`register(string label, address owner)`** — Backend only. Calls `nameWrapper.setSubnodeRecord(parentNode, label, owner, address(this), 0, 0, type(uint64).max)`. No fuses burned for now (per user request — fuses deferred to later iteration). Sets default text records + addr.
- **`setText(bytes32 node, string key, string value)`** — Authorized callers: subname owner (via NameWrapper.ownerOf), backend, or reputationContract.
- **`setAddr(bytes32 node, address _addr)`** — Same authorization.
- **`text(bytes32 node, string key)`** — Public view, returns on-chain stored text record.
- **`addr(bytes32 node)`** — Public view, returns stored address.
- **`subnameNode(string label)`** — Pure utility: `keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))))`
- **`supportsInterface()`** — Returns true for `IAddrResolver` (0x3b3b57de), `ITextResolver` (0x59d1d43c), `IERC165` (0x01ffc9a7)

### Authorization Logic

```solidity
function _isAuthorized(bytes32 node, address caller) internal view returns (bool) {
    if (caller == backend) return true;
    if (caller == reputationContract) return true;
    try nameWrapper.ownerOf(uint256(node)) returns (address owner) {
        return caller == owner;
    } catch {
        return false;
    }
}
```

### Text Records (on-chain, readable by any contract or frontend)

On `register()`, these defaults are set:
- `com.khaalisplit.subname` = label
- `com.khaalisplit.reputation` = "50"

User can later set: `display`, `avatar`, `description`, `com.khaalisplit.payment.chain`, `com.khaalisplit.payment.token`, etc.

### Fuse Note

Per user decision: **No fuses burned for now** (pass `0` for fuses in `setSubnodeRecord`). This means the parent retains control. Fuse configuration will be added in a later iteration.

### Deprecation of old Resolver

Add NatSpec deprecation notice to `khaaliSplitResolver.sol`:
```
@notice DEPRECATED — This contract is no longer actively used.
         Replaced by khaaliSplitSubnames.sol which provides on-chain
         subname registration + text records via ENS NameWrapper.
         Kept for reference only.
```

---

## Change 3: Reputation — On-Chain Scoring

### Files

| Action | File |
|--------|------|
| CREATE | `src/interfaces/IkhaaliSplitReputation.sol` |
| CREATE | `src/khaaliSplitReputation.sol` |
| CREATE | `test/khaaliSplitReputation.t.sol` |
| CREATE | `test/helpers/MockSubnames.sol` |

### `khaaliSplitReputation.sol` — Storage

| Variable | Type | Description |
|----------|------|-------------|
| `backend` | `address` | Authorized backend/relayer |
| `subnameRegistry` | `IkhaaliSplitSubnames` | For ENS text record updates |
| `scores` | `mapping(address => uint256)` | Reputation scores |
| `_initialized` | `mapping(address => bool)` | Track first interaction |
| `userNodes` | `mapping(address => bytes32)` | User → ENS subname node |

### Constants

```
DEFAULT_SCORE = 50
MAX_SCORE = 100
MIN_SCORE = 0
SUCCESS_DELTA = 1
FAILURE_DELTA = 5
```

### Key Design

- **`initialize(address _backend, address _subnameRegistry, address _owner)`**
- **`recordSettlement(address user, bool success)`** — Backend only:
  1. Auto-initialize to 50 on first call
  2. Success: `score = min(score + 1, 100)`
  3. Failure: `score = score > 5 ? score - 5 : 0`
  4. Emit `ReputationUpdated(user, newScore, wasSuccess)`
  5. If `userNodes[user] != 0` && `subnameRegistry != 0`: call `subnameRegistry.setText(node, "com.khaalisplit.reputation", Strings.toString(score))`
- **`setUserNode(address user, bytes32 node)`** — Backend only. Called after user registers ENS subname.
- **`getReputation(address user)`** — Returns `DEFAULT_SCORE` if uninitialized, else stored score.
- Uses OZ `Strings.toString()` for uint→string conversion.

### Events

- `ReputationUpdated(address indexed user, uint256 newScore, bool wasSuccess)`
- `UserNodeSet(address indexed user, bytes32 indexed node)`

---

## Deployment Script Changes

### `DeployCore.s.sol` — Updated

**Deployment order:**
1. `kdioDeployer` factory
2. `khaaliSplitFriends` impl + proxy (unchanged)
3. `khaaliSplitGroups` impl + proxy (unchanged)
4. `khaaliSplitExpenses` impl + proxy (unchanged)
5. `khaaliSplitSubnames` impl + proxy — init: `(nameWrapperAddr, parentNode, backendAddr, ownerAddr)`
6. `khaaliSplitReputation` impl + proxy — init: `(backendAddr, subnamesProxy, ownerAddr)`
7. Wire: `subnames.setReputationContract(reputationProxy)` (owner call)

**Env vars changed:**
- Remove: `GATEWAY_URL`, `GATEWAY_SIGNER`
- Add: `NAME_WRAPPER_ADDRESS`, `PARENT_NODE`

### `DeploySettlement.s.sol` — Updated

After existing init + addToken calls, add CCTP config from `script/cctp.json`:
- `setTokenMessenger()`
- `configureDomain()` for each chain pair
- `setGatewayWallet()` (optional)

---

## Test Strategy

### MockTokenMessengerV2 (new helper)
- Implements `depositForBurn()`, pulls tokens from caller, records call params
- Lets tests assert CCTP was called with correct args

### MockNameWrapper (new helper)
- Implements `setSubnodeRecord()`, tracks subnode ownership
- Implements `ownerOf()` for authorization tests

### MockSubnames (new helper)
- Implements `setText()`, records calls for assertion
- Used by reputation tests to verify ENS sync

### Test Counts (approximate)

| Contract | Test Cases |
|----------|-----------|
| Settlement | ~25 tests: init, token mgmt, CCTP config, same-chain settle, cross-chain settle, permit variants, gateway variants, validations, upgrade |
| Subnames | ~20 tests: init, register, text records (owner/backend/reputation auth), addr records, ERC-165, admin, upgrade |
| Reputation | ~18 tests: init, score queries, increment/decrement/cap/floor, ENS sync, user nodes, admin, upgrade |

### Integration Test (`UserFlows.t.sol`)

Update existing settlement flow to use MockTokenMessengerV2 + new settlement pattern. Add new flow: registration → reputation update → ENS text record verification.

---

## Files Summary

### CREATE (13 files)

1. `src/interfaces/IkhaaliSplitSettlement.sol`
2. `src/interfaces/ITokenMessengerV2.sol`
3. `src/interfaces/IkhaaliSplitSubnames.sol`
4. `src/interfaces/INameWrapperMinimal.sol`
5. `src/interfaces/IkhaaliSplitReputation.sol`
6. `src/khaaliSplitSubnames.sol`
7. `src/khaaliSplitReputation.sol`
8. `test/khaaliSplitSubnames.t.sol`
9. `test/khaaliSplitReputation.t.sol`
10. `test/helpers/MockTokenMessengerV2.sol`
11. `test/helpers/MockNameWrapper.sol`
12. `test/helpers/MockSubnames.sol`
13. `script/cctp.json`

### REWRITE (3 files)

14. `src/khaaliSplitSettlement.sol`
15. `test/khaaliSplitSettlement.t.sol`
16. `script/tokens.json` — USDC only, approved chains only (Sepolia, Base Sepolia, Arc Testnet, Ethereum Mainnet, Base Mainnet)

### MODIFY (4 files)

17. `script/DeployCore.s.sol` — Replace resolver with subnames + reputation
18. `script/DeploySettlement.s.sol` — Add CCTP config post-init
19. `test/integration/UserFlows.t.sol` — Update settlement + add reputation flow
20. `src/khaaliSplitResolver.sol` — Add deprecation NatSpec notice

---

## Verification

1. **Compile**: `forge build` — all contracts compile with no errors
2. **Unit tests**: `forge test` — all new + rewritten tests pass
3. **Gas check**: `forge test --gas-report` — verify settlement + reputation gas costs are reasonable
4. **Integration**: Run `UserFlows.t.sol` end-to-end
5. **Deployment dry-run**: `forge script script/DeployCore.s.sol --rpc-url sepolia` (no --broadcast) to verify script logic
6. **Deployment dry-run**: `forge script script/DeploySettlement.s.sol --rpc-url sepolia` (no --broadcast)
