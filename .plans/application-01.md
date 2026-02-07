# khaaliSplit — Django App Implementation Plan (v2)

## Scope

**Only the Django application.** Contracts are complete. Envio indexer is a separate PR (uses its own Postgres database — can keep completely separate). Deployment infra lives in `vps-orchestration`.

**Repository:** `/Users/thisispalash/local/___2026-final/hacks/hackmoney2026/src/app/`
**Django code:** `src/app/app/` (sibling to `contracts/`)
**Current state:** Django project initialized, 3 empty apps scaffolded (api, web, m), base template exists, Tailwind compiled, HTMX + Hyperscript + ethers.js JS in place. Settings still default (SQLite, no apps registered). No models, views, or routes wired up.

## Key Design Decisions

1. **Django 6.0** with standard DTL + HTMX
2. **Hyperscript** (not Alpine.js) for client-side reactivity
3. **Django sessions** for auth (not JWT)
4. **Poetry** for dependency management
5. **3 Django apps:** `api` (models + HTMX views), `web` (desktop routes), `m` (mobile routes + PWA)
6. **config/** is the Django project folder
7. **Models organized** as separate files in `api/models/`
8. **No Envio indexer** — write directly to Postgres cache (separate PR; indexer gets its own DB)
9. **Backend interfaces with contracts** via web3.py for: pubkey registration, ENS gateway signing
10. **Git commit after every step.** Co-author line included.
11. **VPS deployment** follows the `vps-orchestration` pattern (shared Postgres on `kdio_network`, Nginx reverse proxy, GoatCounter analytics)
12. **Color theme:** dark background `oklch(15.434% 0 none)` with green foreground `oklch(90.537% 0.1574 142.27)` — already configured in `static/css/tw-in.css` as CSS custom properties `--color-background` and `--color-foreground`. Color reference: https://randoma11y.com/oklch(15.434%25%200%20none)/oklch(90.537%25%200.1574%20142.27)
13. **UI inspiration:** Mobile-first expense splitting (Splitwise-like flows) but with our own identity. Not a Splitwise clone — crypto-native with ENS subnames, wallet linking, and encrypted groups.
14. **Wide event logging** — one structured JSON log per request, inspired by https://loggingsucks.com. Middleware pattern copied from `unhinged_lander`. Views can enrich via `request._wide_event['extra']`.
15. **ethers.js as local file** (not CDN) — already added to `static/js/` by user.
16. **Mobile wallet connection** — `window.ethereum` won't exist on mobile PWA. Use Web3Modal / WalletConnect deep linking for device wallet connections.
17. **Dockerfile + Makefile** deferred to last step. `make build` target will handle: Tailwind CSS build, collectstatic, migrations.

---

## Project Structure

All Django code lives in `src/app/app/` — a sibling to `contracts/`.

```
/src/app/                           # repo root
├── contracts/                      # (existing) Smart contracts
├── PRD.md                          # (existing)
├── .plans/                         # (existing) Implementation plans
│
└── app/                            # Django application root
    ├── manage.py                   # (existing)
    ├── pyproject.toml              # (existing) Poetry
    ├── poetry.lock                 # (existing)
    ├── docker-compose.yml          # (existing) dev/prod profiles on kdio_network
    ├── Makefile                    # (existing) needs finalization
    ├── .env.example                # (existing) PG_HOST, PG_PORT, etc.
    ├── tailwindcss                 # (existing) ARM64 binary
    │
    ├── config/                      # (existing) Django project settings
    │   ├── __init__.py
    │   ├── settings.py              # NEEDS CONFIGURATION
    │   ├── context_processors.py    # NEW — GoatCounter URL
    │   ├── urls.py                  # NEEDS WIRING
    │   ├── wsgi.py                  # NEEDS NAMED EXPORT
    │   └── asgi.py
    │
    ├── middleware/                   # NEW — custom middleware
    │   ├── __init__.py
    │   └── wide_event_logging.py    # One JSON log per request (from unhinged pattern)
    │
    ├── api/                         # Models + HTMX partial views
    │   ├── __init__.py              # (existing)
    │   ├── admin.py                 # (existing, empty)
    │   ├── apps.py                  # (existing)
    │   ├── urls.py                  # NEW
    │   ├── views/                   # NEW (replace existing views.py)
    │   │   ├── __init__.py
    │   │   ├── auth.py              # signup, login, logout, onboarding
    │   │   ├── friends.py           # search, request, accept, remove
    │   │   ├── groups.py            # create, invite, accept, leave, detail
    │   │   ├── expenses.py          # add, list, update
    │   │   ├── settlement.py        # debts, initiate, status
    │   │   ├── ens_gateway.py       # CCIP-Read endpoint
    │   │   └── activity.py          # feed, load-more
    │   ├── models/                  # NEW (replace existing models.py)
    │   │   ├── __init__.py          # imports all models
    │   │   ├── user.py              # User, LinkedAddress, BurntAddress
    │   │   ├── friends.py           # CachedFriend
    │   │   ├── groups.py            # CachedGroup, CachedGroupMember
    │   │   ├── expenses.py          # CachedExpense
    │   │   ├── settlement.py        # CachedSettlement
    │   │   └── activity.py          # Activity
    │   ├── forms/                   # NEW
    │   │   ├── __init__.py
    │   │   ├── auth.py              # SignupForm, LoginForm, ProfileForm
    │   │   ├── groups.py            # CreateGroupForm
    │   │   └── expenses.py          # AddExpenseForm
    │   ├── utils/                   # NEW
    │   │   ├── __init__.py
    │   │   ├── web3_utils.py        # Signature verification, pubkey recovery, on-chain calls
    │   │   ├── ens_codec.py         # DNS name parsing, ABI encode/decode for CCIP-Read
    │   │   ├── ens_signer.py        # EIP-191 response signing for gateway
    │   │   └── debt_simplifier.py   # Greedy min-cash-flow algorithm
    │   └── migrations/              # (existing)
    │
    ├── web/                         # (existing) Desktop-specific views/routes
    │   ├── __init__.py
    │   ├── urls.py                  # NEW
    │   └── views.py                 # NEEDS IMPLEMENTATION
    │
    ├── m/                           # (existing) Mobile-specific views/routes + PWA
    │   ├── __init__.py
    │   ├── urls.py                  # NEW
    │   ├── views.py                 # NEEDS IMPLEMENTATION
    │   └── static/m/               # NEW
    │       ├── manifest.json        # PWA manifest
    │       └── sw.js                # Service worker
    │
    ├── templates/                   # (existing) Shared templates
    │   ├── base.html                # (existing) HTMX + Hyperscript + Tailwind + GoatCounter
    │   ├── base_desktop.html        # NEW — desktop layout extending base
    │   ├── base_mobile.html         # NEW — mobile layout extending base
    │   ├── components/              # (existing)
    │   │   ├── header.html          # (existing, empty) NEEDS IMPLEMENTATION
    │   │   └── footer.html          # (existing, empty) NEEDS IMPLEMENTATION
    │   ├── partials/                # NEW
    │   │   ├── toast.html
    │   │   └── loading.html
    │   ├── auth/                    # NEW
    │   │   ├── login.html
    │   │   ├── signup.html
    │   │   └── onboarding/{welcome,profile,wallet}.html
    │   ├── friends/                 # NEW
    │   │   ├── list.html
    │   │   └── partials/{friend_card,search_results,request_card,pending_requests}.html
    │   ├── groups/                  # NEW
    │   │   ├── list.html
    │   │   ├── detail.html
    │   │   ├── create.html
    │   │   └── partials/{group_card,member_list,invite_form,balance_summary}.html
    │   ├── expenses/                # NEW
    │   │   └── partials/{expense_list,expense_form,expense_card}.html
    │   ├── settlement/              # NEW
    │   │   ├── settle.html
    │   │   └── partials/{debt_summary,settle_form,settlement_status}.html
    │   └── activity/                # NEW
    │       ├── feed.html
    │       └── partials/{activity_list,activity_item}.html
    │
    └── static/                      # (existing)
        ├── css/
        │   ├── tw-in.css            # (existing) Tailwind source + CSS custom props
        │   └── tw.css               # (existing) Compiled Tailwind
        └── js/
            ├── htmx@2.0.8.js       # (existing)
            ├── htmx-ext-ws@2.0.4.js # (existing) WebSocket extension
            ├── _hyperscript@0.9.14.js # (existing)
            ├── ethers@6.*.js        # (existing) ethers.js v6 — LOCAL file, no CDN
            ├── goat.js              # (existing) GoatCounter
            ├── wallet.js            # NEW — wallet connect, sign, ECDH, tx submission
            ├── crypto.js            # NEW — Web Crypto API: AES-256-GCM encrypt/decrypt
            └── app.js               # NEW — Hyperscript helpers + HTMX event glue
```

---

## Deployment Context

This app runs on the `vps-orchestration` infrastructure:
- **Shared Postgres** at `kdio_shared_db:5432` on `kdio_network`
- **Nginx reverse proxy** handles SSL + static files (`/static/` aliased to volume)
- **GoatCounter** self-hosted analytics (already in `base.html` via `GOATCOUNTER_URL` env var)
- **Port assignment:** 8002 (next available in `ports.json`)
- **Dockerfile pattern:** Python 3.13-slim, Poetry, Tailwind CLI in `/usr/local/bin`
- **WSGI:** Named export (e.g., `config.wsgi:khaaliSplit`) for Gunicorn
- **Settings pattern:** `os.environ['SECRET_KEY']` (fail loud), `dj_database_url.config()`, GoatCounter context processor

---

## Models

All in `api/models/`. Follow PRD schema (PRD.md:842-935).

### user.py
- **User** (AbstractBaseUser + PermissionsMixin) — subname (USERNAME_FIELD, unique), display_name, avatar_url, reputation_score, farcaster_fid, is_active, is_staff, created_at, updated_at
- **LinkedAddress** — user FK, address (42 chars), is_primary, chain_id, token, token_addr, pub_key, pub_key_registered, verified_at
- **BurntAddress** — address (unique), original_subname, reason, burnt_at

### friends.py
- **CachedFriend** — user FK, friend_address, friend_user FK (nullable), status (pending_sent/pending_received/accepted/removed), updated_at

### groups.py
- **CachedGroup** — group_id (on-chain, unique), name, name_hash, creator FK, member_count, updated_at
- **CachedGroupMember** — group FK, user FK, member_address, encrypted_key, status (invited/accepted/left), updated_at

### expenses.py
- **CachedExpense** — expense_id (on-chain, unique), group FK, creator FK, creator_address, data_hash, encrypted_data, amount, description, split_type, category, participants_json, created_at, updated_at

### settlement.py
- **CachedSettlement** — tx_hash (unique), from_user FK, from_address, to_address, to_user FK (nullable), token, amount, source_chain, dest_chain, status (pending/submitted/bridging/confirmed/failed), group FK (nullable), created_at, updated_at

### activity.py
- **Activity** — user FK, action_type, group_id, expense_id, settlement_hash, metadata JSON, message, is_synced, created_at

**Critical:** `AUTH_USER_MODEL = 'api.User'` must be set before first migration.

---

## URL Routing

### config/urls.py (project root)
```
/admin/          → Django admin
/api/            → api.urls (HTMX partial views + ENS gateway)
/                → web.urls (desktop full-page views)
/m/              → m.urls (mobile full-page views)
```

### api/urls.py
| Route | View | Type |
|-------|------|------|
| `auth/signup/` | SignupView | POST |
| `auth/login/` | LoginView | POST |
| `auth/logout/` | LogoutView | POST |
| `auth/onboarding/profile/` | OnboardingProfileView | GET/POST |
| `auth/onboarding/wallet/` | OnboardingWalletView | GET/POST |
| `auth/address/verify/` | VerifySignatureView | POST |
| `auth/pubkey/register/` | RegisterPubKeyView | POST |
| `friends/search/` | FriendSearchView | GET (HTMX) |
| `friends/request/<subname>/` | SendFriendRequestView | POST (HTMX) |
| `friends/accept/<address>/` | AcceptFriendView | POST (HTMX) |
| `friends/remove/<address>/` | RemoveFriendView | POST (HTMX) |
| `friends/pending/` | PendingRequestsView | GET (HTMX) |
| `groups/create/` | CreateGroupView | POST |
| `groups/<id>/invite/` | InviteMemberView | POST (HTMX) |
| `groups/<id>/accept/` | AcceptGroupInviteView | POST (HTMX) |
| `groups/<id>/leave/` | LeaveGroupView | POST (HTMX) |
| `groups/<id>/members/` | GroupMembersView | GET (HTMX) |
| `groups/<id>/balances/` | GroupBalancesView | GET (HTMX) |
| `expenses/<group_id>/add/` | AddExpenseView | POST (HTMX) |
| `expenses/<group_id>/list/` | ExpenseListView | GET (HTMX) |
| `expenses/<id>/update/` | UpdateExpenseView | POST (HTMX) |
| `settle/<group_id>/debts/` | DebtSummaryView | GET (HTMX) |
| `settle/<group_id>/initiate/` | InitiateSettlementView | POST |
| `settle/status/<tx_hash>/` | SettlementStatusView | GET (HTMX polling) |
| `activity/load-more/` | ActivityLoadMoreView | GET (HTMX) |
| `ens-gateway/<sender>/<data>.json` | CCIPReadView | GET (EIP-3668) |

### web/urls.py (desktop full pages)
| Route | View |
|-------|------|
| `/` | Home (activity feed) |
| `/friends/` | Friends list |
| `/groups/` | Groups list |
| `/groups/<id>/` | Group detail |
| `/groups/create/` | Create group form |
| `/settle/<group_id>/` | Settlement page |
| `/profile/` | Own profile |
| `/profile/<subname>/` | Public profile |

### m/urls.py (mobile full pages)
Same routes as web/ but with mobile-optimized page views.

---

## HTMX + Hyperscript Patterns

1. **Search with debounce** — `hx-trigger="keyup changed delay:300ms"` for friend search
2. **On-chain action flow** — HTMX POST → api/ returns partial with `data-tx-*` attrs → Hyperscript `on load` handler calls wallet.js → tx confirmed → Hyperscript dispatches custom event → HTMX refresh
3. **Polling** — `hx-trigger="every 5s"` for settlement status; stops when partial omits trigger
4. **Infinite scroll** — `hx-trigger="revealed"` for activity feed pagination
5. **OOB toasts** — `hx-swap-oob="afterbegin"` on `#toast-container`
6. **Hyperscript instead of Alpine.js** — Use `_="on click ..."` for client-side wallet state, modal toggles, form validation feedback, loading spinners

---

## Web3 Integration

### Client-Side
- **wallet.js** (ethers.js v6, local file) — wallet connection via Web3Modal/WalletConnect (for mobile PWA deep linking — `window.ethereum` not available on devices), sign messages, ECDH (`SigningKey.computeSharedSecret()`), contract calls (requestFriend, createGroup, addExpense, etc.), EIP-2612 permit signing. Falls back to injected provider on desktop browsers.
- **crypto.js** (Web Crypto API) — AES-256-GCM encrypt/decrypt, group key generation, HKDF from ECDH shared secret
- **app.js** — Hyperscript behavior helpers, global wallet state, HTMX event listeners for on-chain tx coordination

### Server-Side
- **api/utils/web3_utils.py** (web3.py + eth_account) — `recover_message()` for sig verification, pubkey recovery, `registerPubKey()` on-chain via backend wallet
- **api/utils/ens_codec.py** (eth_abi) — DNS name parsing, ABI encode/decode
- **api/utils/ens_signer.py** (eth_account) — EIP-191 signing for CCIP-Read responses

---

## ENS Gateway (CCIP-Read)

Endpoint: `/api/ens-gateway/<sender>/<data>.json`

Flow: Client calls `resolve()` on khaaliSplitResolver → reverts with `OffchainLookup` → client GETs gateway → Django parses DNS name, looks up User, ABI-encodes response, signs → returns JSON

Supports: `addr(bytes32)` → primary address, `text(bytes32,string)` → display, avatar, payment preferences, reputation

---

## Implementation Steps

### Step 0: Add Plan to Repository
1. Copy this plan to `.plans/application-01.md` (overwrite the old one)
2. Commit: `"docs: update app implementation plan (v2)"`

### Step 1: Configure Settings + Middleware
Settings follow the `unhinged_lander` pattern from `vps-orchestration`.
1. Configure `config/settings.py`:
   - `load_dotenv()`, `os.environ['SECRET_KEY']` (fail loud), DEBUG from env
   - `ALLOWED_HOSTS` for dev (localhost, khaalisplit.localhost) and prod
   - `CSRF_TRUSTED_ORIGINS` matching
   - `INSTALLED_APPS`: django-htmx, django-extensions, api, web, m
   - `MIDDLEWARE`: add `django_htmx.middleware.HtmxMiddleware` + `middleware.wide_event_logging.WideEventLoggingMiddleware`
   - `TEMPLATES DIRS`: `[BASE_DIR / 'templates']`
   - `TEMPLATES context_processors`: add `config.context_processors.goatcounter_url`
   - `DATABASES`: `dj_database_url.config()` with PG env vars
   - `STATIC_ROOT`, `STATICFILES_DIRS`
   - `AUTH_USER_MODEL = 'api.User'`
   - `DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'`
   - `LOGGING` config for wide event logger (console handler, JSON format)
   - Web3 env vars: `SEPOLIA_RPC_URL`, `BACKEND_PRIVATE_KEY`, `GATEWAY_SIGNER_KEY`, contract addresses
2. Create `config/context_processors.py` — GoatCounter URL (copy pattern from unhinged)
3. Update `config/wsgi.py` — named export `khaaliSplit = get_wsgi_application()`
4. Create `middleware/wide_event_logging.py` — one JSON log per request (adapt from unhinged pattern, add khaaliSplit-specific fields like subname, wallet address)
5. Update `.env.example` — add Web3 env vars (SEPOLIA_RPC_URL, contract addresses, etc.)
6. Commit: `"feat: configure settings, middleware, context processors"`

### Step 2: Restructure api/ App + Models
1. Delete `api/models.py` and `api/views.py`
2. Create `api/models/`, `api/views/`, `api/forms/`, `api/utils/` directories with `__init__.py` files
3. Implement all models in `api/models/`:
   - `user.py` — User (AbstractBaseUser), LinkedAddress, BurntAddress
   - `friends.py` — CachedFriend
   - `groups.py` — CachedGroup, CachedGroupMember
   - `expenses.py` — CachedExpense
   - `settlement.py` — CachedSettlement
   - `activity.py` — Activity
4. Wire up `api/models/__init__.py` to import all models
5. Register models in `api/admin.py`
6. Run `poetry run python manage.py makemigrations` + `migrate`
7. Commit: `"feat: database models and initial migrations"`

### Step 3: Templates + Components
1. Update `templates/base.html` — add ethers.js, toast container, Hyperscript wallet state on body
2. Create `templates/base_desktop.html` and `templates/base_mobile.html` extending base
3. Implement `templates/components/header.html` — nav with wallet connection status, user subname, links to friends/groups/settle
4. Implement `templates/components/footer.html` — minimal footer
5. Create `templates/partials/toast.html`, `loading.html`
6. Commit: `"feat: base templates with header, footer, toast system"`

### Step 4: Auth (Signup + Login + Onboarding)
1. Implement username generation using `unique-names-generator` package
2. Implement `api/forms/auth.py` — SignupForm, LoginForm, ProfileForm
3. Implement `api/views/auth.py` — SignupView, LoginView, LogoutView, OnboardingProfileView, OnboardingWalletView, VerifySignatureView
4. Create auth templates: `templates/auth/signup.html`, `login.html`, `onboarding/*.html`
5. Wire up `api/urls.py` auth routes
6. Create home page in `web/views.py` and `m/views.py` (activity feed placeholder)
7. Wire up `config/urls.py`, `web/urls.py`, `m/urls.py`
8. Commit: `"feat: auth with signup, login, onboarding wizard"`

### Step 5: Web3 Utils + Wallet Linking
1. Implement `api/utils/web3_utils.py` — signature verification, pubkey recovery, registerPubKey on-chain call
2. Implement RegisterPubKeyView in `api/views/auth.py`
3. Create `static/js/wallet.js` — ethers.js connection, message signing
4. Create `static/js/app.js` — Hyperscript helpers for wallet state
5. Update onboarding/wallet template to use wallet.js + Hyperscript
6. Commit: `"feat: wallet linking with signature verification + pubkey registration"`

### Step 6: ENS Gateway
1. Implement `api/utils/ens_codec.py` — DNS name parsing, ABI encode/decode
2. Implement `api/utils/ens_signer.py` — EIP-191 signing
3. Implement `api/views/ens_gateway.py` — CCIPReadView
4. Wire up ENS gateway route in `api/urls.py`
5. Commit: `"feat: ENS CCIP-Read gateway for subname resolution"`

### Step 7: Friends
1. Implement `api/views/friends.py` — search, request, accept, remove, pending
2. Create friend templates: `templates/friends/list.html`, partials
3. Wire up routes in `api/urls.py`, `web/urls.py`, `m/urls.py`
4. Commit: `"feat: friend search, request, accept flows"`

### Step 8: Groups
1. Implement `api/views/groups.py` — create, invite, accept, leave, members, balances
2. Implement `api/forms/groups.py` — CreateGroupForm
3. Create group templates: `templates/groups/list.html`, `detail.html`, `create.html`, partials
4. Wire up routes
5. Commit: `"feat: group creation, invitation, member management"`

### Step 9: Expenses + Encryption
1. Implement `api/views/expenses.py` — add, list, update
2. Implement `api/forms/expenses.py` — AddExpenseForm
3. Create expense templates: partials
4. Create `static/js/crypto.js` — AES-256-GCM encrypt/decrypt, group key generation
5. Wire up routes
6. Commit: `"feat: encrypted expense tracking with client-side crypto"`

### Step 10: Settlement
1. Implement `api/utils/debt_simplifier.py` — greedy min-cash-flow algorithm
2. Implement `api/views/settlement.py` — debts, initiate, status polling
3. Update `static/js/wallet.js` with EIP-2612 permit signing
4. Create settlement templates
5. Wire up routes
6. Commit: `"feat: debt simplification and USDC settlement with permit"`

### Step 11: Activity Feed
1. Implement `api/views/activity.py` — feed, load-more with infinite scroll
2. Create activity templates
3. Wire up activity creation in other views (signals or direct calls)
4. Commit: `"feat: activity feed with infinite scroll"`

### Step 12: Dockerfile + Makefile + Build Pipeline
1. Finalize `Makefile` — adapt Reference 2 pattern:
   - `make dev` — Tailwind watch + Django runserver in parallel
   - `make server` — Django runserver only
   - `make tailwind` — Tailwind watch only
   - `make build` — Tailwind CSS minify + collectstatic + makemigrations + migrate
   - `make prod` — build + gunicorn
   - `make migrate`, `make makemigrations`, `make shell`
   - `make docker-*` variants
2. Create `Dockerfile` — follow unhinged pattern (Python 3.13-slim, Poetry, Tailwind CLI in `/usr/local/bin`)
3. Verify docker-compose.yml works with `make dev` and `make prod`
4. Commit: `"feat: Dockerfile, Makefile, build pipeline"`

---

## Dependencies (pyproject.toml — already configured)

```
django >=6.0.2, django-htmx, psycopg2-binary, web3 >=7.14.1,
python-dotenv, gunicorn, dj-database-url, unique-names-generator
Dev: ruff, django-extensions
```

All JS is local (no CDN):
- HTMX 2.0.8, Hyperscript 0.9.14, HTMX WS extension, ethers.js v6, GoatCounter

---

## Verification

1. **Step 1:** `poetry run python manage.py runserver` works with Postgres, wide event logs appear in console, GoatCounter context processor functional
2. **Step 2:** Admin shows all models, migrations clean
3. **Step 3:** Base template renders dark theme with green foreground, header/footer visible
4. **Step 4:** Signup creates user with auto-generated subname, login/logout works, onboarding completes
5. **Step 5:** Wallet connects (desktop + mobile via WalletConnect), signature verified, pubkey registered on Sepolia
6. **Step 6:** `curl` to ENS gateway returns valid signed response
7. **Step 7:** Search finds users, friend request/accept works
8. **Step 8:** Group creation + invite/accept works
9. **Step 9:** Expense encrypted, submitted, listed, decrypted
10. **Step 10:** Debt summary correct, settlement permit flow works
11. **Step 11:** Activity feed shows actions with infinite scroll
12. **Step 12:** `make dev` and `make prod` work, Docker builds clean

---

## Critical Contract Files to Reference

- `contracts/src/khaaliSplitFriends.sol` — registerPubKey, requestFriend, acceptFriend
- `contracts/src/khaaliSplitResolver.sol` — CCIP-Read signing scheme (EIP-191)
- `contracts/src/khaaliSplitSettlement.sol` — settleWithPermit parameters
- `contracts/src/khaaliSplitGroups.sol` — createGroup, inviteMember
- `contracts/src/khaaliSplitExpenses.sol` — addExpense, updateExpense
- `contracts/script/tokens.json` — Chain IDs + token addresses
- `PRD.md:842-935` — Database schema
- `PRD.md:619-660` — ECDH + encryption design
