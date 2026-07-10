# briefing link - wire a project to the hub

cmd_link_help() {
  cat <<'EOF'
briefing link - wire a project directory to the briefing repo

Usage:
  briefing [-n|--dry-run] link <project-dir>

What it does (idempotent):
  1. links each skill named in the project's .briefing-skills manifest
     into the project skills dir of each agent present on this machine
     (.vibe/skills/, .cursor/skills/, .claude/skills/), and prunes links
     for skills removed from the manifest
  2. mirrors the project's AGENTS.md as HERMES.md and CLAUDE.md (symlinks,
     again only for agents present on this machine)
  3. generates .cursor/rules/briefing.mdc from directions/AGENTS.md
  4. ignores all generated files machine-locally via .git/info/exclude,
     so nothing needs to be added to the project's committed .gitignore
  5. registers the project so `briefing install` re-links it in future
     (install an agent later and its links appear on the next install)
EOF
}

cmd_link() {
  local PROJECT MANIFEST AGENT TARGET l s
  PROJECT="$(cd "${1:?usage: briefing link <project-dir>}" && pwd)"
  MANIFEST="$PROJECT/.briefing-skills"

  # 1. Skills: link manifest entries into each agent's project skills dir.
  # Only agents present on this machine get artifacts; a project registered
  # here is re-linked by every `briefing install`, so installing an agent
  # later just takes one install (or link) to grow the missing links.
  if [[ -f "$MANIFEST" ]]; then
    for AGENT in vibe cursor claude; do
      agent_present "$AGENT" || { skip "$AGENT not installed, skipping .$AGENT/skills/"; continue; }
      TARGET="$PROJECT/.$AGENT/skills"
      run mkdir -p "$TARGET"
      for l in "$TARGET"/*; do            # drop links no longer in the manifest
        [[ -L "$l" ]] || continue
        case "$(readlink "$l")" in "$HUB/skills/"*)
          grep -qxF "$(basename "$l")" "$MANIFEST" || run rm "$l" ;;
        esac
      done
      while IFS= read -r s; do
        [[ -z "$s" || "${s:0:1}" == "#" ]] && continue
        [[ -d "$HUB/skills/$s" ]] \
          || die "unknown skill: $s (not in $HUB/skills/; edit $MANIFEST or add the skill to the hub)"
        run ln -sfn "$HUB/skills/$s" "$TARGET/$s"
      done < "$MANIFEST"
    done
  fi

  # 2. Hermes and Claude project rules: mirror the project's AGENTS.md.
  # A real committed CLAUDE.md wins - Claude reads it natively - so the
  # mirror is only created when the path is free or already a symlink.
  if [[ -f "$PROJECT/AGENTS.md" ]]; then
    if agent_present hermes; then
      run ln -sfn "$PROJECT/AGENTS.md" "$PROJECT/HERMES.md"
    else
      skip "hermes not installed, skipping HERMES.md mirror"
    fi
    if ! agent_present claude; then
      skip "claude not installed, skipping CLAUDE.md mirror"
    elif [[ ! -e "$PROJECT/CLAUDE.md" || -L "$PROJECT/CLAUDE.md" ]]; then
      run ln -sfn "$PROJECT/AGENTS.md" "$PROJECT/CLAUDE.md"
    else
      skip "left CLAUDE.md alone (real file; Claude reads it natively)"
    fi
  fi

  # 3. Cursor: global directions as an always-on rule (generated, single
  # source). The frontmatter records which hub produced it and at what
  # version, so `status` can explain divergence precisely.
  if agent_present cursor; then
    run mkdir -p "$PROJECT/.cursor/rules"
    { printf -- '---\ndescription: briefing directions (generated, edit %s)\nbriefing-hub: %s\nbriefing-version: %s\nbriefing-sha256: %s\nalwaysApply: true\n---\n' \
        "$DIRECTIONS" "$HUB" "$(hub_version)" "$(emit_text "$DIRECTIONS" | hash_stdin)"
      emit_text "$DIRECTIONS"
    } | write_file "$PROJECT/.cursor/rules/briefing.mdc"
  else
    skip "cursor not installed, skipping .cursor/rules/briefing.mdc"
  fi

  # 4. Ignore everything link may generate, machine-locally. The full
  # pattern set (not just the agents present today) so an agent installed
  # later can never leak fresh links into a commit before the next re-link.
  write_exclude_block "$PROJECT" "$EXCLUDE_PATTERNS"

  # 5. Register (machine-local) so `briefing install` re-links this project
  run mkdir -p "$(dirname "$REG")"
  if ! grep -qxF "$PROJECT" "$REG" 2>/dev/null; then
    if [[ "$DRY_RUN" == "1" ]]; then
      printf 'would register: %s in %s\n' "$PROJECT" "$REG"
    else
      echo "$PROJECT" >> "$REG"
    fi
  fi

  info "linked: $PROJECT"
}
