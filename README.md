# acacia-skills

A personal, curated Claude Code **marketplace** bundling 48 skills plus the
`frontend-slides`, `base44`, and `whatsapp-agentkit` plugins. Use it to make the
same skills available everywhere — your local machine **and** cloud sessions /
cloud agents.

## What's inside

- **`acacia-skills`** plugin — 49 skills covering documents (`docx`, `pdf`,
  `pptx`, `xlsx`), design (`frontend-design`, `canvas-design`, `theme-factory`,
  `brand-guidelines`, `algorithmic-art`), web (`webapp-testing`,
  `web-artifacts-builder`), dev workflow (the `superpowers` set:
  `brainstorming`, `systematic-debugging`, `test-driven-development`,
  `writing-plans`, …), authoring (`skill-creator`, `mcp-builder`,
  `plugin-structure`, `writing-skills`, …), and the ACACIA portfolio's own
  `acacia-app-standard` (apply/audit the shared module contract every
  Mission Control app must implement — mirrors `jospabloh/acacia-app-standard`).
- **`frontend-slides`** plugin — HTML presentation generator with templates and
  PPTX conversion.
- **`base44`** plugin — official Base44 skills (`base44-cli`, `base44-sdk`,
  `base44-troubleshooter`) for building and deploying full-stack Base44 apps.
- **`whatsapp-agentkit`** plugin — `/build-agent` interviews a business owner
  and generates a complete WhatsApp AI agent (FastAPI webhook server, Claude
  brain, per-customer memory, Zernio/Meta Cloud API adapters, Railway deploy).
  Ported from [Hainrixz/whatsapp-agentkit](https://github.com/Hainrixz/whatsapp-agentkit) (MIT).

## Install

### Locally

```bash
claude plugin marketplace add jospabloh/claude-skills   # or your fork's slug
claude plugin install acacia-skills@acacia-skills
claude plugin install frontend-slides@acacia-skills
claude plugin install base44@acacia-skills
claude plugin install whatsapp-agentkit@acacia-skills
```

### In the cloud (Claude Code web / cloud agents)

Cloud sessions don't see your local `~/.claude`. They fetch from GitHub, so this
repo must be pushed first:

```bash
gh repo create claude-skills --private --source=. --push   # one-time
```

Then, in any cloud session, run the same two `claude plugin` commands above. The
marketplace is resolved from GitHub, so the skills load identically to local.

## Updating

Edit/add a skill under `skills/<name>/SKILL.md`, then:

```bash
git add -A && git commit -m "update skills" && git push
claude plugin marketplace update acacia-skills   # refresh local cache
```

## Layout

```
.claude-plugin/marketplace.json   # marketplace manifest (lists all plugins)
skills/<name>/SKILL.md            # one directory per skill
plugins/frontend-slides/          # vendored frontend-slides plugin
plugins/base44/                   # vendored base44 plugin
plugins/whatsapp-agentkit/        # vendored whatsapp-agentkit plugin
```
