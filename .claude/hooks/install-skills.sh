#!/usr/bin/env bash
#
# SessionStart hook: make this repo's skills + plugins auto-callable.
#
# Each skill in the `acacia-skills` marketplace (and the `frontend-slides`
# plugin) only auto-triggers on a request when its plugin is installed, so the
# skill descriptions are loaded for matching. This hook installs them at the
# start of every session.
#
# It exists mainly for Claude Code on the web / cloud agents, where `~/.claude`
# is reset on each session -- without this, the skills would silently disappear.
# All commands are idempotent, so it is also a harmless no-op locally once the
# plugins are already installed.
#
set -uo pipefail

# Repo root: provided by the harness in remote sessions; fall back to resolving
# it relative to this script for local/manual runs.
REPO="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Register this checkout as a local marketplace. We use the local path (not the
# GitHub slug) so it works offline and always matches the current checkout.
claude plugin marketplace add "$REPO" >/dev/null 2>&1 || true

# Install + enable both plugins (no-ops when already present).
claude plugin install acacia-skills@acacia-skills   >/dev/null 2>&1 || true
claude plugin install frontend-slides@acacia-skills >/dev/null 2>&1 || true

exit 0
