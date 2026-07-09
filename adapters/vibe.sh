#!/usr/bin/env bash
# ------------------------------------------------
# vibe.sh - wire Vibe to the hub (pure symlinks, can never go stale)
# ------------------------------------------------
set -euo pipefail
HUB="$(cd "$(dirname "$0")/.." && pwd)"
source "$HUB/lib/log.sh"
source "$HUB/lib/common.sh"
command -v vibe >/dev/null || exit 0

run mkdir -p "$HOME/.vibe"
link "$HUB/directions/AGENTS.md" "$HOME/.vibe/AGENTS.md"   # user-level, always-on
link "$HUB/skills"               "$HOME/.vibe/skills"      # all skills available globally
info "vibe: ok"
