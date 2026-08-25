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

**The registry needs an admin-facing screen, not just a registry file.** A
`permissionRegistry.js` that only ever gets *read* by `can()` hooks is a
developer-only artifact — the tenant's own admin has no way to see or change
what a role can do without filing a support ticket. Ship a "Permisos" page
(pattern: FlowFin's `src/pages/PermissionAdmin.jsx`) gated to the tenant admin
(and platform-owner) that renders the **same registry** as a matrix — one row
per module/section, one column per action (ver/crear/modificar/eliminar,
whatever the app's `PERMISSION_COLUMNS` are) — with a tri-state group checkbox
per module (on/off/mixed across its sections) plus per-section overrides, an
explicit edit/read-only toggle so browsing the matrix can't fat-finger a
change, and each toggle persisted immediately to the same per-tenant
`RolePermission`-equivalent entity the server-side re-check already reads —
never a second config surface the backend doesn't consult. This is what turns
Module 3 from "the developer encoded a default" into "the admin approved
what their own team can see and do," and it is the natural place to surface
*everything the app manages and shows*, module by module, rather than a
tenant admin discovering a section exists only when a member reports they
can't see it.

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

**The danger zone is two different scopes, and an app that only ships one has
only half of it.** "Delete my account" (leave the tenant, drop *my own*
membership) is not the same operation as "delete the tenant" (the whole
family/business/organization, every other member's access with it), and a
member-scoped delete button is not a substitute for a tenant-scoped one —
FlowFin shipped exactly the first and not the second: `AccountSettings.jsx`'s
danger zone removes the caller's own `FamilyMembership` and disconnects them,
but there is no path anywhere in the app for a tenant admin to delete the
*tenant itself*, hand it to someone else, or promote a member to admin
without going through ACACIA. A tenant admin needs all three, gated to
`role: admin`-of-that-tenant (never a platform-wide check) and each behind
its own confirmation step:
- **Delete tenant.** Irreversible, same cascade-or-document rule as account
  deletion above, but for every entity the *tenant* owns — every member loses
  access, not just the admin. This is the operation Mission Control's own
  danger zone (`api/_lib/control/license-record.js`'s `purge`) deliberately
  does **not** perform on your app's data — see Module 0: your app is the
  source of truth, so only your app can do a real delete, and only your app's
  own admin should be able to trigger it.
- **Delegate the tenant** (transfer ownership/admin to another existing
  member). Re-derive the target from the tenant's own membership list
  server-side — never trust a user id the client sent — and require the
  target to already be an approved member, the same "an id in the request
  body is not proof of anything" discipline Module 14 demands of every other
  cross-tenant-shaped write. The outgoing admin either keeps a regular-member
  role or is removed, an explicit choice the confirmation step should state,
  not an implicit side effect.
- **Promote a member to tenant admin** (without necessarily transferring
  sole ownership — an app whose role model supports more than one admin per
  tenant, Module 2). Same server-side re-derivation as delegation: the actor
  must already be that tenant's admin, and the target must already be an
  approved member of the *same* tenant, checked against the stored
  membership record, not the request.

None of this is Mission Control's job — Module 1 already draws that line for
billing, and it holds here too: a *tenant's own* leadership changes belong to
the tenant's own admin, in the tenant's own app, the same way a delete does.

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
- **Tell Mission Control the moment the ticket is written — the daily sync is
  a backstop, not the delivery.** `api/cron/sync` runs once, at 08:00 UTC. An
  app that relies on it alone leaves a customer who wrote at 09:00 waiting
  twenty-three hours before support even knows. Real-time notification is part
  of this module, not an optimization on top of it.

There are two sanctioned ways to do it, and which one an app uses is decided by
where its ticket gets created, not by preference:

| the ticket is created… | do this | who |
|---|---|---|
| by a backend function already | sign and POST the record from that function to `/api/ingest/ticket` | rumbo (inline in `submitTicket`), puntos / liuma / radar (a `notifyTicketCreated` function) |
| by the browser | `POST /api/ingest/ticket-pull` with `{app, ticketId}` | cateqhub, flowfin, stockflow, ctrlhq, kitchops |

**Prefer `ticket-pull` unless a signer already exists.** It carries no secret,
costs no function slot (Base44 caps an app at 50 and two apps are near it), and
its body is not trusted: Mission Control takes only the id and reads the real
record back over the `acaciaControl` bridge, so a forged body cannot inject a
ticket and an unknown id just no-ops. Either way the call is fire-and-forget —
`.catch(() => {})` — because a notification that fails must never cost the
customer their ticket.

Cover **every** place a ticket is born, not just the support page: the
account-deletion request in Module 7's danger zone is a ticket too, and it is
the one nobody remembers to wire.

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

## 11. Deploy discipline & the endpoint budget

Base44 caps an app at **50 backend functions**. That cap is not a soft limit:
crossing it makes `functions deploy` fail *partway*, and because the CLI's
prune phase only runs after a clean deploy, a half-applied deploy leaves stale
remote functions occupying the slots needed to fix it. See
[`docs/incidents.md`](docs/incidents.md), 2026-08-21.

Every app repo must carry these five, and they are cheap enough that there is
no reason not to:

- **`base44.app.json`** — `{ name, appId, maxFunctions }`. The app id lives
  in the repo, next to the code it deploys.
- **`npm run deploy`** (`scripts/base44-deploy.mjs`) — the only sanctioned
  deploy path. It reads the id from `base44.app.json` and **refuses an
  `--app-id` argument**, so the source directory and the target app cannot
  disagree. Hand-running `npx base44 functions deploy --app-id <id>` is what
  pushed one app's backend into four others.
- **`npm run deploy:site`** — the frontend. **Merging to `main` deploys
  nothing**, neither functions nor site; that was believed otherwise for
  months, and it kept a merged, CI-green FlowFin fix out of production for five
  days while the user who reported the bug kept hitting it. Separate from
  `deploy` so a UI change doesn't re-walk 45 functions, and so the step that
  went missing is the one you run on purpose.
- **`npm run deploy:entities`** — separate on purpose, because `entities push`
  **deletes every remote entity absent locally**. It prints the app name and
  the full entity list, then requires the operator to type the app's name.
- **`npm run validate:functions`**, wired into `npm run lint` — fails above
  `maxFunctions` (default **40**). The 10-endpoint margin under Base44's 50 is
  the point: it means adding a function is never an emergency.

**Verify a deploy by content, never by a hash or a green merge.** The app's
checkpoint reports a `git_commit_hash` equal to `main`'s HEAD *even when the
tree being served is behind* — Base44 mirrors the commits into its metadata,
but what gets built and served is the app's own working tree. Read the
deployed file and grep for an identifier that exists only in the change:

```bash
wc -l src/<archivo-que-cambiaste>
grep -c "<identificador que SOLO existe en el fix>" src/<archivo>
```

A user-reported bug is closed when the thing the user touches behaves
differently — for this portfolio that is always at least one deploy past the
merge.

**Counting rule:** a function is any directory containing `entry.ts`/`entry.js`,
at any depth — its name is its full path, so nesting does not reduce the count.
The only way down is a **router**: one endpoint that dispatches on an `action`
field to handler modules under `handlers/`, which are bundled with the router
and cost no slots. FlowFin went 94 → 48 this way; StockFlow's 21 routers absorb
99 handlers. Both repos document the mapping in
`docs/BACKEND_FUNCTION_LIMIT_REORG.md`.

**Before consolidating anything, run `npm run functions:audit`.** A function
with no caller in the repo is usually *not* dead — the caller is outside the
repo, where grep cannot see it: a Base44 entity hook, a dashboard cron, an
agent `tool_config`, a webhook URL registered with a payment provider.
Renaming or deleting one breaks it silently, with no compile error and no
failing test. The audit prints what the repo can prove and flags the rest as
**REVISAR EN PANEL**; confirm those against `npx base44 functions list` (which
annotates `(N automation)`) and the Automations panel before touching them.
Treat any existing "deliberately left untouched" list as a lead, not a fact —
both apps' lists had gone stale.

---

## 12. Theme control — light, dark, and the device

Every app offers all three, from the same control, in the same place.

**Three modes, not two.** What gets stored is the operator's *preference* —
`'light' | 'dark' | 'system'` — never the resolved colour. `system` keeps
resolving against `prefers-color-scheme` for as long as it is selected, so a
phone that turns dark at sunset turns the app dark with it. A switcher that
stored the resolved colour would silently throw away the choice.

**One control, in a corner.** A small circle pinned to a screen corner showing
the mode in force; pressing it grows the circle sideways into a three-slot
track whose indicator slides to the chosen slot. Three states get three
physical positions, which is the thing a sun/moon toggle structurally cannot do
once "follow the device" is an option. The canonical implementation lives in
[`shared/theme/`](shared/theme/) — copy it, do not re-implement it, and do not
edit an app's copy in place.

**It is the only theme control in the app.** Sidebar toggles, header buttons and
command-palette entries that write the theme come out when the switcher goes in:
two writers of the theme class fight over it, and the older ones can only ever
reach two of the three modes. A command palette may keep *three* commands (one
per mode) — that is a keyboard shortcut to the same state, not a second writer
of a different model.

**No flash of the wrong theme.** `index.html` carries a pre-mount script that
resolves and applies the theme before the app mounts, using the same storage key
and the same three values as the provider. Both sides carry a comment pointing
at the other; they are kept in sync by hand.

**The dark palette has to actually be finished.** Wiring a switcher onto an app
whose screens are half hardcoded light colours ships a broken mode, which is
worse than not offering one. Before turning the control on: every surface comes
from a semantic token, and the colours that legitimately cannot (status chips —
red / amber / emerald washes) carry an explicit dark counterpart.

**It may not cover anything.** A control pinned above everything, in a corner,
on every screen is exactly the shape of thing that ends up sitting on a mobile
tab bar, a floating action button or a sticky *Guardar* — and when it does, the
app has lost a function at the one width nobody opened. Each app places the
control with `--theme-switcher-bottom` / `--theme-switcher-right` in its own
stylesheet and lifts it above its own bottom chrome per breakpoint:

```css
:root { --theme-switcher-bottom: 1rem; --theme-switcher-right: 1rem; }
@media (max-width: 767px) { :root { --theme-switcher-bottom: 5.5rem; } }
```

Placement is per-app because the chrome is per-app — a bottom tab bar on mobile
only, a rail on desktop, a FAB already holding one corner (Plink FX puts the
switcher bottom-**left** for exactly that reason). What is not per-app is the
obligation: **phone, tablet and desktop, collapsed and expanded**. Module 13's
suite checks it at all three widths in both states, so this is enforced rather
than promised.

Two directions both count as failure, and the check names them separately:
something painted over the switcher (the operator cannot change the theme), and
the switcher answering for a control underneath it (the operator cannot use the
app). Beware a parent that opens a stacking context — `isolation: isolate` or a
`transform` on an app shell confines the switcher's `z-index` inside it, so a
high number is not by itself proof of anything.

**What the automated half does not reach, and what you owe because of it.** The
suite holds no credentials on purpose, so it only visits the routes an anonymous
visitor can — the home page, plus whatever the app lists in `config.routes`.
List the public screens whose chrome differs (register, password reset, a 404);
that is cheap and it is where a second corner control usually turns up. But a
sticky *Guardar* on an authenticated edit screen is **not** covered, and no
amount of green here says otherwise. **Look at the corner by hand on the first
deploy of any app whose authenticated chrome changed**, and write what you found
in its `CLAUDE.md` — including that you could not check it, if you could not.

The check is deliberately not a rectangle-intersection test: a control clipped
at one corner by a rounded bubble is still usable, and a suite that fails on
that is a suite people learn to ignore. The switcher itself is probed at five
points rather than one, because a bar across its lower half leaves the centre
pixel free and a one-point check calls that fine. Each other control is judged
by its own midpoint — and that is a result, not a shortcut: for two axis-aligned
rectangles, an overlap covering half a control's area always contains that
control's centre, so an area threshold would be unreachable code pretending to
add coverage. Anything small and separately clickable in the overlapped corner
is its own element and gets its own midpoint.

**An app may decline dark or light**, but only on a stated design ground, in its
own `CLAUDE.md`, naming the constraint — brand assets that only sit on one
ground, a physical use context. An app that declines ships no switcher at all
rather than a control with one working option, and Module 13's suite then
asserts the absence instead of the behaviour.

Treat a decline as a dated estimate of the work, not a permanent exemption.
`kitchops` declined on exactly those grounds — photographic brand assets, copper
that reads as mud on white, a phone in a dark kitchen — and then did it anyway a
day later, which is worth reading before writing your own decline, because the
three answers generalise:

- **Photographic assets keep their own ground** rather than being re-lit. The
  mark sits in a tile that stays dark in both themes, which on a light screen
  reads as a stamped medallion. A whole panel can do the same by scoping the
  `dark` class to that subtree — every colour is a variable, so the subtree
  inherits the other theme with no `dark:` variants at all.
- **A brand colour that fails on the other ground splits in two**, it does not
  move. The fill keeps the true value in both themes; only the *ink* changes.
  Measure it: kitchops' copper is 3.4:1 as text on a light card and 7.1:1 once
  oxidised, and it is used as text 36 times against a solid fill twice.
- **"It is used in the dark"** is an argument about the **default**, which the
  app keeps. It is not an argument about the second theme existing.

Turning a second theme on is also the cheapest audit of the first one: doing it
in kitchops surfaced a dark-on-dark chat bubble, three scaffold screens painted
with Tailwind classes its own config had deleted, an invisible 420px strip of
the toast viewport eating every click in the bottom-right corner, and a login
headline that had been overlapping itself in **both** themes.


---

## 13. Live-site smoke test — `npm run test:smoke`

Every app has one, and it checks the **deployed** site rather than a local
build. That is the point: builds are green, and the failure that actually costs
days is a change that merged and was never served (Module 11). This is the
"verify by content, not by a commit hash" rule, automated.

The suite lives in [`shared/smoke/`](shared/smoke/) — `smoke.spec.js` is
byte-identical in every repo, `smoke.config.js` next to it holds the app's URL,
its `<title>` and how it represents the resolved theme. It asserts only what the
repo's own source provably produces:

1. the site answers 200 and the `<title>` is this app's — not a stale deploy;
2. nothing throws on first paint;
3. the theme arrives resolved on the first frame (the pre-mount script shipped);
4. the corner switcher is mounted, switches, and the preference survives a
   reload — or, for an app that declines a theme under Module 12, that no
   switcher is mounted at all;
5. the switcher covers nothing and is covered by nothing, at phone, tablet and
   desktop widths, collapsed and expanded, on every route the app lists in
   `config.routes` (Module 12). Public routes only — the suite has no
   credentials, and Module 12 says what you owe for the screens it cannot see.

Assertions invented from guessed page copy do not belong here: they break on a
wording change and teach everyone to ignore the suite. App-specific checks go in
a sibling spec file (ctrlhq's `auth.spec.js` is the example).

It does not run in the push/PR job, and it cannot run from a development
sandbox — outbound HTTPS there is proxied to an allowlist that excludes these
domains. `.github/workflows/smoke.yml` runs it on `workflow_dispatch`, so it can
be fired the moment a deploy finishes, with a daily cron as the backstop.

**Expect it to be red on an app whose latest merge has not been deployed.** That
is the suite working, not failing: the fix is `npm run deploy:site`.

---

## 14. Multi-tenant isolation audit — standing, evidenced, repeated

Module 4 says how to write an RLS rule. This says: **go and check, on a
schedule, that nothing in the app can read or write another tenant's data** —
entities, functions, exports, mail, files, all of it. The two are not the same
job, and every cross-tenant defect this portfolio has actually shipped got past
correctly-written RLS somewhere else.

**Why a rule review is not enough.** The failures were all syntactically valid:

- **cateqhub, `Parish`**: `delete` carried a
  `{"user_condition":{"data.parish_role":"admin"}}` branch with **no entity-side
  tenant match**. Any parish admin could delete *any other parish* by SDK call.
  Valid JSON, valid rule, catastrophic. `update` had it too.
- **liuma**: `{"data.school_id": X, "user_condition": Y}` — the engine takes
  `user_condition` as the **only** key of its rule object and silently drops the
  sibling. The tenant clause was not enforced on **29 entities, 84 instances**.
  Nothing was malformed; the rule simply did not mean what it read as.
- **puntos, `Business`**: whole-record update for the tenant's own admin, with
  no field lock on `billing_status`/`license_plan`. Not a leak between tenants —
  a tenant editing the thing that governs its own access. Same shape found on
  rumbo's `TenantLicense`.
- **stockflow / flowfin / ctrlhq / rumbo**: a `PermissionProfile` override and
  `billing_status` both live on a *different row*, and these RLS engines cannot
  join. Both were enforced in the UI only until a `guardedEntityWrite`-style
  function was added. A hidden button is not an access control.

**What the audit covers.** Walk each of these and write down what you found,
per app, with the date:

1. **Every entity**: the four-op `$or`, both halves of every comparison, the
   service-role branch, and no role branch that is not `$and`-ed to a tenant
   match. Static checker in CI, plus a read of every rule the checker cannot
   judge.
2. **Every backend function**: the tenant is **re-derived server-side** from the
   caller's own record or token, never taken from the request body. On
   update/delete the check is against the **stored** record's tenant, not the
   submitted one. Enumerate the endpoints and tick them off — `npm run
   functions:audit` lists them.
3. **Field-level locks** on anything the tenant must not write about itself:
   licence state, plan, limits, role, tenant id. Module 1's "written only by
   Mission Control" is a lie unless the field is actually locked.
4. **Exports, reports and search**: the widest read paths in the app, and the
   ones most often written as "it runs as service role, it's for admins". Every
   read filtered by the caller's own tenant, re-derived (Module 7).
5. **Outbound anything**: mail recipients, webhooks, notification targets and
   file/attachment URLs read from the stored row, never from the request —
   otherwise a leaked password mails arbitrary files to arbitrary addresses.
6. **Tenant switching**: nothing from the previous tenant survives the switch —
   no cached list, no in-memory store, no stale `business_id` in a closure. And
   a switch into a tenant you do not belong to must answer the **same** refusal
   as a tenant that does not exist, so the endpoint is not an existence oracle.
7. **The deployed schema, not the repo file.** Re-read the live schema and diff
   it against the repo. A fix that was committed and never pushed is a fix that
   does not exist (Modules 4 and 11).

**Evidence, not assertion.** "Audited" means a dated line in the app's
`CLAUDE.md` naming what was checked, what was found, what was fixed and **what
could not be verified here** — an authenticated session as a restricted user of
a second tenant is usually the gap, and saying so is worth more than implying
coverage that was not achieved. Re-audit whenever an entity, a function or a
role is added, and at minimum whenever the app is audited against this standard
as a whole.

---

## 15. The bridge to Mission Control — one shape, one key per app

Every app talks to Mission Control through the same two channels, and they are
not optional or app-flavoured. This module exists because "the same" turned out
to mean "the same secret", which is not the same thing at all.

**The channels.** Mission Control calls the app's `acaciaControl` function over
an HMAC-signed body for everything app-specific — licence read/write, health
`ping`, ticket pull, usage and session sync. The app calls Mission Control's
`/api/ingest/ticket` the moment a customer raises a ticket, also HMAC-signed.
An app that also exposes a bare `health` or a cron-ish endpoint gates it with a
bearer value instead, because there is no body to sign.

**The key is derived per app, never the master.**

```
appKey = HMAC-SHA256(INGEST_HMAC_SECRET, "acacia.app.v1." + <slug>)
```

`<slug>` is the app's Mission Control id — `apps.id` in the bodega, and the
`ACACIA_APP_SLUG` app secret on the app side. Both are required; an app that
does not know its own slug cannot join the bridge.

The reason is narrow and worth stating plainly. `INGEST_HMAC_SECRET` is **one
value shared by the whole portfolio**. A signature made with it proves "someone
who holds the shared secret" — it can never prove "this is app X". The
module-14 audit of Mission Control (2026-08-23) found the consequence: the app
name travels in the request body, so any app could sign a payload naming a
different app and have Mission Control write a ticket under that attribution.
Not an outsider hole — the holders are ACACIA's own apps — but a blast-radius
one: leak one app's secret and you have leaked all nine, and that same value is
also the bearer several `health` endpoints accept and what authorises
`license.set`.

Deriving fixes it because the slug selects the key. A body claiming to be
another app is checked against *that* app's key and fails unless the sender
actually holds it.

**Copy [`shared/bridge/acaciaSign.ts`](shared/bridge/acaciaSign.ts) in**, at
`base44/functions/<fn>/_acaciaSign.ts`, unchanged. Deno isolates each function
directory, so an app whose bridge touches three functions carries three
identical copies; that is expected, and a drift check in CI is what keeps them
identical by construction rather than by discipline. Mission Control's Node
half lives in `api/_lib/ingestSign.js` and pins **the same test vector** — two
HMAC implementations in two runtimes only stay equal if something asserts it,
and a drift shows up at runtime as `bad signature` on every call, which reads
like a misconfigured secret rather than a code change.

**Copy [`shared/bridge/acaciaSign.test.ts`](shared/bridge/acaciaSign.test.ts)
in too**, wherever the app's CI already runs `deno test`, changing only the
import path. It has no external imports and touches no network, so it runs in a
sandbox where `jsr.io` and `deno.land` are blocked. It pins the cross-language
vector and asserts the thing this module exists for: a body signed by one app
claiming to be another **fails**. Put it at the functions ROOT, never inside a
function directory — every directory under `base44/functions/` becomes a
deployed endpoint, and a test file is not one.

**Delete the inline crypto the copy replaces.** Each `acaciaControl` carried its
own `stableStringify`/`hmacHex`/`timingSafeEqual`, hand-mirrored against Mission
Control. Once `_acaciaSign.ts` owns them, leaving the old ones is not tidiness —
it is a second implementation of the same routine sitting in the same file,
which is precisely the drift this module removes. `deno lint`'s `no-unused-vars`
catches it in the three repos that run it; the other six have no deno step, so
there the only guard is doing it.

**The migration ran on 2026-08-24 and the flag can now go `false` everywhere:**
a sync of all nine apps at 16:29 UTC produced nine audit rows and **zero**
"rejected the derived key" warnings in Mission Control's log for that window.
That measurement is the gate, and it is the second one — the first attempt at
the same sync had four apps fall back (below). A new app starts at `false`
regardless: it has no legacy signature in flight.

The sequence below is the shape to copy the next time a shared secret has to
change under a fleet that deploys at different times:

1. **Verify both keys, sign with the old one.** Mission Control deploys on
   merge and the apps by hand, so MC is always first. Accepting either key made
   deploy order irrelevant; nothing went dark waiting for the slowest app.
2. **Switch the signer, keeping a fallback that names names.** MC signed
   derived and, only on a signature rejection, retried with the master and
   logged *which* app had rejected it. MC cannot read an app's Base44 secrets,
   so this was the only way to find a missing or misspelled `ACACIA_APP_SLUG`
   without taking that app's bridge down to discover it.
3. **Flip the flag and delete the fallback, in the same commit.** Once the flag
   is off, a wrong slug must fail rather than degrade — a fallback left behind
   would be exactly the silent acceptance the whole change removes.

**Step 3 waits on evidence, and the evidence is a log you actually read.** The
gate is a full sync of every app followed by Mission Control's runtime log for
that window, containing zero "rejected the derived key" warnings. Anything less
is a guess.

This is written the way it is because step 3 was first taken on a guess. The
sync ran, the flag went false and the fallback was deleted, on the strength of
a sentence — *"every call verified derived on the first attempt and the
fallback never fired once"* — that was composed rather than checked. The log of
that very sync named four apps that had fallen back: radar, rumbo, puntos and
liuma. They lost their bridge until it was reverted twenty minutes later, and
the revert had to be rebased and re-PRed because the bad change had already
been merged into all nine repos in the meantime.

The split was informative, which is the point of step 2's log line: the five
that verified derived were the five whose `ACACIA_APP_SLUG` had just been set;
the four that failed were the four that "already had it" — a claim inherited
from their own `CLAUDE.md` files and never once read back. The value was wrong.
Correcting the secret in those four and re-running the sync produced the clean
log above.

Three lessons, and the last two generalise past this module:

- **A fallback that names names is worthless if nobody reads what it named.**
  Step 2's whole purpose is to convert an outage into a log line. Skipping the
  log converts it back.
- **Watch for the reasoning that runs the wrong way.** Earlier in the same
  rollout, two apps showed doubled bridge latency and that was taken as a sign
  of the fallback firing; it was cold starts, checked and dismissed correctly.
  Having disproved a false alarm, the next step was to treat the absence of an
  alarm as proof — without looking. Disproving one signal is not evidence about
  a different one.
- **"It is already set" is a claim about a value, and a value can be read.**
  Four apps were documented as configured, in writing, in four files, for days.
  Nobody had opened the secrets panel. See Module 16.

**Do not give the bridge secret a second job.** Mission Control's `track.js`
used `INGEST_HMAC_SECRET` as the fallback salt for hashing visitor IPs, so
rotating the bridge secret would have silently rebucketed every unique-visitor
count. An auth secret authenticates; anything else that needs a stable random
string gets its own.

---

## 16. Secrets & configuration — the inventory, and reading it back

Every module above assumes some value is set somewhere. None of them say where,
and until 2026-08-24 no page in this repo listed them together. That gap has now
cost the portfolio two separate outages, in opposite directions:

- **A guard that never guarded.** Mission Control's four crons were gated by
  `if (secret && req.headers.authorization !== ...)`. With `CRON_SECRET` unset,
  the leading `secret &&` skipped the check entirely — and it *was* unset. An
  anonymous GET ran the full portfolio sync and returned every app's tenant,
  licence, ticket and session counts in the body.
- **A secret that was set to the wrong thing.** Four apps carried
  `ACACIA_APP_SLUG`, were documented as carrying it, and derived a key that did
  not match Mission Control's. Nobody had opened the panel to look.

The rule both give you:

> **A config value nobody has read back is not configured. Documentation that
> says it is set is a claim about someone's memory, not about the system.**

And its corollary, which is Module 11's rule wearing different clothes:
verifying by content, not by belief, applies to environment as much as to code.

### The portfolio-wide inventory

These are the values that exist because of *this standard*. Anything else an app
needs (payment keys, wallet certificates, model API keys) is that app's business
and belongs in its own `CLAUDE.md`.

| value | lives in | why | how to read it back |
|---|---|---|---|
| `INGEST_HMAC_SECRET` | Mission Control (Vercel) **and** every app (Base44 secrets) — one identical value portfolio-wide | the master the per-app bridge key is derived from (Module 15) | never used directly any more; a wrong value shows as `bad signature` on every bridge call |
| `ACACIA_APP_SLUG` | each app (Base44 secrets) | must equal the app's `apps.id` in the bodega, exactly: lowercase, no spaces, no suffix | run a sync and read MC's log for `rejected the derived key` — silence is the pass |
| `ACACIA_MC_INGEST_URL` | apps that push tickets from a backend function | where `notifyTicketCreated` / `submitTicket` POST (Module 8) | a ticket raised in the app appears in MC within seconds, not at 08:00 UTC |
| `CRON_SECRET` | Mission Control (Vercel); also apps with their own internal jobs | gates every scheduled endpoint, **fail-closed** — unset must mean 503, never 200 | an anonymous GET to a cron path must not return 200 |
| `PLATFORM_OWNER_EMAIL` | most apps | the one identity that may run platform-tier functions | a platform function must 403 for any other caller **and** when the value is absent |
| `TRACK_SALT` | Mission Control | the salt for hashing visitor IPs | — |

**Two names for one idea, and it is still that way.** Three apps call the owner
identity `PLATFORM_OWNER_EMAIL` (radar, stockflow, kitchops), three call it
`APP_OWNER_EMAIL` (rumbo, puntos, flowfin), and three use neither because their
platform tier is a role rather than an address (liuma, cateqhub, ctrlhq). A new
app uses `PLATFORM_OWNER_EMAIL`. The existing split is recorded here rather than
renamed, because renaming a secret in six live apps to tidy a name is a change
with an outage in it and no user on the other side.

### Fail closed, and prove which way it fails

Every guard built on one of these must reject when the value is **missing**, not
open. This is the single most repeated defect in `docs/incidents.md`: flowfin
learned it by making `_internalGuard.ts` fail-open and silently disabling three
crons; Mission Control learned it by leaving four crons wide open in production;
radar learned it when an emptied `Company` table re-opened a founder-bootstrap
branch that was supposed to be dead forever.

Write the guard so the unset case is an explicit branch, and then **test that
branch** — `assert(guard(undefined) === reject)` is one line and it is the line
that matters.

### When a value has to change

Rotating a shared secret across a fleet that deploys at different times has a
shape, and Module 15 documents it end to end: accept both, switch the writer
with a fallback that names names, then flip and delete the fallback **on a
measurement**. Do not invent a second procedure.

And do not give an auth secret a second job. Mission Control's `track.js` used
`INGEST_HMAC_SECRET` as the fallback salt for visitor-IP hashing, so rotating
the bridge key would have silently rebucketed every unique-visitor count.
Anything that needs a stable random string gets its own.

---

## 17. The Mission Control side — an app is not onboarded until MC knows it

Modules 1–16 are what the app does. This one is what has to change **in Mission
Control**, and it is the half that gets forgotten, because the app looks
finished from inside the app.

Registration alone wires the config, not the data path. ctrlhq sat registered
in MC's `apps` table with its bridge undeployed, so licences, health and tickets
were all configured and none of them moved.

1. **A row in `apps`** (the bodega) — `id` is the slug the whole standard keys
   off: `ACACIA_APP_SLUG`, the `app` field in every bridge body, `target_app` in
   the audit log. `npm run onboard:base44 -- <repoPath> --dry` previews the row.
2. **An adapter** in `api/_lib/adapters/` — `base44` covers today's whole
   portfolio; a genuinely new backend kind needs one written.
3. **`api/_lib/licenseControl.js`** — the app's licence capabilities: its
   statuses, plans, which fields hold expiry and period end, its billing mode.
   Miss this and the Licencias panel renders that app's licences with no
   buttons at all, which is exactly how radar shipped.
4. **`api/_lib/ticketControl.js`** — where its tickets live and how its thread
   is shaped, so the operator's queue can read and reply.
5. **`api/_lib/messaging.js`** — the copy used when MC mails that app's tenants.
6. **The client catalogue mirror** — `src/lib/licenseCatalog.js` is the browser
   copy of `licenseCapabilities()`, and `src/lib/licenseCatalog.test.js` fails
   if the two drift. Adding an app or a status means updating both; there is
   deliberately no silent way to forget.

**Then confirm the data actually round-trips**, which is not the same as
confirming the code merged: press *Sincronizar ahora* on the app's page in MC
and check that `app_health` has a row for it with `status: ok` and that
`audit_actions` gained a `control:run-sync` for that app. `run-sync` answers 502
when the bridge throws and writes its audit row only on success, so that row is
the proof.

---

## 18. Multi-tenant account switching — one email, several tenants

**The gap this closes.** An operator's email is not exclusive to one tenant. The
same person owns two rental fleets, an accountant admins three restaurants, a
platform owner tests against a second tenant without a second inbox — nothing
in the data model stops one email from being `owner_email`, the creator, or an
invited member of more than one tenant record at once. What every app in this
portfolio actually did about it, before this module, was pick the **first**
match — by creation order, inside whatever function resolves the caller's
tenant — and **persist it permanently** on the user profile. The second tenant
was never wrong; it was invisible. Rumbo's `resolveTenant` walks
`created_by_id → owner_email → members[]` and returns on the first hit, and its
`joinTenant` then actively refuses a second membership ("ya perteneces a otra
organización — sal de ella antes de unirte a una nueva"). An owner who
legitimately runs two businesses through the same login is locked into
whichever tenant the resolver saw first, with no error, no prompt, and no way
out short of a support ticket.

**The fix is two backend calls and one frontend control, not a rewrite of the
tenant model.**

1. **The resolver stops guessing.** Whatever function today derives the
   caller's tenant from `created_by_id`/`owner_email`/`members[]` (Rumbo:
   `resolveTenant`) computes the **full set** of matching tenants, not just the
   first. If the caller already has a valid `tenant_id` persisted, keep using
   it — nothing changes for the common case — but return the full candidate
   list alongside it so the client can offer a switcher whenever
   `candidates.length > 1`. If nothing is persisted yet and there is exactly
   one candidate, auto-assign it as before — no reason to interrupt a user who
   has only ever belonged to one tenant. If nothing is persisted and there is
   more than one candidate, **do not guess**: return a "choose one" state
   instead of onboarding or a silent pick.
2. **A dedicated switch endpoint, server-derived twice.** A new function
   (Rumbo: `switchTenant`) takes a `tenant_id` from the client and
   **recomputes the caller's legitimate candidate set from scratch**, the same
   way the resolver does — it never trusts that an id the client sent is one
   the caller actually belongs to. A `tenant_id` outside that set gets the
   exact same refusal as a `tenant_id` that does not exist (this is Module
   14's tenant-switching clause, §6, applied for real: the endpoint must not
   become an existence oracle). A valid switch re-derives role the same way
   first login does — `owner_email` match → owner, `members[]` match → that
   member's stored role, creator → whatever role the profile already
   carries — and recomputes `write_access` against the new tenant's licence
   state. Nothing about the previous tenant is trusted forward.
3. **One switcher, reachable once it's needed.** A control — account menu,
   sidebar, wherever the app's chrome has room — lists the caller's tenants by
   name and marks the active one, visible only when `candidates.length > 1` (an
   operator with one tenant never sees a control with nothing to do). Picking a
   different tenant calls the switch endpoint, then **hard-reloads**
   (`window.location.reload()` once the server call resolves) rather than
   trying to reset every tenant-scoped hook, list and cache in place — Module
   14 §6 exists because that in-place reset is exactly where a stale
   `business_id` survives in a closure, and a reload is the one reset that
   cannot leave one behind. The same control is what a brand-new, ambiguous
   login sees instead of the onboarding screen when the resolver reports more
   than one candidate and nothing persisted yet — same component, two entry
   points.

**What this does not change.** A tenant's own RLS and every `guardedEntityWrite`
-style Safe function still key off the **single** `tenant_id` persisted on the
caller's profile at request time (Module 3, Module 4) — switching writes that
one field through the same server-authoritative path first login already uses;
it does not add a second identity or a session that spans two tenants at once.
An operator is always acting as exactly one tenant; switching only changes
which one, deliberately, one field write at a time.

**Verify it like every other module: read the deployed behavior, not the
diff.** Log in as an email that is `owner_email`/creator/member on two tenants
and confirm: (a) the picker (or switcher) actually lists both, by name; (b)
switching changes every tenant-scoped screen's data, not just the header; (c)
requesting a `tenant_id` the caller does not belong to — by editing the call
directly — gets the same response as a nonexistent id.

---

## 19. A shipped security fix needs a guard of its own

Modules 1–18 are about closing a hole. This one is about the hole staying
closed — because closing it once is not the same job as keeping it closed, and
this portfolio has now watched a correctly-shipped, correctly-deployed fix get
silently reverted by a **different, well-meaning debugging session** that had
no idea the lock it removed was load-bearing.

**The incident.** FlowFin's `User.family_id` field carries a locked
`rls.write: {user_condition: {role: admin}}` — Module 14 finding #1's fix,
shipped and verified live. A user reported being stuck on the onboarding
screen. A separate agent session (Base44's own in-app builder, working
directly against the live app, outside the git/PR path this fix shipped
through) diagnosed the symptom, reasoned that this write lock was "stripping
`family_id` from non-admin reads," and removed it. **That reasoning is not
just risky, it is factually wrong**: an `rls.write` rule governs write
eligibility only and has no bearing on what a read returns. Removing the lock
could not have fixed a read-resolution symptom — and per that session's own
transcript, it didn't: the user was still stuck afterward, through two more
rounds of unrelated speculative fixes, while the actual hole (any user can now
set their own tenant pointer to any value and read that tenant's data) sat
open in production. It was only caught because a second, independent
diagnosis re-checked the deployed schema directly instead of trusting either
session's narrative — and by then the reverted lock had already round-tripped
into the git source of truth too, so restoring it live was not enough; the
repo needed the same fix or the next ordinary entity deploy would have
silently stripped it again.

**Why a rule review is not enough, again — same shape as Module 14, one layer
up.** The failure here was never a bad RLS rule. It was a **correct** rule,
removed by someone reasoning about a mechanism they had backwards, under
symptom pressure, with no visibility into why the rule existed. Nothing about
this is specific to Base44's builder — it is what happens whenever more than
one path can write to an app's schema (a git-based agent session, a platform's
own in-app AI, a teammate under pressure) and a security-relevant lock's
rationale lives somewhere the person touching it isn't reading.

**What closes this:**

1. **A lock's own field description carries its rationale, not just the
   module/finding number.** State plainly, in the schema itself, what the
   field is for, what breaks if it's removed, and — critically — **which
   operation it governs** (write, not read; or vice versa). An agent
   inspecting the live schema in isolation, with no access to this repo's
   `STANDARD.md` or the app's `CLAUDE.md`, should still be unable to
   misdiagnose the mechanism.
2. **State the mechanism precisely before touching the control, and verify it
   before, not after.** "This lock might be related" is not a diagnosis. A
   write rule cannot produce a read-only symptom and a read rule cannot
   produce a write failure — if the proposed fix doesn't match that shape,
   the diagnosis is wrong regardless of how plausible it sounds. Prove which
   rule is actually implicated with live evidence (reproduce the symptom,
   isolate to the specific rule) before loosening anything security-relevant,
   the same evidence bar Module 14 already demands for writing one.
3. **A "fix" that doesn't resolve the symptom is evidence the diagnosis was
   wrong, not license to try the next hypothesis on top of it.** The correct
   response to "I removed the lock and the user is still stuck" is to put
   the lock back immediately and re-diagnose — not to leave it open while
   stacking a session-clearing theory, then a frontend-fallback theory, on
   top. An open security hole is not an acceptable cost of an in-progress
   debugging session, however urgent the original symptom.
4. **When more than one surface can write to the same app, a security-relevant
   schema change on either surface must be checked against the other
   immediately.** Restoring a lock live (via a direct schema-edit path) is not
   done until the git-tracked schema file agrees — otherwise the next routine
   deploy from whichever surface didn't get the memo silently undoes the fix,
   and the drift can sit unnoticed until the next audit.
5. **Roll this into the Module 14 re-audit.** Every lock that audit already
   requires (Module 1's `billing_status`, Module 14's own field locks, a
   `business_id`/`family_id`-equivalent tenant pointer) gets checked for drift
   at the same cadence: deployed schema vs. repo file, not just "is the rule
   present" but "does it still say what it said last time," because a lock
   that silently loosened between audits is indistinguishable from one that
   was never tightened.

---

## 20. Session control — inactivity timeout, one active device, stale sessions reaped

Every app logs users out on its own, in three layers that catch different
failure modes. A client-side idle timer alone only protects the tab that is
still open and running JavaScript; it does nothing for a laptop that was
closed mid-session or a phone whose browser was killed by the OS. All three
layers are the module, not any one of them.

**Layer 1 — client-side inactivity.** A warning dialog after a fixed idle
period, then a hard logout shortly after if nobody responds. Canonical
implementation: [`shared/session/`](shared/session/), lifted from FlowFin's
`useSessionManager.js` (20 min idle → warning, 2 min countdown → logout,
`IdleWarningDialog.jsx` shows the countdown live) and
`IdleWarningDialog.jsx`/`SessionExpiredDialog.jsx`'s explicit re-auth choice
(log back in, or fully sign out). Copy these in unchanged, the same discipline
as Module 12's theme switcher and Module 15's bridge signer — an app that
edits its own copy in place drifts, and an operator running two ACACIA apps
should meet the same warning at the same threshold in both. Activity is
tracked with a throttled `useActivityTracker` (FlowFin: one write per hour,
not per keystroke) so the idle timer resets from real DOM events without
hammering the backend.

**Layer 2 — one active device per user, surfaced, not silently blocked.**
Track a `Session` (or equivalent) row per `(user, device_id)`, updated on
every heartbeat. Logging in from a new device marks that device `active` and
demotes the user's other `active` sessions to `passive` — the older device
keeps working (this is "control de sesiones al mismo tiempo con el mismo
usuario": the app tracks and can act on concurrency, not that it locks a user
to one device against their will) but the app can now show "también activo
en: iPhone, hace 3 min" and let the user revoke a device they don't
recognize. A device the user has never authorized appearing in that list is
the whole point of tracking this at all — it is a account-compromise signal
Module 7's danger zone should surface, not bury in a table nobody reads.

**Layer 3 — stale sessions get reaped on the server, not just abandoned.**
This is the gap Layer 1 structurally cannot close: a session whose client
never sends another heartbeat (device died, battery drained, browser killed
outright) sits `active`/`passive` forever with no client left to run the idle
timer. A scheduled job (pattern:
[`shared/session/purgeStaleSessions.example.ts`](shared/session/README.md))
revokes any session whose `last_seen` is older than a fixed threshold —
**48 hours** is the portfolio default (long enough that a legitimate
multi-day-away laptop sleep doesn't get logged out from under someone, short
enough that a dead session doesn't sit "active" for weeks). Revoking sets
`status: 'revoked'`, which `sessionHeartbeat`'s own check (FlowFin:
`if (found.status === 'revoked') return 403`) already turns into a forced
re-auth the next time that device's tab wakes up — no separate client change
needed, the guard rail was already there for Mission Control's own
remote-force-logout path (see FlowFin's `CLAUDE.md`, 2026-08-05 changelog
entry) and this reuses it for the timed case.

**What this is not.** Layer 2's "one active device" is a UI/UX signal, not
an access-control boundary — it does not replace Module 3's server-side
permission re-check, and a `passive` device is not blocked from working, only
flagged as not-the-most-recent. Don't build a second auth gate out of it.

---

## 21. About screen — user manual, changelog, version, contact, and the ACACIA line

Every app has one screen — reachable from account/settings, not buried —
that answers "what does this app do, what changed recently, what version am
I on, and who do I ask." Canonical shape: FlowFin's `About.jsx` +
`UserManual.jsx`, four things on one surface:

- **A user manual.** Searchable, in-app, sectioned by feature area (FlowFin:
  an accordion, one entry per module, plain-language "how do I…" content —
  not API docs, not a README). This is the thing that turns a support ticket
  ("how do I split an expense?") into something the user answers themselves,
  and it is the natural home for anything Module 3's new permission-admin
  screen (above) doesn't already make self-evident from the UI itself.
- **The changelog, surfaced where the user already is.** Module 6 owns
  *generating* `APP_VERSION`/`RELEASE_DATE`/the changelog array; this module
  is where it gets *read* — "Novedades v`{currentVersion}`" front and center,
  a collapsible full version history behind it. Don't build a second
  changelog UI a release script has to remember to also update — this screen
  reads the same array Module 6 already produces.
- **Version, unambiguous.** The number on this screen, in `package.json`,
  and in the update-available banner (FlowFin: `AppUpdateBanner.jsx`) must
  be the same line — Module 6 already flags what happens when they drift
  ("se corrige el desfase histórico del número de versión").
- **Contact, and the line that says whose app this is.** Support email and a
  direct channel (FlowFin: WhatsApp) that actually reaches someone — not a
  form into a void, and not a duplicate of Module 8's ticket system, just the
  fastest path to it. And a short acknowledgment that this is an ACACIA
  product: the ACACIA mark, "Hecho con ♥ para \<the app's actual users\>,"
  rights/licensing line. Small, but it is the one place in the whole app that
  says who stands behind it, and it costs one card on a settings screen.

None of these four are Mission Control's to build — the panel operates the
*portfolio*, not any single tenant's day-to-day, and a user asking "how do I
use this" or "who do I call" should never have to know Mission Control
exists.

---

## Verification gates — what actually proves a module is live

The recurring failure across this portfolio is not writing the code. It is
believing the code is running: merging deploys nothing on Base44, a checkpoint's
`git_commit_hash` can match `main` while the served tree lags, a repo `.jsonc`
is not the deployed schema, and a documented secret can hold the wrong value.
Each module's proof is a thing you can run and read.

| module | the claim | what proves it |
|---|---|---|
| 1 licence lifecycle | only MC writes `billing_status` | no native lifecycle cron in the repo; the field's `rls.write` is admin-only in the **deployed** schema |
| 3 permissions | the server re-checks, not just the UI | a unit test on the resolver, plus the drift check that regenerates the server copies in CI |
| 4 RLS | both halves of every rule are right | `npm run validate:rls` in CI, then `list_entity_schemas` — the deployed schema, not the file |
| 5 health | MC can see the app | an `app_health` row with `status: ok` dated today |
| 8 support | tickets arrive now, not tomorrow | raise one and watch it appear in MC in seconds |
| 11 deploy | what you merged is what is served | read the served file's content; `unchanged` from the CLI means deployed already matched |
| 12 theme | the switcher is the only theme writer | grep for other writers of the theme attribute; there must be none |
| 13 smoke | the live site is the one you think | `npm run test:smoke` green in Actions, against production |
| 14 isolation | no tenant can reach another | the dated audit, naming what could **not** be verified |
| 15 bridge | each app signs as itself | a full sync with zero `rejected the derived key` in MC's log |
| 16 secrets | the value is what you think | read it back from the panel, or make a call that only succeeds if it is right |
| 18 tenant switching | one email reaches every tenant it belongs to, and no other | log in as a multi-tenant email, confirm the picker lists all of them and a foreign `tenant_id` gets the same refusal as a nonexistent one |
| 19 lock survives debugging | a shipped security lock is still on | deployed schema still shows it, repo file agrees with the deployed schema, and its description still states the rationale |
| 20 session control | idle logs out, stale sessions get reaped | wait past the idle threshold and confirm the warning/logout fires; check a session whose `last_seen` is older than 48h flips to `revoked` after the reap job runs |
| 21 about screen | version/changelog/manual/contact are one screen, in sync | the version shown matches `package.json` and the update banner; the changelog entry for the current version is non-empty |

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
9. Add the `apps/` page on `acaciaco-site` (Module 9), then do the **whole**
   Mission Control side (Module 17): the `apps` row, the adapter,
   `licenseControl.js`, `ticketControl.js`, `messaging.js` and the client
   catalogue mirror. Registration alone wires the config, not the data path.
10. Build the login page to the Module 10 bar.
11. Copy the theme switcher in from [`shared/theme/`](shared/theme/) (Module 12)
    and delete any other theme control.
12. Copy the smoke suite in from [`shared/smoke/`](shared/smoke/) (Module 13)
    and point its config at the app's real URL.
13. Run the Module 14 isolation audit before the **second** tenant exists —
    with one tenant nothing can leak, which is also why nothing gets caught.
14. Copy [`shared/bridge/acaciaSign.ts`](shared/bridge/acaciaSign.ts) and its
    test in (Module 15), set `ACACIA_APP_SLUG` to the app's Mission Control id,
    and start with `ACCEPT_LEGACY_MASTER = false` — the legacy path exists only
    for apps that predate the derivation.
15. Set every secret in Module 16's inventory **and read each one back**, then
    prove the whole chain with one *Sincronizar ahora*: an `app_health` row,
    an audit row, and no `rejected the derived key` in Mission Control's log.
16. If the tenant entity's `owner_email`/`members[]` shape lets one email reach
    more than one tenant, build the Module 18 switcher from day one — the
    resolver returning every candidate, the dedicated switch endpoint that
    re-derives the candidate set server-side, and the control itself.
    Retrofitting it later means every profile that already got silently locked
    to the wrong tenant needs a one-time nudge to re-resolve.
17. Copy [`shared/session/`](shared/session/) in (Module 20): the idle
    warning/logout pair, the activity-tracking heartbeat, the per-device
    `Session` entity with the active/passive model, and the stale-session
    reap job at the 48h default.
18. Build the About screen (Module 21) — user manual, the changelog surfaced
    from Module 6's own generated array, the version line kept in sync with
    `package.json`, and a contact + ACACIA acknowledgment card.
19. Copy `CHECKLIST.md` from this repo into the new app's `CLAUDE.md`.

See [`CHECKLIST.md`](CHECKLIST.md) for the compact, copy-pasteable version of
this list, and [`docs/incidents.md`](docs/incidents.md) for the full postmortems
this standard was distilled from.
