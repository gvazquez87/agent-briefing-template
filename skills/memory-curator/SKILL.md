---
name: memory-curator
description: Consolidate the briefing memory files - resolve supersedes, dedupe, promote agent facts to canonical, flag rot and contradictions. Run on demand.
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
4. Supersedes: a bullet ending in (supersedes: "<quote>") replaces the older
   bullet it quotes. Delete the old bullet and drop the annotation from the
   new one - this is mechanical, no judgment needed. If the quoted bullet
   cannot be found, keep the annotation and list it for the user.
5. Dedupe within preferences.md and projects.md: merge bullets stating the
   same fact in different wording. Keep the clearest phrasing; never drop
   information while merging.
6. Rot detection: flag bullets that reference projects, tools, or paths that
   no longer appear anywhere else in memory/ or in the linked-projects
   registry ($XDG_STATE_HOME/briefing/linked-projects, default
   ~/.local/state/briefing/linked-projects). Propose their removal in the
   diff, but list every removal explicitly so the user can veto it before
   committing.
7. Contradictions (between any two files, and not resolved by a supersedes
   annotation): do NOT resolve. List them for the user and let them pick the
   truth; canonical files win by default.
8. Never invent facts. Every bullet you write must trace to an existing entry
   in one of the files read in step 2. Preserve TODO placeholder lines as-is.
9. Do not rewrite the agent-owned files under memory/hermes/; each agent owns
   its own format. Curate only the canonical files.
10. Apply the changes by actually editing the files with your file tools.
    Then RE-READ each file from disk and confirm the new content is really
    there. Never report success without this verification.
11. Finish by showing the output of `git -C "$HUB" diff memory/` (the real
    command output, not a reconstruction) and remind the user to run
    `briefing sync` to commit.
