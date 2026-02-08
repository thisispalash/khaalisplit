# khaaliSplit — Application Plan: Connect App to Chain + Indexer

> Connects the Django app to the deployed smart contracts and Envio indexer.
> The backend (via `BACKEND_PRIVATE_KEY`) sends ALL on-chain transactions.
> The client ONLY signs messages — never submits transactions directly.

## Scope

Wire the existing Django app to interact with all deployed smart contracts. The app currently has working auth, UI, and local DB models but no real chain interaction beyond pubkey registration and signature verification.

**Working directory:** `app/` (relative to repo root)

## Architecture

```
Browser (client)                    Django (backend)                 Blockchain
─────────────────                   ─────────────────                ──────────
Sign messages (EIP-191/3009/712)    Verify signatures                Read via indexer (Hasura)
Store keys in IndexedDB             Send ALL on-chain txs            Write via backend wallet
ECDH shared secret derivation       Circle Gateway API calls         Emit events → Envio
Encrypt/decrypt expense data        Sync indexed data to Cached*
HTMX partials                       Serve templates
```

**Key principle:** The client never makes on-chain transactions. All contract calls go through the backend wallet (`BACKEND_PRIVATE_KEY`). The client only produces signatures.

## Prerequisites

| Requirement | Status |
|---|---|
| Contracts deployed on Sepolia + 4 chains | Done (`contracts/deployments.json`) |
| App running with local DB | Done |
| Envio indexer running (from `indexer-01.md`) | Needed for Session 5 |
| Circle Gateway API access | Needs setup (Session 1) |
| `BACKEND_PRIVATE_KEY` funded with Sepolia ETH | Needed for gas |

## Current State (what exists)

| Component | Status |
|---|---|
| `web3_utils.py` | Has `recover_address`, `recover_pubkey`, `register_pubkey_onchain`. Uses **wrong chain IDs** (mainnet instead of testnet). Only has Friends ABI. |
| `wallet.js` | Has `connectWallet`, `signMessage`, stale `settleWithPermit`. Uses **wrong chain IDs**. |
| `crypto.js` | Has `generateGroupKey`, `importGroupKey`, `deriveGroupKey`, `encrypt`, `decrypt`. `encryptGroupKeyForMember` uses broken one-directional hack (not real ECDH). |
| `settings.py` | Has `CONTRACT_FRIENDS`, `CONTRACT_GROUPS`, `CONTRACT_EXPENSES`, `CONTRACT_SETTLEMENT`, `CONTRACT_RESOLVER`. Missing `CONTRACT_SUBNAMES`, `CONTRACT_REPUTATION`. |
| `ens_gateway.py` | CCIP-Read gateway reads from local DB. Needs repurposing to read from indexer. |
| Views (friends, groups, expenses, settlement) | All DB-only. No on-chain calls. |

## Deployed Contract Addresses (proxy)

From `contracts/deployments.json`:

| Contract | Chain | Address |
|---|---|---|
| khaaliSplitFriends | Sepolia | `0xc6513216d6Bc6498De9E37e00478F0Cb802b2561` |
| khaaliSplitGroups | Sepolia | `0xf6f07Bdc4f14b1FB1374A1d821A9E50547EcE820` |
| khaaliSplitExpenses | Sepolia | `0x0058f47e98DF066d34f70EF231AdD634C9857605` |
| khaaliSplitSettlement | Sepolia | `0xd038e9CD05a71765657Fd3943d41820F5035A6C1` |
| khaaliSplitSubnames | Sepolia | `0xE7F20a2c7461cAF3FdCD672E273326fAeCE5Be4F` |
| khaaliSplitReputation | Sepolia | `0x3a916C1cb55352860FA46084EBA5A032dB50312f` |
| khaaliSplitSettlement | Base Sepolia | `0xacDbabeDc22BE4eD68D9084Dd3157c27D7154baa` |
| khaaliSplitSettlement | Arbitrum Sepolia | `0x8A20a346a00f809fbd279c1E8B56883998867254` |
| khaaliSplitSettlement | Optimism Sepolia | `0x8A20a346a00f809fbd279c1E8B56883998867254` |
| khaaliSplitSettlement | Arc Testnet | `0xeB75548245A9C5a31ABF6Eda7CA16977f3Af3690` |

---

## Session 1: Foundation

**Goal:** Fix broken chain IDs, add all contract ABIs and helpers to `web3_utils.py`, add missing settings, set up Circle Gateway API client. After this session, the backend can call any contract function.

### 1.1 Fix chain IDs in `web3_utils.py`

Replace the `CHAIN_IDS` dict with correct **testnet** chain IDs:

```python
CHAIN_IDS = {
    11155111: 'sepolia',
    84532: 'baseSepolia',
    421614: 'arbitrumSepolia',
    11155420: 'optimismSepolia',
    5042002: 'arc_testnet',
}
```

### 1.2 Fix token addresses in `web3_utils.py`

Replace `TOKEN_ADDRESSES` with correct testnet addresses (from `contracts/script/tokens.json`):

```python
TOKEN_ADDRESSES = {
    11155111: {'USDC': '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238', 'EURC': '0x08210F9170F89Ab7658F0B5E3fF39b0E03C594D4'},
    84532:    {'USDC': '0x036CbD53842c5426634e7929541eC2318f3dCF7e', 'EURC': '0x808456652fdb597867f38412077A9182bf77359F'},
    421614:   {'USDC': '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d'},
    11155420: {'USDC': '0x5fd84259d66Cd46123540766Be93DFE6D43130D7'},
    5042002:  {'USDC': '0x3600000000000000000000000000000000000000', 'EURC': '0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a'},
}
```

### 1.3 Fix chain IDs and tokens in `wallet.js`

Update `CHAIN_TOKENS` to match the testnet addresses above.

### 1.4 Add contract ABIs to `web3_utils.py`

Add ABI fragments for every contract function the backend needs to call:

**khaaliSplitFriends:**
- `registerPubKey(address user, bytes pubKey)` — already exists
- `requestFriend(address friend)`
- `acceptFriend(address requester)`
- `removeFriend(address friend)`
- `getPubKey(address user) → bytes` (view)
- `registered(address) → bool` (view)

**khaaliSplitGroups:**
- `createGroup(bytes32 nameHash, bytes encryptedKey) → uint256`
- `inviteMember(uint256 groupId, address member, bytes encryptedKey)`
- `acceptGroupInvite(uint256 groupId)`
- `leaveGroup(uint256 groupId)`
- `getMembers(uint256 groupId) → address[]` (view)

**khaaliSplitExpenses:**
- `addExpense(uint256 groupId, bytes32 dataHash, bytes encryptedData) → uint256`
- `updateExpense(uint256 expenseId, bytes32 newDataHash, bytes newEncryptedData)`

**khaaliSplitSubnames:**
- `register(string label, address owner)`
- `setText(bytes32 node, string key, string value)`
- `setAddr(bytes32 node, address addr)`
- `text(bytes32 node, string key) → string` (view)
- `addr(bytes32 node) → address` (view)

**khaaliSplitReputation:**
- `getReputation(address user) → uint256` (view)
- `setUserNode(address user, bytes32 node)`

**khaaliSplitSettlement:**
- `settleWithAuthorization(bytes32 recipientNode, uint256 amount, bytes memo, (address from, uint256 validAfter, uint256 validBefore, bytes32 nonce) auth, bytes signature)`
- `settleFromGateway(bytes attestationPayload, bytes attestationSignature, bytes32 recipientNode, address sender, bytes memo)`

### 1.5 Add contract helper functions to `web3_utils.py`

```python
def get_contract(name: str, chain_id: int = 11155111):
    """Get a web3 contract instance by name."""
    # Maps name to (address_setting, abi)
    # For settlement on other chains, uses per-chain addresses

def send_tx(contract, fn_name: str, *args, chain_id: int = 11155111) -> str:
    """Build, sign, and send a transaction from the backend wallet. Returns tx hash."""
    # Uses BACKEND_PRIVATE_KEY
    # Handles nonce, gas estimation, signing, sending

def call_view(contract, fn_name: str, *args):
    """Call a view function on a contract. Returns the result."""
```

### 1.6 Add missing settings to `settings.py`

```python
CONTRACT_SUBNAMES = os.getenv('CONTRACT_SUBNAMES', '')
CONTRACT_REPUTATION = os.getenv('CONTRACT_REPUTATION', '')
CIRCLE_API_KEY = os.getenv('CIRCLE_API_KEY', '')
CIRCLE_GATEWAY_URL = os.getenv('CIRCLE_GATEWAY_URL', 'https://api.circle.com')
```

### 1.7 Create Circle Gateway API client

New file: `app/api/utils/circle_gateway.py`

```python
def get_gateway_attestation(burn_intent_signature: str, ...) -> dict:
    """
    Submit a signed BurnIntent to Circle's Gateway API.
    Returns { attestationPayload, attestationSignature }.
    """
    # POST to Circle Gateway API with the user's signed BurnIntent
    # Poll until attestation is ready
    # Return attestation data for settleFromGateway()
```

This needs:
- Circle API key from `.env` (`CIRCLE_API_KEY`)
- Understanding of the Circle Gateway API endpoints (documented in Circle's developer docs)
- Error handling for timeouts, rate limits, etc.

### 1.8 Update `.env.example`

Add the new env vars:
```
CONTRACT_SUBNAMES=0xE7F20a2c7461cAF3FdCD672E273326fAeCE5Be4F
CONTRACT_REPUTATION=0x3a916C1cb55352860FA46084EBA5A032dB50312f
CIRCLE_API_KEY=
CIRCLE_GATEWAY_URL=https://api.circle.com
```

**Commit:** `feat(app): fix chain IDs, add all contract ABIs and helpers, Circle Gateway client`

### Session 1 Verification

| Check | How |
|---|---|
| Chain IDs are testnet only | Inspect `CHAIN_IDS` and `CHAIN_TOKENS` |
| `get_contract()` returns valid contract for each name | Django shell test |
| `send_tx()` can send a tx to Sepolia | Test with a no-op or view call |
| Circle Gateway client initialized | Import succeeds, API key loaded |

### Files Modified

| Action | File |
|---|---|
| Edit | `app/api/utils/web3_utils.py` |
| Edit | `app/static/js/wallet.js` |
| Edit | `app/config/settings.py` |
| Create | `app/api/utils/circle_gateway.py` |
| Edit | `app/.env.example` |

---

## Session 2: Onboarding Flow

**Goal:** Wire the signup → subname registration → wallet linking → pubkey registration → payment preferences flow end-to-end with real on-chain transactions.

### 2.1 Subname registration on signup

**File:** `app/api/views/auth.py` — `signup_view()`

After creating the `User` object and before redirect:
1. Compute the ENS namehash for `{subname}.khaalisplit.eth`
2. Call `khaaliSplitSubnames.register(label=subname, owner=backend_address)` via `send_tx()`
   - Owner is initially the backend address (user hasn't linked a wallet yet)
   - This registers the subname on-chain
3. Call `khaaliSplitSubnames.setText(node, "display_name", display_name)` if display name provided
4. Store the tx_hash in the activity log

**Note:** The subname owner will be updated to the user's wallet address after wallet linking (step 2.3).

### 2.2 Verify pubkey registration still works

**File:** `app/api/views/auth.py` — `register_pubkey()`

This already calls `register_pubkey_onchain()`. Verify it works with the current contract addresses. The `CONTRACT_FRIENDS` setting must point to the correct proxy address.

### 2.3 Update subname owner after wallet linking

**File:** `app/api/views/auth.py` — `verify_signature()`

After successfully linking a wallet (and if it's the primary address):
1. Compute the ENS namehash for `{user.subname}.khaalisplit.eth`
2. Call `khaaliSplitSubnames.setAddr(node, user_address)` via `send_tx()`
   - This updates the on-chain address record so the subname resolves to the user's wallet

### 2.4 Set default payment preferences

**File:** `app/api/views/auth.py` — `verify_signature()`

After wallet linking, set default payment preferences as ENS text records:
1. `khaaliSplitSubnames.setText(node, "com.khaalisplit.payment.flow", "gateway")` — default to Gateway
2. `khaaliSplitSubnames.setText(node, "com.khaalisplit.payment.token", usdc_address)` — USDC on user's chain
3. `khaaliSplitSubnames.setText(node, "com.khaalisplit.payment.chain", str(chain_id))` — user's chain

### 2.5 Payment preferences partial on profile page

**New template:** `app/templates/partials/payment_preferences.html`

Displays current payment preferences:
- Payment flow (Gateway / CCTP)
- Preferred token (USDC address)
- Preferred chain
- Edit form (HTMX) to update preferences

**New API endpoint:** `POST /api/profile/payment-preferences/`

Accepts updated payment preferences and calls `khaaliSplitSubnames.setText()` for each changed field.

**File:** `app/api/views/auth.py` or new `app/api/views/profile.py`

### 2.6 Wire reputation node

After wallet linking, call:
```python
khaaliSplitReputation.setUserNode(user_address, subname_node)
```

This links the user's wallet address to their ENS subname node in the reputation contract, so settlement events can update the correct text record.

**Commit:** `feat(app): wire onboarding flow with on-chain subname registration and payment prefs`

### Session 2 Verification

| Check | How |
|---|---|
| Signup creates subname on-chain | Check `SubnameRegistered` event on Sepolia explorer |
| Wallet linking updates addr record | Check `AddrRecordSet` event |
| Payment prefs set as text records | Query `khaaliSplitSubnames.text(node, key)` |
| Profile shows payment preferences | Visit `/profile/` |
| Pubkey registration works | Check `PubKeyRegistered` event |

### Files Modified

| Action | File |
|---|---|
| Edit | `app/api/views/auth.py` |
| Create | `app/templates/partials/payment_preferences.html` |
| Edit | `app/api/urls.py` (add payment prefs endpoint) |
| Edit or Create | `app/api/views/profile.py` (payment prefs view) |
| Edit | `app/web/views.py` (profile page context) |
| Edit | `app/templates/pages/profile.html` (include prefs partial) |

---

## Session 3: Social Graph (Friends + Groups + Encryption)

**Goal:** Wire friends and groups to on-chain contracts. Fix ECDH encryption model. Implement IndexedDB key storage on client.

### 3.1 Friends: on-chain calls from backend

**File:** `app/api/views/friends.py`

Update each endpoint to call the contract via backend wallet:

**`send_request(request, subname)`:**
1. Look up the target user's primary linked address
2. Look up the current user's primary linked address
3. Call `khaaliSplitFriends.requestFriend(target_address)` via `send_tx()` — NOTE: the backend wallet is `msg.sender`, but `requestFriend` requires `registered[msg.sender]`. **Problem:** The backend is the sender, not the user.

**CRITICAL ISSUE:** The Friends contract requires `msg.sender` to be a registered user. But the backend wallet sends all transactions. Two approaches:

**(a) Register the backend as a proxy for each user** — not supported by the contract.

**(b) The contract needs to be called FROM the user's address** — contradicts the "backend sends all txs" requirement.

**Resolution:** The backend wallet IS registered as the `backend` address in the Friends contract. The `registerPubKey` function already checks `msg.sender == backend`. But `requestFriend`/`acceptFriend` check `registered[msg.sender]` which is the user's address, not the backend.

**This means friend requests MUST come from the user's address.** The backend can't send them on behalf of the user without a contract change.

**Options:**
1. **Have the client sign a meta-transaction** (EIP-712) and the backend submits it with a relay pattern. But the contract doesn't support meta-transactions for friend functions.
2. **Have the backend pre-register itself as each user** — not clean.
3. **Accept that friend/group/expense calls need to come from the user's wallet** — contradicts the stated architecture.
4. **Add a `backend` relayer pattern to the Friends/Groups/Expenses contracts** — contract change needed.

**Recommended approach for the hackathon:** Since the contracts can't be changed at this point (deployed), we need to work with the existing contract interfaces:

- `registerPubKey` → backend can call (has `backend` check)
- `requestFriend` / `acceptFriend` / `removeFriend` → require `msg.sender` = registered user
- `createGroup` / `inviteMember` / `acceptGroupInvite` / `leaveGroup` → require `msg.sender` = registered user
- `addExpense` / `updateExpense` → require `msg.sender` = group member
- `settleWithAuthorization` → anyone can call (no `msg.sender` restriction)
- `settleFromGateway` → anyone can call
- `khaaliSplitSubnames.register` → backend can call (has `backend` check)
- `khaaliSplitSubnames.setText/setAddr` → owner, backend, or reputation contract can call

**So the actual architecture is:**
- **Backend sends:** `registerPubKey`, `register` (subname), `setText`, `setAddr`, `setUserNode`, `settleWithAuthorization`, `settleFromGateway`
- **Client must send (from their wallet):** `requestFriend`, `acceptFriend`, `removeFriend`, `createGroup`, `inviteMember`, `acceptGroupInvite`, `leaveGroup`, `addExpense`, `updateExpense`

**Updated flow for friend/group/expense calls:**
1. Client builds the transaction data
2. Client signs and submits the transaction from their wallet (via `wallet.js`)
3. Client reports the tx_hash back to Django
4. Django records the tx_hash and updates the local cache
5. Indexer picks up the event and confirms

### 3.2 Update `wallet.js` with contract call functions

Add functions for all client-side contract calls:

```javascript
// Friends
window.requestFriend = async function(friendAddress) { ... }
window.acceptFriend = async function(requesterAddress) { ... }
window.removeFriend = async function(friendAddress) { ... }

// Groups
window.createGroup = async function(nameHash, encryptedKey) { ... }
window.inviteMember = async function(groupId, memberAddress, encryptedKey) { ... }
window.acceptGroupInvite = async function(groupId) { ... }
window.leaveGroup = async function(groupId) { ... }

// Expenses
window.addExpense = async function(groupId, dataHash, encryptedData) { ... }
window.updateExpense = async function(expenseId, newDataHash, newEncryptedData) { ... }
```

Each function:
1. Creates a contract instance with `ethers.Contract`
2. Calls the function from the connected wallet (signer)
3. Returns `{ hash: tx.hash }`
4. Reports tx_hash to Django backend via fetch

### 3.3 Update Django views to accept tx_hash callbacks

**File:** `app/api/views/friends.py`

Update `send_request`, `accept`, `remove` to accept a `tx_hash` parameter. The view:
1. Validates the request
2. Updates the local `CachedFriend` record
3. Stores the `tx_hash` for indexer confirmation

Similarly for groups and expenses views.

### 3.4 Fix ECDH in `crypto.js`

Replace the broken `encryptGroupKeyForMember` with proper ECDH using `ethers.SigningKey`:

```javascript
/**
 * Derive a deterministic ECDH shared secret with a friend.
 *
 * Flow:
 * 1. Sign a deterministic message ("khaaliSplit ECDH") with wallet
 * 2. keccak256(signature) → use as a private scalar
 * 3. Use ethers.SigningKey to compute ECDH shared secret with friend's on-chain pubkey
 * 4. Both sides derive the same secret (ECDH is symmetric)
 *
 * @param {string} friendPubKeyHex — friend's uncompressed public key (from on-chain)
 * @returns {Promise<Uint8Array>} — 32-byte shared secret
 */
async deriveSharedSecret(friendPubKeyHex) {
    const signer = await provider.getSigner();

    // Step 1: Sign deterministic message
    const sig = await signer.signMessage("khaaliSplit ECDH");

    // Step 2: Derive private scalar from signature
    const privateScalar = ethers.keccak256(ethers.toUtf8Bytes(sig));

    // Step 3: ECDH with friend's public key
    const signingKey = new ethers.SigningKey(privateScalar);
    const sharedSecret = signingKey.computeSharedSecret('0x' + friendPubKeyHex);

    // Step 4: Hash to 32 bytes (HKDF-like)
    return ethers.getBytes(ethers.keccak256(sharedSecret));
}
```

**Why this works:** Both parties sign the same deterministic message, so they both derive the same private scalar. ECDH(`scalar_a * pubkey_b`) == ECDH(`scalar_b * pubkey_a`).

Update `encryptGroupKeyForMember` to use `deriveSharedSecret`.

### 3.5 IndexedDB key storage

**New file:** `app/static/js/keystore.js`

```javascript
window.khaaliKeystore = {
    // Store a shared secret for a friend
    async storeSharedSecret(friendAddress, secretHex) { ... },

    // Retrieve a shared secret for a friend
    async getSharedSecret(friendAddress) { ... },

    // Store a group key
    async storeGroupKey(groupId, keyHex) { ... },

    // Retrieve a group key
    async getGroupKey(groupId) { ... },

    // Clear all keys (on logout)
    async clearAll() { ... },
};
```

Uses IndexedDB with a `khaaliSplit-keys` database, two object stores: `sharedSecrets` and `groupKeys`.

### 3.6 Group creation flow (end-to-end)

1. Client generates AES group key via `khaaliCrypto.generateGroupKey()`
2. Client encrypts group key for self: `encrypt(groupKeyHex)` using own shared secret (self-ECDH, or just AES with a self-derived key)
3. Client calls `window.createGroup(nameHash, encryptedKey)` — on-chain tx from wallet
4. Client stores group key in IndexedDB: `khaaliKeystore.storeGroupKey(groupId, groupKeyHex)`
5. Client reports tx_hash to Django: `POST /api/groups/create/confirm/`
6. Django creates `CachedGroup` record with tx_hash

### 3.7 Group invite flow (end-to-end)

1. Inviter has the group key in IndexedDB
2. Inviter fetches invitee's pubkey (from indexer or on-chain via view call)
3. Inviter derives shared secret with invitee: `deriveSharedSecret(inviteePubKey)`
4. Inviter encrypts group key for invitee using the shared secret
5. Client calls `window.inviteMember(groupId, memberAddress, encryptedKey)` — on-chain tx
6. Client reports tx_hash to Django

### 3.8 Group accept flow (end-to-end)

1. Invitee reads their `encryptedGroupKey` from on-chain (via indexer or contract view)
2. Invitee derives shared secret with inviter: `deriveSharedSecret(inviterPubKey)`
3. Invitee decrypts group key using shared secret
4. Invitee stores group key in IndexedDB
5. Client calls `window.acceptGroupInvite(groupId)` — on-chain tx
6. Client reports tx_hash to Django

**Commit:** `feat(app): wire friends and groups on-chain, fix ECDH, add IndexedDB keystore`

### Session 3 Verification

| Check | How |
|---|---|
| Friend request emits `FriendRequested` event | Sepolia explorer |
| Accept friend emits `FriendAccepted` | Sepolia explorer |
| Group creation emits `GroupCreated` | Sepolia explorer |
| ECDH shared secret is symmetric | Both users derive same secret for same pair |
| Group key encrypts/decrypts | Create group, invite member, member can decrypt |
| Keys persist in IndexedDB | Check browser DevTools > Application > IndexedDB |

### Files Modified

| Action | File |
|---|---|
| Edit | `app/api/views/friends.py` |
| Edit | `app/api/views/groups.py` |
| Edit | `app/static/js/wallet.js` (add contract call functions) |
| Edit | `app/static/js/crypto.js` (fix ECDH, add `deriveSharedSecret`) |
| Create | `app/static/js/keystore.js` (IndexedDB key storage) |
| Edit | `app/templates/base.html` (include keystore.js script) |
| Edit | Various templates (add Hyperscript for on-chain tx flows) |

---

## Session 4: Expenses + Settlement

**Goal:** Wire expense creation/update with on-chain encryption. Implement both settlement flows (`settleWithAuthorization` and `settleFromGateway`). Create the `/api/settle/for-user/` endpoint.

### 4.1 Expense creation flow (end-to-end)

1. Client retrieves group key from IndexedDB
2. Client sets group key: `khaaliCrypto.importGroupKey(groupKeyHex)`
3. Client encrypts expense JSON: `khaaliCrypto.encrypt(JSON.stringify({description, amount, participants, split_type, category}))`
4. Gets back `{ ciphertext, hash }` — ciphertext is hex-encoded, hash is keccak256
5. Client calls `window.addExpense(groupId, hash, ciphertextBytes)` — on-chain tx
6. Client reports tx_hash + expense details to Django: `POST /api/expenses/{group_id}/add/`
7. Django creates `CachedExpense` with the tx_hash, data_hash, encrypted_data, and decrypted fields

### 4.2 Expense update flow

Same as creation but calls `window.updateExpense(expenseId, newHash, newCiphertextBytes)`.

### 4.3 Expense decryption on load

When loading a group's expense list:
1. Client retrieves group key from IndexedDB
2. For each expense card that has `encrypted_data`:
   - Client decrypts via `khaaliCrypto.decrypt(encryptedData)`
   - Populates the expense card fields (description, amount, etc.)
3. If decryption fails (wrong key, corrupted), show "Encrypted" placeholder

This can be done via Hyperscript on the expense card template, triggered on `htmx:afterSwap`.

### 4.4 New endpoint: `POST /api/settle/for-user/`

**File:** `app/api/views/settlement.py`

New endpoint that accepts settlement requests from anyone (supports third-party relay):

```python
@require_POST
def settle_for_user(request):
    """
    Execute a settlement on behalf of a user.

    Accepts JSON body:
    {
        "type": "authorization" | "gateway",

        # For type="authorization":
        "recipient_node": "0x...",        # ENS namehash of recipient
        "amount": "10000000",             # in token decimals (6 for USDC)
        "memo": "0x...",                  # hex-encoded memo bytes
        "auth": {
            "from": "0x...",              # sender address
            "valid_after": 0,
            "valid_before": 1738000000,
            "nonce": "0x..."              # random bytes32
        },
        "signature": "0x...",             # EIP-3009 signature

        # For type="gateway":
        "recipient_node": "0x...",
        "sender": "0x...",
        "memo": "0x...",
        "burn_intent_signature": "0x..."  # signed BurnIntent for Circle Gateway
    }
    """
```

**Authorization flow:**
1. Validate inputs
2. Call `khaaliSplitSettlement.settleWithAuthorization(recipientNode, amount, memo, auth, signature)` via `send_tx()`
3. Record `CachedSettlement` with tx_hash
4. Return `{ tx_hash, status }`

**Gateway flow:**
1. Validate inputs
2. Call `circle_gateway.get_gateway_attestation(burn_intent_signature, ...)` — gets attestation from Circle
3. Call `khaaliSplitSettlement.settleFromGateway(attestationPayload, attestationSignature, recipientNode, sender, memo)` via `send_tx()`
4. Record `CachedSettlement` with tx_hash
5. Return `{ tx_hash, status }`

### 4.5 Update `wallet.js` settlement signing

Remove stale `settleWithPermit`. Add:

```javascript
/**
 * Sign an EIP-3009 ReceiveWithAuthorization message for direct settlement.
 * Returns the signature + auth params to send to Django.
 */
window.signSettlementAuthorization = async function(recipientNode, amount, tokenAddress) {
    // Build EIP-3009 ReceiveWithAuthorization typed data
    // domain: { name: token.name(), version: "1" or "2", chainId, verifyingContract: tokenAddress }
    // types: ReceiveWithAuthorization { from, to, value, validAfter, validBefore, nonce }
    // to = settlement contract address
    // Sign with signer.signTypedData()
    // Return { auth: { from, validAfter, validBefore, nonce }, signature, recipientNode, amount }
}

/**
 * Sign a BurnIntent for Gateway settlement.
 * Returns the signature to send to Django.
 */
window.signGatewayBurnIntent = async function(recipientNode, amount) {
    // Build BurnIntent typed data per Circle Gateway spec
    // Sign with signer.signTypedData()
    // Return { burnIntentSignature, recipientNode, sender, amount }
}
```

### 4.6 Update settlement UI templates

Update the settle page and debt summary to:
1. Show a "Settle" button for each debt
2. On click: present choice of "Direct" (authorization) or "Gateway" settlement
3. Direct: calls `signSettlementAuthorization()` → posts to `/api/settle/for-user/` with `type=authorization`
4. Gateway: calls `signGatewayBurnIntent()` → posts to `/api/settle/for-user/` with `type=gateway`
5. Show settlement status card with HTMX polling on the tx_hash

**Commit:** `feat(app): wire expenses on-chain with encryption, add dual settlement flows`

### Session 4 Verification

| Check | How |
|---|---|
| Expense creation emits `ExpenseAdded` event | Sepolia explorer |
| Expense data is encrypted on-chain | Check event logs — `encryptedData` is not plaintext |
| `dataHash` matches `keccak256(plaintext)` | Compute locally and compare |
| `/api/settle/for-user/` with type=authorization works | Test with signed EIP-3009 message |
| `/api/settle/for-user/` with type=gateway works | Test with Circle Gateway (requires API key) |
| Settlement emits `SettlementCompleted` event | Sepolia explorer |

### Files Modified

| Action | File |
|---|---|
| Edit | `app/api/views/expenses.py` |
| Edit | `app/api/views/settlement.py` (add `settle_for_user`) |
| Edit | `app/api/urls.py` (add `/api/settle/for-user/`) |
| Edit | `app/static/js/wallet.js` (settlement signing functions) |
| Edit | `app/templates/partials/debt_summary.html` (settlement UI) |
| Edit | `app/templates/pages/settle.html` (settlement flow) |
| Edit | Various expense templates (encryption/decryption Hyperscript) |

---

## Session 5: Indexer Integration + ENS Gateway

**Goal:** Wire the Django app to read from the Envio indexer (via Hasura GraphQL). Hybrid approach: real-time queries for settlement status, background sync for friends/groups/expenses.

**Prerequisite:** Indexer from `indexer-01.md` must be running and populated.

### 5.1 Create Hasura client utility

**New file:** `app/api/utils/hasura_client.py`

```python
HASURA_URL = os.getenv('HASURA_GRAPHQL_ENDPOINT', 'http://kdio_hasura:8080') + '/v1/graphql'
HASURA_ADMIN_SECRET = os.getenv('HASURA_GRAPHQL_ADMIN_SECRET', '')

def query_hasura(query: str, variables: dict = None) -> dict:
    """Execute a GraphQL query against Hasura."""
    # POST to HASURA_URL with headers and JSON body
    # Return response data

def get_settlement_by_tx(tx_hash: str) -> dict | None:
    """Query a settlement by tx hash (real-time)."""

def get_settlements_for_user(address: str, limit: int = 50) -> list[dict]:
    """Query settlements involving a user (as sender or recipient)."""

def get_friends_for_user(address: str) -> list[dict]:
    """Query friend requests involving a user."""

def get_groups_for_user(address: str) -> list[dict]:
    """Query groups where user is a member."""

def get_expenses_for_group(group_id: int) -> list[dict]:
    """Query expenses for a group."""

def get_subname(label: str) -> dict | None:
    """Query a subname by label."""

def get_reputation(address: str) -> int:
    """Query a user's reputation score."""
```

### 5.2 Add Hasura settings

**File:** `app/config/settings.py`

```python
HASURA_GRAPHQL_ENDPOINT = os.getenv('HASURA_GRAPHQL_ENDPOINT', 'http://kdio_hasura:8080')
HASURA_GRAPHQL_ADMIN_SECRET = os.getenv('HASURA_GRAPHQL_ADMIN_SECRET', '')
```

### 5.3 Real-time settlement status

**File:** `app/api/views/settlement.py` — `status()`

Update the settlement status polling to query Hasura directly:

```python
def status(request, tx_hash):
    # First check local cache
    settlement = CachedSettlement.objects.filter(tx_hash=tx_hash).first()

    # Then query Hasura for latest on-chain status
    indexed = hasura_client.get_settlement_by_tx(tx_hash)
    if indexed:
        # Update local cache with confirmed data
        if settlement:
            settlement.status = CachedSettlement.Status.CONFIRMED
            settlement.save()
        # ... render confirmed card

    # If not yet indexed, render with polling trigger
    return render(request, 'lenses/settlement-card.html', {...})
```

### 5.4 Background sync for friends/groups/expenses

**New file:** `app/api/management/commands/sync_indexed_data.py`

Django management command that syncs indexed data from Hasura into `Cached*` models:

```python
class Command(BaseCommand):
    help = 'Sync indexed blockchain data from Hasura into local cache'

    def handle(self, *args, **options):
        self.sync_friends()
        self.sync_groups()
        self.sync_expenses()
        self.sync_settlements()
        self.sync_reputation()

    def sync_friends(self):
        # Query all FriendRequest entities from Hasura
        # Upsert into CachedFriend model
        # Match by friend pair addresses

    def sync_groups(self):
        # Query all Group + GroupMember entities
        # Upsert into CachedGroup + CachedGroupMember

    def sync_expenses(self):
        # Query all Expense entities
        # Upsert into CachedExpense

    def sync_settlements(self):
        # Query all Settlement entities
        # Upsert into CachedSettlement

    def sync_reputation(self):
        # Query ReputationScore entities
        # Update User.reputation_score
```

This can be run periodically via cron or a simple loop in a background thread/process.

### 5.5 Repurpose ENS gateway

**File:** `app/api/views/ens_gateway.py`

Rewrite to read from Hasura instead of local DB:

```python
def ens_gateway(request, sender, data):
    # Decode the CCIP-Read request
    # Query Hasura for:
    #   - Subname → owner address (AddrRecord)
    #   - TextRecord → text records
    # Sign the response with GATEWAY_SIGNER_KEY
    # Return the signed response
```

This replaces the current local DB queries with Hasura queries, so the ENS gateway always returns the latest on-chain data.

### 5.6 Update views to prefer indexed data

Where views currently query only local `Cached*` models, add a check for indexed data:
- If indexer is available, use Hasura data (fresher)
- If Hasura is unreachable, fall back to local cache
- This makes the app resilient to indexer downtime

**Commit:** `feat(app): integrate Envio indexer reads via Hasura, repurpose ENS gateway`

### Session 5 Verification

| Check | How |
|---|---|
| Settlement status updates from indexer | Submit settlement, poll status, see "Confirmed" |
| Sync command populates Cached models | Run `python manage.py sync_indexed_data`, check DB |
| ENS gateway reads from Hasura | Query `ens-gateway` endpoint, verify response matches on-chain data |
| App works when indexer is down | Stop indexer, verify app falls back to local cache |

### Files Modified

| Action | File |
|---|---|
| Create | `app/api/utils/hasura_client.py` |
| Edit | `app/config/settings.py` (Hasura settings) |
| Edit | `app/api/views/settlement.py` (real-time status from Hasura) |
| Create | `app/api/management/commands/sync_indexed_data.py` |
| Edit | `app/api/views/ens_gateway.py` (repurpose for indexer) |
| Edit | `app/.env.example` (Hasura env vars) |

---

## Session 6: Mobile Wallet Deep Linking

**Goal:** Add MetaMask mobile deep linking so the PWA works on mobile devices. Keep it simple — detect mobile, redirect to MetaMask deep link, handle the return.

### 6.1 Detect mobile in `wallet.js`

```javascript
function isMobile() {
    return /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}
```

### 6.2 Update `connectWallet()` for mobile

```javascript
window.connectWallet = async function() {
    let injected = window.ethereum?.providers?.[0] || window.ethereum || null;

    if (injected) {
        // Desktop or already in MetaMask browser — use injected provider
        // ... existing flow
    } else if (isMobile()) {
        // Mobile without injected provider — open MetaMask deep link
        const currentUrl = encodeURIComponent(window.location.href);
        window.location.href = `https://metamask.app.link/dapp/${window.location.host}${window.location.pathname}`;
        return null;
    } else {
        // Desktop without MetaMask
        alert('No wallet found. Please install MetaMask.');
        return null;
    }
};
```

**How it works:**
1. `metamask.app.link/dapp/{url}` opens MetaMask Mobile and navigates to the dApp URL in MetaMask's built-in browser
2. Inside MetaMask's browser, `window.ethereum` is available (injected provider)
3. The existing `connectWallet()` flow works normally from there

### 6.3 Handle deep link return

When MetaMask opens the dApp URL in its browser, the page reloads. Add auto-connect logic:

```javascript
// Auto-connect if we're in MetaMask's browser (has injected provider on load)
window.addEventListener('load', async () => {
    if (window.ethereum && isMobile()) {
        // We're in MetaMask's browser — auto-connect
        await window.connectWallet();
    }
});
```

### 6.4 Update signing flows for mobile

No changes needed — `signMessage()`, `signSettlementAuthorization()`, etc. all use `signer.signMessage()` / `signer.signTypedData()` which work the same in MetaMask's mobile browser.

### 6.5 Update onboarding wallet template

Add mobile-specific messaging:

```html
{% if not wallet_connected %}
  <p class="text-muted text-sm">
    On mobile? Tap "Connect Wallet" to open MetaMask.
  </p>
{% endif %}
```

**Commit:** `feat(app): add MetaMask mobile deep linking for PWA wallet support`

### Session 6 Verification

| Check | How |
|---|---|
| Desktop: unchanged behavior | Connect MetaMask extension, sign message |
| Mobile (no MetaMask): redirects to MetaMask app | Open PWA on phone, tap connect |
| Mobile (in MetaMask browser): auto-connects | After MetaMask opens dApp, wallet is connected |
| Signing works on mobile | Complete onboarding wallet flow on phone |

### Files Modified

| Action | File |
|---|---|
| Edit | `app/static/js/wallet.js` (mobile detection, deep link, auto-connect) |
| Edit | `app/templates/pages/onboarding-wallet.html` (mobile messaging) |

---

## Summary: Files Modified Across All Sessions

| Session | Files Created | Files Modified |
|---|---|---|
| 1: Foundation | `api/utils/circle_gateway.py` | `api/utils/web3_utils.py`, `static/js/wallet.js`, `config/settings.py`, `.env.example` |
| 2: Onboarding | `templates/partials/payment_preferences.html`, `api/views/profile.py` (maybe) | `api/views/auth.py`, `api/urls.py`, `web/views.py`, `templates/pages/profile.html` |
| 3: Social Graph | `static/js/keystore.js` | `api/views/friends.py`, `api/views/groups.py`, `static/js/wallet.js`, `static/js/crypto.js`, `templates/base.html`, various templates |
| 4: Expenses + Settlement | — | `api/views/expenses.py`, `api/views/settlement.py`, `api/urls.py`, `static/js/wallet.js`, various templates |
| 5: Indexer Integration | `api/utils/hasura_client.py`, `api/management/commands/sync_indexed_data.py` | `config/settings.py`, `api/views/settlement.py`, `api/views/ens_gateway.py`, `.env.example` |
| 6: Mobile Deep Linking | — | `static/js/wallet.js`, `templates/pages/onboarding-wallet.html` |

## Risks

| Risk | Mitigation |
|---|---|
| Backend wallet runs out of gas | Fund with enough Sepolia ETH, monitor balance |
| Circle Gateway API not accessible or rate-limited | Implement retry logic, have authorization flow as fallback |
| ECDH shared secret not symmetric due to signing nondeterminism | Use a truly deterministic message; ethers.js `signMessage` is deterministic for the same key+message |
| IndexedDB cleared by browser | Re-derive keys on next wallet connection (requires re-signing) |
| Friend/group/expense contract calls require user wallet tx | Documented in Session 3 — client submits these txs, not backend |
| Indexer not running when app starts | Graceful fallback to local cache |
| EIP-3009 `ReceiveWithAuthorization` domain/types may differ per USDC version | Verify against Sepolia USDC contract |

## Out of Scope

- Contract changes (all contracts are deployed and final)
- Farcaster integration (P1)
- IPFS frontend hosting (P1)
- Expense categorization UI (P1)
- Offline action queue (P1)
- Signal-style ratcheting (P2)
- QR codes for settlement (P2)
