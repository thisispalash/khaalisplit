# khaaliSplit UI Refactor Plan

## Goal
Refactor the Django + HTMX + Tailwind v4 UI from ad-hoc inline styling with duplicated desktop/mobile apps into a unified, token-driven design system with a structured component hierarchy. Only two colors: the existing background (black) and foreground (green). Everything derived via `color-mix()`.

---

## Phase 1: Design Token System

**Rewrite** `app/static/css/tw-in.css`

All semantic colors are derived purely from mixing the two base OKLCH colors at different ratios. No red, yellow, blue, or purple — just different shades of green-on-black.

```css
@import "tailwindcss";

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

**Status color strategy:** Instead of red/yellow/blue, statuses are communicated through **contrast intensity**:
- **High emphasis** (confirmed, success, accepted): `text-emphasis` / `bg-emphasis-muted` — bright green, near foreground
- **Foreground** (errors, destructive): `text-foreground` on `bg-accent-muted` — maximum contrast draws attention
- **Muted** (pending, invited, bridging): `text-muted` / `bg-surface-raised` — mid-tone green
- **Dim** (left, inactive, disabled): `text-dim` / `bg-dim-muted` — faded green
- **Subtle** (timestamps, placeholders): `text-subtle` — almost invisible

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

---

## Phase 2: Self-Hosted Fonts + Strip Form Widget Classes

### 2a. Fonts (already downloaded to `app/static/font/`)

Files already in place:
- `NunitoSans.ttf` (variable weight, normal)
- `NunitoSansItalic.ttf` (variable weight, italic)
- `SyneMono.ttf` (regular weight)

Add `@font-face` declarations in `tw-in.css` **before** the `@theme` block (industry standard for self-hosted):

```css
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
```

Also add Google Fonts `<link>` in `base.html` as network fallback:
```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Nunito+Sans:ital,opsz,wght@0,6..12,200..1000;1,6..12,200..1000&family=Syne+Mono&display=swap" rel="stylesheet">
```

### 2b. Strip `class` attrs from Django form widgets

Since `@layer base` now styles all form elements globally, remove all `'class': '...'` from widget attrs. Keep `placeholder`, `autocomplete`, `step`, `min`.

**Files:**
- `app/api/forms/auth.py` — 5 widget `class` strings (SignupForm, LoginForm, ProfileForm)
- `app/api/forms/expenses.py` — `WIDGET_CLASSES` constant + 4 usages
- `app/api/forms/groups.py` — 1 widget `class` string

---

## Phase 3: Quanta — Stateless Primitives

Create `app/templates/quanta/`. All parameterized via `{% include 'quanta/X.html' with key=val %}`. Default size for all: `md`.

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
- `danger`: `bg-foreground text-background hover:bg-foreground/90 font-bold` (same as primary but bold — urgency via weight, not color)
- `ghost`: `text-subtle hover:text-foreground`

### `quanta/badge.html`
| Param | Values |
|-------|--------|
| `status` | `pending`, `invited`, `submitted`, `bridging`, `confirmed`, `accepted`, `failed`, `left`, `default` |
| `label` | string |
| `pulse` | `"true"` for animated |

Class mapping (all green-on-black shades):
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
Type mapping:
- `error`: `bg-accent-muted text-foreground border border-foreground font-medium`
- `success`: `bg-emphasis-muted text-emphasis border border-emphasis`
- `info`: `bg-surface-raised text-foreground border border-border`

### `quanta/skeleton.html`
Params: `variant` (`line`/`card`/`avatar`), `lines` (default 3)

### `quanta/address.html`
Params: `address`
Renders: `<span class="font-mono text-sm text-subtle">{{ address|truncatechars:14 }}</span>`

### `quanta/amount.html`
Params: `value`, `token` (default "USDC"), `size` (`sm`/`md`)
Renders: `<span class="font-mono text-sm font-medium">{{ value }} USDC</span>`

### `quanta/icon.html`
Params: `name` (`expense`, `settlement`, `friend`, `group`, `wallet`, `info`, `arrow-right`, `arrow-left`, `activity`), `size` (`sm`/`md`/`lg`)
Centralizes the 6 inline SVGs from `activity_item.html`

### `quanta/empty-state.html`
Params: `title`, `subtitle`, `actions` (safe HTML)

### `quanta/input.html`
Params: `name`, `type`, `placeholder`, `label`, `error`, `helper`, `mono`, `extra_attrs`
For manual `<input>` tags in templates (not Django form fields)

### `quanta/select.html`
Params: `name`, `label`, `options`, `error`
For manual `<select>` tags

---

## Phase 4: Photons — Stateful Composites

Create `app/templates/photons/`. These require Django template context.

### `photons/form-field.html`
Context: `field` (bound form field), `label`, `helper`
Replaces: 12 instances of the `<div><label>{{ form.X }}{% if errors %}` pattern

### `photons/form-errors.html`
Context: `errors` (form.non_field_errors)
Replaces: 4 inline error blocks

### `photons/user-pill.html`
Context: `user` object (`.subname`, `.display_name`, `.avatar_url`)
Params: `link` (`"true"`/`"false"`), `size`
Renders: avatar initial + monospace subname + optional display name

### `photons/wallet-button.html`
Context: `user.is_authenticated`
Extracted from: `components/header.html` wallet button + Hyperscript

### `photons/search-bar.html`
Params: `name`, `placeholder`, `hx_get`, `hx_target`
Renders: debounced HTMX search input

### `photons/debt-arrow.html`
Context: `from_subname`, `to_subname`, `from_address`, `to_address`, `is_payer`, `is_payee`
Uses `quanta/icon.html` + `quanta/address.html`
Payer gets `text-foreground` (emphasis = they owe), payee gets `text-emphasis`

### `photons/step-indicator.html`
Params: `current` (int), `total` (int, default 2)

---

## Phase 5: Lenses — Cards

Create `app/templates/lenses/`.

| File | Context | Replaces |
|------|---------|----------|
| `lenses/activity-card.html` | `activity` | `activity/partials/activity_item.html` |
| `lenses/friend-card.html` | `friend_user`, `status` | `friends/partials/friend_card.html` |
| `lenses/group-card.html` | `group` | `groups/partials/group_card.html` |
| `lenses/expense-card.html` | `expense` | `expenses/partials/expense_card.html` (preserves Hyperscript decryption) |
| `lenses/settlement-card.html` | `settlement` | `settlement/partials/settlement_status.html` (preserves HTMX polling) |
| `lenses/invite-card.html` | `group` (invited) | inline invite block in `groups/list.html` |

All cards use `border border-border rounded-md` base. No colored borders — distinguish via text weight and brightness.

---

## Phase 6: Prisms — Sections

Create `app/templates/prisms/`.

### `prisms/nav-header.html`
Desktop only (`hidden md:block`). Logo + nav links + wallet button + logout.
Replaces: `components/header.html`

### `prisms/bottom-nav.html`
Mobile only (`md:hidden`, `fixed bottom-0`). 4 tabs: Activity, Friends, Groups, Profile.
Requires: `active_tab` in context (via context processor).

### `prisms/footer.html`
Desktop only (`hidden md:block`). Tagline + GitHub.
Replaces: `components/footer.html`

### `prisms/activity-feed.html`
HTMX load wrapper with skeleton fallback (replaces spinner).

### `prisms/friend-list.html`
Search + pending + friends list.

### `prisms/group-members.html`
Invite form + HTMX member list.

### `prisms/group-expenses.html`
Expense form + expense list.

### `prisms/balance-summary.html`
HTMX-loaded balance/debt section.

---

## Phase 7: Unified Base Template

**Rewrite** `app/templates/base.html`:
- Merge PWA meta from `base_mobile.html`
- Add `@font-face` fallback links
- Add `font-sans` on `<body>`
- `{% include 'prisms/nav-header.html' %}` (desktop)
- `{% include 'prisms/footer.html' %}` (desktop)
- `{% include 'prisms/bottom-nav.html' %}` (mobile)
- `pb-20 md:pb-8` on `<main>` (clears fixed bottom nav)

**Delete:** `base_desktop.html`, `base_mobile.html`

---

## Phase 8: Page Templates + Backend

### 8a. Create `app/templates/pages/`

| Page | Replaces |
|------|----------|
| `pages/home.html` | `activity/feed.html` |
| `pages/signup.html` | `auth/signup.html` |
| `pages/login.html` | `auth/login.html` |
| `pages/onboarding-profile.html` | `auth/onboarding/profile.html` |
| `pages/onboarding-wallet.html` | `auth/onboarding/wallet.html` |
| `pages/friends.html` | `friends/list.html` |
| `pages/groups-list.html` | `groups/list.html` |
| `pages/group-detail.html` | `groups/detail.html` |
| `pages/group-create.html` | `groups/create.html` |
| `pages/settle.html` | `settlement/settle.html` |
| `pages/profile.html` | profile own view |
| `pages/profile-public.html` | profile public view |

### 8b. Add `active_tab` context processor

Add to existing `app/config/context_processors.py`:
```python
def active_tab(request):
    path = request.path.rstrip('/')
    if path.startswith('/friends'): return {'active_tab': 'friends'}
    if path.startswith('/groups'): return {'active_tab': 'groups'}
    if path.startswith('/profile'): return {'active_tab': 'profile'}
    return {'active_tab': 'activity'}
```

Register in `config/settings.py` `TEMPLATES[0]['OPTIONS']['context_processors']`.

### 8c. Update `app/web/views.py` template paths

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

### 8d. Update API partial template paths

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

---

## Phase 9: Cleanup

- Delete old template directories: `components/`, `partials/`, `auth/`, `activity/`, `friends/`, `groups/`, `expenses/`, `settlement/`
- Route both `''` and `'m/'` to `web.urls` in `config/urls.py`
- Remove `'m'` from `INSTALLED_APPS`
- Move manifest.json to root static
- Delete `m/` app directory

---

## Skippable if tight on time
- `quanta/icon.html` — keep SVGs inline
- `quanta/select.html` — base CSS handles it
- `quanta/empty-state.html` — keep inline
- `quanta/skeleton.html` — keep using spinner
- Merging `m/` app — both still work

---

## Files Modified (Summary)

| Action | Path |
|--------|------|
| **Rewrite** | `app/static/css/tw-in.css` |
| **Rewrite** | `app/templates/base.html` |
| **Edit** | `app/api/forms/auth.py` |
| **Edit** | `app/api/forms/expenses.py` |
| **Edit** | `app/api/forms/groups.py` |
| **Edit** | `app/config/context_processors.py` |
| **Edit** | `app/config/settings.py` |
| **Edit** | `app/web/views.py` |
| **Edit** | `app/api/views/*.py` (partial paths) |
| (exists) | `app/static/font/` (3 TTF files already present) |
| **Create** | `app/templates/quanta/` (11 files) |
| **Create** | `app/templates/photons/` (7 files) |
| **Create** | `app/templates/lenses/` (6 files) |
| **Create** | `app/templates/prisms/` (8 files) |
| **Create** | `app/templates/pages/` (12 files) |
| **Delete** | `app/templates/base_desktop.html` |
| **Delete** | `app/templates/base_mobile.html` |
| **Delete** | Old template directories (after migration) |
| **Delete** | `app/m/` (after merge) |

---

## Verification

1. `make tailwind` — verify `tw.css` builds without errors
2. `make server` — verify Django starts
3. Visit every page: verify Nunito Sans body, Syne Mono addresses, no raw colors
4. `grep -r "foreground/" app/templates/` — zero results (no opacity patterns)
5. `grep -rE "text-red|text-green|text-yellow|text-blue|text-purple" app/templates/` — zero results
6. Test on 375px viewport — nothing overflows, bottom nav visible
7. Test on 1024px+ — top nav visible, bottom nav hidden
8. All HTMX interactions: search, infinite scroll, expense add, settlement polling
9. All Hyperscript: wallet connect, sign/verify, encrypt/decrypt
10. Toast notifications render correctly for all types
