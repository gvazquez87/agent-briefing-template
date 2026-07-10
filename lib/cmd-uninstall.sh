# briefing uninstall - undo everything install and link did on this machine

source "$HUB/lib/cmd-unlink.sh"   # uninstall unlinks every registered project

cmd_uninstall_help() {
  cat <<'EOF'
briefing uninstall - undo everything install and link did on this machine

Usage:
  briefing [-n|--dry-run] uninstall

Run `briefing --dry-run uninstall` first to see the exact actions.

What it does (idempotent):
  1. unlinks every registered project (see `briefing unlink --help`)
  2. runs every adapter in remove mode: hub symlinks go away, any
     .pre-briefing.bak backups are restored, Hermes memory is copied back
     to real files, and the generated SOUL.md section is stripped
  3. removes the ~/.local/bin/briefing symlink
  4. removes the state directory (hub registration, project registry)

This repo is NEVER touched: your directions, memory, and skills stay
committed here. Delete the clone yourself if you want it gone too.
`briefing install` puts everything back.
EOF
}

cmd_uninstall() {
  # 1. Projects first, while the registry still exists
  if [[ -f "$REG" ]]; then
    local p
    while IFS= read -r p; do
      ( cmd_unlink "$p" ) || bad "unlink failed: $p"
    done < "$REG"
  fi

  # 2. Per-agent global teardown
  local a
  for a in "$HUB"/adapters/*.sh; do
    bash "$a" remove
  done

  # 3. PATH symlink (only if it is ours)
  if [[ "$(readlink "$HOME/.local/bin/briefing" 2>/dev/null)" == "$HUB/bin/briefing" ]]; then
    run rm "$HOME/.local/bin/briefing"
  fi

  # 4. Machine-local state
  if [[ -d "$STATE_DIR" ]]; then
    run rm -rf "$STATE_DIR"
  fi

  if [[ "$FAIL" != 0 ]]; then
    die "uninstall finished with errors, see messages above"
  fi
  info "uninstall: done. This repo ($HUB) was not touched - your directions,"
  info "memory, and skills are still committed there. Delete the clone yourself"
  info "if you no longer want it on this machine."
}
