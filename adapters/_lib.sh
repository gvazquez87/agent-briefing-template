# shared helper: safe symlink that never nests into an existing real dir.
# If the destination is a real file/dir (not a symlink), it is preserved as
# a .pre-briefing.bak backup instead of being overwritten.
link() {
  if [ -e "$2" ] && [ ! -L "$2" ]; then mv "$2" "$2.pre-briefing.bak"; fi
  ln -sfn "$1" "$2"
}
