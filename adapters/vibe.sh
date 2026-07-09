#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
HUB="$(cd "$(dirname "$0")/.." && pwd)"
command -v vibe >/dev/null || exit 0

mkdir -p "$HOME/.vibe"
link "$HUB/directions/AGENTS.md" "$HOME/.vibe/AGENTS.md"   # user-level, always-on
link "$HUB/skills"               "$HOME/.vibe/skills"      # all skills available globally
echo "vibe: ok"
