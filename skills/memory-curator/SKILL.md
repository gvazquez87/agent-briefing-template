---
name: memory-curator
description: Consolidate the briefing memory files - dedupe, promote agent facts to canonical, flag contradictions. Run on demand.
---
# Memory curator

Curation pass over the briefing repo's memory/ directory. Resolve the repo
location first: `HUB="$(briefing path)"`. This is the ONE sanctioned
exception to the append-only rule: rewriting files here is allowed because
every change is reviewed as a git diff before commit.

1. Verify `git -C "$HUB" status --porcelain memory/` is clean.
   If not, stop and tell the user to commit or discard pending changes first;
   curation must be a diff of its own.
2. Read all of: memory/preferences.md, memory/projects.md, and every file
   under memory/hermes/ (if present).
3. Promote: any durable fact that exists only in an agent's own memory file
   (e.g. memory/hermes/) gets a bullet in preferences.md or projects.md
   (canonical is the superset).
4. Dedupe within preferences.md and projects.md: merge bullets stating the
   same fact in different wording. Keep the clearest phrasing; never drop
   information while merging.
5. Contradictions (between any two files): do NOT resolve. List them for the
   user and let them pick the truth; canonical files win by default.
6. Never invent facts. Every bullet you write must trace to an existing entry
   in one of the files read in step 2. Preserve TODO placeholder lines as-is.
7. Do not rewrite the agent-owned files under memory/hermes/; each agent owns
   its own format. Curate only the canonical files.
8. Apply the changes by actually editing the files with your file tools.
   Then RE-READ each file from disk and confirm the new content is really
   there. Never report success without this verification.
9. Finish by showing the output of `git -C "$HUB" diff memory/` (the real
   command output, not a reconstruction) and remind the user to run
   `briefing sync` to commit.
