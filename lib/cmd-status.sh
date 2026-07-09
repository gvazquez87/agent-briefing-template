# briefing status - health check for wiring, projects, and the repo

cmd_status_help() {
  cat <<'EOF'
briefing status - health check

Usage:
  briefing status

Checks, without changing anything:
  - global wiring per installed agent (symlinks, generated sections)
  - every registered project (generated rule freshness, mirrors, skills)
  - the repo itself (uncommitted files, unpushed commits)

Exit code 0 when everything is healthy, 1 when something needs attention.
Repairs are one command away: `briefing install` (wiring) or
`briefing sync` (repo).
EOF
}

cmd_status() {
  cd "$HUB"

  echo "global"
  [[ "$(readlink "$HOME/.local/bin/briefing" 2>/dev/null)" == "$HUB/bin/briefing" ]] \
    && ok "briefing on PATH (~/.local/bin/briefing)" || bad "briefing not on PATH (run bin/briefing install)"

  # Vibe: symlinks can't go stale, just verify they point at the hub
  if command -v vibe >/dev/null; then
    [[ "$(readlink "$HOME/.vibe/AGENTS.md" 2>/dev/null)" == "$DIRECTIONS" ]] \
      && ok "vibe: ~/.vibe/AGENTS.md -> directions" || bad "vibe: ~/.vibe/AGENTS.md not linked"
    [[ "$(readlink "$HOME/.vibe/skills" 2>/dev/null)" == "$HUB/skills" ]] \
      && ok "vibe: ~/.vibe/skills -> skills" || bad "vibe: ~/.vibe/skills not linked"
  else skip "vibe: not installed"; fi

  # Hermes: SOUL.md carries a generated copy, compare it against the source
  if command -v hermes >/dev/null; then
    if awk 'f{print} index($0, "briefing directions below"){f=1}' "$HOME/.hermes/SOUL.md" 2>/dev/null \
         | sed '1{/^$/d}' | diff -q - "$DIRECTIONS" >/dev/null 2>&1; then
      ok "hermes: SOUL.md directions section current"
    else
      stale "hermes: SOUL.md directions section (run briefing install)"
    fi
    [[ "$(readlink "$HOME/.hermes/skills/briefing" 2>/dev/null)" == "$HUB/skills" ]] \
      && ok "hermes: skills mounted" || bad "hermes: skills not mounted"
    local f
    for f in MEMORY.md USER.md; do
      [[ "$(readlink "$HOME/.hermes/memories/$f" 2>/dev/null)" == "$HUB/memory/hermes/$f" ]] \
        && ok "hermes: $f captured" || bad "hermes: $f not captured"
    done
  else skip "hermes: not installed"; fi

  echo
  echo "projects"
  if [[ -s "$REG" ]]; then
    local p s t miss
    while IFS= read -r p; do
      echo "  $(basename "$p")"
      if [[ ! -d "$p" ]]; then bad "  directory gone ($p)"; continue; fi
      # Cursor rule: generated copy, 4-line frontmatter then directions verbatim
      if tail -n +5 "$p/.cursor/rules/briefing.mdc" 2>/dev/null | diff -q - "$DIRECTIONS" >/dev/null 2>&1; then
        ok "  briefing.mdc current"
      else
        stale "  briefing.mdc (run briefing link $p)"
      fi
      if [[ -f "$p/AGENTS.md" ]]; then
        [[ "$(readlink "$p/HERMES.md" 2>/dev/null)" == "$p/AGENTS.md" ]] \
          && ok "  HERMES.md mirror" || bad "  HERMES.md mirror missing"
      else
        skip "  no AGENTS.md (no HERMES.md mirror)"
      fi
      if [[ -f "$p/.briefing-skills" ]]; then
        while IFS= read -r s; do
          [[ -z "$s" || "${s:0:1}" == "#" ]] && continue
          miss=""
          for t in .vibe/skills .cursor/skills; do
            [[ "$(readlink "$p/$t/$s" 2>/dev/null)" == "$HUB/skills/$s" ]] || miss="$miss $t"
          done
          [[ -z "$miss" ]] && ok "  skill $s" || bad "  skill $s missing in:$miss"
        done < "$p/.briefing-skills"
      fi
    done < "$REG"
  else
    skip "no projects registered (run briefing link <dir>)"
  fi

  echo
  echo "repo"
  local dirty ahead
  dirty="$(git status --porcelain | wc -l)"
  if [[ "$dirty" -eq 0 ]]; then
    ok "working tree clean"
  else
    stale "$dirty uncommitted file(s), review and run briefing sync"
    git status --porcelain | sed 's/^/        /'
  fi
  ahead="$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo '?')"
  [[ "$ahead" == "0" ]] && ok "in sync with origin" || stale "$ahead commit(s) not pushed"

  exit "$FAIL"
}
