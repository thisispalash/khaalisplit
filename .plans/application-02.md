# khaaliSplit UI Refactor Plan

## Goal
Refactor the Django + HTMX + Tailwind v4 UI from ad-hoc inline styling with duplicated desktop/mobile apps into a unified, token-driven design system with a structured component hierarchy. Only two colors: the existing background (black) and foreground (green). Everything derived via `color-mix()`.

---

## Dependency Graph

```
Session 1: Foundation + Building Blocks
  tw-in.css ──► quanta/ ──► photons/
       │              │           │
       └──► form widget cleanup   │
                                  │
Session 2: Composed UI            │
  lenses/ ◄──────────────────────┘
     │
  prisms/ ◄── lenses/ + quanta/ + photons/
     │
  base.html ◄── prisms/ (nav-header, bottom-nav, footer)
     │
  pages/ ◄── base.html + prisms/ + lenses/

Session 3: Backend Wiring + Cleanup
  context_processors.py (active_tab for bottom-nav)
  web/views.py (template paths → pages/)
  api/views/*.py (partial paths → lenses/, prisms/)
  delete old templates
  merge m/ app
```

Nothing in Session 2 works without Session 1. Nothing in Session 3 works without Session 2.

---

# SESSION 1: Foundation + Building Blocks

**Goal:** Design tokens, fonts, form cleanup, all quanta, all photons. After this session, the component library exists but isn't wired into any pages yet. Existing pages still work (they use old templates).

**Commit after this session.**

## 1.1 Rewrite `tw-in.css` — Design Token System

**File:** `app/static/css/tw-in.css`

```css
@import "tailwindcss";

@font-face {
  font-family: "Nunito Sans";
  src: url("/static/font/NunitoSans.ttf") format("truetype");
  font-weight: 200 1000;
  font-style: normal;
  font-display: swap;
}
@font-face {
  font-family: "Nunito Sans";
  src: url("/static/font/NunitoSansItalic.ttf") format("truetype");
  font-weight: 200 1000;
  font-style: italic;
  font-display: swap;
}
@font-face {
  font-family: "Syne Mono";
  src: url("/static/font/SyneMono.ttf") format("truetype");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}

@theme {
  /* ── Base Colors (unchanged) ─────────────────────────────────── */
  --color-background: oklch(15.434% 0 none);
  --color-foreground: oklch(90.537% 0.1574 142.27);

  /* ── Semantic Colors (all derived via color-mix) ─────────────── */
  --color-surface:        color-mix(in oklch, var(--color-background) 95%, var(--color-foreground));
  --color-surface-raised: color-mix(in oklch, var(--color-background) 90%, var(--color-foreground));
  --color-border:         color-mix(in oklch, var(--color-background) 85%, var(--color-foreground));
  --color-border-hover:   color-mix(in oklch, var(--color-background) 75%, var(--color-foreground));
  --color-muted:          color-mix(in oklch, var(--color-background) 50%, var(--color-foreground));
  --color-subtle:         color-mix(in oklch, var(--color-background) 65%, var(--color-foreground));
  --color-accent:         var(--color-foreground);
  --color-accent-muted:   color-mix(in oklch, var(--color-background) 90%, var(--color-foreground));

  /* Status shades — different mix ratios for visual hierarchy, all green+black */
  --color-emphasis:       color-mix(in oklch, var(--color-background) 25%, var(--color-foreground));
  --color-emphasis-muted: color-mix(in oklch, var(--color-background) 92%, var(--color-foreground));
  --color-dim:            color-mix(in oklch, var(--color-background) 70%, var(--color-foreground));
  --color-dim-muted:      color-mix(in oklch, var(--color-background) 95%, var(--color-foreground));

  /* ── Typography ──────────────────────────────────────────────── */
  --font-sans: "Nunito Sans", ui-sans-serif, system-ui, sans-serif;
  --font-mono: "Syne Mono", ui-monospace, monospace;

  /* ── Spacing ─────────────────────────────────────────────────── */
  --spacing: 4px;

  /* ── Breakpoints ─────────────────────────────────────────────── */
  --breakpoint-xs: 375px;
  --breakpoint-sm: 640px;
  --breakpoint-md: 768px;
  --breakpoint-lg: 1024px;

  /* ── Border Radius ───────────────────────────────────────────── */
  --radius-sm:   calc(var(--spacing) * 1);
  --radius-md:   calc(var(--spacing) * 2);
  --radius-lg:   calc(var(--spacing) * 3);
  --radius-xl:   calc(var(--spacing) * 4);
  --radius-full: 9999px;

  /* ── Animations ──────────────────────────────────────────────── */
  --animate-fade-in:    fade-in 200ms ease-out;
  --animate-slide-up:   slide-up 300ms ease-out;
  --animate-slide-down: slide-down 300ms ease-out;
  --animate-pulse-soft: pulse-soft 2s ease-in-out infinite;
  --animate-skeleton:   skeleton 1.5s ease-in-out infinite;
}

@keyframes fade-in    { from { opacity: 0; } to { opacity: 1; } }
@keyframes slide-up   { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }
@keyframes slide-down { from { opacity: 0; transform: translateY(-8px); } to { opacity: 1; transform: translateY(0); } }
@keyframes pulse-soft { 0%, 100% { opacity: 1; } 50% { opacity: 0.6; } }
@keyframes skeleton   { 0% { background-position: -200% 0; } 100% { background-position: 200% 0; } }

@layer base {
  * { border-color: var(--color-border); }
  body { font-family: var(--font-sans); -webkit-font-smoothing: antialiased; }

  input[type="text"], input[type="password"], input[type="email"],
  input[type="number"], input[type="url"], input[type="search"],
  input[type="tel"], select, textarea {
    width: 100%;
    padding: calc(var(--spacing) * 2) calc(var(--spacing) * 3);
    background: var(--color-background);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    color: var(--color-foreground);
    font-size: 0.875rem;
  }
  input::placeholder, textarea::placeholder { color: var(--color-subtle); }
  input:focus, select:focus, textarea:focus { outline: none; border-color: var(--color-border-hover); }
}
```

**Status color strategy (contrast intensity, not hue):**
- **High emphasis** (confirmed, accepted): `text-emphasis` / `bg-emphasis-muted`
- **Foreground** (errors, destructive): `text-foreground` on `bg-accent-muted`
- **Muted** (pending, invited, bridging): `text-muted` / `bg-surface-raised`
- **Dim** (left, inactive): `text-dim` / `bg-dim-muted`
- **Subtle** (timestamps, placeholders): `text-subtle`

**Old → new mapping:**
| Old Pattern | New Token |
|---|---|
| `text-foreground/30..50` | `text-subtle` |
| `text-foreground/60..70` | `text-muted` |
| `text-foreground/80..90` | `text-foreground` |
| `bg-foreground/5` | `bg-surface` |
| `bg-foreground/10` | `bg-surface-raised` |
| `border-foreground/10..20` | `border-border` (auto via @layer) |
| `border-foreground/40` | `border-border-hover` |
| `text-red-400`, errors | `text-foreground` (max contrast = urgency) |
| `bg-red-900/*`, error bg | `bg-accent-muted` |
| `text-green-400`, success | `text-emphasis` |
| `bg-green-*`, success bg | `bg-emphasis-muted` |
| `text-yellow-400`, pending | `text-muted` |
| `bg-yellow-*`, pending bg | `bg-surface-raised` |
| `text-blue-400`, info | `text-muted` |
| `text-purple-400`, bridging | `text-muted` + `animate-pulse-soft` |

## 1.2 Add Google Fonts fallback to `base.html`

Add inside `<head>` before the Tailwind CSS `<link>`:
```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Nunito+Sans:ital,opsz,wght@0,6..12,200..1000;1,6..12,200..1000&family=Syne+Mono&display=swap" rel="stylesheet">
```

## 1.3 Strip `class` attrs from Django form widgets

Remove all `'class': '...'` from widget attrs. The `@layer base` CSS handles styling globally now. Keep `placeholder`, `autocomplete`, `step`, `min`.

**Files:**
- `app/api/forms/auth.py` — 5 widget `class` strings (SignupForm, LoginForm, ProfileForm)
- `app/api/forms/expenses.py` — `WIDGET_CLASSES` constant + 4 usages
- `app/api/forms/groups.py` — 1 widget `class` string

## 1.4 Create Quanta (Stateless Primitives)

Create `app/templates/quanta/` — 11 files. All parameterized via `{% include 'quanta/X.html' with key=val %}`. Default size: `md`.

### `quanta/button.html`
| Param | Values | Default |
|-------|--------|---------|
| `variant` | `primary`, `secondary`, `danger`, `ghost` | `primary` |
| `size` | `sm`, `md`, `lg` | `md` |
| `label` | string | required |
| `type` | `submit`, `button` | `button` |
| `full_width` | `"true"` / omit | omit |
| `href` | URL (renders `<a>`) | omit |
| `extra_classes` | string | omit |
| `extra_attrs` | raw HTML for hx-*, _= | omit |

Variant classes:
- `primary`: `bg-foreground text-background hover:bg-foreground/90`
- `secondary`: `border border-border text-muted hover:text-foreground hover:border-border-hover`
- `danger`: `bg-foreground text-background hover:bg-foreground/90 font-bold`
- `ghost`: `text-subtle hover:text-foreground`

### `quanta/badge.html`
| Param | Values |
|-------|--------|
| `status` | `pending`, `invited`, `submitted`, `bridging`, `confirmed`, `accepted`, `failed`, `left`, `default` |
| `label` | string |
| `pulse` | `"true"` for animated |

Class mapping:
- `pending`/`invited`/`submitted`: `text-muted bg-surface-raised`
- `bridging`: `text-muted bg-surface-raised animate-pulse-soft`
- `confirmed`/`accepted`: `text-emphasis bg-emphasis-muted`
- `failed`: `text-foreground bg-accent-muted font-medium`
- `left`/`default`: `text-dim bg-dim-muted`

### `quanta/spinner.html`
Params: `message` (default "Loading..."), `size` (`sm`/`md`)
Replaces: `partials/loading.html`

### `quanta/toast.html`
Params: `message`, `type` (`success`/`error`/`info`), `toast_id`
Keeps: `hx-swap-oob` pattern + Hyperscript auto-dismiss
- `error`: `bg-accent-muted text-foreground border border-foreground font-medium`
- `success`: `bg-emphasis-muted text-emphasis border border-emphasis`
- `info`: `bg-surface-raised text-foreground border border-border`

### `quanta/skeleton.html`
Params: `variant` (`line`/`card`/`avatar`), `lines` (default 3)

### `quanta/address.html`
Params: `address`

### `quanta/amount.html`
Params: `value`, `token` (default "USDC"), `size` (`sm`/`md`)

### `quanta/icon.html`
Params: `name` (`expense`, `settlement`, `friend`, `group`, `wallet`, `info`, `arrow-right`, `arrow-left`, `activity`), `size` (`sm`/`md`/`lg`)

### `quanta/empty-state.html`
Params: `title`, `subtitle`, `actions` (safe HTML)

### `quanta/input.html`
Params: `name`, `type`, `placeholder`, `label`, `error`, `helper`, `mono`, `extra_attrs`

### `quanta/select.html`
Params: `name`, `label`, `options`, `error`

## 1.5 Create Photons (Stateful Composites)

Create `app/templates/photons/` — 7 files.

### `photons/form-field.html`
Context: `field` (bound form field), `label`, `helper`
Replaces: 12 instances of the label+field+error pattern

### `photons/form-errors.html`
Context: `errors` (form.non_field_errors)
Replaces: 4 inline error blocks

### `photons/user-pill.html`
Context: `user` object (`.subname`, `.display_name`, `.avatar_url`)
Params: `link` (`"true"`/`"false"`), `size`

### `photons/wallet-button.html`
Context: `user.is_authenticated`
Extracted from: `components/header.html` wallet button + Hyperscript

### `photons/search-bar.html`
Params: `name`, `placeholder`, `hx_get`, `hx_target`

### `photons/debt-arrow.html`
Context: `from_subname`, `to_subname`, `from_address`, `to_address`, `is_payer`, `is_payee`

### `photons/step-indicator.html`
Params: `current` (int), `total` (int, default 2)

## 1.6 Verification (Session 1)

1. `make tailwind` — tw.css builds without errors
2. `make server` — Django starts (existing templates still work since we haven't changed template paths)
3. Verify fonts render on existing pages (Nunito Sans body, Syne Mono where `font-mono` used)
4. Verify form inputs styled correctly (no widget classes, base CSS applies)
5. Confirm new template dirs exist: `quanta/`, `photons/`

---

# SESSION 2: Composed UI — Lenses, Prisms, Base, Pages

**Depends on:** Session 1 complete (quanta/ and photons/ must exist).

**Goal:** Build the full composed UI. Lenses use quanta+photons. Prisms use lenses+quanta+photons. The unified base template uses prisms. Pages use everything. After this session, the new template tree is complete but not yet wired to Django views.

**Commit after this session.**

## 2.1 Create Lenses (Cards)

Create `app/templates/lenses/` — 6 files.

| File | Context | Replaces | Composes |
|------|---------|----------|----------|
| `lenses/activity-card.html` | `activity` | `activity/partials/activity_item.html` | `quanta/icon.html`, `quanta/address.html` |
| `lenses/friend-card.html` | `friend_user`, `status` | `friends/partials/friend_card.html` | `photons/user-pill.html`, `quanta/badge.html`, `quanta/button.html` |
| `lenses/group-card.html` | `group` | `groups/partials/group_card.html` | — |
| `lenses/expense-card.html` | `expense` | `expenses/partials/expense_card.html` | `quanta/badge.html`, `quanta/amount.html` (preserves Hyperscript decryption) |
| `lenses/settlement-card.html` | `settlement` | `settlement/partials/settlement_status.html` | `quanta/badge.html`, `quanta/address.html`, `quanta/amount.html` (preserves HTMX polling) |
| `lenses/invite-card.html` | `group` (invited) | inline invite block in `groups/list.html` | `quanta/button.html` |

All cards: `border border-border rounded-md` base. No colored borders.

### Implementation Notes (2.1)

1. **`quanta/button.html` not used for HTMX-interactive buttons.** Django's `|add:` filter can't reliably build multi-part `hx-*` attribute strings for `extra_attrs`. Buttons with HTMX attributes (`hx-post`, `hx-target`, `hx-swap`, `hx-confirm`) are written as inline `<button>` elements using the same design token classes as the button component. This follows locality of behavior — the HTMX attributes stay visible alongside the element they control.

2. **`settlement-card.html` uses inline `truncatechars:18`** for the tx hash display instead of `quanta/address.html` (which truncates to 14). The old template showed 18 chars for tx hashes, and `address.html` was designed for Ethereum addresses.

3. **`expense-card.html` uses `quanta/badge.html` with `status='default'`** for the category display (replacing the old `bg-foreground/5` inline badge).

## 2.2 Create Prisms (Sections)

Create `app/templates/prisms/` — 8 files.

### `prisms/nav-header.html`
Desktop only (`hidden md:block`). Logo + nav links + wallet button + logout.
**Composes:** `photons/wallet-button.html`
Replaces: `components/header.html`

### `prisms/bottom-nav.html`
Mobile only (`md:hidden`, `fixed bottom-0`). 4 tabs: Activity, Friends, Groups, Profile.
**Composes:** `quanta/icon.html`
**Requires:** `active_tab` in context (wired in Session 3).

### `prisms/footer.html`
Desktop only (`hidden md:block`). Tagline + GitHub.
Replaces: `components/footer.html`

### `prisms/activity-feed.html`
HTMX load wrapper with spinner fallback.
**Composes:** `quanta/spinner.html` (skeleton was skipped in Session 1)

### `prisms/friend-list.html`
Search + pending + friends.
**Composes:** `photons/search-bar.html`, `lenses/friend-card.html`

### `prisms/group-members.html`
Invite form + HTMX member list.
**Composes:** `photons/user-pill.html`, `quanta/badge.html`

### `prisms/group-expenses.html`
HTMX-loaded expense list (the expense form + encryption Hyperscript lives in the API partial, loaded inline).
**Composes:** `quanta/spinner.html`

### `prisms/balance-summary.html`
HTMX-loaded balance/debt section. The pay button Hyperscript (`settleWithPermit`) and amount display live in the API-returned debt summary partial, not in this prism.
**Composes:** `quanta/spinner.html`

### Implementation Notes (2.2)

1. **Prisms that wrap HTMX-loaded content are thin.** `activity-feed.html`, `group-expenses.html`, and `balance-summary.html` are mostly HTMX load containers + spinner. The actual content (expense form, debt cards, activity items) is returned by the API and lives in the old partials — those partials get updated to use lenses/photons in Session 3.

2. **`group-members.html` has the invite form inline** (not extracted to a separate component) since it's tightly coupled to the `#member-list` HTMX target. Locality of behavior.

3. **`bottom-nav.html` only renders for authenticated users** (`{% if user.is_authenticated %}`). `active_tab` context variable will be wired via context processor in Session 3.

## 2.3 Rewrite Unified Base Template

**File:** `app/templates/base.html`

Changes:
- Merge PWA meta from `base_mobile.html`
- Add Google Fonts `<link>` fallback
- Add `font-sans` class on `<body>`
- `{% include 'prisms/nav-header.html' %}` (desktop)
- `{% include 'prisms/footer.html' %}` (desktop)
- `{% include 'prisms/bottom-nav.html' %}` (mobile)
- `pb-20 md:pb-8` on `<main>` (clears fixed bottom nav)

**Delete:** `base_desktop.html`, `base_mobile.html`

## 2.4 Create Page Templates

Create `app/templates/pages/` — 12 files. Each extends `base.html` and composes from prisms/lenses/photons/quanta.

| Page | Replaces | Key Compositions |
|------|----------|-----------------|
| `pages/home.html` | `activity/feed.html` | `prisms/activity-feed.html` |
| `pages/signup.html` | `auth/signup.html` | `photons/form-field.html`, `photons/form-errors.html`, `quanta/button.html` |
| `pages/login.html` | `auth/login.html` | same |
| `pages/onboarding-profile.html` | `auth/onboarding/profile.html` | `photons/step-indicator.html`, `photons/form-field.html` |
| `pages/onboarding-wallet.html` | `auth/onboarding/wallet.html` | `photons/step-indicator.html`, `quanta/button.html` (preserves Hyperscript) |
| `pages/friends.html` | `friends/list.html` | `prisms/friend-list.html` |
| `pages/groups-list.html` | `groups/list.html` | `lenses/invite-card.html`, `lenses/group-card.html` |
| `pages/group-detail.html` | `groups/detail.html` | `prisms/group-members.html`, `prisms/balance-summary.html`, `prisms/group-expenses.html` |
| `pages/group-create.html` | `groups/create.html` | `photons/form-field.html`, `quanta/button.html` |
| `pages/settle.html` | `settlement/settle.html` | `photons/debt-arrow.html`, `lenses/settlement-card.html` |
| `pages/profile.html` | profile own + public view | `photons/form-field.html`, `quanta/address.html`, `quanta/badge.html` |

## 2.5 Verification (Session 2)

1. `make tailwind` — builds without errors (new template classes get picked up)
2. Visually inspect each page template file — verify no raw colors (`text-red-*`, `bg-yellow-*`, `foreground/XX`) remain
3. At this point Django still serves old templates (views haven't been updated). That's fine. The new templates exist side-by-side.

### Implementation Notes (2.4)

1. **`profile.html` and `profile-public.html` merged** into a single `pages/profile.html`. Uses `is_own_profile` context variable to conditionally show the edit form (own profile) or a read-only view (public). The view in Session 3 needs to set `profile_user` and `is_own_profile` in context.

2. **11 pages instead of 12** because of the profile merge.

3. **`onboarding-wallet.html` preserves the full Hyperscript flow** — connect wallet → show sign section → `signMessage()` → fetch `/api/auth/address/verify/` → redirect. The `#sign-error` element uses `text-foreground` (not `text-red-400`) since max contrast = urgency in the token system.

4. **`group-detail.html` uses inline `<a>` and `<button>`** instead of `quanta/button.html` for the "Settle Up" link and "Leave" button because both need dynamic `href`/`hx-post` URLs with `{{ group.group_id }}`. Same `|add:` filter limitation as lenses.

5. **Session 3 context requirements** surfaced by new pages:
   - `pages/profile.html` needs `profile_user`, `is_own_profile`, `form` (when own)
   - `pages/groups-list.html` needs `invited_groups`, `groups`
   - `prisms/bottom-nav.html` needs `active_tab` via context processor

---

# SESSION 3: Backend Wiring + Cleanup

**Depends on:** Session 2 complete (pages/, prisms/, lenses/ must exist).

**Goal:** Wire Django views to the new templates, add context processor for bottom-nav, update API partial paths, delete old templates, merge `m/` app. After this session, the app runs fully on the new template system.

**Commit after this session.**

## 3.1 Add `active_tab` Context Processor

**File:** `app/config/context_processors.py` (add to existing)

```python
def active_tab(request):
    path = request.path.rstrip('/')
    if path.startswith('/friends'): return {'active_tab': 'friends'}
    if path.startswith('/groups'): return {'active_tab': 'groups'}
    if path.startswith('/profile'): return {'active_tab': 'profile'}
    return {'active_tab': 'activity'}
```

**File:** `app/config/settings.py` — register in `TEMPLATES[0]['OPTIONS']['context_processors']`

## 3.2 Update `web/views.py` Template Paths

| View | Old | New |
|------|-----|-----|
| `home` (auth'd) | `activity/feed.html` | `pages/home.html` |
| `home` (anon) | `auth/signup.html` | `pages/signup.html` |
| `friends_list` | `friends/list.html` | `pages/friends.html` |
| `groups_list` | `groups/list.html` | `pages/groups-list.html` |
| `group_detail` | `groups/detail.html` | `pages/group-detail.html` |
| `group_create` | `groups/create.html` | `pages/group-create.html` |
| `settle` | `settlement/settle.html` | `pages/settle.html` |
| `profile` | `auth/onboarding/profile.html` | `pages/profile.html` |
| `profile_public` | `auth/onboarding/profile.html` | `pages/profile-public.html` |

## 3.3 Update API Partial Template Paths

| Old Partial | New |
|-------------|-----|
| `activity/partials/activity_list.html` | thin wrapper looping `lenses/activity-card.html` |
| `friends/partials/search_results.html` | thin wrapper looping `lenses/friend-card.html` |
| `friends/partials/pending_requests.html` | thin wrapper looping `lenses/friend-card.html` |
| `groups/partials/member_list.html` | wrapper using `photons/user-pill.html` + `quanta/badge.html` |
| `groups/partials/balance_summary.html` | `prisms/balance-summary.html` |
| `expenses/partials/expense_list.html` | `prisms/group-expenses.html` |
| `expenses/partials/expense_card.html` | `lenses/expense-card.html` |
| `settlement/partials/debt_summary.html` | wrapper using `photons/debt-arrow.html` |
| `settlement/partials/settlement_status.html` | `lenses/settlement-card.html` |
| `partials/toast.html` | `quanta/toast.html` |
| `partials/loading.html` | `quanta/spinner.html` |

Note: some "thin wrappers" are new files that live alongside the lenses. These contain just a `{% for %}` loop + the infinite scroll sentinel (for activity) or conditional display logic (for pending requests). They can live in `prisms/` or as standalone partials in `lenses/`.

## 3.4 Delete Old Template Directories

After confirming all views point to new templates:
- `app/templates/components/`
- `app/templates/partials/`
- `app/templates/auth/`
- `app/templates/activity/`
- `app/templates/friends/`
- `app/templates/groups/`
- `app/templates/expenses/`
- `app/templates/settlement/`

## 3.5 Merge `m/` App (Optional)

- Route both `''` and `'m/'` to `web.urls` in `config/urls.py`
- Add redirect from `/m/*` → `/*` for backward compat
- Remove `'m'` from `INSTALLED_APPS`
- Move `m/manifest.json` to root static
- Delete `app/m/` directory

## 3.6 Verification (Session 3 — Full)

1. `make tailwind` — builds
2. `make server` — starts
3. Visit every page: Nunito Sans body, Syne Mono addresses, no raw colors
4. `grep -r "foreground/" app/templates/` — zero results (except `hover:bg-foreground/90` on primary buttons, by design)
5. `grep -rE "text-red|text-green|text-yellow|text-blue|text-purple" app/templates/` — zero results
6. 375px viewport — nothing overflows, bottom nav visible, active tab highlighted
7. 1024px+ — top nav visible, bottom nav hidden
8. HTMX interactions: search, infinite scroll, expense add, settlement polling
9. Hyperscript: wallet connect, sign/verify, encrypt/decrypt
10. Toast notifications for all types

### Implementation Notes (3)

1. **`active_tab` also maps `/u/` paths to `profile` tab** since `photons/user-pill.html` links to `/u/<subname>/`.

2. **`profile_public` view reworked.** Now does `User.objects.get(subname=subname)`, raises `Http404` if not found, and detects own-profile (redirects to editable form with `is_own_profile=True`). Both `profile()` and `profile_public()` render `pages/profile.html`.

3. **Added `/u/<str:subname>/` URL route** in `web/urls.py` pointing to `profile_public` view. This is needed because `photons/user-pill.html` links to `/u/{{ user.subname }}/` (short URL pattern). The existing `/profile/<str:subname>/` route remains.

4. **API partial wrappers live in `partials/`** — not in `prisms/` or `lenses/`. These are thin HTMX fragments returned by API views. The hierarchy:
   - `partials/activity_list.html` — loops `lenses/activity-card.html` + infinite scroll sentinel
   - `partials/search_results.html` — friend search results (inline, not using `lenses/friend-card.html` because search needs "Add Friend" action, not friend status display)
   - `partials/pending_requests.html` — pending friend requests with accept/decline buttons
   - `partials/member_list.html` — group members using `photons/user-pill.html` + `quanta/badge.html`
   - `partials/expense_list.html` — includes `partials/expense_form.html` + loops `lenses/expense-card.html`
   - `partials/expense_form.html` — uses `photons/form-field.html`, preserves Hyperscript encryption
   - `partials/debt_summary.html` — uses `photons/debt-arrow.html`, preserves Hyperscript `settleWithPermit`

5. **Direct lens/prism swaps (no wrapper needed):**
   - `friends.send_request` / `friends.accept` → `lenses/friend-card.html`
   - `groups.accept_invite` → `lenses/group-card.html`
   - `expenses.update` → `lenses/expense-card.html`
   - `settlement.status` → `lenses/settlement-card.html`
   - `groups.balances` → `prisms/balance-summary.html`

6. **`expenses.add` (POST success) returns `partials/expense_list.html` without `form`** in context, so the form is omitted from the response (only the card list refreshes). The `expense_list` GET includes `form=AddExpenseForm()`.

7. **`settlement/partials/settle_form.html` dropped.** The manual settlement form was not referenced by any new template or view. Can be re-added later if needed.

8. **Section 3.4 also deleted `partials/loading.html` and `partials/toast.html`** — the old generic partials replaced by `quanta/spinner.html` and `quanta/toast.html`. The `partials/` directory now only contains API wrapper fragments.

9. **Section 3.5 (merge m/ app) skipped** — keeping mobile app separate for now.

10. **All auth views in `api/views/auth.py` updated** — signup, login, onboarding profile, onboarding wallet, and verify_signature HTMX response all point to `pages/` templates. The `groups.create` POST error path also updated.

---

## Skippable if tight on time
- `quanta/icon.html` — keep SVGs inline
- `quanta/select.html` — base CSS handles it
- `quanta/empty-state.html` — keep inline
- `quanta/skeleton.html` — keep using spinner
- Merging `m/` app — both still work

---

## Files Modified (Full Summary)

| Action | Path | Session |
|--------|------|---------|
| **Rewrite** | `app/static/css/tw-in.css` | 1 |
| **Edit** | `app/templates/base.html` (add font links) | 1 |
| **Edit** | `app/api/forms/auth.py` | 1 |
| **Edit** | `app/api/forms/expenses.py` | 1 |
| **Edit** | `app/api/forms/groups.py` | 1 |
| **Create** | `app/templates/quanta/` (11 files) | 1 |
| **Create** | `app/templates/photons/` (7 files) | 1 |
| **Create** | `app/templates/lenses/` (6 files) | 2 |
| **Create** | `app/templates/prisms/` (8 files) | 2 |
| **Rewrite** | `app/templates/base.html` (unified) | 2 |
| **Delete** | `app/templates/base_desktop.html` | 2 |
| **Delete** | `app/templates/base_mobile.html` | 2 |
| **Create** | `app/templates/pages/` (11 files) | 2 |
| **Edit** | `app/config/context_processors.py` | 3 |
| **Edit** | `app/config/settings.py` | 3 |
| **Edit** | `app/web/views.py` | 3 |
| **Edit** | `app/web/urls.py` (add `/u/` route) | 3 |
| **Edit** | `app/api/views/auth.py` | 3 |
| **Edit** | `app/api/views/activity.py` | 3 |
| **Edit** | `app/api/views/friends.py` | 3 |
| **Edit** | `app/api/views/groups.py` | 3 |
| **Edit** | `app/api/views/expenses.py` | 3 |
| **Edit** | `app/api/views/settlement.py` | 3 |
| **Create** | `app/templates/partials/` (7 API wrapper files) | 3 |
| **Delete** | `app/templates/components/` | 3 |
| **Delete** | `app/templates/auth/` | 3 |
| **Delete** | `app/templates/activity/` | 3 |
| **Delete** | `app/templates/friends/` | 3 |
| **Delete** | `app/templates/groups/` | 3 |
| **Delete** | `app/templates/expenses/` | 3 |
| **Delete** | `app/templates/settlement/` | 3 |
| **Delete** | `app/templates/partials/loading.html` | 3 |
| **Delete** | `app/templates/partials/toast.html` | 3 |
| (exists) | `app/static/font/` (3 TTF files) | — |
