# Owner Mode — operating Base44 with full owner access (Acacia, all apps)

Use this when a task needs Claude Code to act with the owner's full access
(cross-tenant reads, deletes, service-role writes) on **any** of this owner's
apps. See `../../../COMPANY.md` for the owner identity and app registry. This
workflow is app-agnostic — always target a specific app by its `appId`.

## 1. Discover apps & pick the working channel

```bash
npx -y base44@latest whoami      # owner identity + login state
# List apps via the Base44 MCP `list_user_apps`, or the dashboard.
```

Capability probe:
- **MCP query/update/create** always work through the proxy (no delete).
- **Deletes / service-role scripts** need either the connector `sandbox:write`
  scope (channel 1) or a working CLI login (channel 2).
  - `run_command` → `Missing required OAuth scope 'sandbox:write'` ⇒ upgrade the
    connector scope (Settings → Connectors → Base44 → Manage permissions).
  - `npx base44 login` → `403 host-not-allowed` ⇒ the environment's network
    egress policy blocks the Base44 auth host; allow it
    (https://code.claude.com/docs/en/claude-code-on-the-web) or use channel 1.

## 2. CLI login (channel 2)

```bash
npx -y base44@latest login        # prints a URL + device code; owner approves in browser
npx -y base44@latest whoami       # confirm owner email
```

## 3. Run owner scripts with `base44 exec` (per app via --app-id)

`exec` runs a script with a pre-authenticated `base44` SDK global (owner context).
**Always pass `--app-id <appId>`** for the target app:

```bash
cat > /tmp/op.ts <<'TS'
// Globals: base44.entities.<E>, base44.asServiceRole, base44.functions
const rows = await base44.asServiceRole.entities.SomeEntity.filter({ /* tenant scope */ });
console.log('count', rows.length);
TS
cat /tmp/op.ts | npx -y base44@latest exec --app-id <APP_ID>
```

For deletes: `await base44.asServiceRole.entities.<E>.delete(id)`. Always
**preview (filter + log) before deleting**. For "apply once" inventory/ledger
models, delete duplicates first, then SET the corrected value (see COMPANY.md and
the target app's own docs).

## 4. Local settings template (gitignored — never commit secrets)

Create `.claude/base44.local.md` in the consuming project. Keep it per-app or
list multiple apps:

```markdown
---
owner_email: h.josepablo@gmail.com
apps:
  stockflow:
    app_id: 69af971d0fdb362c9ae52ed3
    default_business_id: 69c575fa1beaf2c90214d3ee   # Baristop (example tenant)
  # another_app:
  #   app_id: ...
# Do not store tokens here unless .gitignore covers *.local.md; prefer the CLI's
# stored session or an env var.
---
```

Confirm `*.local.md` / `.env*` are gitignored before writing any credential.
