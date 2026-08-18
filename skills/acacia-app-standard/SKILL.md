---
name: acacia-app-standard
description: Apply or audit the ACACIA Portfolio App Standard — the shared set of modules (license lifecycle, roles, granular permissions, multi-tenant RLS, health/latency, changelog, account & danger zone, support/mejoras, acaciaco-site presence, login page) every app must implement to plug into Mission Control. Use when scaffolding a brand-new portfolio app, when the user says an app should "join Mission Control" or "seguir el estándar ACACIA", when auditing one or more existing apps for compliance/gaps against the standard, or when touching license lifecycle, RLS, or permission-registry code in any app repo owned by jospabloh and you should sanity-check it isn't drifting from the shared contract.
tools: Read, Grep, Glob, Bash, WebFetch, Edit, Write
---

# ACACIA Portfolio App Standard

The canonical standard lives in `jospabloh/acacia-app-standard`
(`STANDARD.md` = full contract + rationale, `CHECKLIST.md` = compact
copy-paste block, `docs/incidents.md` = the production postmortems each rule
was distilled from). **That repo is the source of truth, not this skill.**
`references/STANDARD.md` and `references/CHECKLIST.md` here are a point-in-time
mirror, bundled so this skill works even when that repo isn't attached to the
session — but they can drift stale. Whenever you're about to rely on the exact
wording of a rule (not just "there are 10 modules"), prefer the live source:

1. If `jospabloh/acacia-app-standard` is already attached/cloned in this
   session, read it from there.
2. Otherwise `WebFetch` the raw files:
   `https://raw.githubusercontent.com/jospabloh/acacia-app-standard/main/STANDARD.md`
   and `.../CHECKLIST.md`.
3. Only fall back to the bundled `references/` copies if both of the above are
   unreachable (no network / repo not grantable) — and say so, since the copy
   may be out of date.

## The 10 modules, in one line each

1. **License lifecycle** — `billing_status` on the tenant entity, written ONLY
   by Mission Control's unified cron. No app-native lifecycle/renewal cron.
2. **User & role control** — one file declaring the app's own role model,
   distinct from Mission Control's own owner/admin/viewer operator roles.
3. **Granular permissions** — client registry + independent server-side
   re-check on every write path, gated by `billing_status` too.
4. **Multi-tenant RLS** — tenant branch + service-role admin branch on all
   four ops, both rule halves correct, static validator in CI.
5. **Health & latency** — a real endpoint Mission Control's adapter can poll.
6. **Changelog & versioning** — generated only by a deliberate release step,
   never by the routine build.
7. **Account & danger zone** — member mgmt, export, real irreversible-delete.
8. **Support & mejoras** — feeds Mission Control's tickets/leads, not a
   parallel triage system.
9. **Presence on acaciaco-site** — a page under `apps/` (or `freeware/`).
10. **Login page "pro"** — on-brand, real error/suspended/view_only states.

Full rationale, exact contract shape (field names, RLS templates, precedence
order) and the incidents behind each rule: read `STANDARD.md` in full before
implementing any module for the first time. Don't implement from this
one-liner list alone — it's an index, not the spec.

## Two modes

### Mode A — scaffolding a brand-new app

1. Confirm the backend kind (today: always Base44 unless told otherwise) and
   that an adapter exists in `acacia-mission-control/api/_lib/adapters/` —
   flag it if a new adapter kind is needed, that's a Mission Control change,
   not something this skill does on its own.
2. Copy the checklist block from `CHECKLIST.md` (live or bundled) into the new
   app's `CLAUDE.md`, unchecked.
3. Walk the "Onboarding checklist for a brand-new app" section of
   `STANDARD.md` in order — it sequences the 10 modules so RLS/roles/
   permissions exist before anything is built on top of them, and account/
   support/site/login come once there's something real to gate.
4. Do not mark a checklist item done in the app's `CLAUDE.md` without having
   actually verified it (read the code / ran the relevant validator) — a
   checked box that isn't true is worse than an honest unchecked one; the next
   session (or the next audit) will trust it.

### Mode B — auditing one or more existing apps

Used after the standard itself changes, or on request ("audita X contra el
estándar"). For a single app, work through the module list yourself, citing
concrete file evidence per module (✅ implemented / ⚠️ partial or flawed /
❌ missing) — don't assert compliance from a CLAUDE.md's prose alone, spot
check 2–3 of its claims against actual source.

For **multiple apps at once**, this is exactly the "2+ independent tasks with
no shared state" shape — use the `dispatching-parallel-agents` skill's
pattern: one agent per app, each given the module list and this skill's
per-module evidence bar, running read-only (no edits, no deploys) against that
app's local clone. Merge results into one per-app scorecard + a cross-app
"most common gap" summary at the end — the second view is often more
actionable than any single app's report, since a gap repeated across 4 apps is
a candidate for the standard's next revision or for a shared script, not 4
separate fixes.

Report format per app: one line per module (status + evidence), a short
"top gaps" list ordered by severity, one-line overall verdict. Flag explicitly
when a module doesn't cleanly apply to what a given product actually is
(e.g. a non-multi-tenant tool) rather than forcing a verdict — false-positive
gaps erode trust in the next audit.

## Keeping this skill's mirror in sync

If you edit `STANDARD.md`/`CHECKLIST.md` in `jospabloh/acacia-app-standard`,
update `references/STANDARD.md` and `references/CHECKLIST.md` in this skill in
the same session if both repos are attached — otherwise leave a note in the
commit message that the mirror is now stale, so the next person/session
knows to refresh it rather than trusting it silently.
