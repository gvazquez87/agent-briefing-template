# ------------------------------------------------
# common.sh - shared helpers for briefing commands and adapters
#
# Environment:
#   DRY_RUN = 0 | 1   (1: print mutating actions instead of performing them)
# ------------------------------------------------

# run CMD... - execute a mutating command, or print it when DRY_RUN=1.
# Wrap every state-changing call in run so dry runs stay faithful.
run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'would run: %s\n' "$*"
  else
    "$@"
  fi
}

# link SRC DST - safe symlink that never destroys a real file or directory:
# an existing non-symlink DST is preserved as DST.pre-briefing.bak first.
link() {
  if [[ -e "$2" && ! -L "$2" ]]; then
    run mv "$2" "$2.pre-briefing.bak"
  fi
  run ln -sfn "$1" "$2"
}

# write_file DST - write stdin to DST, honoring dry runs (input is discarded
# but still consumed, so pipelines behave identically in both modes).
write_file() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'would write: %s\n' "$1"
    cat > /dev/null
  else
    cat > "$1"
  fi
}
