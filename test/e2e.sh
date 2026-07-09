#!/usr/bin/env bash
# End-to-end test in an isolated HOME with fake agents. Safe to run anywhere:
# touches nothing outside a temp directory. Usage: test/e2e.sh
set -euo pipefail
TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d /tmp/briefing-e2e.XXXXXX)"
trap 'rm -rf "$T"' EXIT

export HOME="$T"
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

echo "== 2. first install =="
"$HUB/bin/briefing" install

[ "$(readlink "$T/.local/bin/briefing")" = "$HUB/bin/briefing" ] || fail "briefing not on PATH"
pass "briefing symlinked into ~/.local/bin"
[ "$(cat "$T/.local/state/briefing/hub")" = "$HUB" ] || fail "hub state file wrong"
pass "hub path recorded in XDG state"
[ "$(readlink "$T/.vibe/AGENTS.md")" = "$HUB/directions/AGENTS.md" ] || fail "vibe AGENTS.md"
[ "$(readlink "$T/.vibe/skills")" = "$HUB/skills" ] || fail "vibe skills"
pass "vibe wired"
[ "$(readlink "$T/.hermes/skills/briefing")" = "$HUB/skills" ] || fail "hermes skills"
[ "$(readlink "$T/.hermes/memories/MEMORY.md")" = "$HUB/memory/hermes/MEMORY.md" ] || fail "hermes MEMORY.md"
grep -q 'briefing directions below' "$T/.hermes/SOUL.md" || fail "SOUL.md marker"
grep -q '# Working with me' "$T/.hermes/SOUL.md" || fail "SOUL.md directions content"
pass "hermes wired (skills, memory capture, SOUL.md section)"

echo "== 3. memory adoption: pre-existing hermes memory survives =="
rm "$T/.hermes/memories/USER.md"
echo "existing user fact" > "$T/.hermes/memories/USER.md"
: > "$HUB/memory/hermes/USER.md"   # empty dst triggers adoption
"$HUB/bin/briefing" install >/dev/null
grep -q 'existing user fact' "$HUB/memory/hermes/USER.md" || fail "memory not adopted"
[ -L "$T/.hermes/memories/USER.md" ] || fail "memory not re-linked after adoption"
pass "existing hermes memory adopted into repo"
git -C "$HUB" checkout -q -- . 2>/dev/null || true

echo "== 4. link a project =="
P="$T/myproject"
mkdir -p "$P"
echo "# myproject rules" > "$P/AGENTS.md"
echo "memory-curator" > "$P/.briefing-skills"
"$T/.local/bin/briefing" link "$P"

[ "$(readlink "$P/HERMES.md")" = "$P/AGENTS.md" ] || fail "HERMES.md mirror"
pass "HERMES.md mirrors AGENTS.md"
[ "$(readlink "$P/.vibe/skills/memory-curator")" = "$HUB/skills/memory-curator" ] || fail "vibe project skill"
[ "$(readlink "$P/.cursor/skills/memory-curator")" = "$HUB/skills/memory-curator" ] || fail "cursor project skill"
pass "manifest skills linked for vibe and cursor"
head -1 "$P/.cursor/rules/briefing.mdc" | grep -qx -- '---' || fail "mdc frontmatter"
tail -n +5 "$P/.cursor/rules/briefing.mdc" | diff -q - "$HUB/directions/AGENTS.md" >/dev/null || fail "mdc content"
pass "briefing.mdc generated with directions verbatim"
grep -qxF "$P" "$T/.local/state/briefing/linked-projects" || fail "project not registered"
pass "project registered"

echo "== 5. manifest pruning: removed skill gets unlinked =="
mkdir -p "$HUB/skills/tempskill"; echo x > "$HUB/skills/tempskill/SKILL.md"
printf 'memory-curator\ntempskill\n' > "$P/.briefing-skills"
"$T/.local/bin/briefing" link "$P" >/dev/null
[ -L "$P/.vibe/skills/tempskill" ] || fail "tempskill not linked"
printf 'memory-curator\n' > "$P/.briefing-skills"
"$T/.local/bin/briefing" link "$P" >/dev/null
[ ! -e "$P/.vibe/skills/tempskill" ] || fail "tempskill not pruned"
pass "manifest pruning works"
rm -rf "$HUB/skills/tempskill"

echo "== 6. unknown skill rejected =="
printf 'no-such-skill\n' > "$P/.briefing-skills"
if "$T/.local/bin/briefing" link "$P" >/dev/null 2>&1; then fail "unknown skill accepted"; fi
pass "unknown skill rejected"
printf 'memory-curator\n' > "$P/.briefing-skills"
"$T/.local/bin/briefing" link "$P" >/dev/null

echo "== 7. install re-links registered projects =="
rm "$P/.cursor/rules/briefing.mdc"
"$T/.local/bin/briefing" install >/dev/null
[ -f "$P/.cursor/rules/briefing.mdc" ] || fail "project not re-linked by install"
pass "install re-links registered projects"

echo "== 8. status exits 0 when healthy =="
"$T/.local/bin/briefing" status || fail "status reported problems (exit $?)"
pass "status clean"

echo "== 9. status detects breakage, install repairs =="
rm "$T/.vibe/AGENTS.md"
if "$T/.local/bin/briefing" status >/dev/null 2>&1; then fail "status missed broken vibe link"; fi
pass "status exits non-zero on broken wiring"
"$T/.local/bin/briefing" install >/dev/null
"$T/.local/bin/briefing" status >/dev/null || fail "repair did not restore health"
pass "install repairs, status green again"

echo "== 10. safe-link backup: real file preserved =="
rm "$T/.vibe/AGENTS.md"
echo "precious user content" > "$T/.vibe/AGENTS.md"
"$T/.local/bin/briefing" install >/dev/null
grep -q 'precious user content' "$T/.vibe/AGENTS.md.pre-briefing.bak" || fail "real file not backed up"
pass "real files backed up as .pre-briefing.bak, never destroyed"

echo
echo "ALL TESTS PASSED"
