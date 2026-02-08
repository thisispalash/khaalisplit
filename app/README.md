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
- **`web`** — Full-page routes (renders page templates)
- **`m`** — Mobile routes (PWA-ready, separate app)
- **`config`** — Settings, WSGI, URL root, context processors
- **`middleware`** — Wide event logging (one structured JSON log per request)

## Design System

The UI follows a token-driven component hierarchy. Two base colors (black background, green foreground) derive all semantic colors via `color-mix()`.

### Component Hierarchy

```
quanta/     → Stateless primitives (button, badge, spinner, toast, icon, address, amount, ...)
photons/    → Stateful composites (form-field, user-pill, wallet-button, search-bar, debt-arrow, ...)
lenses/     → Card templates (activity-card, friend-card, group-card, expense-card, settlement-card, invite-card)
prisms/     → Section templates (nav-header, bottom-nav, footer, activity-feed, friend-list, group-members, ...)
pages/      → Full page templates (extend base.html, compose from prisms/lenses/photons/quanta)
partials/   → API response fragments (HTMX swap targets returned by api/views/)
```

### Design Tokens

All colors derived from two base values via `color-mix()` in `tw-in.css`:

| Token | Usage |
|-------|-------|
| `surface` / `surface-raised` | Card/section backgrounds |
| `border` / `border-hover` | Borders, dividers |
| `foreground` | Primary text, errors (max contrast = urgency) |
| `muted` | Secondary text, pending states |
| `subtle` | Timestamps, placeholders |
| `emphasis` / `emphasis-muted` | Success, confirmed states |
| `dim` / `dim-muted` | Inactive, left states |
| `accent-muted` | Error backgrounds |

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
│   ├── font/           # Nunito Sans, Syne Mono (self-hosted TTF)
│   └── js/             # htmx, hyperscript, ethers, wallet.js, app.js, crypto.js
├── templates/
│   ├── base.html       # unified base (desktop nav + mobile bottom-nav + footer)
│   ├── pages/          # 11 full-page templates
│   ├── prisms/         # 8 section templates
│   ├── lenses/         # 6 card templates
│   ├── photons/        # 7 stateful composites
│   ├── quanta/         # 12 stateless primitives + 10 SVG icons
│   └── partials/       # 7 API response fragments (HTMX swap targets)
├── web/                # full-page routes + urls
├── m/                  # mobile routes (PWA)
├── Dockerfile
├── Makefile
├── docker-compose.yml
├── manage.py
└── pyproject.toml
```

### Template File Inventory

**pages/ (11):** home, signup, login, onboarding-profile, onboarding-wallet, friends, groups-list, group-detail, group-create, settle, profile

**prisms/ (8):** nav-header, bottom-nav, footer, activity-feed, friend-list, group-members, group-expenses, balance-summary

**lenses/ (6):** activity-card, friend-card, group-card, expense-card, settlement-card, invite-card

**photons/ (7):** form-field, form-errors, user-pill, wallet-button, search-bar, debt-arrow, step-indicator

**quanta/ (12):** button (+2 internal), badge, spinner, toast, icon, address, amount, empty-state, input, select

**partials/ (7):** activity_list, search_results, pending_requests, member_list, expense_list, expense_form, debt_summary

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

## URL Routes

### Web (full pages)

| Route | View | Template |
|-------|------|----------|
| `/` | `home` | `pages/home.html` (auth) / `pages/signup.html` (anon) |
| `/friends/` | `friends_list` | `pages/friends.html` |
| `/groups/` | `groups_list` | `pages/groups-list.html` |
| `/groups/create/` | `group_create` | `pages/group-create.html` |
| `/groups/<id>/` | `group_detail` | `pages/group-detail.html` |
| `/settle/<id>/` | `settle` | `pages/settle.html` |
| `/profile/` | `profile` | `pages/profile.html` (own, editable) |
| `/profile/<subname>/` | `profile_public` | `pages/profile.html` (public or own) |
| `/u/<subname>/` | `profile_public` | `pages/profile.html` (short URL) |

### API (HTMX partials + JSON)

| Route | Returns |
|-------|---------|
| `/api/auth/signup/` | `pages/signup.html` |
| `/api/auth/login/` | `pages/login.html` |
| `/api/auth/onboarding/profile/` | `pages/onboarding-profile.html` |
| `/api/auth/onboarding/wallet/` | `pages/onboarding-wallet.html` |
| `/api/activity/load-more/` | `partials/activity_list.html` |
| `/api/friends/search/` | `partials/search_results.html` |
| `/api/friends/request/<subname>/` | `lenses/friend-card.html` |
| `/api/friends/accept/<addr>/` | `lenses/friend-card.html` |
| `/api/friends/pending/` | `partials/pending_requests.html` |
| `/api/groups/create/` | redirect / `pages/group-create.html` |
| `/api/groups/<id>/invite/` | `partials/member_list.html` |
| `/api/groups/<id>/accept/` | `lenses/group-card.html` |
| `/api/groups/<id>/members/` | `partials/member_list.html` |
| `/api/groups/<id>/balances/` | `prisms/balance-summary.html` |
| `/api/expenses/<id>/add/` | `partials/expense_list.html` / `partials/expense_form.html` |
| `/api/expenses/<id>/list/` | `partials/expense_list.html` |
| `/api/expenses/<id>/update/` | `lenses/expense-card.html` |
| `/api/settle/<id>/debts/` | `partials/debt_summary.html` |
| `/api/settle/status/<hash>/` | `lenses/settlement-card.html` |

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
