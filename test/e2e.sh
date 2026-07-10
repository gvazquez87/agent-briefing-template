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

# Fake agents on PATH so all adapters (and project-level delivery, which is
# gated on agent presence) activate
mkdir -p "$T/fakebin"
for a in vibe hermes claude cursor; do
  printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/$a"
  chmod +x "$T/fakebin/$a"
done
export PATH="$T/fakebin:$PATH"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "  ok: $1"; }
# print FILE with a guaranteed final newline; generated copies are built from
# this normalized form (see emit_text in lib/common.sh)
norm() { awk 1 "$1"; }

echo "== 1. clone like a real user =="
git clone -q "$TEMPLATE" "$T/.local/agent-briefing"
HUB="$T/.local/agent-briefing"
# A clone only carries committed state; bring over uncommitted changes and
# untracked (non-ignored) files so the test always exercises the working
# tree being edited, not stale HEAD.
if ! git -C "$TEMPLATE" diff --quiet HEAD; then
  git -C "$TEMPLATE" diff HEAD | git -C "$HUB" apply
fi
git -C "$TEMPLATE" ls-files --others --exclude-standard | while IFS= read -r f; do
  mkdir -p "$HUB/$(dirname "$f")"
  cp "$TEMPLATE/$f" "$HUB/$f"
done
if [ -n "$(git -C "$HUB" status --porcelain)" ]; then
  git -C "$HUB" add -A
  git -C "$HUB" -c user.email=e2e@test -c user.name=e2e commit -qm "e2e: uncommitted working tree changes"
fi
# status compares HEAD to @{upstream}. Local-path clones (and shallow CI
# checkouts) often lack tracking; point origin at HEAD so the repo check is green.
branch="$(git -C "$HUB" branch --show-current)"
if [[ -z "$branch" ]]; then
  git -C "$HUB" checkout -qb e2e-main
  branch=e2e-main
fi
git -C "$HUB" update-ref "refs/remotes/origin/$branch" "$(git -C "$HUB" rev-parse HEAD)"
git -C "$HUB" branch -u "origin/$branch"
DIRECTIONS="$HUB/directions/AGENTS.md"

echo "== 2. help and dry run before anything exists =="
"$HUB/bin/briefing" --help | grep -q 'install' || fail "top-level help"
[ "$("$HUB/bin/briefing" --version)" = "briefing $(tr -d '[:space:]' < "$HUB/VERSION")" ] || fail "--version"
pass "--version prints VERSION file"
"$HUB/bin/briefing" install --help | grep -q 'idempotent' || fail "per-command help"
"$HUB/bin/briefing" --dry-run install > "$T/dryrun.out"
grep -q 'would' "$T/dryrun.out" || fail "dry run printed no actions"
[ ! -e "$T/.local/bin/briefing" ] || fail "dry run created the PATH symlink"
[ ! -e "$T/.vibe" ] || fail "dry run created ~/.vibe"
[ ! -e "$T/.local/state/briefing" ] || fail "dry run created state dir"
# The flag must also work after the command (used to be silently ignored,
# turning an intended dry run into a real install)
"$HUB/bin/briefing" install --dry-run > "$T/dryrun-after.out"
grep -q 'would' "$T/dryrun-after.out" || fail "post-command --dry-run printed no actions"
[ ! -e "$T/.local/bin/briefing" ] || fail "post-command --dry-run performed a real install"
if "$HUB/bin/briefing" install --bogus-flag >/dev/null 2>&1; then fail "unknown option accepted"; fi
pass "help works; dry run mutates nothing (flag accepted on either side of the command)"

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
[ "$(readlink "$T/.claude/CLAUDE.md")" = "$DIRECTIONS" ] || fail "claude CLAUDE.md"
CSKILL="$(basename "$(find "$HUB/skills" -mindepth 1 -maxdepth 1 -type d | sort | head -1)")"
[ "$(readlink "$T/.claude/skills/$CSKILL")" = "$HUB/skills/$CSKILL" ] || fail "claude skill link"
pass "claude wired (CLAUDE.md, per-skill links)"
[ "$(readlink "$T/.hermes/skills/briefing")" = "$HUB/skills" ] || fail "hermes skills"
[ "$(readlink "$T/.hermes/memories/MEMORY.md")" = "$HUB/memory/hermes/MEMORY.md" ] || fail "hermes MEMORY.md"
awk 'f && $0 !~ /^<!-- briefing-sha256/ {print} index($0, "briefing directions below"){f=1}' "$T/.hermes/SOUL.md" \
  | sed '1{/^$/d;}' | diff -q - <(norm "$DIRECTIONS") >/dev/null || fail "SOUL.md directions section"
grep -q '^<!-- briefing-sha256: [0-9a-f]* -->$' "$T/.hermes/SOUL.md" || fail "SOUL.md sha stamp missing"
pass "hermes wired (skills, memory capture, SOUL.md section with sha stamp)"

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
[ "$(readlink "$P/.claude/skills/$FIRST_SKILL")" = "$HUB/skills/$FIRST_SKILL" ] || fail "claude project skill"
[ "$(readlink "$P/CLAUDE.md")" = "$P/AGENTS.md" ] || fail "CLAUDE.md mirror"
pass "manifest skills linked for vibe, cursor, and claude ($FIRST_SKILL); CLAUDE.md mirror"
head -1 "$P/.cursor/rules/briefing.mdc" | grep -qx -- '---' || fail "mdc frontmatter"
awk 'body{print;next} /^---$/ && ++n==2 {body=1}' "$P/.cursor/rules/briefing.mdc" \
  | diff -q - <(norm "$DIRECTIONS") >/dev/null || fail "mdc content"
grep -q "^briefing-hub: $HUB\$" "$P/.cursor/rules/briefing.mdc" || fail "mdc provenance: hub"
grep -q '^briefing-version: .' "$P/.cursor/rules/briefing.mdc" || fail "mdc provenance: version"
grep -q '^briefing-sha256: [0-9a-f]' "$P/.cursor/rules/briefing.mdc" || fail "mdc provenance: sha256"
pass "briefing.mdc generated with directions verbatim and provenance stamp"
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
# a project's own committed CLAUDE.md must never be replaced by the mirror
echo "own claude rules" > "$P2/CLAUDE.md"
"$T/.local/bin/briefing" link "$P2" >/dev/null
[ ! -L "$P2/CLAUDE.md" ] || fail "real CLAUDE.md replaced by mirror"
grep -q 'own claude rules' "$P2/CLAUDE.md" || fail "real CLAUDE.md content lost"
"$T/.local/bin/briefing" status >/dev/null || fail "status not green with project-own CLAUDE.md"
"$T/.local/bin/briefing" unlink "$P2" >/dev/null
grep -q 'own claude rules' "$P2/CLAUDE.md" || fail "unlink removed the project's own CLAUDE.md"
pass "a real committed CLAUDE.md survives link and unlink"

echo "== 14. install survives one broken project =="
REGFILE="$T/.local/state/briefing/linked-projects"
P3="$T/brokenproject"
mkdir -p "$P3"
printf 'no-such-skill\n' > "$P3/.briefing-skills"
# register the broken project FIRST so a healthy one comes after it
printf '%s\n' "$P3" | cat - "$REGFILE" > "$REGFILE.tmp" && mv "$REGFILE.tmp" "$REGFILE"
rm "$P/.cursor/rules/briefing.mdc"
if "$T/.local/bin/briefing" install > "$T/install-broken.out" 2>&1; then
  fail "install with a broken project exited 0"
fi
grep -q "link failed: $P3" "$T/install-broken.out" || fail "broken project not reported"
[ -f "$P/.cursor/rules/briefing.mdc" ] || fail "healthy project not re-linked past the broken one"
pass "install reports the broken project and still re-links the rest"
grep -vxF "$P3" "$REGFILE" > "$REGFILE.tmp" && mv "$REGFILE.tmp" "$REGFILE"
rm -rf "$P3"

echo "== 15. status tells wrong-hub links apart from missing ones =="
mkdir -p "$T/otherhub/skills/$FIRST_SKILL"
ln -sfn "$T/otherhub/skills/$FIRST_SKILL" "$P/.vibe/skills/$FIRST_SKILL"
"$T/.local/bin/briefing" status > "$T/status-wronghub.out" 2>&1 || true
grep -q "skill $FIRST_SKILL linked to another hub" "$T/status-wronghub.out" || fail "wrong-hub skill link not distinguished"
grep -q "skill $FIRST_SKILL not linked" "$T/status-wronghub.out" && fail "wrong-hub skill link misreported as missing"
# portable in-place edit (BSD sed's -i takes a mandatory suffix argument)
MDC="$P/.cursor/rules/briefing.mdc"
sed 's|^briefing-hub: .*|briefing-hub: /some/other/hub|' "$MDC" > "$MDC.tmp" && mv "$MDC.tmp" "$MDC"
"$T/.local/bin/briefing" status > "$T/status-foreignmdc.out" 2>&1 || true
grep -q 'briefing.mdc generated by another hub: /some/other/hub' "$T/status-foreignmdc.out" || fail "foreign-hub mdc not flagged"
"$T/.local/bin/briefing" link "$P" >/dev/null
"$T/.local/bin/briefing" status >/dev/null || fail "relink did not repair wrong-hub artifacts"
pass "status names the foreign hub; relink repairs"

echo "== 16. a second checkout cannot masquerade as the hub =="
git clone -q "$HUB" "$T/clone2"
if "$T/clone2/bin/briefing" status >/dev/null 2>"$T/identity.err"; then
  fail "status from an unregistered checkout did not refuse"
fi
grep -q 'not the registered hub' "$T/identity.err" || fail "identity refusal message missing"
[ "$("$T/clone2/bin/briefing" path)" = "$T/clone2" ] || fail "path should work from any checkout"
pass "unregistered checkout refused for status; path still answers"

echo "== 17. install adopts a new checkout explicitly, then all is green =="
"$T/clone2/bin/briefing" install > "$T/adopt.out" 2>&1 || fail "adopting install failed"
grep -q "adopting $T/clone2" "$T/adopt.out" || fail "adoption notice missing"
[ "$(cat "$T/.local/state/briefing/hub")" = "$T/clone2" ] || fail "hub state not adopted"
"$T/clone2/bin/briefing" status >/dev/null || fail "status not green after adoption"
if "$HUB/bin/briefing" status >/dev/null 2>&1; then
  fail "old hub still accepted after adoption"
fi
pass "install adopts the new checkout; old checkout is refused afterwards"

echo "== 18. adopt imports existing instruction files =="
"$HUB/bin/briefing" install >/dev/null   # re-adopt the original hub
if "$T/clone2/bin/briefing" adopt >/dev/null 2>&1; then
  fail "adopt from an unregistered checkout did not refuse"
fi
pass "adopt refused from an unregistered checkout"
mkdir -p "$T/.claude" "$T/.codex"
# ~/.claude/CLAUDE.md is a hub symlink by now; replace it with a real
# pre-existing file so the scan has something genuine to import
rm -f "$T/.claude/CLAUDE.md"
printf 'claude rule one\n' > "$T/.claude/CLAUDE.md"
: > "$T/.codex/AGENTS.md"                # empty: must be skipped
"$HUB/bin/briefing" --dry-run adopt > "$T/adopt-dry.out"
grep -q "would adopt: $T/.claude/CLAUDE.md" "$T/adopt-dry.out" || fail "dry-run adopt printed nothing"
grep -q 'claude rule one' "$DIRECTIONS" && fail "dry-run adopt mutated directions"
"$HUB/bin/briefing" adopt > "$T/adopt1.out"
grep -q 'claude rule one' "$DIRECTIONS" || fail "adopt did not import content"
grep -q "adopted from $T/.claude/CLAUDE.md on" "$DIRECTIONS" || fail "adoption marker missing"
grep -q "adopted from $T/.codex/AGENTS.md" "$DIRECTIONS" && fail "empty file adopted"
# the vibe backup that install preserved in section 12 must be found by the scan
grep -q 'precious user content' "$DIRECTIONS" || fail "vibe .pre-briefing.bak not adopted"
# the live ~/.vibe/AGENTS.md is a hub symlink by now and must be skipped
grep -q "adopted from $T/.vibe/AGENTS.md on" "$DIRECTIONS" && fail "vibe hub symlink adopted by scan"
# hermes SOUL.md: the identity section (from section 4) is adopted, the
# generated directions section below the marker is not
grep -q "adopted from $T/.hermes/SOUL.md on" "$DIRECTIONS" || fail "SOUL.md identity not adopted"
grep -q 'my identity line' "$DIRECTIONS" || fail "SOUL.md identity content missing"
grep -q 'briefing directions below' "$DIRECTIONS" && fail "generated SOUL.md section adopted back"
"$HUB/bin/briefing" adopt >/dev/null
[ "$(grep -c 'claude rule one' "$DIRECTIONS")" = "1" ] || fail "adopt not idempotent"
grep -q 'claude rule one' "$T/.claude/CLAUDE.md" || fail "adopt modified the source file"
[ ! -L "$T/.claude/CLAUDE.md" ] || fail "adopt replaced the source with a symlink"
pass "adopt imports once, skips empty files, never touches sources"
echo "extra rules" > "$T/extra.md"
"$HUB/bin/briefing" adopt "$T/extra.md" >/dev/null
grep -q 'extra rules' "$DIRECTIONS" || fail "explicit file not adopted"
"$HUB/bin/briefing" adopt "$T/.vibe/AGENTS.md" > "$T/adopt-managed.out"
grep -q "already managed" "$T/adopt-managed.out" || fail "hub symlink not skipped"
grep -q "adopted from $T/.vibe/AGENTS.md on" "$DIRECTIONS" && fail "hub symlink adopted"
pass "explicit files adopted; symlinks into the hub skipped"
git -C "$HUB" checkout -q -- directions/AGENTS.md

echo "== 19. status: hand-edited briefing.mdc is BAD, outdated is stale =="
"$HUB/bin/briefing" link "$P" >/dev/null
echo "sneaky manual edit" >> "$P/.cursor/rules/briefing.mdc"
if "$HUB/bin/briefing" status > "$T/status-handedit.out" 2>&1; then
  fail "status missed a hand-edited briefing.mdc"
fi
grep -q 'briefing.mdc HAND-EDITED' "$T/status-handedit.out" || fail "hand-edited mdc not called out"
"$HUB/bin/briefing" link "$P" >/dev/null
echo "- a brand new direction" >> "$DIRECTIONS"
"$HUB/bin/briefing" status > "$T/status-outdated.out" 2>&1 || true
grep -q 'briefing.mdc HAND-EDITED' "$T/status-outdated.out" && fail "outdated mdc misreported as hand-edited"
grep -Eq 'briefing.mdc (outdated|differs)' "$T/status-outdated.out" || fail "outdated mdc not reported stale"
git -C "$HUB" checkout -q -- directions/AGENTS.md
pass "status tells hand-edited apart from outdated (briefing.mdc)"

echo "== 20. status: hand-edited SOUL.md section is BAD, install repairs =="
"$HUB/bin/briefing" install >/dev/null
echo "sneaky soul edit" >> "$T/.hermes/SOUL.md"
if "$HUB/bin/briefing" status > "$T/status-soul.out" 2>&1; then
  fail "status missed a hand-edited SOUL.md section"
fi
grep -q 'SOUL.md directions section HAND-EDITED' "$T/status-soul.out" || fail "hand-edited SOUL.md not called out"
echo "- a brand new direction" >> "$DIRECTIONS"
"$HUB/bin/briefing" install >/dev/null   # regenerates the section from new directions
"$HUB/bin/briefing" status > "$T/status-soul-stale.out" 2>&1 || true
grep -q 'SOUL.md directions section HAND-EDITED' "$T/status-soul-stale.out" && fail "current SOUL.md misreported as hand-edited"
git -C "$HUB" checkout -q -- directions/AGENTS.md
"$HUB/bin/briefing" status > "$T/status-soul-outdated.out" 2>&1 || true
grep -q 'SOUL.md directions section HAND-EDITED' "$T/status-soul-outdated.out" && fail "outdated SOUL.md misreported as hand-edited"
grep -q 'stale.*SOUL.md directions section' "$T/status-soul-outdated.out" || fail "outdated SOUL.md not reported stale"
"$HUB/bin/briefing" install >/dev/null
"$HUB/bin/briefing" status >/dev/null || fail "install did not restore health after drift tests"
pass "status tells hand-edited apart from outdated (SOUL.md); install repairs"

echo "== 20b. directions file missing its final newline stays healthy =="
# an editor stripping the trailing newline must break neither generation nor
# drift detection (copies and sha stamps are newline-normalized)
printf '%s' "$(cat "$DIRECTIONS")" > "$DIRECTIONS.tmp" && mv "$DIRECTIONS.tmp" "$DIRECTIONS"
"$HUB/bin/briefing" install >/dev/null
"$HUB/bin/briefing" link "$P" >/dev/null
awk 'f && $0 !~ /^<!-- briefing-sha256/ {print} index($0, "briefing directions below"){f=1}' "$T/.hermes/SOUL.md" \
  | sed '1{/^$/d;}' | diff -q - <(norm "$DIRECTIONS") >/dev/null || fail "SOUL.md section wrong without final newline"
# the strip may dirty the repo (a stale, non-zero status); only the
# generated-copy lines matter here
"$HUB/bin/briefing" status > "$T/status-nonl.out" 2>&1 || true
grep -q 'SOUL.md directions section current' "$T/status-nonl.out" || fail "SOUL.md section not current without final newline"
grep -q 'briefing.mdc current' "$T/status-nonl.out" || fail "briefing.mdc not current without final newline"
grep -q 'HAND-EDITED' "$T/status-nonl.out" && fail "missing final newline misreported as hand-edited"
git -C "$HUB" checkout -q -- directions/AGENTS.md
"$HUB/bin/briefing" install >/dev/null
"$HUB/bin/briefing" link "$P" >/dev/null
"$HUB/bin/briefing" status >/dev/null || fail "status not green after restoring the newline"
pass "missing final newline breaks neither generation nor drift detection"

echo "== 21. unlink detaches a project, leaves user files alone =="
"$HUB/bin/briefing" link "$P" >/dev/null   # ensure fully linked
"$HUB/bin/briefing" --dry-run unlink "$P" > "$T/unlink-dry.out"
grep -q 'would' "$T/unlink-dry.out" || fail "dry-run unlink printed no actions"
[ -f "$P/.cursor/rules/briefing.mdc" ] || fail "dry-run unlink removed briefing.mdc"
grep -qxF "$P" "$T/.local/state/briefing/linked-projects" || fail "dry-run unlink deregistered"
"$HUB/bin/briefing" unlink "$P" >/dev/null
[ ! -e "$P/.cursor/rules/briefing.mdc" ] || fail "briefing.mdc not removed"
[ ! -e "$P/.vibe/skills/$FIRST_SKILL" ] || fail "vibe skill link not removed"
[ ! -e "$P/.cursor/skills/$FIRST_SKILL" ] || fail "cursor skill link not removed"
[ ! -e "$P/.claude/skills/$FIRST_SKILL" ] || fail "claude skill link not removed"
[ ! -e "$P/.vibe" ] || fail "empty .vibe not pruned"
[ ! -e "$P/.claude" ] || fail "empty .claude not pruned"
[ ! -e "$P/HERMES.md" ] || fail "HERMES.md mirror not removed"
[ ! -e "$P/CLAUDE.md" ] || fail "CLAUDE.md mirror not removed"
[ -f "$P/AGENTS.md" ] || fail "unlink touched the project's AGENTS.md"
[ -f "$P/.briefing-skills" ] || fail "unlink touched .briefing-skills"
grep -qxF "$P" "$T/.local/state/briefing/linked-projects" && fail "project still registered"
"$HUB/bin/briefing" unlink "$P" >/dev/null || fail "unlink not idempotent"
"$HUB/bin/briefing" status >/dev/null || fail "status not green after unlink"
pass "unlink removes generated state, keeps committed files, deregisters"
# a foreign hub's briefing.mdc must survive an unlink
"$HUB/bin/briefing" link "$P" >/dev/null
MDC="$P/.cursor/rules/briefing.mdc"
sed 's|^briefing-hub: .*|briefing-hub: /some/other/hub|' "$MDC" > "$MDC.tmp" && mv "$MDC.tmp" "$MDC"
"$HUB/bin/briefing" unlink "$P" >/dev/null
[ -f "$P/.cursor/rules/briefing.mdc" ] || fail "foreign briefing.mdc removed"
rm "$P/.cursor/rules/briefing.mdc"
pass "unlink leaves a foreign hub's briefing.mdc alone"

echo "== 21b. project delivery gated on installed agents; ignore block =="
P4="$T/gatedproject"
mkdir -p "$P4"
git -C "$P4" init -q
echo "# rules" > "$P4/AGENTS.md"
printf '%s\n' "$FIRST_SKILL" > "$P4/.briefing-skills"
rm "$T/fakebin/claude"
hash -r 2>/dev/null || true
"$HUB/bin/briefing" link "$P4" > "$T/link-gated.out"
if command -v claude >/dev/null; then
  echo "  (claude present on this host; skipping absence assertions)"
else
  [ ! -e "$P4/.claude" ] || fail "claude skill links created without claude installed"
  [ ! -e "$P4/CLAUDE.md" ] || fail "CLAUDE.md mirror created without claude installed"
  grep -q 'claude not installed' "$T/link-gated.out" || fail "link did not report the skipped agent"
  "$HUB/bin/briefing" status >/dev/null || fail "status not green with claude absent"
fi
# vibe/cursor are still (fake-)installed, their delivery must be unaffected
[ -L "$P4/.vibe/skills/$FIRST_SKILL" ] || fail "vibe delivery broken by gating"
[ -f "$P4/.cursor/rules/briefing.mdc" ] || fail "cursor delivery broken by gating"
# generated files are ignored machine-locally, nothing shows up as untracked
grep -q '>>> briefing' "$P4/.git/info/exclude" || fail "exclude block not written"
for f in HERMES.md .vibe/skills/x .cursor/rules/briefing.mdc CLAUDE.md; do
  git -C "$P4" check-ignore -q "$f" || fail "$f not ignored via .git/info/exclude"
done
git -C "$P4" status --porcelain | grep -Eq 'HERMES|CLAUDE|\.vibe|\.cursor' \
  && fail "generated files leak into git status"
# installing the agent later: the next install re-links and grows the links
printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/claude"
chmod +x "$T/fakebin/claude"
hash -r 2>/dev/null || true
"$HUB/bin/briefing" install >/dev/null
[ "$(readlink "$P4/CLAUDE.md")" = "$P4/AGENTS.md" ] || fail "CLAUDE.md mirror not added after claude appeared"
[ "$(readlink "$P4/.claude/skills/$FIRST_SKILL")" = "$HUB/skills/$FIRST_SKILL" ] || fail "claude skill links not added after claude appeared"
git -C "$P4" status --porcelain | grep -q 'CLAUDE' && fail "late claude artifacts leak into git status"
pass "delivery skips absent agents; a later install grows their links; all ignored"
# unlink removes the ignore block again
"$HUB/bin/briefing" unlink "$P4" >/dev/null
grep -q '>>> briefing' "$P4/.git/info/exclude" 2>/dev/null && fail "exclude block not removed on unlink"
pass "unlink removes the .git/info/exclude block"
rm -rf "$P4"

echo "== 22. uninstall reverses install; reinstall brings it back =="
"$HUB/bin/briefing" link "$P" >/dev/null
echo "- memfact from repo" >> "$HUB/memory/hermes/MEMORY.md"
"$HUB/bin/briefing" --dry-run uninstall > "$T/uninst-dry.out"
grep -q 'would' "$T/uninst-dry.out" || fail "dry-run uninstall printed no actions"
[ -L "$T/.local/bin/briefing" ] || fail "dry-run uninstall removed the PATH symlink"
[ -d "$T/.local/state/briefing" ] || fail "dry-run uninstall removed the state dir"
"$HUB/bin/briefing" uninstall > "$T/uninst.out"
[ ! -e "$T/.local/bin/briefing" ] || fail "PATH symlink not removed"
[ ! -e "$T/.local/state/briefing" ] || fail "state dir not removed"
# vibe: the .pre-briefing.bak from section 12 comes back as the real file
[ ! -L "$T/.vibe/AGENTS.md" ] || fail "vibe AGENTS.md still a symlink"
grep -q 'precious user content' "$T/.vibe/AGENTS.md" || fail "vibe backup not restored"
[ ! -e "$T/.vibe/skills" ] || fail "vibe skills link not removed"
# claude: the backup taken when install re-wired after section 18 comes back
[ ! -L "$T/.claude/CLAUDE.md" ] || fail "claude CLAUDE.md still a symlink"
grep -q 'claude rule one' "$T/.claude/CLAUDE.md" || fail "claude backup not restored"
[ ! -e "$T/.claude/skills" ] || fail "claude skills dir not removed"
# hermes: memory materialized (repo held the only copy), identity kept
[ -f "$T/.hermes/memories/MEMORY.md" ] || fail "hermes MEMORY.md gone"
[ ! -L "$T/.hermes/memories/MEMORY.md" ] || fail "hermes MEMORY.md still a symlink"
grep -q 'memfact from repo' "$T/.hermes/memories/MEMORY.md" || fail "hermes memory content lost"
[ ! -e "$T/.hermes/skills/briefing" ] || fail "hermes skills mount not removed"
grep -q 'my identity line' "$T/.hermes/SOUL.md" || fail "SOUL.md identity lost"
grep -q 'briefing directions below' "$T/.hermes/SOUL.md" && fail "SOUL.md section not stripped"
# project unlinked as part of uninstall
[ ! -e "$P/HERMES.md" ] || fail "project not unlinked by uninstall"
# the repo itself is untouched
grep -q 'memfact from repo' "$HUB/memory/hermes/MEMORY.md" || fail "uninstall touched the repo"
pass "uninstall restores backups, materializes memory, strips SOUL.md, keeps the repo"
git -C "$HUB" checkout -q -- memory/
# clear the materialized copy too, or reinstall would adopt the test fact
# back into the (just-reverted) repo and leave the working tree dirty
: > "$T/.hermes/memories/MEMORY.md"
"$HUB/bin/briefing" uninstall >/dev/null || fail "uninstall not idempotent"
"$HUB/bin/briefing" install >/dev/null
"$HUB/bin/briefing" link "$P" >/dev/null
"$HUB/bin/briefing" status >/dev/null || fail "reinstall after uninstall not green"
pass "uninstall is idempotent; install + link bring everything back green"

echo
echo "ALL TESTS PASSED"
