#!/usr/bin/env bash
# ------------------------------------------------
# vibe.sh - wire Vibe to the hub (pure symlinks, can never go stale)
#
# Called bare (or with "install") by `briefing install`; called with
# "remove" by `briefing uninstall` to undo the wiring and restore backups.
# ------------------------------------------------
set -euo pipefail
HUB="$(cd "$(dirname "$0")/.." && pwd)"
source "$HUB/lib/log.sh"
source "$HUB/lib/common.sh"
MODE="${1:-install}"

if [[ "$MODE" == "remove" ]]; then
  # Clean up even when the vibe binary is gone; leftovers don't need it.
  unwire "$HOME/.vibe/AGENTS.md" "$HUB/directions/AGENTS.md"
  unwire "$HOME/.vibe/skills"    "$HUB/skills"
  info "vibe: removed"
  exit 0
fi

command -v vibe >/dev/null || exit 0

run mkdir -p "$HOME/.vibe"
link "$HUB/directions/AGENTS.md" "$HOME/.vibe/AGENTS.md"   # user-level, always-on
link "$HUB/skills"               "$HOME/.vibe/skills"      # all skills available globally
info "vibe: ok"
