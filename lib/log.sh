# ------------------------------------------------
# log.sh - color output helpers, shared by every briefing command and adapter
#
# Environment:
#   BRIEFING_COLOR = auto | always | never   (default auto: color only on a tty)
# ------------------------------------------------

: "${BRIEFING_COLOR:=auto}"
if [[ "$BRIEFING_COLOR" == "always" || ( "$BRIEFING_COLOR" == "auto" && -t 1 ) ]]; then
  C_RESET=$'\e[0m'; C_DIM=$'\e[2m'
  C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'
else
  C_RESET= C_DIM= C_GREEN= C_YELLOW= C_RED=
fi

# FAIL accumulates across ok/bad/stale so `briefing status` can exit non-zero
FAIL=0
ok()    { printf '  %s ok  %s %s\n' "$C_GREEN"  "$C_RESET" "$1"; }
bad()   { printf '  %s BAD %s %s\n' "$C_RED"    "$C_RESET" "$1"; FAIL=1; }
stale() { printf '  %sstale%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; FAIL=1; }
skip()  { printf '  %s  -  %s %s\n' "$C_DIM"    "$C_RESET" "$1"; }
info()  { printf '%s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
die()   { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; exit 1; }
