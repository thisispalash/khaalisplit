# khaaliSplit — Envio HyperIndex Indexer Plan (v2)

> Rewrite of the original indexer-01.md. Updated for current contract deployments,
> new contracts (Subnames, Reputation), corrected settlement events, and
> shared VPS infrastructure (Postgres + Hasura).

## Scope

Self-hosted Envio HyperIndex indexer. All files live in `indexer/` alongside `app/` and `contracts/`. Uses the shared VPS Postgres (`kdio_shared_db`) and shared Hasura (`kdio_hasura`) instances from the `vps-orchestration` repo.

**Working directory:** `indexer/` (relative to repo root)
**Current state:** `indexer/` directory does not exist yet.

## Prerequisites

| Requirement | Status |
|---|---|
| Shared Postgres (`kdio_shared_db`) on `kdio_network` | Running on VPS |
| `khaaliSplit_db` database created in shared Postgres | Done (app uses it) |
| Shared Hasura (`kdio_hasura`) on `kdio_network`, port 8080 | Running on VPS |
| Envio API token (for HyperSync) | Needed — get from https://envio.dev/app/api-tokens |
| Contracts deployed — addresses in `contracts/deployments.json` | Done |
| Foundry compiled artifacts in `contracts/out/` | Done (`forge build`) |

## Key Decisions

1. **Shared infrastructure.** Indexer writes to `khaaliSplit_db` with `ENVIO_PG_PUBLIC_SCHEMA=envio`. No bundled Postgres or Hasura — uses the VPS shared instances.
2. **8 contracts indexed** (all contracts in `contracts/src/`): Friends, Groups, Expenses, Settlement, Subnames, Reputation, Resolver, kdioDeployer.
3. **No relay service.** Settlement routing (Gateway/CCTP) happens atomically on-chain inside `settleWithAuthorization()` and `settleFromGateway()`. No off-chain relay worker needed.
4. **ABIs extracted** from Foundry compiled artifacts at `contracts/out/`.
5. **Contract addresses** from `contracts/deployments.json` (proxy addresses).
6. **TypeScript** event handlers.
7. **Docker Compose** follows `app/docker-compose.yml` pattern (dev/prod profiles, `kdio_network` external).
8. **`unordered_multichain_mode: true`** for Settlement across chains.
9. **Event handlers upsert** — updates (e.g. `ExpenseUpdated`, `FriendRemoved`) modify existing entities rather than creating new ones.
10. **Git commit after every session.**

## Deployed Contract Addresses

From `contracts/deployments.json` (proxy addresses — these are what we index):

**Sepolia (11155111) — all core contracts:**

| Contract | Proxy Address |
|---|---|
| khaaliSplitFriends | `0xc6513216d6Bc6498De9E37e00478F0Cb802b2561` |
| khaaliSplitGroups | `0xf6f07Bdc4f14b1FB1374A1d821A9E50547EcE820` |
| khaaliSplitExpenses | `0x0058f47e98DF066d34f70EF231AdD634C9857605` |
| khaaliSplitSettlement | `0xd038e9CD05a71765657Fd3943d41820F5035A6C1` |
| khaaliSplitSubnames | `0xE7F20a2c7461cAF3FdCD672E273326fAeCE5Be4F` |
| khaaliSplitReputation | `0x3a916C1cb55352860FA46084EBA5A032dB50312f` |
| khaaliSplitResolver | `0x7403caAFB6d87d3DFF00ddDA3Ef02ACA13C8364A` |
| kdioDeployer | `0x0f04784d0BFaEeFB4bc15C8EbDe4e483ccE2154f` |

**Settlement proxy addresses on other chains:**

| Chain | Chain ID | Proxy Address |
|---|---|---|
| Base Sepolia | 84532 | `0xacDbabeDc22BE4eD68D9084Dd3157c27D7154baa` |
| Arbitrum Sepolia | 421614 | `0x8A20a346a00f809fbd279c1E8B56883998867254` |
| Optimism Sepolia | 11155420 | `0x8A20a346a00f809fbd279c1E8B56883998867254` |
| Arc Testnet | 5042002 | `0xeB75548245A9C5a31ABF6Eda7CA16977f3Af3690` |

## Contracts & Events to Index

### khaaliSplitFriends (Sepolia)
```
PubKeyRegistered(address indexed user, bytes pubKey)
FriendRequested(address indexed from, address indexed to)
FriendAccepted(address indexed user, address indexed friend)
FriendRemoved(address indexed user, address indexed friend)
```

### khaaliSplitGroups (Sepolia)
```
GroupCreated(uint256 indexed groupId, address indexed creator, bytes32 nameHash)
MemberInvited(uint256 indexed groupId, address indexed inviter, address indexed invitee)
MemberAccepted(uint256 indexed groupId, address indexed member)
MemberLeft(uint256 indexed groupId, address indexed member)
```

### khaaliSplitExpenses (Sepolia)
```
ExpenseAdded(uint256 indexed groupId, uint256 indexed expenseId, address indexed creator, bytes32 dataHash, bytes encryptedData)
ExpenseUpdated(uint256 indexed groupId, uint256 indexed expenseId, address indexed creator, bytes32 dataHash, bytes encryptedData)
```

### khaaliSplitSettlement (Sepolia + 4 other chains)
```
SettlementCompleted(address indexed sender, address indexed recipient, address token, uint256 amount, uint256 senderReputation, bytes memo)
TokenAdded(address indexed token)
TokenRemoved(address indexed token)
TokenMessengerUpdated(address indexed newTokenMessenger)
GatewayWalletUpdated(address indexed newGatewayWallet)
GatewayMinterUpdated(address indexed newGatewayMinter)
DomainConfigured(uint256 indexed chainId, uint32 domain)
SubnameRegistryUpdated(address indexed newSubnameRegistry)
ReputationContractUpdated(address indexed newReputationContract)
```

### khaaliSplitSubnames (Sepolia)
```
SubnameRegistered(bytes32 indexed node, string label, address indexed owner)
TextRecordSet(bytes32 indexed node, string key, string value)
AddrRecordSet(bytes32 indexed node, address addr)
BackendUpdated(address indexed newBackend)
ReputationContractUpdated(address indexed newReputationContract)
```

### khaaliSplitReputation (Sepolia)
```
ReputationUpdated(address indexed user, uint256 newScore, bool wasSuccess)
UserNodeSet(address indexed user, bytes32 indexed node)
BackendUpdated(address indexed newBackend)
SubnameRegistryUpdated(address indexed newSubnameRegistry)
SettlementContractUpdated(address indexed newSettlementContract)
```

### khaaliSplitResolver (Sepolia) — deprecated but still deployed
```
SignerAdded(address indexed signer)
SignerRemoved(address indexed signer)
UrlUpdated(string newUrl)
```

### kdioDeployer (Sepolia)
```
Deployed(address indexed proxy, bytes32 indexed salt, address indexed implementation)
```

**Total: 8 contracts, 33 events, across 5 chains.**

## File Structure (final)

```
indexer/
├── .gitignore
├── .dockerignore
├── .env.example
├── package.json
├── tsconfig.json
├── Dockerfile
├── docker-compose.yml
├── config.yaml
├── schema.graphql
├── abis/
│   ├── ERC20.json              (Session 1 — USDC test, kept for reference)
│   ├── khaaliSplitFriends.json
│   ├── khaaliSplitGroups.json
│   ├── khaaliSplitExpenses.json
│   ├── khaaliSplitSettlement.json
│   ├── khaaliSplitSubnames.json
│   ├── khaaliSplitReputation.json
│   ├── khaaliSplitResolver.json
│   └── kdioDeployer.json
└── src/
    └── EventHandlers.ts
```

## Critical Reference Files

| File | Purpose |
|---|---|
| `app/docker-compose.yml` | Pattern for dev/prod profiles, `kdio_network`, `env_file` |
| `contracts/out/{Source}.sol/{Contract}.json` | Compiled ABIs to extract |
| `contracts/deployments.json` | Proxy addresses per chain |
| `contracts/script/tokens.json` | Token addresses per chain |
| `contracts/script/cctp.json` | CCTP/Gateway config |
| `contracts/src/*.sol` | Event signatures (source of truth) |
| https://docs.envio.dev/docs/HyperIndex/self-hosting | Envio self-hosting docs |
| https://github.com/enviodev/local-docker-example | Envio local docker reference |

---

## Session 1: Scaffold + USDC Test

**Goal:** Get Envio running end-to-end by indexing USDC Transfer events on Sepolia. Validates the full pipeline: ABI → config → schema → codegen → Docker → shared Postgres → Hasura.

### 1.1 Create `indexer/.gitignore`
```
node_modules/
generated/
.envio/
*.env
.DS_Store
```

### 1.2 Create `indexer/.dockerignore`
```
node_modules
generated
.envio
.git
.DS_Store
*.md
```

### 1.3 Create `indexer/package.json`
```json
{
  "name": "khaalisplit-indexer",
  "version": "0.2.0",
  "private": true,
  "scripts": {
    "codegen": "envio codegen",
    "dev": "envio dev",
    "start": "envio start"
  },
  "dependencies": {
    "envio": "^2.26.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
```

### 1.4 Create `indexer/tsconfig.json`
```json
{
  "compilerOptions": {
    "target": "es2022",
    "module": "commonjs",
    "lib": ["es2022"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "generated"]
}
```

### 1.5 Extract ABIs

Extract the `abi` array from each Foundry compiled JSON and also add a standard ERC20 ABI:

**From Foundry artifacts** (command: `jq '.abi' contracts/out/<Source>.sol/<Contract>.json > indexer/abis/<Contract>.json`):

| Source | Destination |
|---|---|
| `khaaliSplitFriends.sol/khaaliSplitFriends.json` | `abis/khaaliSplitFriends.json` |
| `khaaliSplitGroups.sol/khaaliSplitGroups.json` | `abis/khaaliSplitGroups.json` |
| `khaaliSplitExpenses.sol/khaaliSplitExpenses.json` | `abis/khaaliSplitExpenses.json` |
| `khaaliSplitSettlement.sol/khaaliSplitSettlement.json` | `abis/khaaliSplitSettlement.json` |
| `khaaliSplitSubnames.sol/khaaliSplitSubnames.json` | `abis/khaaliSplitSubnames.json` |
| `khaaliSplitReputation.sol/khaaliSplitReputation.json` | `abis/khaaliSplitReputation.json` |
| `khaaliSplitResolver.sol/khaaliSplitResolver.json` | `abis/khaaliSplitResolver.json` |
| `kdioDeployer.sol/kdioDeployer.json` | `abis/kdioDeployer.json` |

**ERC20 ABI** — create `abis/ERC20.json` manually with standard Transfer and Approval events:
```json
[
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "name": "from", "type": "address" },
      { "indexed": true, "name": "to", "type": "address" },
      { "indexed": false, "name": "value", "type": "uint256" }
    ],
    "name": "Transfer",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "name": "owner", "type": "address" },
      { "indexed": true, "name": "spender", "type": "address" },
      { "indexed": false, "name": "value", "type": "uint256" }
    ],
    "name": "Approval",
    "type": "event"
  }
]
```

### 1.6 Create test `indexer/schema.graphql` (USDC only)

```graphql
type USDCTransfer @entity {
  id: ID!            # "{chainId}-{txHash}-{logIndex}"
  from: String!
  to: String!
  value: BigInt!
  blockNumber: Int!
  blockTimestamp: Int!
  txHash: String!
}
```

### 1.7 Create test `indexer/config.yaml` (USDC only)

```yaml
name: khaaliSplit
description: "Envio HyperIndex indexer for khaaliSplit — USDC test"
ecosystem: evm

contracts:
  - name: USDC
    abi_file_path: abis/ERC20.json
    handler: src/EventHandlers.ts
    events:
      - event: Transfer(address indexed from, address indexed to, uint256 value)

networks:
  - id: 11155111
    contracts:
      - name: USDC
        address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
        start_block: 7800000   # Recent block to avoid long sync
```

### 1.8 Create test `indexer/src/EventHandlers.ts` (USDC only)

```typescript
import { USDC } from "generated";

USDC.Transfer.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  const id = `${chainId}-${event.transaction.hash}-${event.logIndex}`;

  context.USDCTransfer.set({
    id,
    from: event.params.from.toLowerCase(),
    to: event.params.to.toLowerCase(),
    value: event.params.value,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
    txHash: event.transaction.hash,
  });
});
```

### 1.9 Create `indexer/.env.example`

```env
COMPOSE_PROFILES="dev"

# Envio API Token (required for HyperSync)
ENVIO_API_TOKEN=""

# PostgreSQL (shared instance — kdio_shared_db)
ENVIO_PG_USER="your_pg_username"
ENVIO_PG_PASSWORD="your_pg_password"
ENVIO_PG_HOST="kdio_shared_db"
ENVIO_PG_PORT="5432"
ENVIO_PG_DATABASE="khaaliSplit_db"
ENVIO_PG_PUBLIC_SCHEMA="envio"

# Hasura (shared instance — kdio_hasura)
HASURA_GRAPHQL_ENDPOINT="http://kdio_hasura:8080"
HASURA_GRAPHQL_ADMIN_SECRET="your_hasura_admin_secret"

# Logging
LOG_LEVEL="trace"
TUI_OFF="true"
```

### 1.10 Create `indexer/Dockerfile`

```dockerfile
FROM node:24-slim

RUN corepack enable pnpm && \
    apt-get update && apt-get install -y --no-install-recommends postgresql-client && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile || pnpm install

COPY config.yaml schema.graphql tsconfig.json ./
COPY abis/ abis/

RUN pnpm envio codegen

COPY src/ src/

CMD ["pnpm", "envio", "start"]
```

### 1.11 Create `indexer/docker-compose.yml`

```yaml
services:
  khaalisplit_indexer_dev:
    container_name: khaalisplit_indexer_dev
    build:
      context: .
      dockerfile: Dockerfile
    profiles: ["dev"]
    env_file: .env
    environment:
      LOG_LEVEL: "trace"
      TUI_OFF: "true"
    volumes:
      - .:/app
      - /app/node_modules
    networks:
      - kdio_network

  khaalisplit_indexer:
    container_name: khaalisplit_indexer
    build:
      context: .
      dockerfile: Dockerfile
    profiles: ["prod"]
    env_file: .env
    environment:
      LOG_LEVEL: "info"
      TUI_OFF: "true"
    restart: always
    deploy:
      resources:
        limits:
          cpus: "0.8"
          memory: 800M
    networks:
      - kdio_network

networks:
  kdio_network:
    external: true
```

### 1.12 Update root `docker-compose.yml`

```yaml
include:
  - app/docker-compose.yml
  - indexer/docker-compose.yml
```

### 1.13 Validate

```bash
cd indexer
pnpm install
pnpm envio codegen
docker compose --profile dev config
docker compose --profile dev build
```

**Commit:** `feat(indexer): scaffold Envio HyperIndex with USDC test indexing`

### Session 1 Verification

| Check | How |
|---|---|
| ABIs are valid JSON arrays | `jq '.' indexer/abis/*.json` |
| codegen succeeds | `pnpm envio codegen` exits 0 |
| Docker config valid | `docker compose --profile dev config` |
| Docker builds | `docker compose --profile dev build` |
| Indexer starts and syncs | Start container, check logs for USDC Transfer events being indexed |
| Hasura shows data | Query `USDCTransfer` via Hasura console |

---

## Session 2: Real Schema + Event Handlers

**Goal:** Replace the USDC test with the full khaaliSplit schema and all event handlers. After this session, the indexer watches all 8 contracts across 5 chains and processes all 33 events.

### 2.1 Replace `indexer/schema.graphql`

Remove `USDCTransfer`. Add the full schema:

```graphql
# ── Friends ──────────────────────────────────────

type RegisteredUser @entity {
  id: ID!                  # address (lowercase)
  pubKey: String!          # hex-encoded ECDH public key
  registeredAt: Int!       # block timestamp
  txHash: String!
}

type FriendRequest @entity {
  id: ID!                  # sorted pair: "0xaaa-0xbbb"
  from: String!            # requester address (lowercase)
  to: String!              # target address (lowercase)
  status: String!          # "pending" | "accepted" | "removed"
  requestedAt: Int!
  acceptedAt: Int
  removedAt: Int
  txHash: String!          # latest tx hash
}

# ── Groups ───────────────────────────────────────

type Group @entity {
  id: ID!                  # groupId (uint256 as string)
  nameHash: String!        # bytes32 hex
  creator: String!         # address (lowercase)
  memberCount: Int!
  createdAt: Int!
  txHash: String!
  members: [GroupMember!]! @derivedFrom(field: "group")
  expenses: [Expense!]!    @derivedFrom(field: "group")
}

type GroupMember @entity {
  id: ID!                  # "{groupId}-{memberAddress}"
  group: Group!
  memberAddress: String!   # address (lowercase)
  invitedBy: String!       # address (lowercase)
  status: String!          # "invited" | "accepted" | "left"
  invitedAt: Int!
  acceptedAt: Int
  leftAt: Int
  txHash: String!          # latest tx hash
}

# ── Expenses ─────────────────────────────────────

type Expense @entity {
  id: ID!                  # expenseId (uint256 as string)
  group: Group!
  creator: String!         # address (lowercase)
  dataHash: String!        # bytes32 hex (keccak256 of plaintext)
  encryptedData: String!   # hex-encoded AES-256-GCM ciphertext
  createdAt: Int!
  createdTxHash: String!   # original creation tx
  updatedAt: Int           # null until updated
  updatedTxHash: String    # null until updated
}

# ── Settlement ───────────────────────────────────

type Settlement @entity {
  id: ID!                  # "{chainId}-{txHash}-{logIndex}"
  sender: String!          # address (lowercase)
  recipient: String!       # address (lowercase)
  token: String!           # address (lowercase)
  amount: BigInt!          # in token decimals (e.g. 6 for USDC)
  senderReputation: BigInt!# 0-100, or 500 if reputation not set
  memo: String!            # hex-encoded memo bytes
  sourceChainId: Int!      # chain where tx was mined
  blockNumber: Int!
  blockTimestamp: Int!
  txHash: String!
}

type AllowedToken @entity {
  id: ID!                  # "{chainId}-{tokenAddress}"
  chainId: Int!
  token: String!           # address (lowercase)
  isAllowed: Boolean!
  txHash: String!
}

# ── Settlement Admin Config ──────────────────────

type SettlementConfig @entity {
  id: ID!                  # "{chainId}-{configType}"
  chainId: Int!
  configType: String!      # "tokenMessenger" | "gatewayWallet" | "gatewayMinter" | "subnameRegistry" | "reputationContract"
  value: String!           # address (lowercase)
  txHash: String!
}

type CctpDomain @entity {
  id: ID!                  # "{sourceChainId}-{targetChainId}"
  sourceChainId: Int!
  targetChainId: Int!
  domain: Int!             # uint32 CCTP domain
  txHash: String!
}

# ── Subnames ─────────────────────────────────────

type Subname @entity {
  id: ID!                  # bytes32 node (hex)
  label: String!           # human-readable label (e.g. "alice")
  owner: String!           # address (lowercase)
  registeredAt: Int!
  txHash: String!
  textRecords: [TextRecord!]! @derivedFrom(field: "subname")
}

type TextRecord @entity {
  id: ID!                  # "{node}-{key}"
  subname: Subname!
  key: String!
  value: String!
  txHash: String!
}

type AddrRecord @entity {
  id: ID!                  # bytes32 node (hex)
  node: String!
  addr: String!            # address (lowercase)
  txHash: String!
}

# ── Reputation ───────────────────────────────────

type ReputationScore @entity {
  id: ID!                  # address (lowercase)
  score: BigInt!           # 0-100
  totalSettlements: Int!
  successfulSettlements: Int!
  failedSettlements: Int!
  lastUpdatedAt: Int!
  txHash: String!
}

type ReputationUserNode @entity {
  id: ID!                  # address (lowercase)
  node: String!            # bytes32 ENS node (hex)
  txHash: String!
}

# ── Resolver (deprecated but still deployed) ─────

type ResolverSigner @entity {
  id: ID!                  # address (lowercase)
  isActive: Boolean!
  txHash: String!
}

type ResolverUrl @entity {
  id: ID!                  # "current" (singleton)
  url: String!
  txHash: String!
}

# ── kdioDeployer ─────────────────────────────────

type Deployment @entity {
  id: ID!                  # "{salt}-{proxy}"
  proxy: String!           # address (lowercase)
  salt: String!            # bytes32 hex
  implementation: String!  # address (lowercase)
  chainId: Int!
  blockNumber: Int!
  blockTimestamp: Int!
  txHash: String!
}
```

### 2.2 Replace `indexer/config.yaml`

Remove USDC test config. Full config with all 8 contracts across 5 chains:

```yaml
name: khaaliSplit
description: "Envio HyperIndex indexer for khaaliSplit contracts"
ecosystem: evm
unordered_multichain_mode: true

contracts:
  # ── Sepolia-only contracts ────────────────────────
  - name: khaaliSplitFriends
    abi_file_path: abis/khaaliSplitFriends.json
    handler: src/EventHandlers.ts
    events:
      - event: PubKeyRegistered(address indexed user, bytes pubKey)
      - event: FriendRequested(address indexed from, address indexed to)
      - event: FriendAccepted(address indexed user, address indexed friend)
      - event: FriendRemoved(address indexed user, address indexed friend)

  - name: khaaliSplitGroups
    abi_file_path: abis/khaaliSplitGroups.json
    handler: src/EventHandlers.ts
    events:
      - event: GroupCreated(uint256 indexed groupId, address indexed creator, bytes32 nameHash)
      - event: MemberInvited(uint256 indexed groupId, address indexed inviter, address indexed invitee)
      - event: MemberAccepted(uint256 indexed groupId, address indexed member)
      - event: MemberLeft(uint256 indexed groupId, address indexed member)

  - name: khaaliSplitExpenses
    abi_file_path: abis/khaaliSplitExpenses.json
    handler: src/EventHandlers.ts
    events:
      - event: ExpenseAdded(uint256 indexed groupId, uint256 indexed expenseId, address indexed creator, bytes32 dataHash, bytes encryptedData)
      - event: ExpenseUpdated(uint256 indexed groupId, uint256 indexed expenseId, address indexed creator, bytes32 dataHash, bytes encryptedData)

  - name: khaaliSplitSubnames
    abi_file_path: abis/khaaliSplitSubnames.json
    handler: src/EventHandlers.ts
    events:
      - event: SubnameRegistered(bytes32 indexed node, string label, address indexed owner)
      - event: TextRecordSet(bytes32 indexed node, string key, string value)
      - event: AddrRecordSet(bytes32 indexed node, address addr)
      - event: BackendUpdated(address indexed newBackend)
      - event: ReputationContractUpdated(address indexed newReputationContract)

  - name: khaaliSplitReputation
    abi_file_path: abis/khaaliSplitReputation.json
    handler: src/EventHandlers.ts
    events:
      - event: ReputationUpdated(address indexed user, uint256 newScore, bool wasSuccess)
      - event: UserNodeSet(address indexed user, bytes32 indexed node)
      - event: BackendUpdated(address indexed newBackend)
      - event: SubnameRegistryUpdated(address indexed newSubnameRegistry)
      - event: SettlementContractUpdated(address indexed newSettlementContract)

  - name: khaaliSplitResolver
    abi_file_path: abis/khaaliSplitResolver.json
    handler: src/EventHandlers.ts
    events:
      - event: SignerAdded(address indexed signer)
      - event: SignerRemoved(address indexed signer)
      - event: UrlUpdated(string newUrl)

  - name: kdioDeployer
    abi_file_path: abis/kdioDeployer.json
    handler: src/EventHandlers.ts
    events:
      - event: Deployed(address indexed proxy, bytes32 indexed salt, address indexed implementation)

  # ── Multi-chain contract ──────────────────────────
  - name: khaaliSplitSettlement
    abi_file_path: abis/khaaliSplitSettlement.json
    handler: src/EventHandlers.ts
    events:
      - event: SettlementCompleted(address indexed sender, address indexed recipient, address token, uint256 amount, uint256 senderReputation, bytes memo)
      - event: TokenAdded(address indexed token)
      - event: TokenRemoved(address indexed token)
      - event: TokenMessengerUpdated(address indexed newTokenMessenger)
      - event: GatewayWalletUpdated(address indexed newGatewayWallet)
      - event: GatewayMinterUpdated(address indexed newGatewayMinter)
      - event: DomainConfigured(uint256 indexed chainId, uint32 domain)
      - event: SubnameRegistryUpdated(address indexed newSubnameRegistry)
      - event: ReputationContractUpdated(address indexed newReputationContract)

networks:
  # ── Sepolia: all contracts ────────────────────────
  - id: 11155111
    contracts:
      - name: khaaliSplitFriends
        address: "0xc6513216d6Bc6498De9E37e00478F0Cb802b2561"
        start_block: 0     # TODO: set to deployment block
      - name: khaaliSplitGroups
        address: "0xf6f07Bdc4f14b1FB1374A1d821A9E50547EcE820"
        start_block: 0
      - name: khaaliSplitExpenses
        address: "0x0058f47e98DF066d34f70EF231AdD634C9857605"
        start_block: 0
      - name: khaaliSplitSettlement
        address: "0xd038e9CD05a71765657Fd3943d41820F5035A6C1"
        start_block: 0
      - name: khaaliSplitSubnames
        address: "0xE7F20a2c7461cAF3FdCD672E273326fAeCE5Be4F"
        start_block: 0
      - name: khaaliSplitReputation
        address: "0x3a916C1cb55352860FA46084EBA5A032dB50312f"
        start_block: 0
      - name: khaaliSplitResolver
        address: "0x7403caAFB6d87d3DFF00ddDA3Ef02ACA13C8364A"
        start_block: 0
      - name: kdioDeployer
        address: "0x0f04784d0BFaEeFB4bc15C8EbDe4e483ccE2154f"
        start_block: 0

  # ── Base Sepolia: Settlement only ─────────────────
  - id: 84532
    contracts:
      - name: khaaliSplitSettlement
        address: "0xacDbabeDc22BE4eD68D9084Dd3157c27D7154baa"
        start_block: 0

  # ── Arbitrum Sepolia: Settlement only ─────────────
  - id: 421614
    contracts:
      - name: khaaliSplitSettlement
        address: "0x8A20a346a00f809fbd279c1E8B56883998867254"
        start_block: 0

  # ── Optimism Sepolia: Settlement only ─────────────
  - id: 11155420
    contracts:
      - name: khaaliSplitSettlement
        address: "0x8A20a346a00f809fbd279c1E8B56883998867254"
        start_block: 0

  # ── Arc Testnet: Settlement only ──────────────────
  - id: 5042002
    rpc_config:
      url: "https://rpc.testnet.arc.network"
    contracts:
      - name: khaaliSplitSettlement
        address: "0xeB75548245A9C5a31ABF6Eda7CA16977f3Af3690"
        start_block: 0
```

**Notes:**
- `start_block: 0` is a placeholder. Set to deployment block numbers before production sync.
- Arc Testnet needs explicit `rpc_config` — HyperSync likely doesn't support it.

### 2.3 Replace `indexer/src/EventHandlers.ts`

Full event handlers for all 33 events. Key design patterns:

**Helpers:**
- `addr(a)` — normalize address to lowercase
- `friendPairId(a, b)` — sorted pair ID so alice-bob == bob-alice

**Upsert behavior (critical):**
- `FriendRemoved` → **updates** existing `FriendRequest` entity status to `"removed"`, sets `removedAt`
- `FriendAccepted` → **updates** existing `FriendRequest` entity status to `"accepted"`, sets `acceptedAt`
- `MemberAccepted` → **updates** existing `GroupMember` status to `"accepted"`, **increments** `Group.memberCount`
- `MemberLeft` → **updates** existing `GroupMember` status to `"left"`, **decrements** `Group.memberCount`
- `ExpenseUpdated` → **updates** existing `Expense` entity (preserves `createdAt` and `createdTxHash`)
- `TokenRemoved` → **updates** existing `AllowedToken.isAllowed` to `false`
- `SignerRemoved` → **updates** existing `ResolverSigner.isActive` to `false`
- `ReputationUpdated` → **updates** existing `ReputationScore` (increments counters, updates score)

**Handler details per contract:**

#### khaaliSplitFriends (4 handlers)

```
PubKeyRegistered → context.RegisteredUser.set({
  id: addr(user),
  pubKey: hexEncode(pubKey),
  registeredAt: block.timestamp,
  txHash: tx.hash
})

FriendRequested → context.FriendRequest.set({
  id: friendPairId(from, to),
  from: addr(from),
  to: addr(to),
  status: "pending",
  requestedAt: block.timestamp,
  txHash: tx.hash
})

FriendAccepted → load existing FriendRequest by friendPairId(user, friend), update:
  status: "accepted",
  acceptedAt: block.timestamp,
  txHash: tx.hash

FriendRemoved → load existing FriendRequest by friendPairId(user, friend), update:
  status: "removed",
  removedAt: block.timestamp,
  txHash: tx.hash
```

#### khaaliSplitGroups (4 handlers)

```
GroupCreated → create Group + create GroupMember for creator:
  Group: { id: groupId, nameHash, creator: addr(creator), memberCount: 1, createdAt, txHash }
  GroupMember: { id: "{groupId}-{addr(creator)}", group: groupId, memberAddress: addr(creator),
                 invitedBy: addr(creator), status: "accepted", invitedAt: timestamp, acceptedAt: timestamp, txHash }

MemberInvited → context.GroupMember.set({
  id: "{groupId}-{addr(invitee)}",
  group: groupId,
  memberAddress: addr(invitee),
  invitedBy: addr(inviter),
  status: "invited",
  invitedAt: timestamp,
  txHash
})

MemberAccepted → load existing GroupMember, update status to "accepted", set acceptedAt.
                  Load Group, increment memberCount.

MemberLeft → load existing GroupMember, update status to "left", set leftAt.
             Load Group, decrement memberCount.
```

#### khaaliSplitExpenses (2 handlers)

```
ExpenseAdded → context.Expense.set({
  id: expenseId,
  group: groupId,
  creator: addr(creator),
  dataHash: hexEncode(dataHash),
  encryptedData: hexEncode(encryptedData),
  createdAt: timestamp,
  createdTxHash: tx.hash,
  updatedAt: undefined,
  updatedTxHash: undefined
})

ExpenseUpdated → load existing Expense, update:
  dataHash, encryptedData, updatedAt: timestamp, updatedTxHash: tx.hash
  (preserve createdAt and createdTxHash)
```

#### khaaliSplitSettlement (9 handlers)

```
SettlementCompleted → context.Settlement.set({
  id: "{chainId}-{tx.hash}-{logIndex}",
  sender: addr(sender),
  recipient: addr(recipient),
  token: addr(token),
  amount,
  senderReputation,
  memo: hexEncode(memo),
  sourceChainId: chainId,
  blockNumber: block.number,
  blockTimestamp: block.timestamp,
  txHash: tx.hash
})

TokenAdded → context.AllowedToken.set({
  id: "{chainId}-{addr(token)}",
  chainId, token: addr(token), isAllowed: true, txHash
})

TokenRemoved → load existing AllowedToken, set isAllowed: false, update txHash

TokenMessengerUpdated → context.SettlementConfig.set({
  id: "{chainId}-tokenMessenger", chainId, configType: "tokenMessenger",
  value: addr(newTokenMessenger), txHash
})

GatewayWalletUpdated → same pattern, configType: "gatewayWallet"
GatewayMinterUpdated → same pattern, configType: "gatewayMinter"
SubnameRegistryUpdated → same pattern, configType: "subnameRegistry"
ReputationContractUpdated → same pattern, configType: "reputationContract"

DomainConfigured → context.CctpDomain.set({
  id: "{sourceChainId}-{targetChainId}",
  sourceChainId: chainId (source = where event was emitted),
  targetChainId: chainId (from event param),
  domain, txHash
})
```

#### khaaliSplitSubnames (5 handlers)

```
SubnameRegistered → context.Subname.set({
  id: hexEncode(node),
  label,
  owner: addr(owner),
  registeredAt: timestamp,
  txHash
})

TextRecordSet → context.TextRecord.set({
  id: "{hexEncode(node)}-{key}",
  subname: hexEncode(node),
  key, value, txHash
})

AddrRecordSet → context.AddrRecord.set({
  id: hexEncode(node),
  node: hexEncode(node),
  addr: addr(addr),
  txHash
})

BackendUpdated → no entity (skip or log)
ReputationContractUpdated → no entity (skip or log)
```

#### khaaliSplitReputation (5 handlers)

```
ReputationUpdated → load existing ReputationScore or create:
  id: addr(user)
  score: newScore
  totalSettlements: existing.totalSettlements + 1
  successfulSettlements: wasSuccess ? existing + 1 : existing
  failedSettlements: !wasSuccess ? existing + 1 : existing
  lastUpdatedAt: timestamp
  txHash

UserNodeSet → context.ReputationUserNode.set({
  id: addr(user), node: hexEncode(node), txHash
})

BackendUpdated → skip
SubnameRegistryUpdated → skip
SettlementContractUpdated → skip
```

#### khaaliSplitResolver (3 handlers)

```
SignerAdded → context.ResolverSigner.set({
  id: addr(signer), isActive: true, txHash
})

SignerRemoved → load existing, set isActive: false, update txHash

UrlUpdated → context.ResolverUrl.set({
  id: "current", url: newUrl, txHash
})
```

#### kdioDeployer (1 handler)

```
Deployed → context.Deployment.set({
  id: "{hexEncode(salt)}-{addr(proxy)}",
  proxy: addr(proxy),
  salt: hexEncode(salt),
  implementation: addr(implementation),
  chainId,
  blockNumber: block.number,
  blockTimestamp: block.timestamp,
  txHash: tx.hash
})
```

**Commit:** `feat(indexer): add full schema and event handlers for all 8 contracts`

### Session 2 Verification

| Check | How |
|---|---|
| codegen succeeds with full schema | `pnpm envio codegen` exits 0 |
| TypeScript compiles | No type errors in EventHandlers.ts |
| Handler count | 33 event handlers registered |

---

## Session 3: Codegen + Debug

**Goal:** Run the full indexer against live Sepolia data, verify entities populate correctly, fix any issues.

### 3.1 Run codegen

```bash
cd indexer
pnpm envio codegen
```

Fix any schema/config mismatches or type errors.

### 3.2 Start indexer locally or on VPS

```bash
# Local (requires kdio_shared_db and kdio_hasura accessible)
COMPOSE_PROFILES=dev docker compose up -d

# Or run directly
pnpm envio dev
```

### 3.3 Verify entities in Hasura

Query each entity type via Hasura console or GraphQL:
- `RegisteredUser` — should have entries for registered pubkeys
- `FriendRequest` — should reflect friend request/accept/remove lifecycle
- `Group` / `GroupMember` — verify memberCount accuracy
- `Expense` — verify ExpenseUpdated preserves createdAt
- `Settlement` — verify cross-chain settlements from all 5 chains
- `Subname` / `TextRecord` / `AddrRecord` — verify subname registrations
- `ReputationScore` — verify score computation
- `Deployment` — verify kdioDeployer CREATE2 deployments

### 3.4 Debug and fix

Common issues to watch for:
- `start_block: 0` causing very slow sync → update to deployment block numbers
- HyperSync not supporting Arc Testnet → verify `rpc_config` fallback works
- Entity ID collisions → verify ID generation logic
- BigInt handling for amounts/scores
- Hasura schema tracking — may need to manually track new tables

**Commit:** `fix(indexer): address codegen/runtime issues`

### Session 3 Verification

| Check | How |
|---|---|
| Indexer running without errors | Docker logs clean |
| All entity types populated | Hasura queries return data |
| Upsert logic correct | ExpenseUpdated preserves createdAt, FriendRemoved updates status |
| Multi-chain works | Settlements from Base/Arbitrum/Optimism/Arc indexed |

---

## Risks

| Risk | Mitigation |
|---|---|
| HyperSync may not support Arc Testnet (5042002) | `rpc_config` fallback with explicit RPC URL |
| `ENVIO_PG_PUBLIC_SCHEMA=envio` on shared DB conflicts | Hasura uses `hdb_catalog`; `envio` schema is isolated |
| Hasura container name mismatch | Must match VPS orchestration — assumed `kdio_hasura` |
| `start_block: 0` causes slow initial sync | Update to deployment block numbers from broadcast txs |
| Envio env var names may differ across versions | Verify against Envio 2.26.0 docs |
| Codegen generates different handler signatures | Adapt EventHandlers.ts after codegen based on generated types |

## Out of Scope

- VPS orchestration changes (Hasura setup, Nginx, Makefile)
- Settlement relay service (not needed — routing is atomic on-chain)
- Django app integration (covered in `application-03.md`)
- Hasura metadata/permissions configuration
- Production monitoring/alerting

---

## Implementation Notes (Session 1)

### Envio version
- Plan specified `envio@^2.26.0`, installed `envio@2.32.3`. No breaking changes.

### Critical: `optionalDependencies` for `generated` module
- The plan's `package.json` was missing `"optionalDependencies": { "generated": "./generated" }`.
- Without this, `import { USDC } from "generated"` fails at runtime with `Cannot find module 'generated'`.
- The `generated/` directory has `"name": "generated"` in its `package.json` — pnpm links it into `node_modules/generated` via the optional dep.
- Found by checking Envio's own [local-docker-example](https://github.com/enviodev/local-docker-example/blob/main/package.json).

### Critical: `field_selection` required for `event.transaction.hash`
- In Envio v2.11+, `Transaction_t` is **empty by default** (`{}`). Fields must be opted into via `field_selection` in `config.yaml`.
- `Block_t` always has `number`, `timestamp`, `hash` — no opt-in needed.
- Added to config.yaml:
  ```yaml
  field_selection:
    transaction_fields:
      - hash
  ```
- This applies globally. Session 2 config must also include this.

### Database name is lowercase
- The plan references `khaaliSplit_db` but the actual database on the shared Postgres is `khaalisplit_db` (all lowercase).
- Updated `.env` and `.env.example` to use `khaalisplit_db`.

### Hasura table tracking warning (expected)
- On startup, Envio tries to track tables (`USDCTransfer`, `raw_events`, `_meta`, `chain_metadata`) in Hasura.
- This fails with `"invalid-configuration"` because the shared Hasura's default source doesn't point at the `envio` schema in `khaalisplit_db`.
- The indexer logs this as a WARNING and continues — **indexing works fine**, but GraphQL queries via Hasura won't work until the Hasura source is configured to use the `envio` schema.
- This is out of scope for the indexer (covered in VPS orchestration / Hasura metadata config).

### Docker dev mode with bind mount
- The Dockerfile runs `pnpm envio codegen` during build, so the baked image has `generated/` correctly.
- Dev mode bind-mounts `.:/app` and uses an anonymous volume for `/app/node_modules`.
- The bind mount means the host's `generated/` (from local codegen) is used, which works because the symlink in `node_modules/generated` → `../generated` resolves correctly.

### USDC test start_block
- Used `10217500` (~100 blocks behind Sepolia head at time of implementation).
- Indexed **656 Transfer events** within the first ~450 blocks as validation.

### Session 1 Verification Results

| Check | Result |
|---|---|
| ABIs are valid JSON arrays | ✅ All 9 ABIs valid |
| codegen succeeds | ✅ 124/124 ReScript files compiled |
| Docker config valid | ✅ `docker compose --profile dev config` |
| Docker builds | ✅ Image built with codegen inside container |
| Indexer starts and syncs | ✅ HyperSync connected, blocks processed |
| Data in Postgres | ✅ 656+ `USDCTransfer` rows in `envio."USDCTransfer"` |
| Hasura shows data | ⚠️ Hasura source not configured for `envio` schema (expected, out of scope) |

---

## Implementation Notes (Session 2)

### Generated type names are PascalCase
- The plan assumed `khaaliSplitFriends` (camelCase) as the import name from `"generated"`.
- Envio codegen converts contract names to PascalCase: `KhaaliSplitFriends`, `KhaaliSplitGroups`, `KhaaliSplitSettlement`, `KdioDeployer`, etc.
- The plan's `import { khaaliSplitFriends } from "generated"` became `import { KhaaliSplitFriends } from "generated"`.

### Relation fields use `_id` suffix
- Schema declares `group: Group!` on `GroupMember` and `Expense`, and `subname: Subname!` on `TextRecord`.
- Envio codegen flattens these to `group_id: id` and `subname_id: id` (string) in the entity types.
- Handlers must set `group_id: groupId` (not `group: groupId`).

### `DomainConfigured.domain` is `bigint`, entity expects `number`
- `uint32 domain` in the ABI maps to `bigint` in `event.params.domain`.
- Schema defines `domain: Int!` → entity type has `domain: number`.
- Fixed with `Number(event.params.domain)` cast. Safe because uint32 fits in JS number.

### `DomainConfigured.chainId` event param vs `event.chainId`
- The `DomainConfigured(uint256 indexed chainId, uint32 domain)` event has a `chainId` param that represents the **target chain**.
- `event.chainId` represents the **source chain** (where the event was emitted).
- Handler correctly maps `sourceChainId = event.chainId` and `targetChainId = Number(event.params.chainId)`.

### Admin/config events with no entity
- 5 events are logged but don't create entities: `Subnames.BackendUpdated`, `Subnames.ReputationContractUpdated`, `Reputation.BackendUpdated`, `Reputation.SubnameRegistryUpdated`, `Reputation.SettlementContractUpdated`.
- These use `context.log.info()` for observability without DB writes.
- Settlement's config update events (`TokenMessengerUpdated`, `GatewayWalletUpdated`, etc.) DO create `SettlementConfig` entities because they're useful for tracking cross-chain configuration.

### `start_block` set to `10215968` for all chains
- User provided a single `start_block: 10215968` for all networks.
- Applied at the network level (not per-contract) in config.yaml.
- Note: this is a Sepolia block number. L2 chains (Base Sepolia, Arbitrum Sepolia, Optimism Sepolia, Arc Testnet) have different block numbering — the actual deployment blocks on those chains may differ. This should work fine for initial indexing since blocks before the deployment will simply have no matching events.

### `unordered_multichain_mode: true`
- Added as planned for Settlement contract across 5 chains.
- This allows events from different chains to be processed without strict ordering.

### Address normalization
- All addresses are lowercased via the `addr()` helper before storage.
- `event.params.*` addresses come as `Address_t` (hex string) from HyperSync — may already be checksummed, so `.toLowerCase()` ensures consistency.

### Upsert pattern for updates
- Handlers that update existing entities (FriendAccepted, FriendRemoved, MemberAccepted, MemberLeft, ExpenseUpdated, TokenRemoved, SignerRemoved, ReputationUpdated) use `context.Entity.get(id)` to load the existing record.
- If the existing record is not found (e.g., missed the creation event), fallback values are used to create a valid entity anyway.
- `ReputationUpdated` increments `totalSettlements`, `successfulSettlements`, and `failedSettlements` counters, starting from 0 if no prior record exists.

### TypeScript type checking
- `npx tsc --noEmit --skipLibCheck` reports 0 errors in `src/EventHandlers.ts`.
- The remaining errors are in Envio's generated ReScript bindings (`require` not found) — expected and irrelevant at runtime.

### Session 2 Verification Results

| Check | Result |
|---|---|
| codegen succeeds with full schema | ✅ 124/124 ReScript files compiled |
| TypeScript compiles (handlers only) | ✅ 0 type errors in `src/EventHandlers.ts` |
| Handler count | ✅ 33 event handlers registered (4+4+2+9+5+5+3+1) |
| Entity count | ✅ 18 entity types in schema |
| Contracts indexed | ✅ 8 contracts across 5 chains |
