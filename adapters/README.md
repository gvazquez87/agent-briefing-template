# Adapters

An adapter wires one agent to this repo. `briefing install` runs every
`adapters/*.sh` (except `_lib.sh`), so adding support for a new agent means
adding one file here. No registration, no config.

## The contract

Each adapter must:

1. **Exit 0 silently when its agent is not installed.** The standard opener:

   ```bash
   command -v myagent >/dev/null || exit 0
   ```

2. **Be idempotent.** `briefing install` runs on every sync, on every machine,
   forever. Running an adapter twice must be the same as running it once.

3. **Derive all paths.** The hub location comes from the script's own position
   (`HUB="$(cd "$(dirname "$0")/.." && pwd)"`), the user's home from `$HOME`.
   Never hardcode a clone location or a username.

4. **Never destroy user files.** Use the `link` helper from `_lib.sh`: if the
   destination is a real file or directory, it is moved to a
   `.pre-briefing.bak` backup before the symlink is created.

5. **Only touch its own agent's config.** An adapter for agent X writes under
   X's config directories (and, when adopting existing memory, under this
   repo's `memory/`). Nothing else.

6. **Prefer symlinks over copies.** Symlinks never go stale. Use a generated
   copy only when the agent cannot follow a symlink or needs a merged file
   (see `hermes.sh`, which regenerates a marked section of `SOUL.md`).

## Delivery patterns

- **Symlink** (`vibe.sh`): the agent reads a file that is a symlink into this
  repo. Zero staleness, the cheapest option. Use whenever the agent tolerates it.
- **Marked section** (`hermes.sh`): the agent owns a file the user also edits.
  Keep everything above a marker comment, regenerate everything below it.
- **Generated copy** (`briefing link`, for Cursor): the agent needs a file in
  a specific format inside each project. Generate it, gitignore it in the
  project, and let `briefing install` / `briefing sync` keep it fresh.
- **Memory capture** (`hermes.sh`): when the agent keeps its own memory files,
  adopt them on first run (copy into `memory/<agent>/`), then symlink them
  back so future writes land in this repo and travel through git.
