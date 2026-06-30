# Owner Mode — operating Base44 with full owner access (Acacia / StockFlow)

Use this when the task needs Claude Code to act with the owner's full access
(cross-tenant reads, deletes, service-role writes). See `../../../COMPANY.md` for
the company profile (app id, tenants, RLS contract).

## 1. Pick the working channel

Run a capability probe first:

```bash
# MCP sandbox channel (preferred in Cowork): does run_command work?
#   -> "Missing required OAuth scope 'sandbox:write'" means the connector needs
#      its scope upgraded (Settings → Connectors → Base44 → Manage permissions).
# CLI channel: is the owner logged in?
npx -y base44@latest whoami     # 403 "host not in allowlist" => network policy blocks auth
```

- **MCP query/update/create** always work through the proxy (no delete).
- **Deletes / service-role scripts** need either the connector `sandbox:write`
  scope (channel 1) or a working CLI login (channel 2).

## 2. CLI login (channel 2)

```bash
npx -y base44@latest login        # prints a URL + device code; owner approves in browser
npx -y base44@latest whoami       # confirm: should show h.josepablo@gmail.com
```

If `login` returns `403 Forbidden` while generating the device code, the
environment's **network egress policy** is blocking the Base44 auth host — add it
to the policy (see https://code.claude.com/docs/en/claude-code-on-the-web) or
switch to channel 1.

## 3. Run owner scripts with `base44 exec`

`exec` runs a script with a pre-authenticated `base44` SDK global (owner context):

```bash
cat > /tmp/op.ts <<'TS'
// Owner-context globals: base44.entities.<E>, base44.asServiceRole, base44.functions
const biz = '69c575fa1beaf2c90214d3ee'; // Baristop
const movs = await base44.asServiceRole.entities.Movement.filter({ business_id: biz });
console.log('count', movs.length);
TS
cat /tmp/op.ts | npx -y base44@latest exec --app-id 69af971d0fdb362c9ae52ed3
```

For deletes: `await base44.asServiceRole.entities.Movement.delete(id)`.
Always **preview (filter + log) before deleting**, and for inventory delete the
duplicate movements first, then SET the corrected `Product.stock` (see COMPANY.md).

## 4. Local settings template (gitignored — never commit secrets)

Create `.claude/base44.local.md` in the consuming project:

```markdown
---
base44_app_id: 69af971d0fdb362c9ae52ed3
owner_email: h.josepablo@gmail.com
default_business_id: 69c575fa1beaf2c90214d3ee   # Baristop
# Do NOT put tokens here if the repo's .gitignore doesn't cover .claude/*.local.md.
# Prefer the CLI's own stored session or an env var for the token.
---

Notes: owner-mode operational notes for this project.
```

Confirm `.claude/*.local.md` (or `*.local.md`) is gitignored before writing any
credential into it.
