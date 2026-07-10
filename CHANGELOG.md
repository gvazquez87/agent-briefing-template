# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Generated copies and their sha256 stamps are newline-normalized, so a
  `directions/AGENTS.md` saved without a final newline is no longer
  misreported by `briefing status` as hand-edited (`emit_text` helper in
  `lib/common.sh`)

## [0.2.0] - 2026-07-10

### Added

- `briefing adopt [file...]`: import existing instruction files (e.g.
  `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`) into
  `directions/AGENTS.md` under review markers; idempotent, never touches
  the source files
- Hand-edit detection: generated artifacts (`briefing.mdc`, the SOUL.md
  directions section) carry a `briefing-sha256` stamp, and `briefing status`
  now reports a hand-edited copy as BAD (edits would be lost on the next
  install) instead of merely stale
- Supersede convention for append-only memory: append
  `(supersedes: "<old bullet>")` instead of editing; the `memory-curator`
  skill collapses the pairs and also flags rotted entries
- `briefing unlink <dir>`: inverse of `link` - removes generated files and
  hub-owned skill links from a project and deregisters it
- `briefing uninstall`: inverse of `install` - unlinks all projects, runs
  every adapter in remove mode (restores `.pre-briefing.bak` backups,
  copies Hermes memory back to real files, strips the generated SOUL.md
  section), removes PATH symlink and machine state; the repo is never
  touched
- Adapter contract rule 8 (remove mode) and a shared `unwire` helper in
  `lib/common.sh`
- Claude Code adapter: `~/.claude/CLAUDE.md` symlink, per-skill links in
  `~/.claude/skills/`, project `CLAUDE.md -> AGENTS.md` mirror (a real
  committed `CLAUDE.md` is never overwritten), `.claude/skills/` manifest
  delivery, status checks, and adopt/remove support
- CI workflow running the end-to-end tests on Linux and macOS for every
  push to main and every pull request

### Fixed

- macOS compatibility: replaced `readlink -f` (macOS < 12.3 lacks it) with
  a portable symlink-resolution loop, made sed usage BSD-compatible
  (`{...;}` block syntax, no `sed -i`), and trimmed BSD `wc` padding in
  status output

## [0.1.0] - 2026-07-10

### Added

- `briefing` CLI with `install`, `link`, `sync`, `status`, and `path` commands
- Per-command `--help` and global `--dry-run` support
- Adapters for Hermes, Vibe, and Cursor (global wiring plus per-project delivery)
- Hub identity: one registered hub per machine, explicit adopt-on-install
- Provenance-stamped `.cursor/rules/briefing.mdc` (`briefing-hub`, `briefing-version`)
- Append-only memory layout with Hermes memory adoption on install
- Self-contained end-to-end test (`test/e2e.sh`) in a throwaway HOME
- `VERSION` file and `briefing --version`

[Unreleased]: https://github.com/gvazquez87/agent-briefing-template/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/gvazquez87/agent-briefing-template/releases/tag/v0.2.0
[0.1.0]: https://github.com/gvazquez87/agent-briefing-template/releases/tag/v0.1.0
