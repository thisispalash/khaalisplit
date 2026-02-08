# khaaliSplit — Deployment & Cross-Chain Architecture

> How contracts are deployed deterministically and how the system spans multiple chains.

## Cross-Chain Topology
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`04-deployment-and-cross-chain-1.png`](./img/04-deployment-and-cross-chain-1.png)
>
> </details>

```mermaid
graph TB
    subgraph sepolia["Sepolia (Home Chain)"]
        direction TB
        KD1[kdioDeployer]
        KF[khaaliSplitFriends]
        KG[khaaliSplitGroups]
        KE[khaaliSplitExpenses]
        KSub[khaaliSplitSubnames]
        KR[khaaliSplitReputation]
        KS1[khaaliSplitSettlement]
        NW[ENS NameWrapper]
        U1[USDC]
    end

    subgraph base["Base Sepolia"]
        direction TB
        KD2[kdioDeployer]
        KS2[khaaliSplitSettlement<br/><i>Same CREATE2 address</i>]
        U2[USDC]
    end

    subgraph arc["Arc Testnet"]
        direction TB
        KD3[kdioDeployer]
        KS3[khaaliSplitSettlement<br/><i>Same CREATE2 address</i>]
        U3[USDC]
    end

    subgraph circle["Circle Infrastructure"]
        GW[Gateway Wallet<br/><i>0x00777...19B9</i>]
        GM[Gateway Minter<br/><i>0x00222...475B</i>]
        TM[TokenMessengerV2]
        API[Circle Gateway API]
    end

    KS1 <-->|"CCTP burn/mint<br/>domain 0 ↔ 6"| KS2
    KS1 -->|Gateway deposit| GW
    KS2 -->|Gateway deposit| GW
    KS3 -->|Gateway deposit| GW
    GM -->|mint USDC| KS1
    GM -->|mint USDC| KS2

    classDef home fill:#4a9eff,stroke:#2563eb,color:#fff
    classDef remote fill:#10b981,stroke:#059669,color:#fff
    classDef infra fill:#f59e0b,stroke:#d97706,color:#fff
    classDef deployer fill:#8b5cf6,stroke:#7c3aed,color:#fff

    class KF,KG,KE,KSub,KR,KS1 home
    class KS2,KS3 remote
    class GW,GM,TM,API infra
    class KD1,KD2,KD3 deployer
    class NW,U1,U2,U3 infra
```

---

## CREATE2 Deterministic Deployment

The `kdioDeployer` factory ensures the same proxy address across all chains for the Settlement contract.
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`04-deployment-and-cross-chain-2.png`](./img/04-deployment-and-cross-chain-2.png)
>
> </details>

```mermaid
sequenceDiagram
    participant Deployer as Deployer EOA
    participant Factory as kdioDeployer
    participant Impl as Settlement Implementation
    participant Proxy as ERC1967Proxy

    Note over Deployer: Step 1: Deploy factory<br/>(same nonce → same address)

    Deployer ->> Factory: deploy (regular CREATE)

    Note over Deployer: Step 2: Deploy implementation<br/>(address doesn't matter)

    Deployer ->> Impl: deploy (regular CREATE)

    Note over Deployer: Step 3: Deploy proxy via CREATE2<br/>(deterministic address!)

    Deployer ->> Factory: deploy(salt, impl, initData="")
    Factory ->> Proxy: new ERC1967Proxy{salt}(impl, "")

    Note over Factory: Address = keccak256(<br/>  0xff ++ factory ++ salt ++<br/>  keccak256(creationCode)<br/>)<br/><br/>Empty initData = identical<br/>creationCode on every chain

    Note over Deployer: Step 4: Initialize separately<br/>(chain-specific params)

    Deployer ->> Proxy: initialize(owner)

    Note over Proxy: Post-init config (owner-only):<br/>• addToken(USDC_address)<br/>• setTokenMessenger(...)<br/>• configureDomain(...)<br/>• setGatewayWallet(...)<br/>• setSubnameRegistry(...)<br/>• setReputationContract(...)
```

---

## Deployment Order

Two deployment scripts handle the full system:

### `DeployCore.s.sol` — Home Chain (Sepolia)
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`04-deployment-and-cross-chain-3.png`](./img/04-deployment-and-cross-chain-3.png)
>
> </details>

```mermaid
graph TD
    D1["1. Deploy kdioDeployer"] --> D2["2. Deploy Friends impl"]
    D2 --> D3["3. Deploy Friends proxy<br/>(CREATE2 + initialize)"]
    D3 --> D4["4. Deploy Groups impl"]
    D4 --> D5["5. Deploy Groups proxy<br/>(init with Friends addr)"]
    D5 --> D6["6. Deploy Expenses impl"]
    D6 --> D7["7. Deploy Expenses proxy<br/>(init with Groups addr)"]
    D7 --> D8["8. Deploy Subnames impl"]
    D8 --> D9["9. Deploy Subnames proxy<br/>(init with NameWrapper,<br/>parentNode, backend)"]
    D9 --> D10["10. Deploy Reputation impl"]
    D10 --> D11["11. Deploy Reputation proxy<br/>(init with backend,<br/>subnamesProxy)"]
    D11 --> D12["12. Wire: subnames<br/>.setReputationContract(<br/>reputationProxy)"]

    classDef deploy fill:#4a9eff,stroke:#2563eb,color:#fff
    classDef wire fill:#f59e0b,stroke:#d97706,color:#fff

    class D1,D2,D3,D4,D5,D6,D7,D8,D9,D10,D11 deploy
    class D12 wire
```

### `DeploySettlement.s.sol` — Each Chain
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`04-deployment-and-cross-chain-4.png`](./img/04-deployment-and-cross-chain-4.png)
>
> </details>

```mermaid
graph TD
    S1["1. Deploy Settlement impl"] --> S2["2. Deploy proxy via<br/>kdioDeployer (CREATE2,<br/>empty initData)"]
    S2 --> S3["3. initialize(owner)"]
    S3 --> S4["4. addToken(USDC)"]
    S4 --> S5["5. setTokenMessenger(<br/>from cctp.json)"]
    S5 --> S6["6. configureDomain(<br/>for each chain pair)"]
    S6 --> S7["7. setGatewayWallet(<br/>from cctp.json)"]
    S7 --> S8["8. setGatewayMinter(<br/>from cctp.json)"]
    S8 --> S9["9. setSubnameRegistry(<br/>Sepolia proxy addr)"]
    S9 --> S10["10. setReputationContract(<br/>Sepolia proxy addr)"]

    classDef step fill:#10b981,stroke:#059669,color:#fff
    class S1,S2,S3,S4,S5,S6,S7,S8,S9,S10 step
```

---

## UUPS Upgrade Pattern

All contracts (except kdioDeployer) follow the same upgrade pattern:
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`04-deployment-and-cross-chain-5.png`](./img/04-deployment-and-cross-chain-5.png)
>
> </details>

```mermaid
graph LR
    subgraph proxy["ERC1967Proxy (fixed address)"]
        P[Storage + Delegatecall]
    end

    subgraph v1["Implementation V1"]
        I1[Contract Logic V1]
    end

    subgraph v2["Implementation V2"]
        I2[Contract Logic V2]
    end

    P -->|"delegatecall<br/>(current)"| I1
    P -.->|"upgradeTo(v2)<br/>owner only"| I2

    classDef proxy fill:#8b5cf6,stroke:#7c3aed,color:#fff
    classDef impl fill:#4a9eff,stroke:#2563eb,color:#fff
    classDef future fill:#94a3b8,stroke:#64748b,color:#fff

    class P proxy
    class I1 impl
    class I2 future
```

**Key properties:**
- Proxy address never changes (users and other contracts always call the same address)
- Storage lives in the proxy, logic lives in the implementation
- Only the contract owner can trigger upgrades (`_authorizeUpgrade` + `onlyOwner`)
- Constructor calls `_disableInitializers()` to prevent direct implementation initialization

---

## Cross-Chain Settlement Sequence (CCTP End-to-End)

How a payment moves from Sepolia to Base via CCTP burn-and-mint:
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`04-deployment-and-cross-chain-6.png`](./img/04-deployment-and-cross-chain-6.png)
>
> </details>

```mermaid
sequenceDiagram
    actor Alice as Alice (Sepolia)
    participant SetS as Settlement<br/>(Sepolia)
    participant USDC_S as USDC<br/>(Sepolia)
    participant TM_S as TokenMessengerV2<br/>(Sepolia)
    participant Circle as Circle Attestation<br/>Service (off-chain)
    participant TM_B as MessageTransmitter<br/>(Base)
    participant USDC_B as USDC<br/>(Base)
    actor Bob as Bob (Base)

    Note over Alice: Signs EIP-3009 auth<br/>on Sepolia

    Alice ->> SetS: settleWithAuthorization(...)

    SetS ->> USDC_S: receiveWithAuthorization(...)
    Note over USDC_S: 20 USDC pulled from Alice<br/>to Settlement contract

    Note over SetS: Recipient's ENS says:<br/>payment.flow = "cctp"<br/>payment.cctp = "6" (Base)

    SetS ->> USDC_S: forceApprove(TokenMessenger, 20)
    SetS ->> TM_S: depositForBurn(<br/>  20, domain=6,<br/>  bytes32(bob), USDC)

    Note over TM_S: Burns 20 USDC on Sepolia<br/>Emits MessageSent event

    TM_S -->> Circle: MessageSent event observed

    Note over Circle: Generates attestation<br/>for the burn message

    Circle -->> TM_B: receiveMessage(<br/>  message, attestation)

    TM_B ->> USDC_B: mint(bob, 20)

    Note over Bob: 20 USDC arrives on Base!
```

---

## Cross-Chain Settlement Sequence (Gateway Mint)

How a payment moves cross-chain via Circle Gateway (burn on source → attestation → mint on destination):
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`04-deployment-and-cross-chain-7.png`](./img/04-deployment-and-cross-chain-7.png)
>
> </details>

```mermaid
sequenceDiagram
    actor Alice as Alice (Base)
    participant Backend as khaaliSplit Backend
    participant CircleAPI as Circle Gateway API
    participant SetS as Settlement<br/>(Sepolia)
    participant GM as Gateway Minter<br/>(Sepolia)
    participant USDC_S as USDC<br/>(Sepolia)
    participant GW_S as Gateway Wallet<br/>(Sepolia)
    actor Bob as Bob (Sepolia)

    Note over Alice: Signs BurnIntent (EIP-712)<br/>on Base, destination = Sepolia

    Alice -->> Backend: Submit BurnIntent signature

    Backend ->> CircleAPI: POST /v1/transfer<br/>(from Base → Sepolia)
    CircleAPI -->> Backend: attestationPayload +<br/>attestationSignature

    Backend ->> SetS: settleFromGateway(<br/>  attestation, sig,<br/>  bobNode, alice, memo)

    SetS ->> USDC_S: balanceOf(Settlement)
    USDC_S -->> SetS: balanceBefore = 0

    SetS ->> GM: gatewayMint(attestation, sig)
    Note over GM: Verifies Circle attestation<br/>Mints 20 USDC → Settlement

    SetS ->> USDC_S: balanceOf(Settlement)
    USDC_S -->> SetS: balanceAfter = 20
    Note over SetS: amount = 20

    Note over SetS: Bob's ENS says:<br/>payment.flow = "gateway"

    SetS ->> USDC_S: forceApprove(GatewayWallet, 20)
    SetS ->> GW_S: depositFor(USDC, bob, 20)

    Note over Bob: 20 USDC in Bob's<br/>Gateway balance on Sepolia!
```

---

## UUPS Upgrade Sequence

How a contract upgrade works, showing the on-chain transaction flow:
> <details>
>
>  <summary>see rendered image</summary>
>
>  ![`04-deployment-and-cross-chain-8.png`](./img/04-deployment-and-cross-chain-8.png)
>
> </details>

```mermaid
sequenceDiagram
    actor Owner as Contract Owner
    participant Proxy as ERC1967Proxy<br/>(fixed address)
    participant ImplV1 as Implementation V1<br/>(current)
    participant ImplV2 as Implementation V2<br/>(new)

    Note over Owner: Step 1: Deploy new implementation

    Owner ->> ImplV2: deploy (regular CREATE)
    Note over ImplV2: Constructor calls<br/>_disableInitializers()<br/>(cannot be initialized directly)

    Note over Owner: Step 2: Upgrade proxy

    Owner ->> Proxy: upgradeToAndCall(implV2, "")
    Proxy ->> ImplV1: _authorizeUpgrade(implV2)<br/>(delegatecall)
    Note over ImplV1: require(owner == msg.sender) ✓

    Proxy ->> Proxy: Update ERC1967<br/>implementation slot<br/>to implV2 address

    Note over Proxy: All future calls now<br/>delegatecall to ImplV2

    Note over Owner: Step 3: Verify

    Owner ->> Proxy: someFunction()
    Proxy ->> ImplV2: someFunction()<br/>(delegatecall)
    Note over ImplV2: New logic executes<br/>with existing storage<br/>Address unchanged ✓
```
