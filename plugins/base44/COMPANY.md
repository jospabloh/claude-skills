# Company Profile — Acacia / StockFlow (Owner Mode)

> Company-specific configuration for the `base44` plugin. This file is loaded by
> the base44 skills to tailor behavior to this company's apps, tenancy model, and
> owner workflows. **It contains no secrets** — credentials live only in the
> gitignored local file described under "Owner access", never in this repo.

## Identity

- **Company / org:** Acacia
- **Owner:** Jose Pablo Herrera — `h.josepablo@gmail.com`
- **Primary Base44 app:** **StockFlow** — `appId: 69af971d0fdb362c9ae52ed3`
  - Repo: `jospabloh/stockflow` (schema-as-code in `base44/entities/*.jsonc`,
    backend functions in `base44/functions/*/entry.ts`).

## Tenancy model (read before any data operation)

StockFlow is **multi-tenant**. Every business-scoped record carries a
`business_id`, and tenants are isolated by Row-Level Security. Known tenants:

| Business | `business_id` |
|---|---|
| Baristop Distribuidora | `69c575fa1beaf2c90214d3ee` |
| ACACIA OWNER SANDBOX | `69c593f99e0839c7e07fb5d0` |

**Always scope queries/mutations by `business_id`.** The full RLS contract (the
two-halves rule, the `asServiceRole` admin branch required on all four ops) is
documented in `stockflow/CLAUDE.md` — treat it as authoritative and run
`npm run validate:rls` after touching any `rls` block.

## Inventory model invariant

`applyMovementStock` is the single authority for stock deltas and is idempotent
via `Movement.stock_applied`. On record **delete**, the `syncProductStock`
automation re-adds the exit quantity (`+qty`, floored at 0). When remediating
duplicated movements, **delete first, then SET the corrected stock** — the final
set overrides the automation's revert and is exact even where a burst clamped at 0.

## Owner access (how Claude Code operates as owner)

Owner-level access does **not** come from this plugin (skills are instructions).
It comes from one of these channels — pick the one available in the current
environment:

1. **Base44 MCP connector** (works through the pre-configured proxy). Read +
   update + create are available by default. **Delete and sandbox execution
   require the `sandbox:write` scope** — grant it by reconnecting the Base44
   connector (in Cowork desktop: Settings → Connectors → Base44 → Manage
   permissions → approve sandbox/write). With that scope, `run_command` can run
   service-role SDK scripts (full owner access incl. delete).
2. **Base44 CLI** — `npx base44 login` (OAuth device-code flow), then
   `npx base44 exec` runs SDK scripts pre-authenticated as the owner
   (`base44.entities.<E>.delete(id)`, `base44.asServiceRole`, …).
   ⚠️ **Requires network egress to the Base44 auth endpoints.** In locked-down
   remote environments the device-code request returns `403 Forbidden`
   ("host not in allowlist"); add the Base44 auth/api hosts to the environment's
   network policy, or use channel 1 instead.

### Credentials — never commit

Any owner token, API key, or `BASE44_APP_ID` override goes in a **gitignored**
local file or env var, never in this repo:

- Local plugin settings: `.claude/base44.local.md` (gitignored) — see
  `references/owner-mode.md`.
- Or environment variables: `BASE44_APP_ID`, plus the CLI's own stored token.

## Safety rules for owner operations

- **Confirm destructive data operations** (delete / bulk update of production
  records) before executing, and prefer a dry-run/preview first.
- **Respect tenant isolation** — never let one tenant's `business_id` leak into
  another's records.
- Remediations on production sales/inventory should run during a **quiet window**
  (no active selling) to avoid racing concurrent movements.
