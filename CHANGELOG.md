# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/gvazquez87/agent-briefing-template/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/gvazquez87/agent-briefing-template/releases/tag/v0.1.0
