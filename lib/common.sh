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

# unwire DST SRC - inverse of link: remove DST when it is the symlink to SRC
# that link() created, then restore the .pre-briefing.bak backup that link()
# may have preserved. A DST that is not our symlink is never touched (unless
# it is absent and a backup is waiting to come back).
unwire() {
  if [[ "$(readlink "$1" 2>/dev/null)" == "$2" ]]; then
    run rm "$1"
    if [[ -e "$1.pre-briefing.bak" ]]; then
      run mv "$1.pre-briefing.bak" "$1"
    fi
  elif [[ ! -e "$1" && -e "$1.pre-briefing.bak" ]]; then
    run mv "$1.pre-briefing.bak" "$1"
  fi
}

# resolve_path FILE - follow the symlink chain of FILE itself, portably
# (macOS only gained `readlink -f` in 12.3). Directory components are kept
# logical, matching how $HUB and every symlink target are constructed.
resolve_path() {
  local p="$1" target
  while [[ -L "$p" ]]; do
    target="$(readlink "$p")"
    [[ "$target" == /* ]] || target="$(dirname "$p")/$target"
    p="$target"
  done
  printf '%s\n' "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
}

# hub_version - human-readable stamp of the hub's current state (tag, commit,
# dirty marker). Written into generated files so `status` can tell *why* a
# copy diverged instead of just reporting that it did.
hub_version() {
  git -C "$HUB" describe --tags --always --dirty 2>/dev/null || echo unknown
}

# hash_stdin - sha256 of stdin, first field only. Stamped into generated
# files at generation time so `status` can tell a hand-edited copy (body no
# longer matches its own stamp) from a merely outdated one.
hash_stdin() {
  if command -v sha256sum >/dev/null; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
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
