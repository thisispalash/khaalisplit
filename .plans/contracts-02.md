# khaaliSplit Smart Contracts — Implementation Plan (Phase 2)

> Phase 1 (initial build) is complete — 93/93 tests passing. This plan covers fixes, new features, and integration tests.

## Changes Overview

| # | Change | Contract/File | Priority |
|---|--------|---------------|----------|
| 0 | Copy this plan to repo | `.plans/contracts-02.md` | Setup |
| 1 | Mutual friend request auto-accept | khaaliSplitFriends | High |
| 2 | `removeFriend()` | khaaliSplitFriends | High |
| 3 | `leaveGroup()` | khaaliSplitGroups | High |
| 4 | `updateExpense()` | khaaliSplitExpenses | High |
| 5 | Integration tests (full user flows) | test/integration/ | High |
| 6 | Update README — Encryption section | contracts/README.md | High |

**No new storage variables** — all changes add functions/events/errors on existing mappings. Safe for UUPS upgrades.
**No interface changes** — new functions are user-facing, not cross-contract.

### On Ratcheting

Signal-style double ratchet is listed in the PRD as **Priority 2 (Nice to Have)** and **post-hackathon**. It is NOT needed at the contract level because:
- All encryption/decryption is **client-side** — contracts just store encrypted blobs
- Ratcheting would be implemented in the PWA/frontend, not in Solidity
- The contracts' role is key distribution (storing encrypted group AES keys per member)
- For `leaveGroup()`: we delete the departed member's `encryptedGroupKey` and emit `MemberLeft` — the client can use this event as a signal to rotate the group key, but that logic lives off-chain

---

## Step 0: Copy Plan to Repository

Copy this plan to `/.plans/contracts-02.md` at the project root (alongside the existing `contracts.md` from Phase 1).

> **Git:** `"docs: add phase 2 implementation plan"`

---

## Step 1: Mutual Friend Request Auto-Accept

**File:** `contracts/src/khaaliSplitFriends.sol`

Replace the TODO block (lines 112–118) in `requestFriend()`. Before creating a pending request, check if the reverse request already exists:

```solidity
// If the other party already requested us, auto-accept
if (pendingRequest[friend][msg.sender]) {
    isFriend[friend][msg.sender] = true;
    isFriend[msg.sender][friend] = true;
    _friendsList[friend].push(msg.sender);
    _friendsList[msg.sender].push(friend);
    delete pendingRequest[friend][msg.sender];
    emit FriendAccepted(msg.sender, friend);
    return;
}

pendingRequest[msg.sender][friend] = true;
emit FriendRequested(msg.sender, friend);
```

- Reuses existing `FriendAccepted` event — no new events/errors needed
- Mirrors `acceptFriend()` logic exactly
- `return` prevents falling through to the normal pending-request path

**Tests to add** (`test/khaaliSplitFriends.t.sol`):

| Test | Description |
|------|-------------|
| `test_requestFriend_mutualRequest_autoAccepts` | Bob requests alice, then alice requests bob → auto-accept, both `isFriend` true, pending cleaned up |
| `test_requestFriend_mutualRequest_emitsFriendAccepted` | Emits `FriendAccepted`, NOT `FriendRequested` |
| `test_requestFriend_mutualRequest_thenAlreadyFriends` | After auto-accept, re-requesting reverts `AlreadyFriends` |

> **Git:** `"fix: auto-accept mutual friend requests"`

---

## Step 2: Add `removeFriend()`

**File:** `contracts/src/khaaliSplitFriends.sol`

**New event:**
```solidity
event FriendRemoved(address indexed user, address indexed friend);
```

**New error:**
```solidity
error NotFriends();
```

**New function** (after `acceptFriend`, before Views):
```solidity
function removeFriend(address friend) external {
    if (!isFriend[msg.sender][friend]) revert NotFriends();
    isFriend[msg.sender][friend] = false;
    isFriend[friend][msg.sender] = false;
    emit FriendRemoved(msg.sender, friend);
}
```

- Soft-delete only — does NOT remove from `_friendsList` (O(n) gas). Indexer filters by `isFriend`.
- Does NOT cascade to group memberships.

**Tests to add** (`test/khaaliSplitFriends.t.sol`):

| Test | Description |
|------|-------------|
| `test_removeFriend_success` | Both directions set to false |
| `test_removeFriend_emitsEvent` | Emits `FriendRemoved(alice, bob)` |
| `test_removeFriend_notFriends_reverts` | Revert if not friends |
| `test_removeFriend_canReRequest` | After removal, can request + accept again |
| `test_removeFriend_bothDirections` | Bob removes alice (not just alice removes bob) |

> **Git:** `"feat: add removeFriend to khaaliSplitFriends"`

---

## Step 3: Add `leaveGroup()`

**File:** `contracts/src/khaaliSplitGroups.sol`

**New event:**
```solidity
event MemberLeft(uint256 indexed groupId, address indexed member);
```

**New error:**
```solidity
error CreatorCannotLeave(uint256 groupId);
```

**New function** (after `acceptGroupInvite`, before Views):
```solidity
function leaveGroup(uint256 groupId) external {
    if (!isMember[groupId][msg.sender]) revert NotGroupMember(groupId, msg.sender);
    if (groups[groupId].creator == msg.sender) revert CreatorCannotLeave(groupId);
    isMember[groupId][msg.sender] = false;
    groups[groupId].memberCount--;
    delete encryptedGroupKey[groupId][msg.sender];
    emit MemberLeft(groupId, msg.sender);
}
```

- Soft-delete — does NOT remove from `_memberList`.
- Creator cannot leave (they own the group).
- Clears encrypted group key for the leaving member.

**Tests to add** (`test/khaaliSplitGroups.t.sol`):

| Test | Description |
|------|-------------|
| `test_leaveGroup_success` | `isMember` false, `memberCount` decremented, encrypted key cleared |
| `test_leaveGroup_emitsEvent` | Emits `MemberLeft(groupId, bob)` |
| `test_leaveGroup_creatorCannotLeave` | Creator reverts `CreatorCannotLeave` |
| `test_leaveGroup_notMember_reverts` | Non-member reverts `NotGroupMember` |
| `test_leaveGroup_canBeReinvited` | After leaving, can be re-invited and re-accept |

> **Git:** `"feat: add leaveGroup to khaaliSplitGroups"`

---

## Step 4: Add `updateExpense()`

**File:** `contracts/src/khaaliSplitExpenses.sol`

**New event:**
```solidity
event ExpenseUpdated(
    uint256 indexed groupId,
    uint256 indexed expenseId,
    address indexed creator,
    bytes32 dataHash,
    bytes encryptedData
);
```

**New errors:**
```solidity
error NotExpenseCreator(uint256 expenseId, address user);
error ExpenseDoesNotExist(uint256 expenseId);
```

**New function** (after `addExpense`, before Views):
```solidity
function updateExpense(
    uint256 expenseId,
    bytes32 newDataHash,
    bytes calldata newEncryptedData
) external {
    Expense storage e = expenses[expenseId];
    if (e.creator == address(0)) revert ExpenseDoesNotExist(expenseId);
    if (e.creator != msg.sender) revert NotExpenseCreator(expenseId, msg.sender);
    if (!groupRegistry.isMember(e.groupId, msg.sender)) {
        revert NotGroupMember(e.groupId, msg.sender);
    }
    e.dataHash = newDataHash;
    e.timestamp = block.timestamp;
    emit ExpenseUpdated(e.groupId, expenseId, msg.sender, newDataHash, newEncryptedData);
}
```

- Only the original creator can update (and must still be a group member).
- Updates `dataHash` + `timestamp`. Does NOT change `groupId` or `creator`.
- Encrypted data emitted in event only (same pattern as `addExpense`).

**Tests to add** (`test/khaaliSplitExpenses.t.sol`):

| Test | Description |
|------|-------------|
| `test_updateExpense_success` | Hash + timestamp updated, groupId/creator unchanged |
| `test_updateExpense_emitsEvent` | Emits `ExpenseUpdated` with correct params |
| `test_updateExpense_notCreator_reverts` | Bob can't update alice's expense |
| `test_updateExpense_doesNotExist_reverts` | Non-existent expense ID reverts |
| `test_updateExpense_notGroupMember_reverts` | Creator who left group can't update (depends on Step 3) |

> **Git:** `"feat: add updateExpense to khaaliSplitExpenses"`

---

## Step 5: Integration Tests

**New file:** `contracts/test/integration/UserFlows.t.sol`

Deploys ALL contracts through ERC1967 proxies, wires them together, tests full user flows from the PRD.

### Setup

- Deploy Friends, Groups, Expenses, Settlement proxies
- Deploy MockUSDC, add as allowed token
- Create `alice` (with private key for permit), `bob`, `charlie`

### Test Flows

| Test | Description |
|------|-------------|
| `test_flow_onboarding_friends_group_expense` | Register 3 users → alice-bob friend (request+accept) → alice-charlie friend (mutual request auto-accept) → create group → invite+accept both → add 2 expenses → verify all state |
| `test_flow_settlement_with_permit` | Full setup → alice settles with bob via `settleWithPermit` → verify USDC balances + event |
| `test_flow_leaveGroup_and_updateExpense` | Full setup → charlie leaves group → charlie can't add expense (reverts) → alice updates her expense → verify state |
| `test_flow_removeFriend_no_cascade` | Full setup → alice removes bob as friend → `isFriend` false → bob still group member → bob can still add expenses |
| `test_flow_kdioDeployer_endToEnd` | Deploy all contracts via kdioDeployer → verify deterministic addresses → initialize → register user → create group → add expense |

### Helper functions

```
_deployAll()                    // Deploy + wire all proxies
_registerUsers()                // Register alice, bob, charlie via backend
_makeFriends()                  // alice↔bob (request+accept), alice↔charlie (mutual auto-accept)
_createGroupWithMembers()       // Create group, invite+accept bob+charlie → returns groupId
_buildPermitDigest(...)         // EIP-2612 digest (reused from settlement test)
```

> **Git:** `"test: add integration tests for full user flows"`

---

## Step 6: Update README — Encryption Section

**File:** `contracts/README.md`

Add a new `## Encryption Model` section (after Architecture, before Build & Test) documenting the three-tier encryption approach. Also update `Known Limitations` to reflect the new CRUD operations added in Steps 1–4.

### Encryption Model content:

**Three tiers:**

1. **Friend Pairing (ECDH)** — Wallet ECDH public keys registered on-chain during onboarding (backend recovers from signature via `ecrecover`). Pairwise shared secrets computed client-side: `sharedSecret = ECDH(myPrivKey, theirPubKey)`. Never transmitted.

2. **Group Shared Key (AES-256-GCM)** — Group creator generates a symmetric AES key, encrypts it with each member's pairwise shared secret, and stores the per-member encrypted copies on-chain (`encryptedGroupKey[groupId][member]`). Members decrypt client-side.

3. **Expense Encryption** — Expense JSON encrypted client-side with the group shared key (AES-256-GCM). On-chain stores only the `keccak256` hash (`dataHash`). Full encrypted blob emitted in events for off-chain indexing.

**Key rotation:** When a member leaves a group (`leaveGroup()`), their `encryptedGroupKey` is deleted on-chain and a `MemberLeft` event is emitted. The client should use this event as a signal to generate a new group key and re-encrypt for remaining members. **No ratcheting at the contract level** — Signal-style double ratchet is a post-hackathon enhancement (PRD Priority 2).

### Known Limitations update:

Update the first bullet to reflect that `removeFriend()`, `leaveGroup()`, and `updateExpense()` now exist, but note that these are soft-deletes (array entries not removed) and there is still no `removeMember()` or `deleteExpense()`.

> **Git:** `"docs: add encryption model to README, update known limitations"`

---

## Step 7: Verify

```bash
forge build        # Clean compilation
forge test -vvv    # All tests pass
```

Expected: ~116 tests total (93 existing + ~23 new).

---

## Implementation Order

| Step | Depends On | Commit |
|------|-----------|--------|
| 0 — Copy plan to repo | — | `docs: add phase 2 implementation plan` |
| 1 — Auto-accept mutual requests | — | `fix: auto-accept mutual friend requests` |
| 2 — `removeFriend()` | — | `feat: add removeFriend to khaaliSplitFriends` |
| 3 — `leaveGroup()` | — | `feat: add leaveGroup to khaaliSplitGroups` |
| 4 — `updateExpense()` | Step 3 (for notGroupMember test) | `feat: add updateExpense to khaaliSplitExpenses` |
| 5 — Integration tests | Steps 1–4 | `test: add integration tests for full user flows` |
| 6 — Update README | Steps 1–4 | `docs: add encryption model to README, update known limitations` |
| 7 — Full verification | Step 6 | (no commit, just verify) |
