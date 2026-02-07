# khaaliSplit

A censorship-resistant way to split payments with friends and strangers.

Built for **ETHGlobal HackMoney 2026**. Django + HTMX + ethers.js — server-rendered hypermedia with on-chain settlement.

## Architecture

```
browser ─── HTMX partials ──► Django views ──► Postgres (cache layer)
   │                                              │
   └── ethers.js ──► smart contracts ◄────────────┘
                     (Sepolia + L2s)         (sync on-chain state)
```

**Local-first cache**: All data lives in Postgres for fast UX. On-chain transactions happen client-side via the connected wallet. The backend caches results and serves them as HTMX partials.

### Stack

| Layer | Tech |
|-------|------|
| Backend | Django 6.0, Python 3.13 |
| Frontend | HTMX 2.0, Hyperscript, Tailwind CSS v4 |
| Wallet | ethers.js v6 (local, not CDN) |
| Database | PostgreSQL (shared `kdio_shared_db` on Docker network) |
| Encryption | AES-256-GCM via Web Crypto API, HKDF key derivation |
| Auth | Django sessions, EIP-191 signature verification |
| ENS | CCIP-Read (EIP-3668) offchain resolver gateway |
| Settlement | EIP-2612 permit + `settleWithPermit` on-chain |
| Analytics | GoatCounter (self-hosted) |
| Deployment | Docker, Gunicorn, Nginx reverse proxy |

### Django Apps

- **`api`** — Models, HTMX views, forms, utils (web3, ENS, crypto, debt simplification)
- **`web`** — Desktop full-page routes
- **`m`** — Mobile full-page routes (PWA-ready)
- **`config`** — Settings, WSGI, URL root, context processors
- **`middleware`** — Wide event logging (one structured JSON log per request)

## Project Structure

```
app/
├── api/
│   ├── forms/          # auth, groups, expenses
│   ├── models/         # user, friends, groups, expenses, settlement, activity
│   ├── utils/          # web3_utils, ens_codec, ens_signer, debt_simplifier
│   └── views/          # auth, friends, groups, expenses, settlement, activity, ens_gateway
├── config/             # settings, urls, wsgi, context_processors
├── middleware/          # wide_event_logging
├── static/
│   ├── css/            # tw-in.css (Tailwind input), tw.css (compiled)
│   └── js/             # htmx, hyperscript, ethers, wallet.js, app.js, crypto.js
├── templates/
│   ├── auth/           # signup, login, onboarding
│   ├── activity/       # feed + partials
│   ├── friends/        # list + partials
│   ├── groups/         # list, detail, create + partials
│   ├── expenses/       # partials (form, card, list)
│   ├── settlement/     # settle page + partials
│   ├── components/     # header, footer
│   └── partials/       # toast, loading
├── web/                # desktop routes
├── m/                  # mobile routes
├── Dockerfile
├── Makefile
├── docker-compose.yml
├── manage.py
└── pyproject.toml
```

## Setup

### Prerequisites

- Docker + Docker Compose
- `kdio_network` Docker network (`docker network create kdio_network`)
- `kdio_shared_db` PostgreSQL container running on that network
- `.env` file (copy from `.env.example`)

### Quick Start

```bash
# 1. Copy env and fill in values
cp .env.example .env

# 2. Create database + run migrations
make docker-db-setup

# 3. Start dev server (Tailwind watch + Django runserver)
COMPOSE_PROFILES=dev docker compose up -d
```

The app will be available at `http://khaalisplit.localhost` (via nginx) or `http://localhost:8002` (direct).

### Makefile Targets

| Target | Description |
|--------|-------------|
| `make dev` | Tailwind watch + Django runserver (parallel) |
| `make server` | Django runserver only |
| `make tailwind` | Tailwind watch only |
| `make build` | Build CSS + collectstatic + migrations |
| `make prod` | Full build + Gunicorn |
| `make migrate` | Run Django migrations |
| `make makemigrations` | Generate Django migrations |
| `make shell` | Django shell |
| `make docker-db-setup` | Create DB (if not exists) + migrations |
| `make docker-migrate` | Run migrations inside container |
| `make docker-shell` | Django shell inside container |

## Environment Variables

```bash
# Django
SECRET_KEY=             # required, fail-loud
DEBUG=true              # required, fail-loud

# PostgreSQL
PG_HOST=kdio_shared_db
PG_PORT=5432
PG_USER=
PG_PASS=
PG_DATABASE=khaaliSplit_db

# Analytics
GOATCOUNTER_URL=        # leave blank to disable

# Web3
SEPOLIA_RPC_URL=        # Alchemy/Infura RPC
BACKEND_PRIVATE_KEY=    # for server-side tx (pubkey registration)
GATEWAY_SIGNER_KEY=     # for ENS CCIP-Read response signing

# Contracts (Sepolia addresses, set after deployment)
CONTRACT_FRIENDS=
CONTRACT_GROUPS=
CONTRACT_EXPENSES=
CONTRACT_SETTLEMENT=
CONTRACT_RESOLVER=
```

## Features

### Auth & Identity
- Signup with auto-generated subname (adjective-animal via `unique-names-generator`)
- Django session auth
- Wallet linking with EIP-191 signature verification
- Public key recovery + on-chain registration

### ENS Integration
- CCIP-Read (EIP-3668) offchain resolver gateway
- Subname resolution: `yourname.khaalisplit.eth`
- Resolves `addr()`, `text()` (display name, avatar, reputation, payment prefs)

### Friends
- Search by subname (HTMX debounced)
- Send/accept/remove friend requests
- Bidirectional `CachedFriend` records

### Groups
- Create groups, invite members by subname
- Accept invitations, leave groups
- HTMX lazy-loaded member list and balance summary

### Expenses
- Add expenses with equal/exact/percentage splits
- Client-side AES-256-GCM encryption before submission
- Group keys derived via ECDH + HKDF
- Encrypted data stored server-side, decrypted in-browser

### Settlement
- Greedy min-cash-flow debt simplification algorithm
- EIP-2612 permit signing for gasless USDC approval
- `settleWithPermit` on-chain call via ethers.js
- Settlement status polling (HTMX, every 5s, auto-stops on confirmed/failed)
- Multi-chain support: Sepolia, Base, Arbitrum, Avalanche, Optimism

### Activity Feed
- Paginated feed with HTMX infinite scroll (`hx-trigger="revealed"`)
- 14 action types with per-type icons

## Smart Contracts

Contracts are in `../../contracts/`. Currently **not yet deployed** — the app runs in local-cache mode. Once deployed, set addresses in `.env` and the client-side wallet interactions will go through.

| Contract | Purpose |
|----------|---------|
| `khaaliSplitFriends` | On-chain friend graph |
| `khaaliSplitGroups` | Group creation + membership |
| `khaaliSplitExpenses` | Encrypted expense data hashes |
| `khaaliSplitSettlement` | USDC settlement with EIP-2612 permit |
| `khaaliSplitResolver` | ENS offchain resolver (CCIP-Read verifier) |

## Production

```bash
# Build + start with Gunicorn
COMPOSE_PROFILES=prod docker compose up -d
```

Served behind nginx reverse proxy on the `kdio_network`. Static files served from the `khaalisplit_static` Docker volume.
