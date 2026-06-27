#!/usr/bin/env bash
# Install the acacia-skills marketplace + plugins so all 48 skills (and the
# frontend-slides plugin) auto-trigger in every Claude Code session.
#
# Local machine:  run this once, then restart Claude Code.
# Cloud (web):    point your environment's Setup Script at this file, or paste
#                 its commands there. It runs before every cloud session.
#
# Installs at USER scope, so the skills are available in any repo you open.
set -euo pipefail

MARKETPLACE="${ACACIA_SKILLS_SOURCE:-jospabloh/claude-skills}"

echo "==> Adding marketplace: ${MARKETPLACE}"
claude plugin marketplace add "${MARKETPLACE}" || \
  claude plugin marketplace update acacia-skills

echo "==> Installing plugins"
claude plugin install acacia-skills@acacia-skills
claude plugin install frontend-slides@acacia-skills
claude plugin install base44@acacia-skills

echo "==> Done. Restart Claude Code (local) for the skills to register."
claude plugin list
