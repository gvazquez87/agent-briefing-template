# briefing adopt - import existing agent instruction files into directions/

cmd_adopt_help() {
  cat <<'EOF'
briefing adopt - import existing instruction files into directions/AGENTS.md

Usage:
  briefing [-n|--dry-run] adopt [file ...]

Without arguments, scans well-known global instruction files:
  ~/.claude/CLAUDE.md   (Claude Code - pre-install file, or the
                         .pre-briefing.bak that `briefing install` preserved)
  ~/.codex/AGENTS.md    (Codex)
  ~/.gemini/GEMINI.md   (Gemini CLI)
  ~/.vibe/AGENTS.md     (Vibe - pre-install file, or the .pre-briefing.bak
                         that `briefing install` preserved)
  ~/.hermes/SOUL.md     (Hermes - only your identity section above the
                         generated directions marker)
With arguments, adopts exactly the named files.

Each file's content is APPENDED to directions/AGENTS.md under a marker
comment recording where it came from. Nothing is merged automatically and
the source files are never modified: review the diff, fold the useful rules
into your sections, delete the markers, then run `briefing sync`.

Skipped automatically: missing or empty files, symlinks into this repo
(already managed by an adapter), and files adopted before (idempotent).
EOF
}

# adopt_one FILE [CONTENT] - append CONTENT (a file, default FILE itself) to
# directions/AGENTS.md under a marker naming FILE, unless it should be
# skipped. Sets ADOPTED=1 when content was (or would be) appended.
adopt_one() {
  local f="$1" content="${2:-$1}"
  if [[ ! -f "$f" || ! -s "$content" ]]; then
    skip "nothing to adopt: $f (missing or empty)"
    return 0
  fi
  if [[ -L "$f" && "$(resolve_path "$f")" == "$HUB"/* ]]; then
    skip "already managed by this hub: $f"
    return 0
  fi
  if grep -qF "adopted from $f " "$DIRECTIONS" 2>/dev/null; then
    skip "already adopted: $f"
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'would adopt: %s -> %s\n' "$f" "$DIRECTIONS"
  else
    { printf '\n<!-- adopted from %s on %s - review, merge into the sections above, then delete this comment -->\n' \
        "$f" "$(date +%F)"
      cat "$content"
    } >> "$DIRECTIONS"
    ok "adopted: $f"
  fi
  ADOPTED=1
}

# adopt_hermes_soul - SOUL.md is half ours: everything below the marker is
# the generated directions copy (never adopt that back), everything above is
# the user's hand-written identity, worth importing like any other file.
adopt_hermes_soul() {
  local soul="$HOME/.hermes/SOUL.md" tmp
  [[ -f "$soul" ]] || { skip "nothing to adopt: $soul (missing or empty)"; return 0; }
  tmp="$(mktemp)"
  awk 'index($0, "briefing directions below"){exit} {lines[NR]=$0; n=NR}
       END{while(n>0 && lines[n]=="") n--; for(i=1;i<=n;i++) print lines[i]}' \
    "$soul" > "$tmp"
  adopt_one "$soul" "$tmp"
  rm -f "$tmp"
}

cmd_adopt() {
  local ADOPTED=0 f
  if [[ $# -gt 0 ]]; then
    for f in "$@"; do
      [[ "$f" == /* ]] || f="$PWD/$f"   # absolute path for a stable marker
      adopt_one "$f"
    done
  else
    # Claude and Vibe appear twice: as the live file (real before the first
    # install, then a hub symlink that adopt_one skips) and as the backup
    # that the safe-link helper preserved when install took the path over.
    for f in "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md.pre-briefing.bak" \
             "$HOME/.codex/AGENTS.md" \
             "$HOME/.gemini/GEMINI.md" "$HOME/.vibe/AGENTS.md" \
             "$HOME/.vibe/AGENTS.md.pre-briefing.bak"; do
      adopt_one "$f"
    done
    adopt_hermes_soul
  fi
  if [[ "$ADOPTED" == 1 ]]; then
    info "review the diff (git -C $HUB diff directions/), fold the adopted rules"
    info "into your sections, delete the markers, then run: briefing sync"
  else
    info "adopt: nothing new to import"
  fi
}
