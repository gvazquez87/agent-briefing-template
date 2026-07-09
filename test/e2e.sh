#!/usr/bin/env bash
# End-to-end test in an isolated HOME with fake agents. Content-agnostic:
# it verifies the machinery against whatever directions/memory/skills the
# repo carries, so the same file passes in the template and in personal
# copies. Touches nothing outside a temp directory. Usage: test/e2e.sh
set -euo pipefail
TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d /tmp/briefing-e2e.XXXXXX)"
trap 'rm -rf "$T"' EXIT

export HOME="$T"
export BRIEFING_COLOR=never
unset XDG_STATE_HOME XDG_CONFIG_HOME || true

# Fake agents on PATH so both adapters activate
mkdir -p "$T/fakebin"
printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/vibe"
printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/hermes"
chmod +x "$T/fakebin/vibe" "$T/fakebin/hermes"
export PATH="$T/fakebin:$PATH"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "  ok: $1"; }

echo "== 1. clone like a real user =="
git clone -q "$TEMPLATE" "$T/.local/briefing"
HUB="$T/.local/briefing"
DIRECTIONS="$HUB/directions/AGENTS.md"

echo "== 2. help and dry run before anything exists =="
"$HUB/bin/briefing" --help | grep -q 'install' || fail "top-level help"
"$HUB/bin/briefing" install --help | grep -q 'idempotent' || fail "per-command help"
"$HUB/bin/briefing" --dry-run install > "$T/dryrun.out"
grep -q 'would' "$T/dryrun.out" || fail "dry run printed no actions"
[ ! -e "$T/.local/bin/briefing" ] || fail "dry run created the PATH symlink"
[ ! -e "$T/.vibe" ] || fail "dry run created ~/.vibe"
[ ! -e "$T/.local/state/briefing" ] || fail "dry run created state dir"
pass "help works; dry run mutates nothing"

echo "== 3. first install =="
"$HUB/bin/briefing" install

[ "$(readlink "$T/.local/bin/briefing")" = "$HUB/bin/briefing" ] || fail "briefing not on PATH"
pass "briefing symlinked into ~/.local/bin"
[ "$(cat "$T/.local/state/briefing/hub")" = "$HUB" ] || fail "hub state file wrong"
[ "$("$T/.local/bin/briefing" path)" = "$HUB" ] || fail "briefing path wrong via symlink"
pass "hub path recorded and resolvable through the symlink"
[ "$(readlink "$T/.vibe/AGENTS.md")" = "$DIRECTIONS" ] || fail "vibe AGENTS.md"
[ "$(readlink "$T/.vibe/skills")" = "$HUB/skills" ] || fail "vibe skills"
pass "vibe wired"
[ "$(readlink "$T/.hermes/skills/briefing")" = "$HUB/skills" ] || fail "hermes skills"
[ "$(readlink "$T/.hermes/memories/MEMORY.md")" = "$HUB/memory/hermes/MEMORY.md" ] || fail "hermes MEMORY.md"
awk 'f{print} index($0, "briefing directions below"){f=1}' "$T/.hermes/SOUL.md" \
  | sed '1{/^$/d}' | diff -q - "$DIRECTIONS" >/dev/null || fail "SOUL.md directions section"
pass "hermes wired (skills, memory capture, SOUL.md section)"

echo "== 4. SOUL.md: identity preserved, old markers migrated, idempotent =="
printf 'my identity line\n\n<!-- briefing directions below - some OLD marker wording -->\n\nstale old directions copy\n' > "$T/.hermes/SOUL.md"
"$HUB/bin/briefing" install >/dev/null
head -1 "$T/.hermes/SOUL.md" | grep -q 'my identity line' || fail "identity lost"
grep -q 'stale old directions copy' "$T/.hermes/SOUL.md" && fail "old directions not replaced"
[ "$(grep -c 'briefing directions below' "$T/.hermes/SOUL.md")" = "1" ] || fail "duplicate markers"
cp "$T/.hermes/SOUL.md" "$T/soul.run1"
"$HUB/bin/briefing" install >/dev/null
diff -q "$T/soul.run1" "$T/.hermes/SOUL.md" >/dev/null || fail "SOUL.md not idempotent"
pass "SOUL.md keeps identity, migrates old markers, is idempotent"

echo "== 5. memory adoption: pre-existing hermes memory survives =="
rm "$T/.hermes/memories/USER.md"
echo "existing user fact" > "$T/.hermes/memories/USER.md"
: > "$HUB/memory/hermes/USER.md"   # empty dst triggers adoption
"$HUB/bin/briefing" install >/dev/null
grep -q 'existing user fact' "$HUB/memory/hermes/USER.md" || fail "memory not adopted"
[ -L "$T/.hermes/memories/USER.md" ] || fail "memory not re-linked after adoption"
pass "existing hermes memory adopted into repo"
git -C "$HUB" checkout -q -- . 2>/dev/null || true

echo "== 6. link a project =="
P="$T/myproject"
mkdir -p "$P"
echo "# myproject rules" > "$P/AGENTS.md"
FIRST_SKILL="$(basename "$(find "$HUB/skills" -mindepth 1 -maxdepth 1 -type d | sort | head -1)")"
[ -n "$FIRST_SKILL" ] || fail "repo has no skills to test with"
echo "$FIRST_SKILL" > "$P/.briefing-skills"
"$T/.local/bin/briefing" link "$P"

[ "$(readlink "$P/HERMES.md")" = "$P/AGENTS.md" ] || fail "HERMES.md mirror"
pass "HERMES.md mirrors AGENTS.md"
[ "$(readlink "$P/.vibe/skills/$FIRST_SKILL")" = "$HUB/skills/$FIRST_SKILL" ] || fail "vibe project skill"
[ "$(readlink "$P/.cursor/skills/$FIRST_SKILL")" = "$HUB/skills/$FIRST_SKILL" ] || fail "cursor project skill"
pass "manifest skills linked for vibe and cursor ($FIRST_SKILL)"
head -1 "$P/.cursor/rules/briefing.mdc" | grep -qx -- '---' || fail "mdc frontmatter"
tail -n +5 "$P/.cursor/rules/briefing.mdc" | diff -q - "$DIRECTIONS" >/dev/null || fail "mdc content"
pass "briefing.mdc generated with directions verbatim"
grep -qxF "$P" "$T/.local/state/briefing/linked-projects" || fail "project not registered"
pass "project registered"

echo "== 7. manifest pruning: removed skill gets unlinked =="
mkdir -p "$HUB/skills/tempskill"; echo x > "$HUB/skills/tempskill/SKILL.md"
printf '%s\ntempskill\n' "$FIRST_SKILL" > "$P/.briefing-skills"
"$T/.local/bin/briefing" link "$P" >/dev/null
[ -L "$P/.vibe/skills/tempskill" ] || fail "tempskill not linked"
printf '%s\n' "$FIRST_SKILL" > "$P/.briefing-skills"
"$T/.local/bin/briefing" link "$P" >/dev/null
[ ! -e "$P/.vibe/skills/tempskill" ] || fail "tempskill not pruned"
pass "manifest pruning works"
rm -rf "$HUB/skills/tempskill"

echo "== 8. unknown skill rejected =="
printf 'no-such-skill\n' > "$P/.briefing-skills"
if "$T/.local/bin/briefing" link "$P" >/dev/null 2>&1; then fail "unknown skill accepted"; fi
pass "unknown skill rejected"
printf '%s\n' "$FIRST_SKILL" > "$P/.briefing-skills"
"$T/.local/bin/briefing" link "$P" >/dev/null

echo "== 9. install re-links registered projects =="
rm "$P/.cursor/rules/briefing.mdc"
"$T/.local/bin/briefing" install >/dev/null
[ -f "$P/.cursor/rules/briefing.mdc" ] || fail "project not re-linked by install"
pass "install re-links registered projects"

echo "== 10. status exits 0 when healthy =="
"$T/.local/bin/briefing" status || fail "status reported problems (exit $?)"
pass "status clean"

echo "== 11. status detects breakage, install repairs =="
rm "$T/.vibe/AGENTS.md"
if "$T/.local/bin/briefing" status >/dev/null 2>&1; then fail "status missed broken vibe link"; fi
pass "status exits non-zero on broken wiring"
"$T/.local/bin/briefing" install >/dev/null
"$T/.local/bin/briefing" status >/dev/null || fail "repair did not restore health"
pass "install repairs, status green again"

echo "== 12. safe-link backup: real file preserved =="
rm "$T/.vibe/AGENTS.md"
echo "precious user content" > "$T/.vibe/AGENTS.md"
"$T/.local/bin/briefing" install >/dev/null
grep -q 'precious user content' "$T/.vibe/AGENTS.md.pre-briefing.bak" || fail "real file not backed up"
pass "real files backed up as .pre-briefing.bak, never destroyed"

echo "== 13. dry-run link mutates nothing =="
P2="$T/otherproject"
mkdir -p "$P2"
echo "# rules" > "$P2/AGENTS.md"
"$T/.local/bin/briefing" --dry-run link "$P2" > "$T/dryrun2.out"
grep -q 'would' "$T/dryrun2.out" || fail "dry-run link printed no actions"
[ ! -e "$P2/.cursor" ] || fail "dry-run link created .cursor"
[ ! -e "$P2/HERMES.md" ] || fail "dry-run link created HERMES.md"
grep -qxF "$P2" "$T/.local/state/briefing/linked-projects" && fail "dry-run link registered project"
pass "dry-run link mutates nothing"

echo
echo "ALL TESTS PASSED"
