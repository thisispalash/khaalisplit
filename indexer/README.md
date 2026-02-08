# khaaliSplit Indexer

Envio HyperIndex event indexer for khaaliSplit. Watches all 8 contracts across 5 chains and writes to the shared Postgres via Hasura.

## Architecture

```
on-chain events              Envio HyperIndex              Shared Postgres
─────────────────            ─────────────────             ───────────────

8 contracts on 5 chains  →   Event Handlers (pure)     →   khaaliSplit_db.envio
  Friends                      33 event handlers             schema
  Groups                       deterministic,
  Expenses                     no side effects
  Settlement (×5 chains)
  Subnames
  Reputation
  Resolver
  kdioDeployer
```

No relay service needed — settlement routing (Gateway/CCTP) happens atomically on-chain inside `settleWithAuthorization()` and `settleFromGateway()`.

## Indexed Chains

| Chain | Chain ID | Contracts |
|-------|----------|-----------|
| Sepolia | 11155111 | All 8 |
| Base Sepolia | 84532 | Settlement only |
| Arbitrum Sepolia | 421614 | Settlement only |
| Optimism Sepolia | 11155420 | Settlement only |
| Arc Testnet | 5042002 | Settlement only |

## Setup

```bash
cp .env.example .env
# Fill in ENVIO_API_TOKEN, PG credentials, Hasura secret

pnpm install
pnpm envio codegen
```

## Running

```bash
# Local development
pnpm envio dev

# Docker (dev)
COMPOSE_PROFILES=dev docker compose up -d

# Docker (prod)
COMPOSE_PROFILES=prod docker compose up -d
```

## Infrastructure

Uses the shared VPS infrastructure:
- **Postgres**: `kdio_shared_db` on `kdio_network`, database `khaaliSplit_db`, schema `envio`
- **Hasura**: `kdio_hasura` on `kdio_network`, port 8080

See `.plans/indexer-01.md` for the full implementation plan.
