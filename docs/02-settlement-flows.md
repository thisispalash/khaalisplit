# khaaliSplit — Settlement Flows

> How USDC payments are routed from sender to recipient across chains.

## Overview

khaaliSplit supports two settlement entry points, each routing through one of two payment rails based on the recipient's ENS text record preferences.

```mermaid
graph LR
    subgraph entry["Entry Points"]
        A["settleWithAuthorization<br/><i>EIP-3009 signed auth</i>"]
        B["settleFromGateway<br/><i>Circle attestation mint</i>"]
    end

    subgraph routing["Routing (per recipient ENS prefs)"]
        R{payment.flow<br/>text record?}
    end

    subgraph rails["Payment Rails"]
        GW["Gateway<br/><i>depositFor → unified balance</i>"]
        CCTP["CCTP<br/><i>depositForBurn → cross-chain</i>"]
    end

    A --> R
    B --> R
    R -->|"empty / 'gateway'" <br/> default| GW
    R -->|"'cctp'" <br/> opt-in| CCTP

    classDef entry fill:#4a9eff,stroke:#2563eb,color:#fff
    classDef route fill:#f59e0b,stroke:#d97706,color:#fff
    classDef rail fill:#10b981,stroke:#059669,color:#fff

    class A,B entry
    class R route
    class GW,CCTP rail
```

---

## Flow 1: Direct Settlement (EIP-3009)

The primary flow for peer-to-peer payments. The sender signs a `ReceiveWithAuthorization` message off-chain; anyone can submit it on-chain (enables NFC, Bluetooth, QR, or relayed payments).

```mermaid
sequenceDiagram
    actor Sender
    actor Submitter as Submitter<br/>(anyone)
    participant Settlement as khaaliSplitSettlement
    participant USDC as USDC (EIP-3009)
    participant Subnames as khaaliSplitSubnames
    participant GW as Gateway Wallet
    participant Rep as khaaliSplitReputation

    Note over Sender: Signs ReceiveWithAuthorization<br/>off-chain (to = Settlement contract)

    Sender -->> Submitter: Transmit signature<br/>(NFC / Bluetooth / QR)

    Submitter ->> Settlement: settleWithAuthorization(<br/>  recipientNode, amount, memo,<br/>  auth, signature)

    Settlement ->> Subnames: addr(recipientNode)
    Subnames -->> Settlement: recipient address

    Settlement ->> Subnames: text(node, "payment.token")
    Subnames -->> Settlement: token address (USDC)

    Settlement ->> USDC: receiveWithAuthorization(<br/>  from, to, amount, ...)
    Note over USDC: Verifies EIP-3009 signature<br/>Transfers USDC → Settlement

    Settlement ->> Subnames: text(node, "payment.flow")
    Subnames -->> Settlement: "gateway" (default)

    Settlement ->> GW: depositFor(token, recipient, amount)
    Note over GW: Recipient gets unified<br/>Gateway USDC balance

    Settlement ->> Rep: recordSettlement(sender, true)
    Rep ->> Subnames: setText(node, "reputation", "51")

    Settlement -->> Submitter: SettlementCompleted event
```

---

## Flow 2: Gateway Mint Settlement (Cross-Chain)

For cross-chain payments from a Gateway balance. The sender signs a BurnIntent (EIP-712) off-chain; the backend obtains a Circle attestation and calls the contract.

```mermaid
sequenceDiagram
    actor Sender
    participant Backend
    participant CircleAPI as Circle Gateway API
    participant Settlement as khaaliSplitSettlement
    participant Minter as Gateway Minter
    participant USDC as USDC
    participant Subnames as khaaliSplitSubnames
    participant GW as Gateway Wallet
    participant Rep as khaaliSplitReputation

    Note over Sender: Signs BurnIntent (EIP-712)<br/>destinationRecipient = Settlement

    Sender -->> Backend: Submit signed BurnIntent

    Backend ->> CircleAPI: POST /v1/transfer
    CircleAPI -->> Backend: attestationPayload +<br/>attestationSignature

    Backend ->> Settlement: settleFromGateway(<br/>  attestation, sig,<br/>  recipientNode, sender, memo)

    Settlement ->> Subnames: text(node, "payment.token")
    Subnames -->> Settlement: token address (USDC)

    Settlement ->> USDC: balanceOf(Settlement)
    USDC -->> Settlement: balanceBefore

    Settlement ->> Minter: gatewayMint(attestation, sig)
    Note over Minter: Verifies Circle attestation<br/>Mints USDC → Settlement

    Settlement ->> USDC: balanceOf(Settlement)
    USDC -->> Settlement: balanceAfter
    Note over Settlement: amount = balanceAfter - balanceBefore

    Settlement ->> Subnames: addr(recipientNode)
    Subnames -->> Settlement: recipient address

    Settlement ->> Subnames: text(node, "payment.flow")
    Subnames -->> Settlement: "gateway"

    Settlement ->> GW: depositFor(token, recipient, amount)

    Settlement ->> Rep: recordSettlement(sender, true)

    Settlement -->> Backend: SettlementCompleted event
```

---

## Flow 3: CCTP Routing (Opt-In Cross-Chain Burn)

When a recipient opts into CCTP by setting `payment.flow = "cctp"` and `payment.cctp = "<domain>"` in their ENS text records. Works with either entry point.

```mermaid
sequenceDiagram
    participant Settlement as khaaliSplitSettlement
    participant Subnames as khaaliSplitSubnames
    participant USDC as USDC
    participant TM as CCTP TokenMessengerV2

    Note over Settlement: USDC already pulled<br/>(via EIP-3009 or Gateway Mint)

    Settlement ->> Subnames: text(node, "payment.flow")
    Subnames -->> Settlement: "cctp"

    Settlement ->> Subnames: text(node, "payment.cctp")
    Subnames -->> Settlement: "6" (Base domain)

    Settlement ->> USDC: forceApprove(TokenMessenger, amount)

    Settlement ->> TM: depositForBurn(<br/>  amount, domain=6,<br/>  bytes32(recipient), USDC)

    Note over TM: Burns USDC on source chain<br/>Circle attestation service mints<br/>USDC on destination chain (Base)
```

---

## ENS Text Record Payment Preferences

Recipients configure their payment routing via ENS text records on their `{user}.khaalisplit.eth` subname:

| Text Record Key | Example Value | Description |
|-----------------|---------------|-------------|
| `com.khaalisplit.payment.token` | `0x833589fC...` | USDC address on destination chain |
| `com.khaalisplit.payment.chain` | `8453` | Destination chain ID |
| `com.khaalisplit.payment.flow` | `gateway` / `cctp` | Routing preference (default: gateway) |
| `com.khaalisplit.payment.cctp` | `6` | CCTP domain (required if flow = cctp) |

## Supported Chains

| Chain | Chain ID | CCTP Domain | Gateway | CCTP |
|-------|----------|:-----------:|:-------:|:----:|
| Sepolia | 11155111 | 0 | Yes | Yes |
| Base Sepolia | 84532 | 6 | Yes | Yes |
| Arc Testnet | 1397 | N/A | Yes | No |
| Ethereum | 1 | 0 | Yes | Yes |
| Base | 8453 | 6 | Yes | Yes |
