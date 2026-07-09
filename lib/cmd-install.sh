# briefing install - wire every installed agent to this repo

source "$HUB/lib/cmd-link.sh"   # install re-links registered projects

cmd_install_help() {
  cat <<'EOF'
briefing install - wire every installed agent to this repo

Usage:
  briefing [-n|--dry-run] install

What it does (idempotent, safe to re-run any time):
  1. records the repo location in $XDG_STATE_HOME/briefing/hub
  2. symlinks `briefing` into ~/.local/bin so it is on PATH
  3. runs every adapters/*.sh; each one wires its agent and exits
     silently when that agent is not installed on this machine
  4. re-links every project registered on this machine, so generated
     copies (like .cursor/rules/briefing.mdc) never go stale
EOF
}

cmd_install() {
  run mkdir -p "$STATE_DIR" "$HOME/.local/bin"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'would write: %s\n' "$STATE_DIR/hub"
  else
    echo "$HUB" > "$STATE_DIR/hub"
  fi
  run ln -sfn "$HUB/bin/briefing" "$HOME/.local/bin/briefing"

  local a
  for a in "$HUB"/adapters/*.sh; do
    bash "$a"
  done

  # Re-link every registered project so generated copies never go stale
  if [[ -f "$REG" ]]; then
    local p
    while IFS= read -r p; do
      [[ -d "$p" ]] && cmd_link "$p"
    done < "$REG"
  fi
  info "install: ok ($HUB)"
}
