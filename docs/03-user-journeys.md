# khaaliSplit — User Journey Flows

> End-to-end flows from a user's perspective: onboarding, social graph, expense tracking, and settlement.

## Complete User Journey
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`03-user-journeys-1.png`](./img/03-user-journeys-1.png)
>
> </details>

```mermaid
graph LR
    A[Register] --> B[Add Friends]
    B --> C[Create Group]
    C --> D[Add Expenses]
    D --> E[Settle Debts]
    E --> F[Reputation Updated]

    classDef step fill:#4a9eff,stroke:#2563eb,color:#fff
    class A,B,C,D,E,F step
```

---

## 1. Onboarding Flow

A new user registers their wallet, gets an ENS subname, and is linked into the reputation system.
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`03-user-journeys-2.png`](./img/03-user-journeys-2.png)
>
> </details>

```mermaid
sequenceDiagram
    actor User
    participant PWA as PWA Client
    participant Backend
    participant Friends as khaaliSplitFriends
    participant Subnames as khaaliSplitSubnames
    participant NW as ENS NameWrapper
    participant Rep as khaaliSplitReputation

    User ->> PWA: Connect wallet
    PWA ->> PWA: Derive ECDH public key<br/>from wallet signature

    PWA ->> Backend: Send pubkey + chosen username

    par Register public key
        Backend ->> Friends: registerPubKey(user, pubKey)
        Note over Friends: registered[user] = true<br/>walletPubKey[user] = pubKey
    and Register ENS subname
        Backend ->> Subnames: register("alice", userAddr)
        Subnames ->> NW: setSubnodeRecord(<br/>  parentNode, "alice", user,<br/>  resolver=this, fuses=0,<br/>  expiry=max)
        Note over Subnames: Sets defaults:<br/>text("subname") = "alice"<br/>text("reputation") = "50"<br/>addr(node) = userAddr
    and Link reputation node
        Backend ->> Rep: setUserNode(user, aliceNode)
        Note over Rep: userNodes[user] = node<br/>Ready for settlement scoring
    end

    Backend -->> PWA: Onboarding complete
    PWA -->> User: alice.khaalisplit.eth is yours!
```

---

## 2. Social Graph Flow

Users build their friend graph and form expense-splitting groups.
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`03-user-journeys-3.png`](./img/03-user-journeys-3.png)
>
> </details>

```mermaid
sequenceDiagram
    actor Alice
    actor Bob
    participant Friends as khaaliSplitFriends
    participant Groups as khaaliSplitGroups

    Note over Alice,Bob: Both already registered (onboarding complete)

    rect rgb(240, 249, 255)
        Note right of Alice: Friend Request Flow
        Alice ->> Friends: requestFriend(bob)
        Note over Friends: pendingRequest[alice][bob] = true

        alt Bob also requests Alice (mutual)
            Bob ->> Friends: requestFriend(alice)
            Note over Friends: Detects mutual request<br/>Auto-accepts!<br/>isFriend[alice][bob] = true<br/>isFriend[bob][alice] = true
        else Bob accepts explicitly
            Bob ->> Friends: acceptFriend(alice)
            Note over Friends: isFriend bidirectional = true
        end
    end

    rect rgb(240, 255, 244)
        Note right of Alice: Group Creation Flow
        Alice ->> Alice: Generate AES-256 group key
        Alice ->> Alice: Encrypt key with<br/>ECDH(alice, alice) shared secret

        Alice ->> Groups: createGroup(nameHash, encryptedKey)
        Note over Groups: Group #1 created<br/>alice = creator + member

        Alice ->> Alice: Encrypt group key with<br/>ECDH(alice, bob) shared secret

        Alice ->> Groups: inviteMember(1, bob, encryptedKeyForBob)
        Groups ->> Friends: isFriend(alice, bob)?
        Friends -->> Groups: true
        Note over Groups: isInvited[1][bob] = true

        Bob ->> Groups: acceptGroupInvite(1)
        Note over Groups: isMember[1][bob] = true<br/>memberCount = 2
    end
```

---

## 3. Expense Tracking Flow

Group members add and update encrypted expenses. Only hashes are stored on-chain; full encrypted data is emitted in events for off-chain indexing.
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`03-user-journeys-4.png`](./img/03-user-journeys-4.png)
>
> </details>

```mermaid
sequenceDiagram
    actor Alice
    participant PWA as PWA Client
    participant Expenses as khaaliSplitExpenses
    participant Groups as khaaliSplitGroups
    participant Indexer as Off-chain Indexer

    rect rgb(255, 247, 237)
        Note right of Alice: Add Expense
        Alice ->> PWA: "Dinner $60, split 3 ways"

        PWA ->> PWA: Build expense JSON:<br/>{amount: 60, splits: [...],<br/> description: "Dinner"}

        PWA ->> PWA: Encrypt with group AES key<br/>Hash plaintext → dataHash

        Alice ->> Expenses: addExpense(groupId,<br/>  dataHash, encryptedData)
        Expenses ->> Groups: isMember(groupId, alice)?
        Groups -->> Expenses: true

        Note over Expenses: Stores: {groupId, creator,<br/>dataHash, timestamp}<br/>Expense #1 created

        Expenses -->> Indexer: ExpenseAdded event<br/>(includes encryptedData blob)

        Note over Indexer: Stores encrypted blob<br/>for group members to<br/>fetch and decrypt
    end

    rect rgb(245, 243, 255)
        Note right of Alice: Update Expense
        Alice ->> PWA: Edit expense → $75

        PWA ->> PWA: Re-encrypt + re-hash

        Alice ->> Expenses: updateExpense(1,<br/>  newDataHash, newEncryptedData)
        Note over Expenses: Only creator can update<br/>Must still be group member

        Expenses -->> Indexer: ExpenseUpdated event
    end
```

---

## 4. Settlement Flow (Simplified User Perspective)

After expenses are tallied client-side, the payer settles their debt in USDC.
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`03-user-journeys-5.png`](./img/03-user-journeys-5.png)
>
> </details>

```mermaid
sequenceDiagram
    actor Alice as Alice (payer)
    actor Bob as Bob (recipient)
    participant PWA as PWA Client
    participant Settlement as khaaliSplitSettlement
    participant USDC
    participant Rep as khaaliSplitReputation

    PWA ->> PWA: Calculate net debts<br/>from decrypted expenses<br/>Alice owes Bob $20

    Note over Alice: Signs EIP-3009<br/>ReceiveWithAuthorization<br/>for 20 USDC

    alt In-person (NFC/Bluetooth)
        Alice -->> Bob: Transmit signature via NFC
        Bob ->> Settlement: settleWithAuthorization(...)
    else Remote (backend relay)
        Alice ->> PWA: Submit settlement
        PWA ->> Settlement: settleWithAuthorization(...)
    end

    Settlement ->> USDC: Pull 20 USDC from Alice
    Settlement ->> Settlement: Route to Bob per<br/>his ENS preferences
    Settlement ->> Rep: recordSettlement(alice, true)

    Note over Rep: Alice's reputation: 50 → 51

    Settlement -->> PWA: SettlementCompleted event
    PWA -->> Alice: Debt settled!
    PWA -->> Bob: Payment received!
```

---

## End-to-End Summary
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`03-user-journeys-6.png`](./img/03-user-journeys-6.png)
>
> </details>

```mermaid
graph TD
    subgraph onboard["1. Onboarding"]
        R1[Register ECDH pubkey]
        R2[Register ENS subname]
        R3[Link reputation node]
    end

    subgraph social["2. Social Graph"]
        S1[Request / accept friends]
        S2[Create group + AES key]
        S3[Invite friends to group]
    end

    subgraph expense["3. Expenses"]
        E1[Add encrypted expense]
        E2[Update expense]
        E3[Client decrypts + tallies]
    end

    subgraph settle["4. Settlement"]
        P1[Sign EIP-3009 auth]
        P2[Submit to Settlement contract]
        P3[Route via Gateway or CCTP]
        P4[Reputation updated + synced to ENS]
    end

    onboard --> social --> expense --> settle

    classDef phase fill:#4a9eff,stroke:#2563eb,color:#fff
    classDef step fill:#e0f2fe,stroke:#0284c7,color:#0c4a6e

    class R1,R2,R3,S1,S2,S3,E1,E2,E3,P1,P2,P3,P4 step
```
