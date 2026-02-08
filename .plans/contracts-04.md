# khaaliSplit: Settlement V2 — Gateway Minting + bytes32 Node Refactor

## Overview

Two changes to the settlement contract:

1. **`settleFromGateway`** — New function for settling from a Gateway balance. Atomically calls `gatewayMinter.gatewayMint()` to mint USDC into the settlement contract, then routes to recipient + updates reputation. Enables paying from a unified Gateway USDC balance while preserving the on-chain reputation flow.

2. **`bytes32 recipientNode` refactor** — Replace `address recipient` with `bytes32 recipientNode` as the primary parameter in all settlement functions. The contract reads the recipient's wallet address from the subname registry via `addr(node)` instead of looking up the node via `addressToNode(address)`. This is more natural (the ENS node is the canonical identifier), more efficient (avoids the reverse lookup), and sets up cleanly for future flows.

**Branch:** `contracts-settlement` (continues from contracts-03 settlement work)
**Worktree:** `src/contracts-settlement/`

---

## Background: Gateway Architecture

### Key Contracts (same address on all chains, deployed via CREATE2)

| Contract | Address | Role |
|----------|---------|------|
| GatewayWallet | `0x0077777d7EBA4688BDeF3E311b846F25870A19B9` | Holds deposited USDC, manages Gateway balances |
| GatewayMinter | `0x0022222ABE238Cc2C7Bb1f21003F0a260052475B` | Mints USDC on destination chain from attestation |

### Gateway Transfer Flow

```
1. User signs a BurnIntent (EIP-712) off-chain
   - destinationRecipient = settlement contract address (CREATE2, same on all chains)
   - destinationCaller = 0x00 (anyone can submit) or relayer address
   - hookData = 0x (not auto-executed by Gateway — we handle routing ourselves)

2. Backend submits signed BurnIntent to Circle API:
   POST https://gateway-api.circle.com/v1/transfer
   → receives attestationPayload + attestationSignature (valid 10 minutes)

3. Backend calls settlement.settleFromGateway(attestation, sig, recipientNode, memo)
   → contract calls gatewayMinter.gatewayMint() → USDC minted to settlement contract
   → contract routes USDC to recipient via Gateway/CCTP (same as settleWithAuthorization)
   → contract updates sender reputation
   → emits SettlementCompleted
   → all atomic — if routing/reputation reverts, the mint reverts too
```

### BurnIntent Structure (EIP-712)

```solidity
struct TransferSpec {
    uint32 version;             // 1
    uint32 sourceDomain;        // source chain CCTP domain
    uint32 destinationDomain;   // destination chain CCTP domain
    bytes32 sourceContract;     // GatewayWallet address (padded)
    bytes32 destinationContract;// GatewayMinter address (padded)
    bytes32 sourceToken;        // USDC on source chain (padded)
    bytes32 destinationToken;   // USDC on destination chain (padded)
    bytes32 sourceDepositor;    // sender's address (padded)
    bytes32 destinationRecipient; // settlement contract address (padded)
    bytes32 sourceSigner;       // sender's EOA (padded)
    bytes32 destinationCaller;  // 0x00 or relayer address (padded)
    uint256 value;              // USDC amount
    bytes32 salt;               // random nonce for replay protection
    bytes hookData;             // arbitrary — not executed by Gateway
}

struct BurnIntent {
    uint256 maxBlockHeight;     // expiration block
    uint256 maxFee;             // max fee sender will pay
    TransferSpec spec;          // the transfer spec above
}
```

### Key Insight: hookData is NOT auto-executed

The GatewayMinter's `gatewayMint` function does exactly one thing: mint USDC to `destinationRecipient`. It does NOT read hookData, does NOT call back into the recipient, does NOT execute any post-mint logic. hookData is opaque metadata included in the TransferSpec hash for integrity. Our settlement contract handles all post-mint logic itself.

---

## Change 1: `settleFromGateway`

### New Interface: `IGatewayMinter`

```solidity
interface IGatewayMinter {
    function gatewayMint(
        bytes memory attestationPayload,
        bytes memory signature
    ) external;
}
```

Minimal interface — we only need `gatewayMint`.

### New Function on `khaaliSplitSettlement`

```solidity
function settleFromGateway(
    bytes calldata attestationPayload,
    bytes calldata attestationSignature,
    bytes32 recipientNode,
    bytes calldata memo
) external {
    // 1. Record USDC balance before mint
    address token = _resolveToken(recipientNode);
    if (!allowedTokens[token]) revert TokenNotAllowed(token);
    uint256 balanceBefore = IERC20(token).balanceOf(address(this));

    // 2. Call gatewayMint — USDC is minted to this contract
    gatewayMinter.gatewayMint(attestationPayload, attestationSignature);

    // 3. Calculate actual minted amount (after fees)
    uint256 balanceAfter = IERC20(token).balanceOf(address(this));
    uint256 amount = balanceAfter - balanceBefore;
    if (amount == 0) revert ZeroAmount();

    // 4. Resolve recipient address from ENS node
    address recipient = subnameRegistry.addr(recipientNode);
    if (recipient == address(0)) revert RecipientNotRegistered(recipient);

    // 5. Route settlement (same logic as settleWithAuthorization)
    _routeSettlement(recipientNode, recipient, token, amount);

    // 6. Extract sender from attestation for reputation
    //    sourceDepositor is at a known offset in the attestation payload
    address sender = _extractSenderFromAttestation(attestationPayload);

    // 7. Update reputation
    uint256 senderReputation = _updateReputation(sender);

    // 8. Emit event
    emit SettlementCompleted(sender, recipient, token, amount, senderReputation, memo);
}
```

### New Storage

```solidity
IGatewayMinter public gatewayMinter;
```

### New Admin Setter

```solidity
function setGatewayMinter(address _gatewayMinter) external onlyOwner {
    gatewayMinter = IGatewayMinter(_gatewayMinter);
    emit GatewayMinterUpdated(_gatewayMinter);
}
```

### Sender Extraction from Attestation

The `sourceDepositor` field is at a known byte offset in the TransferSpec portion of the attestation payload. We need to determine the exact offset by inspecting the attestation encoding format.

Two approaches:

**Option A: Offset-based extraction (gas efficient)**
```solidity
function _extractSenderFromAttestation(bytes calldata attestation) internal pure returns (address) {
    // Extract sourceDepositor at known offset, convert bytes32 → address
    bytes32 depositor = bytes32(attestation[OFFSET:OFFSET+32]);
    return address(uint160(uint256(depositor)));
}
```

**Option B: Pass sender as parameter + validate (simpler, hackathon-appropriate)**
```solidity
function settleFromGateway(
    bytes calldata attestationPayload,
    bytes calldata attestationSignature,
    bytes32 recipientNode,
    address sender,        // passed explicitly
    bytes calldata memo
) external { ... }
```

Since the attestation is verified by Circle's GatewayMinter (signature check), and the minted USDC amount is verified by our balance check, the sender parameter is informational (used for reputation only). If someone lies about `sender`, they'd only be updating the wrong person's reputation — the USDC routing is unaffected.

**Recommendation: Option B for the hackathon.** Simpler, no offset math, and the sender is verified off-chain by Circle's attestation system. We can add on-chain attestation parsing later.

### Config Updates

**`script/cctp.json`** — Add GatewayMinter addresses:
```json
{
  "gatewayMinter": {
    "testnet": "0x0022222ABE238Cc2C7Bb1f21003F0a260052475B",
    "mainnet": "0x0022222ABE238Cc2C7Bb1f21003F0a260052475B"
  }
}
```

Note: Same address on testnet and mainnet (CREATE2 deterministic).

**`script/DeploySettlement.s.sol`** — Add `setGatewayMinter()` call after init.

---

## Change 2: `bytes32 recipientNode` Refactor

### What Changes

Replace `address recipient` with `bytes32 recipientNode` as the primary parameter in the public API.

The contract resolves the wallet address internally: `subnameRegistry.addr(recipientNode)`.

### Why

- The ENS node is the canonical identifier in our system — addresses can change (via `setAddr`), but the node is permanent
- Eliminates the `addressToNode` reverse lookup mapping (added in contracts-03)
- More natural for the client — the client already knows the subname and can compute the namehash trivially
- Consistent with the Gateway flow where `recipientNode` is already the natural parameter

### `settleWithAuthorization` — Updated Signature

```solidity
function settleWithAuthorization(
    bytes32 recipientNode,     // was: address recipient
    uint256 amount,
    bytes calldata memo,
    Authorization calldata auth,
    bytes calldata signature
) external
```

Internally:
```solidity
address recipient = subnameRegistry.addr(recipientNode);
if (recipient == address(0)) revert RecipientNotRegistered(recipientNode);
```

### `settle` stub — Updated Signature

```solidity
function settle(bytes32, uint256, bytes calldata) external pure {
    revert NotImplemented();
}
```

### Error Update

```solidity
error RecipientNotRegistered(bytes32 node);  // was: RecipientNotRegistered(address)
```

### Interface Update

`IkhaaliSplitSettlement.sol` — Update all function signatures to use `bytes32 recipientNode`.

### Subnames Contract: Revert `addressToNode`

The `addressToNode` mapping added in contracts-03 (`2244ec0`) is no longer needed. Remove:
- `mapping(address => bytes32) public addressToNode` from `khaaliSplitSubnames.sol`
- `addressToNode[owner] = node` from `register()`
- `addressToNode(address) returns (bytes32)` from `IkhaaliSplitSubnames.sol`

### Subnames Contract: Confirm `addr(bytes32)` exists

The subnames contract already has `addr(bytes32 node) external view returns (address)` — this is the forward lookup we need. Verify this is in the interface as well.

---

## Files

| Action | File | Description |
|--------|------|-------------|
| CREATE | `src/interfaces/IGatewayMinter.sol` | Minimal GatewayMinter interface |
| MODIFY | `src/interfaces/IkhaaliSplitSettlement.sol` | `bytes32 recipientNode` params, add `settleFromGateway`, add `setGatewayMinter` |
| MODIFY | `src/interfaces/IkhaaliSplitSubnames.sol` | Remove `addressToNode` |
| MODIFY | `src/khaaliSplitSettlement.sol` | `bytes32 recipientNode` refactor, add `settleFromGateway`, add `gatewayMinter` storage/setter |
| MODIFY | `src/khaaliSplitSubnames.sol` | Remove `addressToNode` mapping |
| MODIFY | `test/khaaliSplitSettlement.t.sol` | Update all tests for `bytes32 recipientNode`, add `settleFromGateway` tests |
| CREATE | `test/helpers/MockGatewayMinter.sol` | Mock that mints tokens to caller (simulates `gatewayMint`) |
| MODIFY | `test/khaaliSplitSubnames.t.sol` | Remove `addressToNode` tests |
| MODIFY | `script/cctp.json` | Add `gatewayMinter` addresses |
| MODIFY | `script/DeploySettlement.s.sol` | Add `setGatewayMinter()` call |

---

## Implementation Order

```
1. Remove addressToNode from subnames contract + interface + tests
2. Create IGatewayMinter interface
3. Update IkhaaliSplitSettlement interface (bytes32 recipientNode + settleFromGateway)
4. Update khaaliSplitSettlement.sol (both changes)
5. Create MockGatewayMinter
6. Update settlement tests (bytes32 refactor + new settleFromGateway tests)
7. Update cctp.json + DeploySettlement.s.sol
8. forge build + forge test
```

---

## Test Plan

### Existing Tests — Updated for `bytes32 recipientNode`

All 52 existing settlement tests need parameter changes:
- `address recipient` → `bytes32 recipientNode` in all calls
- Internal mock setup: register subname, use node instead of address
- Validation tests: `RecipientNotRegistered(bytes32)` instead of `RecipientNotRegistered(address)`

### New Tests — `settleFromGateway`

| Test | Description |
|------|-------------|
| `test_gatewayMint_success` | Full flow: mock mint → route via gateway → reputation → event |
| `test_gatewayMint_routesViaCCTP` | Recipient has `flow=cctp` → routes through CCTP after mint |
| `test_gatewayMint_emitsEvent` | Verify SettlementCompleted event with correct fields |
| `test_gatewayMint_updatesReputation` | Verify sender reputation updated after mint |
| `test_gatewayMint_reputationNotSet_emits500` | Reputation contract not configured → 500 sentinel |
| `test_gatewayMint_revertsIfMinterNotSet` | `gatewayMinter == address(0)` → revert |
| `test_gatewayMint_revertsIfMintFails` | Mock minter reverts → entire tx reverts |
| `test_gatewayMint_revertsIfZeroMinted` | Mint produces 0 tokens → revert ZeroAmount |
| `test_gatewayMint_revertsIfTokenNotAllowed` | Recipient's token not in allowedTokens |
| `test_gatewayMint_revertsIfRecipientNotRegistered` | Node has no addr record → revert |
| `test_gatewayMint_withMemo` | Memo passed through to event |
| `test_gatewayMint_anyoneCanCall` | Non-owner, non-sender can submit |
| `test_setGatewayMinter_success` | Owner sets minter address |
| `test_setGatewayMinter_revertsNotOwner` | Non-owner cannot set |
| `test_setGatewayMinter_allowsZero` | Can disable by setting to address(0) |

### Subname Tests — Removed

- Remove any `test_addressToNode_*` tests
- Remove `addressToNode` assertions from `test_register_*` tests

---

## NFC/Bluetooth UX Implications

Both settlement flows now share the same UX pattern:

| Flow | What the sender signs | What gets transferred | Who calls the contract |
|------|----------------------|----------------------|----------------------|
| **Direct** (EIP-3009) | `receiveWithAuthorization` | Signed auth + signature | Anyone (recipient, sender, backend) |
| **Gateway** (BurnIntent) | `BurnIntent` (EIP-712) | Signed burn intent | Backend (must hit Circle API first) |

The client can differentiate with a `type` field in the NFC/Bluetooth payload:
- `type: "direct"` → EIP-3009 flow → `settleWithAuthorization`
- `type: "gateway"` → BurnIntent flow → backend → Circle API → `settleFromGateway`

---

## Implementation Notes (2026-02-07)

### Change 2: `bytes32 recipientNode` Refactor — COMPLETED

**Commit:** `e0608fa`

**What was done:**
- Removed `addressToNode` mapping from `khaaliSplitSubnames.sol` (storage + register assignment)
- Removed `addressToNode` from `IkhaaliSplitSubnames.sol` interface
- Updated `settle()` stub: `address` → `bytes32` first param
- Updated `settleWithAuthorization()`: `address recipient` → `bytes32 recipientNode`, now resolves wallet address via `subnameRegistry.addr(recipientNode)`
- Updated `RecipientNotRegistered` error: `address` → `bytes32 node`
- Updated `IkhaaliSplitSettlement.sol` to match new signatures
- Updated all 52 settlement tests to pass `BOB_NODE` / `CHARLIE_NODE` instead of `bob` / `charlie`
- Updated `MockSubnamesForSettlement`: removed `addressToNode` mapping, `_registerRecipient` now uses `setAddr(node, recipient)` instead of `setAddressToNode(recipient, node)`
- Updated README: `addressToNode()` → `addr(node)` in subnames description
- No `addressToNode` tests existed in subnames test file (nothing to remove)

**Deviations from plan:** None. The refactor was straightforward.

**Test results:** 250 passing, 0 failed, 1 skipped (old integration test). All 52 settlement tests updated and green.

### Change 1: `settleFromGateway` — COMPLETED

**Commits:**
- `1f20d60` — feat(interfaces): add IGatewayMinter and settleFromGateway to settlement interface
- `c834bc5` — feat(settlement): add settleFromGateway and MockGatewayMinter
- `0397378` — test(settlement): add settleFromGateway and setGatewayMinter tests
- `50e2a26` — feat(deploy): add gatewayMinter to cctp.json and deploy script

**What was done:**
- Created `src/interfaces/IGatewayMinter.sol` — minimal interface with `gatewayMint(bytes, bytes)`
- Updated `IkhaaliSplitSettlement.sol` — added `settleFromGateway` function signature, `setGatewayMinter` admin setter, `GatewayMinterUpdated` event
- Added `IGatewayMinter public gatewayMinter` storage to settlement contract
- Added `setGatewayMinter(address)` admin setter with `GatewayMinterUpdated` event
- Added `GatewayMinterNotSet` error
- Implemented `settleFromGateway(attestationPayload, attestationSignature, recipientNode, sender, memo)` using Option B (sender passed explicitly)
  - Validates recipientNode, subnameRegistry, gatewayMinter up front
  - Resolves token from ENS text records, records balance before mint
  - Calls `gatewayMinter.gatewayMint()` — USDC minted to settlement contract
  - Computes minted amount via `balanceAfter - balanceBefore` (handles Gateway fees)
  - Resolves recipient address from ENS node
  - Routes via `_routeSettlement()` (same Gateway/CCTP logic as settleWithAuthorization)
  - Updates sender reputation, emits SettlementCompleted
- Created `test/helpers/MockGatewayMinter.sol` — mints configurable MockUSDC to msg.sender, with `shouldRevert` and `shouldMintZero` toggles
- Added 15 new `settleFromGateway` tests + 3 `setGatewayMinter` admin tests (18 total new tests)
- Updated `test_initialize_state` to verify `gatewayMinter` field
- Added `gatewayMinter` addresses to `script/cctp.json` (0x0022222ABE238Cc2C7Bb1f21003F0a260052475B, same on testnet/mainnet)
- Updated `script/DeploySettlement.s.sol` to read and configure `gatewayMinter` from cctp.json

**Deviations from plan:**
- Used Option B (sender passed explicitly) as recommended — no attestation byte parsing
- Did not extract a modifier for the `recipientNode == bytes32(0)` / `subnameRegistryNotSet` checks — kept inline for consistency with existing `settleWithAuthorization` style

**Test results:** 268 passing, 0 failed, 1 skipped (old integration test). 70 settlement tests (52 existing + 18 new).

---

## Open Questions

1. **Attestation sender extraction**: Do we pass `sender` explicitly (Option B, recommended for hackathon) or extract from attestation bytes (Option A, production-grade)? Plan assumes Option B.

2. **Fee handling**: Gateway charges fees on transfers. The `balanceAfter - balanceBefore` approach handles this naturally (we route whatever USDC actually arrives). Should we emit the fee amount in the event? Probably not for hackathon.

3. **GatewayMinter on Arc Testnet**: Arc Testnet has no CCTP. Does it have a GatewayMinter? If not, `settleFromGateway` won't work on Arc Testnet. This is fine — Gateway is a cross-chain product, Arc Testnet is a single-chain testnet.
