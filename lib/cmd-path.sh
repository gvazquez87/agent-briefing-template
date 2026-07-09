# briefing path - print where this repo lives

cmd_path_help() {
  cat <<'EOF'
briefing path - print the absolute path of the briefing repo

Usage:
  briefing path

Skills and directions reference the repo through this command so nothing
needs to hardcode a clone location.
EOF
}

cmd_path() { echo "$HUB"; }
