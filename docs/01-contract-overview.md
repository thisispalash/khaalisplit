# khaaliSplit — Contract Architecture Overview

> High-level view of all contracts, their roles, and how they connect.

## System Architecture

```mermaid
graph TB
    subgraph deploy["Deployment Layer"]
        KD[kdioDeployer<br/><i>CREATE2 Factory</i>]
    end

    subgraph social["Social Layer — Sepolia"]
        KF[khaaliSplitFriends<br/><i>ECDH Keys + Friendships</i>]
        KG[khaaliSplitGroups<br/><i>Groups + Encrypted Keys</i>]
        KE[khaaliSplitExpenses<br/><i>Encrypted Expense Hashes</i>]
    end

    subgraph identity["Identity Layer — Sepolia"]
        KSub[khaaliSplitSubnames<br/><i>ENS Registrar + Resolver</i>]
        NW[ENS NameWrapper<br/><i>External</i>]
    end

    subgraph payment["Settlement Layer — All Chains"]
        KSet[khaaliSplitSettlement<br/><i>USDC Payment Router</i>]
        GW[Circle Gateway Wallet<br/><i>External</i>]
        GM[Circle Gateway Minter<br/><i>External</i>]
        TM[CCTP TokenMessengerV2<br/><i>External</i>]
    end

    subgraph reputation["Reputation Layer — Sepolia"]
        KR[khaaliSplitReputation<br/><i>Score 0–100</i>]
    end

    %% Social layer dependencies
    KG -->|checks friendship| KF
    KE -->|checks membership| KG

    %% Identity interactions
    KSub -->|registers subnames| NW

    %% Settlement reads from identity
    KSet -->|reads payment prefs<br/>addr + text records| KSub

    %% Settlement routes payments
    KSet -->|default: depositFor| GW
    KSet -->|opt-in: depositForBurn| TM
    KSet -->|cross-chain mint: gatewayMint| GM

    %% Settlement updates reputation
    KSet -->|recordSettlement| KR

    %% Reputation syncs to ENS
    KR -->|setText reputation score| KSub

    %% Deployer deploys all
    KD -.->|deploys proxies| KF
    KD -.->|deploys proxies| KG
    KD -.->|deploys proxies| KE
    KD -.->|deploys proxies| KSub
    KD -.->|deploys proxies| KR
    KD -.->|deploys proxies| KSet

    classDef internal fill:#4a9eff,stroke:#2563eb,color:#fff
    classDef external fill:#f59e0b,stroke:#d97706,color:#fff
    classDef deployer fill:#8b5cf6,stroke:#7c3aed,color:#fff

    class KF,KG,KE,KSub,KSet,KR internal
    class NW,GW,GM,TM external
    class KD deployer
```

## Contract Summary

| Contract | Chain(s) | Role | Upgradeable |
|----------|----------|------|:-----------:|
| **kdioDeployer** | All | CREATE2 factory — deploys ERC1967Proxy instances at deterministic addresses | No (stateless) |
| **khaaliSplitFriends** | Sepolia | ECDH public key registry + bidirectional friend graph | UUPS |
| **khaaliSplitGroups** | Sepolia | Group creation + invite/accept with encrypted AES group keys | UUPS |
| **khaaliSplitExpenses** | Sepolia | Expense hash storage + encrypted data emission via events | UUPS |
| **khaaliSplitSubnames** | Sepolia | ENS `{user}.khaalisplit.eth` registrar + on-chain text/addr resolver | UUPS |
| **khaaliSplitReputation** | Sepolia | Per-user reputation score (0–100), auto-synced to ENS text records | UUPS |
| **khaaliSplitSettlement** | All | USDC payment router — EIP-3009 auth + Gateway/CCTP routing | UUPS |

## Inter-Contract Call Flow

A single settlement touches nearly every contract. This sequence shows the full chain of cross-contract calls.

```mermaid
sequenceDiagram
    actor User
    participant Backend
    participant Friends as khaaliSplitFriends
    participant Groups as khaaliSplitGroups
    participant Expenses as khaaliSplitExpenses
    participant Subnames as khaaliSplitSubnames
    participant NW as ENS NameWrapper
    participant Settlement as khaaliSplitSettlement
    participant USDC
    participant GW as Gateway Wallet
    participant Rep as khaaliSplitReputation

    rect rgb(240, 249, 255)
        Note right of User: Phase 1 — Onboarding
        Backend ->> Friends: registerPubKey(user, pubKey)
        Backend ->> Subnames: register("alice", user)
        Subnames ->> NW: setSubnodeRecord(parentNode, ...)
        Backend ->> Rep: setUserNode(user, node)
    end

    rect rgb(240, 255, 244)
        Note right of User: Phase 2 — Social
        User ->> Friends: requestFriend(bob)
        User ->> Groups: createGroup(nameHash, encKey)
        Groups ->> Friends: registered(user)?
        User ->> Groups: inviteMember(1, bob, encKeyForBob)
        Groups ->> Friends: isFriend(user, bob)?
    end

    rect rgb(255, 247, 237)
        Note right of User: Phase 3 — Expenses
        User ->> Expenses: addExpense(groupId, hash, encData)
        Expenses ->> Groups: isMember(groupId, user)?
    end

    rect rgb(245, 243, 255)
        Note right of User: Phase 4 — Settlement
        User ->> Settlement: settleWithAuthorization(node, amt, ...)
        Settlement ->> Subnames: addr(node)
        Settlement ->> Subnames: text(node, "payment.token")
        Settlement ->> USDC: receiveWithAuthorization(...)
        Settlement ->> Subnames: text(node, "payment.flow")
        Settlement ->> GW: depositFor(token, recipient, amt)
        Settlement ->> Rep: recordSettlement(sender, true)
        Rep ->> Subnames: setText(node, "reputation", "51")
    end
```

## Social Layer Dependency Chain

The Social layer forms a strict dependency chain where each contract validates against the previous one.

```mermaid
sequenceDiagram
    actor Alice
    participant Friends as khaaliSplitFriends
    participant Groups as khaaliSplitGroups
    participant Expenses as khaaliSplitExpenses

    Note over Alice,Expenses: Every action validates against the upstream contract

    Alice ->> Friends: registerPubKey(alice, pubKey)
    Note over Friends: registered[alice] = true

    Alice ->> Groups: createGroup(nameHash, encKey)
    Groups ->> Friends: registered(alice)?
    Friends -->> Groups: true ✓
    Note over Groups: Group #1 created, alice is member

    Alice ->> Groups: inviteMember(1, bob, encKeyForBob)
    Groups ->> Friends: isFriend(alice, bob)?
    Friends -->> Groups: true ✓
    Note over Groups: isInvited[1][bob] = true

    Alice ->> Expenses: addExpense(1, dataHash, encData)
    Expenses ->> Groups: isMember(1, alice)?
    Groups -->> Expenses: true ✓
    Note over Expenses: Expense #1 stored

    Alice ->> Expenses: updateExpense(1, newHash, newData)
    Expenses ->> Groups: isMember(1, alice)?
    Groups -->> Expenses: true ✓
    Note over Expenses: Only creator can update
```

## Key Design Patterns

- **All contracts are UUPS upgradeable** — `Initializable` + `UUPSUpgradeable` + `OwnableUpgradeable`
- **CREATE2 deterministic deployment** — same proxy addresses across chains (Settlement)
- **ENS as identity backbone** — subname nodes are the canonical user identifier
- **Client-side encryption** — contracts store only hashes; encrypted blobs in events
- **USDC only** — single approved token across all chains
