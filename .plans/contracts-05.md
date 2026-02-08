# khaaliSplit — Contracts Plan: Add Backend Relay Functions

## Motivation

The khaaliSplit architecture requires that **the backend sends all on-chain transactions** on behalf of users. Users only sign messages client-side — they never submit transactions directly. This is critical for:

1. **Gasless UX** — users don't need ETH for gas. The backend wallet pays all gas fees.
2. **PWA compatibility** — the app is a progressive web app. On mobile, wallet interactions should be limited to signing (which MetaMask handles well via deep links). Requiring users to submit transactions breaks the flow — they'd need to switch to MetaMask, approve the tx, wait for confirmation, then return to the PWA.
3. **Consistency** — `registerPubKey`, `register` (subnames), `setText`, `setAddr`, and both settlement functions already support backend relay. Friends, Groups, and Expenses are the only contracts that don't.
4. **Offline settlement** — `settleWithAuthorization` already supports anyone submitting a signed authorization. The same pattern should apply to social graph and expense operations.

## Problem

The following contract functions check `msg.sender` directly, which means only the user's wallet can call them:

**khaaliSplitFriends:**
- `requestFriend(address friend)` — checks `registered[msg.sender]`
- `acceptFriend(address requester)` — checks `pendingRequest[requester][msg.sender]`
- `removeFriend(address friend)` — checks `isFriend[msg.sender][friend]`

**khaaliSplitGroups:**
- `createGroup(bytes32 nameHash, bytes encryptedKey)` — checks `friendRegistry.registered(msg.sender)`
- `inviteMember(uint256 groupId, address member, bytes encryptedKey)` — checks `isMember[groupId][msg.sender]`
- `acceptGroupInvite(uint256 groupId)` — checks `isInvited[groupId][msg.sender]`
- `leaveGroup(uint256 groupId)` — checks `isMember[groupId][msg.sender]`

**khaaliSplitExpenses:**
- `addExpense(uint256 groupId, bytes32 dataHash, bytes encryptedData)` — checks group membership via `groupRegistry.isMember(groupId, msg.sender)`
- `updateExpense(uint256 expenseId, bytes32 newDataHash, bytes newEncryptedData)` — checks `expenses[expenseId].creator == msg.sender`

If the backend wallet submits these transactions, `msg.sender` is the backend address, not the user — so all checks fail.

## Solution

Add `*For` relay functions to each contract that accept a `user` parameter and check `msg.sender == backend` instead. This mirrors the existing pattern in `khaaliSplitFriends.registerPubKey()` and `khaaliSplitSubnames.register()`.

All three contracts are **UUPS upgradeable**, so we can add new functions without redeploying — just upgrade the implementation.

## Scope

Single session. Add relay functions, update tests, upgrade on Sepolia + all settlement chains (Groups references Friends, so ordering matters).

---

## Session 1: Add Backend Relay Functions + Upgrade

### 1.1 `khaaliSplitFriends` — add relay functions

Add three new functions alongside the existing ones:

```solidity
/// @notice Backend relay: send a friend request on behalf of `user`.
function requestFriendFor(address user, address friend) external {
    if (msg.sender != backend) revert NotBackend();
    if (!registered[user]) revert NotRegistered(user);
    if (!registered[friend]) revert NotRegistered(friend);
    if (user == friend) revert CannotFriendSelf();
    if (isFriend[user][friend]) revert AlreadyFriends();
    if (pendingRequest[user][friend]) revert AlreadyRequested();

    if (pendingRequest[friend][user]) {
        isFriend[friend][user] = true;
        isFriend[user][friend] = true;
        _friendsList[friend].push(user);
        _friendsList[user].push(friend);
        delete pendingRequest[friend][user];
        emit FriendAccepted(user, friend);
        return;
    }

    pendingRequest[user][friend] = true;
    emit FriendRequested(user, friend);
}

/// @notice Backend relay: accept a friend request on behalf of `user`.
function acceptFriendFor(address user, address requester) external {
    if (msg.sender != backend) revert NotBackend();
    if (!pendingRequest[requester][user]) revert NoPendingRequest();

    isFriend[requester][user] = true;
    isFriend[user][requester] = true;
    _friendsList[requester].push(user);
    _friendsList[user].push(requester);
    delete pendingRequest[requester][user];

    emit FriendAccepted(user, requester);
}

/// @notice Backend relay: remove a friend on behalf of `user`.
function removeFriendFor(address user, address friend) external {
    if (msg.sender != backend) revert NotBackend();
    if (!isFriend[user][friend]) revert NotFriends();

    isFriend[user][friend] = false;
    isFriend[friend][user] = false;
    emit FriendRemoved(user, friend);
}
```

**Note:** The existing `requestFriend`, `acceptFriend`, `removeFriend` functions remain unchanged. Users can still call them directly if they want.

### 1.2 `khaaliSplitGroups` — add relay functions

First, add a `backend` state variable and setter (Groups doesn't currently have one):

```solidity
address public backend;

error NotBackend();

function setBackend(address _backend) external onlyOwner {
    backend = _backend;
}
```

Then add relay functions:

```solidity
/// @notice Backend relay: create a group on behalf of `user`.
function createGroupFor(address user, bytes32 nameHash, bytes calldata encryptedKey) external returns (uint256 groupId) {
    if (msg.sender != backend) revert NotBackend();
    if (!friendRegistry.registered(user)) revert NotRegistered(user);

    groupId = ++groupCount;
    groups[groupId] = Group({ nameHash: nameHash, creator: user, memberCount: 1 });
    isMember[groupId][user] = true;
    _memberList[groupId].push(user);
    encryptedGroupKey[groupId][user] = encryptedKey;

    emit GroupCreated(groupId, user, nameHash);
}

/// @notice Backend relay: invite a member on behalf of `inviter`.
function inviteMemberFor(address inviter, uint256 groupId, address member, bytes calldata encryptedKey) external {
    if (msg.sender != backend) revert NotBackend();
    if (groups[groupId].creator == address(0)) revert GroupDoesNotExist(groupId);
    if (!isMember[groupId][inviter]) revert NotGroupMember(groupId, inviter);
    if (!friendRegistry.isFriend(inviter, member)) revert NotFriends(inviter, member);
    if (isMember[groupId][member]) revert AlreadyMember(groupId, member);
    if (isInvited[groupId][member]) revert AlreadyInvited(groupId, member);

    isInvited[groupId][member] = true;
    encryptedGroupKey[groupId][member] = encryptedKey;

    emit MemberInvited(groupId, inviter, member);
}

/// @notice Backend relay: accept a group invite on behalf of `user`.
function acceptGroupInviteFor(address user, uint256 groupId) external {
    if (msg.sender != backend) revert NotBackend();
    if (!isInvited[groupId][user]) revert NotInvited(groupId, user);

    isInvited[groupId][user] = false;
    isMember[groupId][user] = true;
    _memberList[groupId].push(user);
    groups[groupId].memberCount++;

    emit MemberAccepted(groupId, user);
}

/// @notice Backend relay: leave a group on behalf of `user`.
function leaveGroupFor(address user, uint256 groupId) external {
    if (msg.sender != backend) revert NotBackend();
    if (!isMember[groupId][user]) revert NotGroupMember(groupId, user);
    if (groups[groupId].creator == user) revert CreatorCannotLeave(groupId);

    isMember[groupId][user] = false;
    groups[groupId].memberCount--;
    delete encryptedGroupKey[groupId][user];

    emit MemberLeft(groupId, user);
}
```

### 1.3 `khaaliSplitExpenses` — add relay functions

First, add a `backend` state variable and setter (Expenses doesn't currently have one):

```solidity
address public backend;

error NotBackend();

function setBackend(address _backend) external onlyOwner {
    backend = _backend;
}
```

Then add relay functions:

```solidity
/// @notice Backend relay: add an expense on behalf of `creator`.
function addExpenseFor(address creator, uint256 groupId, bytes32 dataHash, bytes calldata encryptedData) external returns (uint256 expenseId) {
    if (msg.sender != backend) revert NotBackend();
    if (!groupRegistry.isMember(groupId, creator)) revert NotGroupMember(groupId, creator);

    expenseId = ++expenseCount;
    expenses[expenseId] = Expense({
        groupId: groupId,
        creator: creator,
        dataHash: dataHash,
        timestamp: block.timestamp
    });
    _groupExpenses[groupId].push(expenseId);

    emit ExpenseAdded(groupId, expenseId, creator, dataHash, encryptedData);
}

/// @notice Backend relay: update an expense on behalf of `creator`.
function updateExpenseFor(address creator, uint256 expenseId, bytes32 newDataHash, bytes calldata newEncryptedData) external {
    if (msg.sender != backend) revert NotBackend();
    Expense storage exp = expenses[expenseId];
    if (exp.creator != creator) revert NotExpenseCreator(expenseId, creator);

    exp.dataHash = newDataHash;
    exp.timestamp = block.timestamp;

    emit ExpenseUpdated(exp.groupId, expenseId, creator, newDataHash, newEncryptedData);
}
```

**Note:** `NotGroupMember` and `NotExpenseCreator` errors may need to be added if they don't already exist in the Expenses contract. Check the existing error definitions and align.

### 1.4 Update interfaces

Update the interface files to include the new functions:

- `IkhaaliSplitFriends.sol` — add `requestFriendFor`, `acceptFriendFor`, `removeFriendFor`
- `IkhaaliSplitGroups.sol` — add `createGroupFor`, `inviteMemberFor`, `acceptGroupInviteFor`, `leaveGroupFor`, `setBackend`
- Add `IkhaaliSplitExpenses.sol` if it doesn't exist — or update if it does

### 1.5 Write tests

For each new relay function, test:
1. **Happy path** — backend calls, state changes correctly, event emitted
2. **Not backend** — non-backend caller reverts with `NotBackend()`
3. **Same validation as original** — e.g. `requestFriendFor` with unregistered user reverts with `NotRegistered`
4. **Original functions still work** — users can still call `requestFriend` directly

Test file locations:
- `test/khaaliSplitFriends.t.sol` — add `test_requestFriendFor_*`, `test_acceptFriendFor_*`, `test_removeFriendFor_*`
- `test/khaaliSplitGroups.t.sol` — add `test_createGroupFor_*`, `test_inviteMemberFor_*`, `test_acceptGroupInviteFor_*`, `test_leaveGroupFor_*`
- `test/khaaliSplitExpenses.t.sol` — add `test_addExpenseFor_*`, `test_updateExpenseFor_*`

### 1.6 Run full test suite

```bash
forge test -vvv
```

All existing tests must still pass. New tests must pass.

### 1.7 Create upgrade script

**No upgrade script exists.** `script/DeployCore.s.sol` handles fresh deployments only (implementations + proxies via CREATE2). We need a new `script/UpgradeCore.s.sol` that:

1. Deploys **only** new implementations (no proxies — those already exist)
2. Calls `upgradeToAndCall()` on each existing proxy with the new implementation address
3. Calls `setBackend(backendAddress)` on Groups and Expenses proxies (Friends already has a backend set)

```solidity
// script/UpgradeCore.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {khaaliSplitFriends} from "../src/khaaliSplitFriends.sol";
import {khaaliSplitGroups} from "../src/khaaliSplitGroups.sol";
import {khaaliSplitExpenses} from "../src/khaaliSplitExpenses.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UpgradeCore
 * @notice Upgrades Friends, Groups, and Expenses proxies to new implementations
 *         that include backend relay functions (*For pattern).
 *
 * @dev Required environment variables:
 *   - DEPLOYER_PRIVATE_KEY: Private key for the owner EOA (must be proxy owner)
 *   - BACKEND_ADDRESS: Backend/relayer address to set on Groups and Expenses
 *   - FRIENDS_PROXY: Address of the khaaliSplitFriends proxy
 *   - GROUPS_PROXY: Address of the khaaliSplitGroups proxy
 *   - EXPENSES_PROXY: Address of the khaaliSplitExpenses proxy
 *
 * Usage:
 *   forge script script/UpgradeCore.s.sol:UpgradeCore --rpc-url sepolia --broadcast --verify
 */
contract UpgradeCore is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address backendAddress = vm.envAddress("BACKEND_ADDRESS");
        address friendsProxy = vm.envAddress("FRIENDS_PROXY");
        address groupsProxy = vm.envAddress("GROUPS_PROXY");
        address expensesProxy = vm.envAddress("EXPENSES_PROXY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new implementations
        address newFriendsImpl = address(new khaaliSplitFriends());
        console.log("New Friends impl:", newFriendsImpl);

        address newGroupsImpl = address(new khaaliSplitGroups());
        console.log("New Groups impl:", newGroupsImpl);

        address newExpensesImpl = address(new khaaliSplitExpenses());
        console.log("New Expenses impl:", newExpensesImpl);

        // 2. Upgrade proxies (order matters: Friends -> Groups -> Expenses)
        UUPSUpgradeable(friendsProxy).upgradeToAndCall(newFriendsImpl, "");
        console.log("Friends proxy upgraded");

        UUPSUpgradeable(groupsProxy).upgradeToAndCall(newGroupsImpl, "");
        console.log("Groups proxy upgraded");

        UUPSUpgradeable(expensesProxy).upgradeToAndCall(newExpensesImpl, "");
        console.log("Expenses proxy upgraded");

        // 3. Set backend on Groups and Expenses (Friends already has one)
        khaaliSplitGroups(groupsProxy).setBackend(backendAddress);
        console.log("Groups backend set:", backendAddress);

        khaaliSplitExpenses(expensesProxy).setBackend(backendAddress);
        console.log("Expenses backend set:", backendAddress);

        vm.stopBroadcast();

        console.log("\n=== Upgrade Summary ===");
        console.log("Friends proxy:", friendsProxy, "-> impl:", newFriendsImpl);
        console.log("Groups proxy:", groupsProxy, "-> impl:", newGroupsImpl);
        console.log("Expenses proxy:", expensesProxy, "-> impl:", newExpensesImpl);
    }
}
```

**Important:** Before running on Sepolia, test on a local fork first:
```bash
forge script script/UpgradeCore.s.sol:UpgradeCore --fork-url sepolia -vvv
```

### 1.8 Run upgrade on Sepolia

```bash
FRIENDS_PROXY=0xc6513216d6Bc6498De9E37e00478F0Cb802b2561 \
GROUPS_PROXY=0xf6f07Bdc4f14b1FB1374A1d821A9E50547EcE820 \
EXPENSES_PROXY=0x0058f47e98DF066d34f70EF231AdD634C9857605 \
forge script script/UpgradeCore.s.sol:UpgradeCore --rpc-url sepolia --broadcast --verify
```

**Important ordering** (handled by the script in sequence):
- Friends can be upgraded independently
- Groups depends on Friends (for `friendRegistry.registered` / `isFriend` checks) — upgrade after Friends
- Expenses depends on Groups (for `groupRegistry.isMember`) — upgrade after Groups

### 1.9 Update `deployments.json`

Update implementation addresses in `contracts/deployments.json` for the three upgraded contracts. Proxy addresses remain the same.

### 1.10 Verify on Etherscan

Verify the new implementation contracts on Sepolia Etherscan so the ABIs are available. (The `--verify` flag on the forge script should handle this automatically.)

**Commit:** `feat(contracts): add backend relay functions to Friends, Groups, Expenses + upgrade`

---

## Verification

| Check | How |
|---|---|
| All existing tests pass | `forge test -vvv` — 268+ passing |
| New relay tests pass | `forge test --match-test "For" -vvv` |
| Friends upgrade successful | Call `requestFriendFor` on proxy — succeeds |
| Groups upgrade successful | Call `createGroupFor` on proxy — succeeds |
| Expenses upgrade successful | Call `addExpenseFor` on proxy — succeeds |
| Original functions still work | Call `requestFriend` directly — still succeeds |
| `setBackend` called on Groups and Expenses | Query `backend()` on each proxy |

## Events

No new events are added. The relay functions emit the **same events** as the original functions (`FriendRequested`, `FriendAccepted`, `GroupCreated`, etc.). This means:
- The Envio indexer does not need any changes
- The indexed data looks identical regardless of whether the user or backend submitted the tx
- Activity tracking in Django works the same way

## Impact on Other Plans

**`application-03.md` Session 3 (Social Graph):**
- After this upgrade, the backend CAN send all friend/group/expense transactions
- `wallet.js` does NOT need `requestFriend()`, `createGroup()`, `addExpense()` etc.
- All contract calls go through `web3_utils.py` via `send_tx()`
- The client only signs messages (for wallet linking, ECDH, and settlement)
- Session 3 becomes simpler — no need for client-side contract call functions

**`indexer-01.md`:**
- No changes needed — same events emitted

## Risks

| Risk | Mitigation |
|---|---|
| UUPS upgrade breaks proxy | Test upgrade on local fork first (`forge script script/UpgradeCore.s.sol:UpgradeCore --fork-url sepolia -vvv`) |
| New `backend` storage slot collides with existing storage | Both Groups and Expenses use `Initializable` + `OwnableUpgradeable`. New storage variables are appended at the end — no collision. Verify with `forge inspect` storage layout. |
| Backend wallet compromise allows arbitrary friend/group/expense manipulation | Same risk as existing `registerPubKey` relay. Backend is a trusted relayer. Acceptable for hackathon. |
| Gas costs increase due to added functions | Negligible — functions are small. No new storage slots read/written beyond what originals already access. |
