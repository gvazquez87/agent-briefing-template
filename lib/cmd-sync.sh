# briefing sync - commit memory, pull, reinstall, push

source "$HUB/lib/cmd-install.sh"

cmd_sync_help() {
  cat <<'EOF'
briefing sync - bring this machine and the repo in step

Usage:
  briefing [-n|--dry-run] sync [commit-message]

What it does:
  1. commits any changes under memory/ (message defaults to the date);
     other changes are left alone for you to review and commit yourself
  2. git pull --rebase --autostash
  3. re-runs install (re-wires agents, re-links registered projects)
  4. git push

Safe to run at any time, from cron or by hand.
EOF
}

cmd_sync() {
  cd "$HUB"
  if [[ -n "$(git status --porcelain memory/)" ]]; then
    run git add memory/
    run git commit -m "memory: ${1:-update $(date +%F)}"
  fi
  run git pull --rebase --autostash
  cmd_install
  run git push
}
