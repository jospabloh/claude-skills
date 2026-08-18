# ACACIA Portfolio App Standard

This is the contract every app in the ACACIA portfolio must satisfy to plug into
**Mission Control** (`jospabloh/acacia-mission-control`) at the same quality bar
as the rest of the portfolio. It exists because these modules were built once,
independently, in stockflow / flowfin / puntos / rumbo / liuma / plink_fx, at real
cost — see [`docs/incidents.md`](docs/incidents.md) — and a new app should start
from the lesson, not repeat the incident.

**Who this is for:** anyone (human or Claude) creating a new app that should
become part of the portfolio, or auditing an existing one for drift.

**How to use it:**
1. Read this file top to bottom before scaffolding a new app.
2. Copy [`CHECKLIST.md`](CHECKLIST.md) into the new app's `CLAUDE.md` (or link to
   it) so every session working on that app sees the contract, not just the one
   that created it.
3. When Mission Control's own model changes (a new bodega table, a new adapter
   capability), update this doc first, then bring apps into compliance — this
   repo is the source of truth, not any single app.

This standard is stack-agnostic in principle, but today the whole portfolio is
**Base44 backend + Vite/React frontend**, deployed standalone, registered into
Mission Control's Supabase "bodega" via a per-backend adapter
(`api/_lib/adapters/{base44,supabase,external,static}` in Mission Control). Where
this doc says "Base44", read "your backend" if a future app isn't one.

---

## 0. The relationship to Mission Control, in one paragraph

Mission Control is **not** a Base44 app and does not own your data. It is a
central panel that (a) keeps a read-optimized *copy* of your app's operational
data in its own Supabase "bodega" for cross-portfolio dashboards, and (b) is
**the single owner of cross-app automation** — license lifecycle, portfolio-wide
reminders, the ACACIA marketing site's app listing. Your app's own backend stays
the source of truth for its own users/licenses/support; Mission Control reads
and writes it through an adapter, never the other way around. Concretely, this
means: **do not build a second copy of a module Mission Control already owns
centrally** (see Module 1). Every incident in `docs/incidents.md` where this was
violated cost days of silent breakage.

---

## 1. License lifecycle — owned centrally, not per-app

**Rule:** an app does **not** run its own trial/active/view_only/suspended state
machine, billing reminders, or renewal cron. That logic is
`runUnifiedLifecycleForApp` in `acacia-mission-control/api/cron/license-lifecycle.js`,
and it runs once, portfolio-wide, against Mercado Pago (the only payment
provider — **Stripe is not used anywhere** in this portfolio).

**What your app must provide instead:**
- A tenant/account entity (`Business`, `Family`, or equivalent) with a
  **`billing_status`** field taking exactly `trial | active | view_only | suspended`.
  Mission Control writes this field; your app **reads** it to gate features
  (`view_only` and `suspended` should degrade the UI, not 500 it).
- A registry row in Mission Control's `apps` table (Supabase) so the lifecycle
  cron and adapter know your app exists — see `scripts/onboard-base44.js` in
  Mission Control, `npm run onboard:base44 -- <repoPath> --dry` to preview it.
- An adapter under `acacia-mission-control/api/_lib/adapters/` matching your
  backend kind (`base44` today for every existing app) so Mission Control's
  cron can actually reach your entity.
- Manual admin actions (`confirmRenewalPayment`, `adminUpdateTenantLicense`,
  or your app's equivalent) **may** stay in-app — those aren't the automated
  cron, they're a human doing a one-off override, and Mission Control's admin UI
  calls into them via the adapter rather than duplicating them.

**What to remove, if scaffolding from an older app or migrating one in:** any
`checkAccountLifecycle`, `processMonthlyRenewal`, `checkTrialExpiration`,
`expireTrials`, `queueBillingReminders`, `sendLifecycleEmails`-as-a-cron. If your
new app needs a lifecycle email Mission Control's unified cron doesn't send yet
(check current gaps first — flowfin's CLAUDE.md notes Mercado Pago pre-charge
reminders as one open gap at time of writing), the fix is to extend the shared
cron, not to add a parallel one.

---

## 2. User & role control — two layers, don't conflate them

**Layer 1 — Mission Control operator role** (who can drive the *panel*, not your
app): Supabase Auth users mapped in `members` to `owner | admin | viewer`
(ranks 3/2/1). RLS enforces this on Mission Control's client; its `api/`
functions use the service_role key and bypass it. This is orthogonal to your
app's own users.

**Layer 2 — your app's own role model**, which must:
- Map cleanly onto a small, named set of roles (see puntos' canonical example:
  `admin` = platform/ACACIA owner, `business_admin` = tenant admin,
  `merchant` = staff/cashier, `customer` = end consumer — kept in one file,
  `src/lib/rbac.js`, as the single place the mapping is declared).
- Use the backend's **built-in** role field for anything RLS needs to key off
  (Base44's `role`), and tenant/store scoping via **custom** fields
  (`business_id`, `storeId`) set through `auth.updateMe({ role, data: {...} })`
  at onboarding — never invent a parallel "is this an admin" flag that RLS
  can't see.
- Never let the two layers merge: an `owner` in Mission Control's `members`
  table has no automatic role inside your app, and vice versa. Mission Control
  reaches your app's data through the service-role adapter, not by impersonating
  one of your app's users.

---

## 3. Granular permissions module

**Client side:** one registry file (pattern: `src/lib/permissionRegistry.js`)
listing every gated action as `"Section:action"` (e.g. `Caja Chica:add_fund`,
`Cotizaciones:edit_items`), with per-role defaults, consumed by a
`PermissionContext`/`can()` hook that hides/disables UI. This part alone is
**not sufficient** — see the next paragraph.

**Server side — mandatory, not optional:** every write path the client can hit
must independently re-check the same permission key server-side, in the
function that performs the write, in this precedence order (mirrors
`PermissionContext.can()` exactly so client and server never disagree):
1. platform-owner email or `role: admin` → always allowed;
2. else an explicit `true`/`false` override for that tenant + role in a
   `PermissionProfile`-equivalent entity wins;
3. else fall back to the registry default for that role.

Then, still server-side, check the account's `billing_status` (`view_only` /
`suspended` → reject, same gate every other write already has) *before* the
permission check would otherwise allow it.

**Why this is non-negotiable, not a nice-to-have:** stockflow shipped exactly
the client-only version first, for three entities, across two release cycles,
before closing it — an authenticated low-privilege user could open devtools and
call the backend directly, bypassing a permission their admin had explicitly
revoked. See `docs/incidents.md` for the full writeup and the pattern that
closed it (dedicated "Safe" function per write path, checked by real unit
tests against the permission-check logic in isolation — no SDK imports in that
one file, so it's testable without simulating the whole backend).

**Keep the manifest in sync automatically**, not by hand: a generator script
(`scripts/generatePermissionManifests.mjs` pattern) that reads the one registry
file and regenerates every backend copy of the canonical keys/defaults, wired
into your release script. Backends that can't share code across function
directories (Base44/Deno: each function is isolated, can't import a sibling)
mean you'll have N *generated*, identical copies — that's fine, hand-diverging
them is not.

---

## 4. Multi-tenant data isolation (RLS)

If your backend has row-level security with a templated left/right rule syntax
(Base44 does), the two halves of every rule must **both** be correct
independently, because getting either one wrong fails **silently** — no error,
the rule just stops matching real rows:

- **Entity side:** custom fields live under `data.` — `business_id` alone
  points at a field that doesn't exist, so the rule matches *every* row (RLS
  effectively off, cross-tenant leak). Use `data.business_id`.
- **User side:** custom user fields resolve as `{{user.data.business_id}}` —
  bare `{{user.business_id}}` resolves to nothing, so the rule matches *zero*
  rows (every tenant sees an empty app).
- **Service-role calls have no end-user context.** Your backend "Safe"
  functions run as service-role/admin to perform validated writes — so **every**
  tenant-scoped entity's `$or` needs an explicit
  `{"user_condition":{"role":"admin"}}` branch on **all four** operations
  (read/create/update/delete), or service-role reads return zero rows (silent
  "not found", features that read-then-write just stop working) and
  service-role writes get rejected outright.
- **Migrate additively, never by narrowing a live rule.** Add new tenant
  branches on top of whatever access already works; don't rewrite an existing
  branch believing it's equivalent. Two production outages in this portfolio
  (stockflow, 2026-06-16 and 2026-06-17) came from narrowing a live RLS rule
  one half at a time — full writeup in `docs/incidents.md`, worth reading before
  touching any live `rls` block.

**Guard this with a static checker in CI** (`validate-rls.mjs` pattern) that
parses every entity schema file and fails the build on an invalid entity- or
user-side path, and warns when a tenant-scoped op is missing the service-role
admin branch. A static checker only catches *malformed* rules, not
*over-restrictive-but-valid* ones (FlowFin's `family_id` incident: a bot pushed
a syntactically valid rule that simply forgot non-admin members could read
their own data, undetected for 9 days) — so also add a rule to the checker for
every specific shape of over-restriction you've been burned by, the way
FlowFin's checker now fails if a `family_id`/`admin_user_id` entity's `read` is
narrowed to platform-admin-only with no member fallback.

**The schema-as-code trap:** your entity definitions live in a repo file
(`base44/entities/*.jsonc` or equivalent), but the backend runs against
whatever was last **deployed**. Committing the file changes nothing at runtime.
Every field addition and every RLS fix needs an explicit deploy step
(`update_entity_schema` / your backend's equivalent) — verify against the live
schema, don't assume the diff shipped itself.

---

## 5. Health & latency reporting

Mission Control's bodega has a `health` table it reads via your app's adapter
to drive the portfolio dashboard (uptime, latency, error rate). Your app's
obligation is narrow and mechanical:
- Expose a cheap, unauthenticated-or-service-role health check endpoint (a
  `/api/health`-style route, or a Base44 function) that the adapter can poll —
  it should measure real backend latency (a round-trip to your own DB/entity
  store), not just return `200 OK` unconditionally.
- Don't build your own uptime dashboard — Mission Control's is the portfolio
  one. If you need in-app status for your own users, keep it thin and pull from
  the same signal, not a second one that can disagree.

---

## 6. Changelog & versioning

Pattern (see FlowFin): a single `appConfig.js`-equivalent holding
`APP_VERSION`, `RELEASE_DATE`, and an in-app changelog array, kept in sync by a
release script — never hand-edited per feature commit, and never regenerated
as part of the normal `build` step. A generator that stamps "last synced: today"
into a **git-tracked** file and runs on every `build` produces a spurious local
diff on every build, which then fights the next `git pull` the moment `main`
has a newer copy from someone else's real release — see FlowFin's incident.
Rule of thumb: **`build` validates, `release` generates.** If a routine build
needs to mutate a tracked file to stay "fresh," that's the bug, not a fact of
life.

Surface the changelog to users somewhere reachable from Account (Module 8),
and to Mission Control's `announcements` table if the release is portfolio-
notable (breaking change, new module, pricing change) — that's how the panel
surfaces it across the whole operator team without a manual cross-post.

---

## 7. Account & danger zone

Every app needs an Account/Settings surface, reachable by any authenticated
user, containing at minimum:
- Profile/org info edit (name, contact, branding if applicable).
- Member management scoped to the app's own role model (Module 2, layer 2) —
  invite, change role, remove — gated by the same permission module as
  everything else (Module 3), not a bespoke check.
- **Danger zone**, visually separated (confirmation step, red affordance):
  export data, and irreversible account deletion/downgrade. Deletion must
  either cascade correctly through your own entities or explicitly document
  what it does *not* touch (e.g. billing history retained for compliance) —
  don't ship a "delete account" button before deciding that.
- Current `billing_status` and plan, read-only (Module 1 owns writing it) —
  don't let this screen invite the user to self-serve a status change that
  bypasses Mercado Pago.

---

## 8. Support & improvements → Mission Control

Support tickets, feature requests ("mejoras"), and leads are **Mission
Control's tables** (`tickets`, `leads` in the bodega), not a parallel inbox per
app. Your app's obligation:
- A visible "Soporte" / "Sugerir una mejora" entry point that writes to your
  own backend first (so it's not lost if the sync to Mission Control lags),
  tagged with your app's registry id, then syncs into the bodega via your
  adapter (or Mission Control's ingest webhook, HMAC-signed —
  `INGEST_HMAC_SECRET`, server-only, never exposed with a `VITE_`/client
  prefix).
- Don't build your own ticket-status UI beyond "submitted / resolved" — triage
  and response happen from Mission Control's panel, where an operator sees
  every app's queue in one place. A per-app ticket system that diverges from
  that is exactly the parallel permission model Module 0 already warns against.

---

## 9. Presence on the ACACIA site (`acaciaco-site`)

Every portfolio app gets one page under `apps/` in `jospabloh/acaciaco-site`
(static HTML, no framework, no build step — see that repo's `CLAUDE.md`).
Minimum bar: what it does, who it's for, pricing tier, a link into the app's
own login/trial flow. Reuse `styles/base.css` tokens (`--bg-card`, `--border`,
`--text-muted`, `--radius-card`) — hand-coding colors breaks the moment
`[data-theme="dark"]` is toggled, since the site has a real dark theme, not a
cosmetic one. Comments/identifiers in English, all user-facing copy in
Spanish, matching every other page on the site.

If the app is public/freeware rather than licensed, it likely belongs under
`freeware/` instead of `apps/` — check the existing pattern before adding a
new top-level section.

---

## 10. Login page — "pro" bar

The login screen is the first thing every tenant's staff sees, and it's the
one screen every app in the portfolio should look like it came from the same
company. Concretely, "pro" means:
- Same visual language as the rest of the app (design tokens, not one-off
  colors) and as `acaciaco-site`'s own branding — a user clicking through from
  the marketing site should not land somewhere that looks like a different
  product.
- Real states: loading, wrong-credentials, account `suspended`/`view_only`
  (Module 1) explained in plain language instead of a generic auth error,
  rate-limit/lockout feedback if you have one.
- No dead ends: a link to request access / start a trial (→ the app's
  `acaciaco-site` page), and to support (Module 8) for a locked-out tenant.
- Dark-theme correct by default, like every other screen (Module 9's
  dark-theme rule applies here too — a login page is the worst place for a
  washed-out unstyled color to show up first).

---

## Onboarding checklist for a brand-new app

1. Pick the backend kind and confirm an adapter exists in Mission Control
   (`api/_lib/adapters/`) — build one if this is a new kind (not `base44`).
2. Stand up the tenant entity with `billing_status` (Module 1) from day one —
   retrofitting it later means an audit/backfill script, not a migration.
3. Declare the role model in one file (Module 2) before writing any RLS rule
   that depends on it.
4. Stand up the permission registry + server-side "Safe function" pattern
   (Module 3) for every write path from the start — this is far cheaper before
   a permission bypass has shipped than after.
5. Write RLS with the four-op `$or` shape from Module 4 from the first entity,
   run the static validator in CI from commit one.
6. Add the health check endpoint (Module 5).
7. Wire `appConfig`-style versioning + release script (Module 6).
8. Build the Account/Danger-zone screen (Module 7) and the Support entry point
   (Module 8) before first tenant onboarding, not after.
9. Add the `apps/` page on `acaciaco-site` (Module 9) and register the app in
   Mission Control's `apps` table (`npm run onboard:base44 -- <repoPath> --dry`
   to preview).
10. Build the login page to the Module 10 bar.
11. Copy `CHECKLIST.md` from this repo into the new app's `CLAUDE.md`.

See [`CHECKLIST.md`](CHECKLIST.md) for the compact, copy-pasteable version of
this list, and [`docs/incidents.md`](docs/incidents.md) for the full postmortems
this standard was distilled from.
