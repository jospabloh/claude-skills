# Portfolio Standard — Checklist

Copy this block into the app's own `CLAUDE.md`. Full rationale for each item is
in [`STANDARD.md`](https://github.com/jospabloh/acacia-app-standard/blob/main/STANDARD.md)
in `jospabloh/acacia-app-standard` — read it before implementing any item below
for the first time, and re-read the relevant section before touching a module
that's already implemented.

```
## ACACIA Portfolio Standard

This app is part of the ACACIA portfolio and must stay compliant with
jospabloh/acacia-app-standard. Status:

- [ ] Module 1 — License lifecycle: tenant entity has `billing_status`
      (trial|active|view_only|suspended), written ONLY by Mission Control's
      unified cron. No native lifecycle/renewal/reminder cron in this repo.
- [ ] Module 2 — Roles: app role model declared in one file, mapped onto the
      backend's built-in role field; Mission Control operator roles
      (owner/admin/viewer) are a separate layer, never conflated.
- [ ] Module 3 — Granular permissions: one client registry file + server-side
      re-check on every write path (permission key, in the same precedence
      order as the client), gated behind billing_status too. No entity is
      written to directly from the client without a Safe-function equivalent.
      An admin-facing "Permisos" screen renders that same registry as a
      matrix (module x action, tri-state group + per-section overrides) so
      the tenant's own admin can see and approve what each role can do,
      instead of a registry file only the client hides/disables UI from.
- [ ] Module 4 — RLS: every tenant-scoped entity has the four-op `$or` shape
      (tenant branch + service-role admin branch), both halves of every rule
      verified (data.* on the entity side, {{user.data.*}} on the user side).
      Static validator wired into CI. Schema changes are deployed, not just
      committed.
- [ ] Module 5 — Health: a real (not hardcoded-200) health/latency endpoint
      Mission Control's adapter can poll.
- [ ] Module 6 — Changelog: APP_VERSION/RELEASE_DATE + in-app changelog,
      generated only by the release script, never by the routine build.
- [ ] Module 7 — Account & danger zone: member management gated by Module 3,
      data export, irreversible delete with a real confirmation step.
      Danger zone covers BOTH scopes, not just one: "delete my account"
      (leave the tenant) is separate from "delete the tenant" (every
      member loses access), plus delegate/transfer tenant admin to another
      approved member and promote a member to tenant admin — all three
      re-derive actor and target from the tenant's own stored membership,
      never from the request body.
- [ ] Module 8 — Support/mejoras: entry point writes to this app first, then
      syncs into Mission Control's tickets/leads bodega. No parallel triage UI.
      EVERY place a ticket is born (support page AND the danger zone's deletion
      request) notifies Mission Control in real time — sign and POST from a
      backend function if one already creates the ticket, else ping
      `/api/ingest/ticket-pull` with `{app, ticketId}` from the browser. The
      08:00 UTC sync is the backstop; on its own it costs the customer a day.
- [ ] Module 9 — acaciaco-site: this app has a page under apps/ (or freeware/),
      using styles/base.css tokens, dark-theme correct.
- [ ] Module 10 — Login page: on-brand, real error/suspended/view_only states,
      links to trial and support, dark-theme correct.

- [ ] Module 11 — Deploy discipline: `base44.app.json` + `npm run deploy`
      (refuses `--app-id`), `deploy:site` for the frontend (merging to `main`
      deploys nothing), `deploy:entities` behind a typed confirmation, and
      `validate:functions` in lint keeping endpoints under 40 (Base44 caps at
      50). Run `npm run functions:audit` before consolidating anything, and
      verify every deploy by reading the served file, not by a hash or a merge.

- [ ] Module 12 — Theme control: the shared corner switcher from
      `shared/theme/`, offering claro / oscuro / sistema, copied in unchanged
      and rendered once inside the theme provider. Preference stored as
      'light' | 'dark' | 'system' (never the resolved colour), pre-mount script
      in index.html so there is no flash, and no other theme control left in
      the app. Placed with `--theme-switcher-bottom/right` so it covers no
      control and is covered by none, on phone, tablet and desktop, collapsed
      and expanded. An app that ships only one theme says so, with its reason,
      here.

- [ ] Module 13 — Live-site smoke test: `npm run test:smoke` runs the shared
      suite from `shared/smoke/` against the DEPLOYED site (title, no throw,
      theme painted pre-mount, switcher works and collides with nothing at the
      three widths on every public route listed), wired to
      `.github/workflows/smoke.yml` on
      workflow_dispatch + a daily cron. Red here means the last merge was never
      deployed — that is the suite working.

- [ ] Module 14 — Multi-tenant isolation audit: dated, evidenced, and repeated
      whenever an entity, a function or a role is added. Not a re-read of the
      RLS rules (Module 4) — a walk of every entity, every backend function
      (tenant re-derived server-side, never from the request body; checked
      against the STORED record on update/delete), every field lock, every
      export/report/search, every outbound recipient, and tenant switching. The
      deployed schema, not the repo file. Write down what could NOT be verified.

- [ ] Module 15 — Bridge to Mission Control: `shared/bridge/acaciaSign.ts`
      copied in unchanged (one copy per bridge-touching function directory —
      Deno isolates them) plus its test at the functions ROOT, and outbound
      signing on the DERIVED key, never the bare `INGEST_HMAC_SECRET`. That
      secret is one value shared by the whole portfolio, so a signature made
      with it proves "someone holds the shared secret", never "this is app X".
      A new app starts at `ACCEPT_LEGACY_MASTER = false`; the legacy path
      exists only for apps that predate the derivation.

- [ ] Module 16 — Secrets: `INGEST_HMAC_SECRET` (identical portfolio-wide),
      `ACACIA_APP_SLUG` (exactly this app's Mission Control id — lowercase, no
      spaces, no suffix), `ACACIA_MC_INGEST_URL` if a backend function pushes
      tickets, `PLATFORM_OWNER_EMAIL`, and `CRON_SECRET` for any scheduled
      endpoint. Every guard built on one of these FAILS CLOSED when the value
      is missing, and that branch has a test. Each value has been READ BACK
      from the panel or proven by a call that only succeeds if it is right — a
      value documented as set is a claim about someone's memory, not about the
      system, and this portfolio has lost the bridge once and exposed four
      crons once on exactly that.

- [ ] Module 17 — Mission Control side: row in `apps` (its `id` is the slug
      everything else keys off), an adapter, and entries in
      `licenseControl.js`, `ticketControl.js`, `messaging.js` plus the client
      catalogue mirror. Then PROVE the data path, not just the config: press
      Sincronizar ahora and confirm an `app_health` row with `status: ok` and a
      `control:run-sync` audit row for this app.

- [ ] Module 18 — Multi-tenant account switching: the resolver that derives a
      caller's tenant from creator/owner_email/members[] computes the FULL set
      of matches, not just the first, and returns it alongside whatever is
      already persisted — a persisted, still-valid tenant_id keeps winning, an
      unambiguous single candidate still auto-assigns, and only true ambiguity
      (no persisted tenant_id, 2+ candidates) blocks on a choice instead of
      guessing. A dedicated switch endpoint re-derives the caller's candidate
      set from scratch server-side (never trusts the requested tenant_id) and
      answers a tenant the caller doesn't belong to with the exact same
      refusal as a nonexistent one. The switcher control is visible only when
      there is more than one candidate, and a successful switch hard-reloads
      rather than resetting tenant-scoped state in place.

- [ ] Module 19 — Lock survives debugging: every security-relevant RLS/field
      lock this app has (Module 1's `billing_status`, Module 14's tenant-pointer
      locks, etc.) states its rationale AND which operation it governs (write
      vs. read) in its own field description — not just in this file. Checked
      for drift at the same cadence as the Module 14 re-audit: deployed schema
      still has it, repo file agrees with the deployed schema. A "fix" for an
      unrelated symptom that touches one of these locks is verified against the
      lock's actual mechanism (a write rule cannot explain a read symptom, or
      the reverse) before it ships, live or otherwise.

- [ ] Module 20 — Session control: client-side idle warning + hard logout
      (`shared/session/`), a per-device Session with the active/passive
      model so a user can see and revoke concurrent devices, and a
      server-side reap job that revokes any session idle past 48h — the
      layer the client-side timer structurally cannot reach.

- [ ] Module 21 — About screen: an in-app user manual, the changelog from
      Module 6 surfaced where the user already is (current version's
      changes + collapsible history), the version line in sync with
      package.json, and a contact + ACACIA acknowledgment card.

Last audited against the standard: <date> — <what changed / what's still open>
Last multi-tenant isolation audit: <date> — <scope, findings, what's unverified>
Secrets last read back: <date> — <which ones, and how each was proven>
Security locks last checked for drift (Module 19): <date> — <deployed vs. repo, any found open>
```
