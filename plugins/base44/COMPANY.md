# Company Profile — Acacia (Base44 owner)

> Company-wide configuration for the `base44` plugin. It applies to **all** of
> this owner's Base44 apps — not any single app. It tailors the base44 skills to
> this company's identity, owner-access workflows, and conventions.
> **No secrets are stored here** — credentials live only in gitignored local
> files / env vars (see "Owner access").

## Identity

- **Company / org:** Acacia
- **Owner:** Jose Pablo Herrera — `h.josepablo@gmail.com`

## App registry (all apps, extensible)

This plugin serves every app under this owner. Discover the live list with
`npx base44 whoami` / the Base44 MCP `list_user_apps`, and add rows here as apps
are created. Always target operations at a specific app via its `appId`
(`--app-id` for the CLI, the `appId` arg for MCP tools).

| App | `appId` | Repo | Notes |
|---|---|---|---|
| StockFlow | `69af971d0fdb362c9ae52ed3` | `jospabloh/stockflow` | Multi-tenant inventory; see `stockflow/CLAUDE.md` |
| _add new apps here_ | | | |

Per-app specifics (entities, tenancy, RLS, business rules) live in **that app's
own repo / `CLAUDE.md`**, not in this file. Read the target app's docs before
operating on its data.

## Conventions that apply across apps

- **Multi-tenancy:** most apps here are tenant-scoped by a `business_id` (or
  equivalent) with Row-Level Security. Always scope queries/mutations by the
  tenant key, and never let one tenant's id leak into another's records. Each
  app's RLS contract is authoritative in its own repo (e.g. StockFlow's
  two-halves rule + `asServiceRole` admin branch in `stockflow/CLAUDE.md`).
- **Idempotent writes / inventory:** when an app uses an "apply exactly once"
  stock/ledger model, remediating duplicates means **delete the duplicate
  records first, then SET the corrected value** (a final set overrides any
  automation that reverts on delete). Confirm the app's specific model first.

## Owner access (how Claude Code acts as owner — same for every app)

Owner access does **not** come from this plugin (skills are instructions). It
comes from one of these channels — pick whichever the current environment allows
(see `references/owner-mode.md` for commands):

1. **Base44 MCP connector** (works through the pre-configured proxy). Read +
   update + create are available by default; **delete and sandbox execution need
   the `sandbox:write` scope** — grant it by reconnecting the Base44 connector
   (Cowork desktop: Settings → Connectors → Base44 → Manage permissions).
2. **Base44 CLI** — `npx base44 login` (OAuth device-code) → `npx base44 exec`
   runs SDK scripts pre-authenticated as the owner, for any app via `--app-id`.
   ⚠️ Requires network egress to the Base44 auth endpoints; locked-down remote
   environments return `403 host-not-allowed` — use channel 1 or adjust the
   environment's network policy.

### Credentials — never commit

Owner tokens / API keys / `BASE44_APP_ID` overrides go in a **gitignored** local
file (`.claude/base44.local.md`) or env vars, never in this repo. `*.local.md`
and `.env*` are gitignored here.

## Safety rules for owner operations (all apps)

- **Confirm destructive data operations** (delete / bulk update of production
  records) before executing; prefer a dry-run/preview first.
- Run production data remediations during a **quiet window** (no active writes).
- Respect each app's tenant isolation and RLS contract.
