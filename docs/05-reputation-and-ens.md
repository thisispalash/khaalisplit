# khaaliSplit — Reputation & ENS Identity System

> How on-chain reputation scoring works and how it integrates with ENS subnames as the identity backbone.

## ENS as Identity Backbone

Every khaaliSplit user gets an ENS subname (`{user}.khaalisplit.eth`) that serves as their on-chain identity. The subname node (`bytes32`) is the canonical identifier used across the entire system.

```mermaid
graph TB
    subgraph ens["ENS Identity: alice.khaalisplit.eth"]
        NODE["bytes32 node<br/><i>namehash('alice.khaalisplit.eth')</i>"]

        subgraph records["On-Chain Records (khaaliSplitSubnames)"]
            ADDR["addr(node) → 0xAlice..."]
            T1["text('com.khaalisplit.subname') → 'alice'"]
            T2["text('com.khaalisplit.reputation') → '51'"]
            T3["text('com.khaalisplit.payment.flow') → 'gateway'"]
            T4["text('com.khaalisplit.payment.token') → '0x833...'"]
            T5["text('com.khaalisplit.payment.chain') → '8453'"]
            T6["text('com.khaalisplit.payment.cctp') → '6'"]
        end
    end

    subgraph consumers["Who Reads These Records"]
        SET["Settlement Contract<br/><i>reads addr, payment.*</i>"]
        REP["Reputation Contract<br/><i>writes reputation score</i>"]
        CLIENT["PWA Client<br/><i>reads all records</i>"]
    end

    NODE --> records
    SET -->|reads| ADDR
    SET -->|reads| T3
    SET -->|reads| T4
    REP -->|writes| T2
    CLIENT -->|reads| records

    classDef node fill:#8b5cf6,stroke:#7c3aed,color:#fff
    classDef record fill:#e0f2fe,stroke:#0284c7,color:#0c4a6e
    classDef consumer fill:#4a9eff,stroke:#2563eb,color:#fff

    class NODE node
    class ADDR,T1,T2,T3,T4,T5,T6 record
    class SET,REP,CLIENT consumer
```

---

## Reputation Score Mechanics

```mermaid
graph LR
    subgraph scoring["Score Range: 0–100"]
        MIN["0<br/><i>Floor</i>"]
        DEFAULT["50<br/><i>Default</i>"]
        MAX["100<br/><i>Cap</i>"]
    end

    SUCCESS["+1 per successful<br/>settlement"] -->|min cap| MAX
    FAILURE["-5 per failed<br/>settlement"] -->|floor| MIN

    classDef good fill:#10b981,stroke:#059669,color:#fff
    classDef bad fill:#ef4444,stroke:#dc2626,color:#fff
    classDef neutral fill:#f59e0b,stroke:#d97706,color:#fff

    class SUCCESS good
    class FAILURE bad
    class DEFAULT neutral
    class MIN bad
    class MAX good
```

| Scenario | Delta | Example |
|----------|-------|---------|
| Successful settlement | +1 | 50 → 51 → 52 → ... → 100 (cap) |
| Failed settlement | -5 | 50 → 45 → 40 → ... → 0 (floor) |
| New user (no settlements) | — | Returns default 50 |
| Score exactly at 5 | -5 | 5 → 0 (exact boundary) |
| Score below 5 (e.g. 3) | -5 | 3 → 0 (underflow protection) |

---

## Reputation Update & ENS Sync Flow

After every settlement, the reputation score is updated and automatically synced to the user's ENS text record.

```mermaid
sequenceDiagram
    participant Settlement as khaaliSplitSettlement
    participant Rep as khaaliSplitReputation
    participant Subnames as khaaliSplitSubnames
    participant NW as ENS NameWrapper

    Note over Settlement: Settlement completed<br/>(EIP-3009 or Gateway Mint)

    Settlement ->> Rep: recordSettlement(sender, true)

    Note over Rep: First call for user?<br/>Initialize score to 50

    Rep ->> Rep: score = min(score + 1, 100)
    Rep ->> Rep: scores[sender] = 51

    Rep -->> Rep: emit ReputationUpdated(<br/>  sender, 51, true)

    Rep ->> Subnames: setText(userNode,<br/>  "com.khaalisplit.reputation",<br/>  "51")

    Note over Subnames: _isAuthorized check:<br/>caller == reputationContract? ✓

    Subnames ->> Subnames: _texts[node]["reputation"] = "51"
    Subnames -->> Subnames: emit TextRecordSet(node, key, "51")

    Note over Subnames: Score now readable by<br/>any ENS client or contract<br/>via text(node, key)
```

---

## Subname Registration Sequence

How a new ENS subname is registered and wired into the system:

```mermaid
sequenceDiagram
    actor User
    participant PWA as PWA Client
    participant Backend
    participant Subnames as khaaliSplitSubnames
    participant NW as ENS NameWrapper
    participant Rep as khaaliSplitReputation

    User ->> PWA: Choose username "alice"
    PWA ->> Backend: Request registration

    Backend ->> Subnames: register("alice", userAddr)

    Note over Subnames: Checks:<br/>msg.sender == backend? ✓<br/>label not empty? ✓<br/>owner != address(0)? ✓

    Subnames ->> NW: ownerOf(uint256(node))
    NW -->> Subnames: address(0) (not registered)

    Subnames ->> NW: setSubnodeRecord(<br/>  parentNode, "alice",<br/>  userAddr, resolver=this,<br/>  ttl=0, fuses=0,<br/>  expiry=max)

    Note over NW: alice.khaalisplit.eth<br/>now exists in ENS!<br/>Owner = userAddr<br/>Resolver = Subnames contract

    Subnames ->> Subnames: Set default records:<br/>text("subname") = "alice"<br/>text("reputation") = "50"<br/>addr(node) = userAddr

    Subnames -->> Backend: SubnameRegistered event

    Note over Backend: Now link user to<br/>reputation system

    Backend ->> Rep: setUserNode(userAddr, aliceNode)
    Note over Rep: userNodes[userAddr] = node<br/>Ready for scoring!

    Backend -->> PWA: Registration complete
    PWA -->> User: alice.khaalisplit.eth is yours!
```

---

## Record Update Authorization Sequence

How the `_isAuthorized` check works when different callers try to set records:

```mermaid
sequenceDiagram
    participant Caller
    participant Subnames as khaaliSplitSubnames
    participant NW as ENS NameWrapper

    Note over Caller,NW: Case 1: Backend sets a record

    Caller ->> Subnames: setText(node, key, value)
    Subnames ->> Subnames: _isAuthorized(node, caller)
    Note over Subnames: caller == backend?<br/>✓ YES → authorized
    Subnames ->> Subnames: _texts[node][key] = value
    Subnames -->> Caller: TextRecordSet event

    Note over Caller,NW: Case 2: Reputation contract syncs score

    Caller ->> Subnames: setText(node, "reputation", "51")
    Subnames ->> Subnames: _isAuthorized(node, caller)
    Note over Subnames: caller == backend? No<br/>reputationContract != 0 &&<br/>caller == reputationContract?<br/>✓ YES → authorized
    Subnames ->> Subnames: _texts[node]["reputation"] = "51"

    Note over Caller,NW: Case 3: Subname owner sets own record

    Caller ->> Subnames: setText(node, "avatar", "url")
    Subnames ->> Subnames: _isAuthorized(node, caller)
    Note over Subnames: caller == backend? No<br/>caller == reputationContract? No
    Subnames ->> NW: ownerOf(uint256(node))
    NW -->> Subnames: ownerAddress
    Note over Subnames: caller == ownerAddress?<br/>✓ YES → authorized

    Note over Caller,NW: Case 4: Unauthorized caller

    Caller ->> Subnames: setText(node, key, value)
    Subnames ->> Subnames: _isAuthorized(node, caller)
    Note over Subnames: Not backend, not reputation,<br/>not owner → REVERT
    Subnames -->> Caller: Unauthorized()
```

---

## Authorization Model

Three contracts share a trust relationship for reading and writing ENS records:

```mermaid
graph TD
    subgraph writers["Who Can Write Records"]
        BACKEND["Backend<br/><i>registers subnames,<br/>sets any record</i>"]
        OWNER["Subname Owner<br/><i>sets own records<br/>via NameWrapper.ownerOf</i>"]
        REP["Reputation Contract<br/><i>writes reputation score<br/>after settlements</i>"]
    end

    subgraph sub["khaaliSplitSubnames"]
        AUTH{"_isAuthorized(node, caller)"}
        RECORDS["Text & Addr Records"]
    end

    subgraph readers["Who Reads Records"]
        SETTLEMENT["Settlement Contract<br/><i>payment preferences</i>"]
        CLIENT["PWA / Any ENS Client<br/><i>public view functions</i>"]
    end

    BACKEND -->|"caller == backend"| AUTH
    OWNER -->|"caller == ownerOf(node)"| AUTH
    REP -->|"caller == reputationContract"| AUTH
    AUTH -->|authorized| RECORDS
    RECORDS -->|"text() / addr()"| SETTLEMENT
    RECORDS -->|"text() / addr()"| CLIENT

    classDef writer fill:#f59e0b,stroke:#d97706,color:#fff
    classDef auth fill:#8b5cf6,stroke:#7c3aed,color:#fff
    classDef reader fill:#10b981,stroke:#059669,color:#fff

    class BACKEND,OWNER,REP writer
    class AUTH auth
    class SETTLEMENT,CLIENT reader
```

---

## Reputation Sentinel Value

When the reputation contract is not configured on the settlement contract (`address(0)`), the `SettlementCompleted` event emits a sentinel value of **500** for `senderReputation`. This is distinguishable from valid scores (0–100) and lets indexers/clients know that reputation was not tracked for this settlement.

```mermaid
graph LR
    SET[Settlement Contract]

    SET -->|"reputationContract != 0"| NORMAL["recordSettlement(sender, true)<br/>→ returns actual score (0–100)"]
    SET -->|"reputationContract == 0"| SENTINEL["Skip reputation update<br/>→ emit 500 (sentinel)"]

    classDef normal fill:#10b981,stroke:#059669,color:#fff
    classDef sentinel fill:#94a3b8,stroke:#64748b,color:#fff

    class NORMAL normal
    class SENTINEL sentinel
```

---

## Encryption Model

The contract system supports three tiers of client-side encryption. Contracts never see plaintext data.

```mermaid
graph TD
    subgraph tier1["Tier 1: Friend Pairing (ECDH)"]
        PK["Wallet ECDH pubkeys<br/><i>stored on-chain via registerPubKey</i>"]
        SS["Pairwise shared secret<br/><i>computed client-side<br/>ECDH(myPriv, theirPub)</i>"]
        PK --> SS
    end

    subgraph tier2["Tier 2: Group Key (AES-256-GCM)"]
        GK["Group AES key<br/><i>generated by creator</i>"]
        EGK["Per-member encrypted copies<br/><i>encryptedGroupKey[groupId][member]<br/>encrypted with pairwise secret</i>"]
        GK --> EGK
    end

    subgraph tier3["Tier 3: Expense Data"]
        EXP["Expense JSON<br/><i>amounts, splits, description</i>"]
        HASH["keccak256 hash<br/><i>stored on-chain (dataHash)</i>"]
        BLOB["Encrypted blob<br/><i>emitted in ExpenseAdded event<br/>indexed off-chain</i>"]
        EXP --> HASH
        EXP --> BLOB
    end

    SS -->|"encrypts"| EGK
    GK -->|"encrypts"| BLOB

    classDef t1 fill:#4a9eff,stroke:#2563eb,color:#fff
    classDef t2 fill:#8b5cf6,stroke:#7c3aed,color:#fff
    classDef t3 fill:#10b981,stroke:#059669,color:#fff

    class PK,SS t1
    class GK,EGK t2
    class EXP,HASH,BLOB t3
```

### Encryption Key Exchange Sequence

How encrypted group keys are distributed when creating a group and inviting members:

```mermaid
sequenceDiagram
    actor Alice
    participant PWA_A as Alice's PWA
    participant Friends as khaaliSplitFriends
    participant Groups as khaaliSplitGroups
    participant PWA_B as Bob's PWA
    actor Bob

    Note over Alice: Step 1: Derive shared secrets

    PWA_A ->> Friends: getPubKey(alice)
    Friends -->> PWA_A: alicePubKey (ECDH)

    PWA_A ->> Friends: getPubKey(bob)
    Friends -->> PWA_A: bobPubKey (ECDH)

    PWA_A ->> PWA_A: selfSecret = ECDH(alicePriv, alicePub)
    PWA_A ->> PWA_A: pairSecret = ECDH(alicePriv, bobPub)

    Note over Alice: Step 2: Create group

    PWA_A ->> PWA_A: groupKey = random AES-256 key
    PWA_A ->> PWA_A: encKeyForAlice = AES.encrypt(<br/>  groupKey, selfSecret)

    Alice ->> Groups: createGroup(nameHash, encKeyForAlice)
    Note over Groups: Group #1 created<br/>encryptedGroupKey[1][alice]<br/>= encKeyForAlice

    Note over Alice: Step 3: Invite Bob

    PWA_A ->> PWA_A: encKeyForBob = AES.encrypt(<br/>  groupKey, pairSecret)

    Alice ->> Groups: inviteMember(1, bob, encKeyForBob)
    Note over Groups: encryptedGroupKey[1][bob]<br/>= encKeyForBob

    Note over Bob: Step 4: Bob decrypts

    Bob ->> Groups: acceptGroupInvite(1)

    PWA_B ->> Groups: encryptedGroupKey(1, bob)
    Groups -->> PWA_B: encKeyForBob

    PWA_B ->> Friends: getPubKey(alice)
    Friends -->> PWA_B: alicePubKey

    PWA_B ->> PWA_B: pairSecret = ECDH(bobPriv, alicePub)
    Note over PWA_B: Same shared secret as Alice<br/>computed (ECDH is symmetric)

    PWA_B ->> PWA_B: groupKey = AES.decrypt(<br/>  encKeyForBob, pairSecret)

    Note over Bob: Bob now has the group AES key<br/>and can encrypt/decrypt expenses!
```
