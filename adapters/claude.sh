#!/usr/bin/env bash
# ------------------------------------------------
# claude.sh - wire Claude Code to the hub
#
# Global directions as a ~/.claude/CLAUDE.md symlink (never stale). Note:
# Claude's "#" memory shortcut appends to CLAUDE.md, so such appends land in
# directions/AGENTS.md and show up as a reviewable git diff.
#
# Skills are linked one by one into ~/.claude/skills/ (Claude discovers
# <name>/SKILL.md there); links into this hub are pruned when the skill is
# gone, the user's own skills are never touched.
#
# Called bare (or with "install") by `briefing install`; called with
# "remove" by `briefing uninstall`.
# ------------------------------------------------
set -euo pipefail
HUB="$(cd "$(dirname "$0")/.." && pwd)"
source "$HUB/lib/log.sh"
source "$HUB/lib/common.sh"
MODE="${1:-install}"

SKILLS="$HOME/.claude/skills"

if [[ "$MODE" == "remove" ]]; then
  # Clean up even when the claude binary is gone; leftovers don't need it.
  unwire "$HOME/.claude/CLAUDE.md" "$HUB/directions/AGENTS.md"
  for l in "$SKILLS"/*; do
    [[ -L "$l" ]] || continue
    case "$(readlink "$l")" in "$HUB/skills/"*) run rm "$l" ;; esac
  done
  if [[ -d "$SKILLS" && -z "$(ls -A "$SKILLS")" ]]; then run rmdir "$SKILLS"; fi
  info "claude: removed"
  exit 0
fi

command -v claude >/dev/null || exit 0

run mkdir -p "$HOME/.claude"
link "$HUB/directions/AGENTS.md" "$HOME/.claude/CLAUDE.md"   # user-level, always-on

# Skills: one link per hub skill, pruning links whose skill left the hub
run mkdir -p "$SKILLS"
for l in "$SKILLS"/*; do
  [[ -L "$l" ]] || continue
  case "$(readlink "$l")" in
    "$HUB/skills/"*) [[ -d "$HUB/skills/$(basename "$l")" ]] || run rm "$l" ;;
  esac
done
for s in "$HUB"/skills/*/; do
  [[ -d "$s" ]] || continue
  link "${s%/}" "$SKILLS/$(basename "$s")"
done
info "claude: ok"
