---
name: memory-hygiene
description: "Audit and clean a Claude Code auto-memory directory so the index actually loads: count how much of MEMORY.md reaches the agent at startup (200 lines / ~25k chars), find overlong index lines, broken and orphan entries, near-duplicates, frontmatter errors, and feedback rules that sit below the cut, then archive finished project memories and shorten the index after the user approves. Also a session-wrap mode that files one topic memory plus one short index line. Use when the user says 'clean up memory', 'MEMORY.md is too long', 'memory got truncated', 'tidy memories', 'wrap up the session', 'save what we learned', or when a startup warning says the memory index was cut off."
allowed-tools: Read, Bash, Edit, Write, AskUserQuestion
---

# /memory-hygiene — a memory the agent never reads is not a memory

Claude Code loads only the head of `MEMORY.md` at startup: the first 200 lines,
and in practice fewer, because it also stops at about 25,000 characters. An index
that grows one fat line per session hits that wall long before 200 lines. From
then on every new entry pushes an old one out of view, and the old ones are
usually the *rules* — the feedback memories the user gave once and expects to be
followed forever. The agent starts breaking them without knowing they exist.

This skill makes the loss visible, then fixes it without deleting anything:
finished project memories move to `archive/`, fat index lines get short, rules
move to the top.

## When to use this

- A startup warning says MEMORY.md was cut off, or the user says memory is too
  long / truncated / messy.
- The agent keeps forgetting a rule the user remembers giving.
- **Session wrap** — end of a working session: "save what we learned", "wrap up".

## When NOT to use this

- Editing a project's checked-in `CLAUDE.md` / `AGENTS.md` — that is repo
  documentation, not auto-memory.
- Deleting memories. This skill archives. Deleting a file needs the user's
  explicit yes for that file.

## Workflow — cleanup

1. **Audit (read-only):**
   ```bash
   bash "$SKILL_DIR/scripts/audit.sh"                # memory dir for the current cwd
   bash "$SKILL_DIR/scripts/audit.sh" <memory-dir>
   bash "$SKILL_DIR/scripts/audit.sh" <memory-dir> --json
   ```
   The headline is "only N lines load — M lines never reach the agent". Also:
   lines over 200 chars, links to missing files, orphans, frontmatter errors,
   feedback/user rules below the cut, near-duplicate names, and archive
   candidates (project memories whose text says DONE / MERGED / ENDED / SHIPPED /
   superseded, oldest first).

2. **Propose a plan** — numbers first, then the moves:
   - **Rules to the top.** Every `feedback` and `user` memory gets an index line
     in a `## Rules` block at the top of MEMORY.md. These must always load.
   - **Archive finished projects.** Move each finished `project` memory to
     `archive/<same-name>.md`, drop its index line, and keep one line:
     `- [Archive](archive/) — N finished projects; grep here before re-investigating`.
     Read each candidate's description first — the audit's keyword match is a
     heuristic; "DONE" next to "open = …" is not finished.
   - **Shorten fat lines** to ≤150 chars. What the line loses goes into the topic
     file's body, not into the void.
   - **Merge near-duplicates** (dated re-runs of one topic, `run6`/`run7`/`run8`)
     into the newest file; the older ones go to `archive/`.
   - **Fix** orphans (index them or archive them) and frontmatter errors.
   - Target: the whole index loads, with headroom (≤150 lines, ≤18k chars).

3. **Ask before touching anything** — `AskUserQuestion` with the plan's parts as
   options (recommended first: "rules to top + archive finished + shorten"), and
   name the count of files each part moves.

4. **Apply** with Edit/Write and `mv` into `archive/`. Never `rm`. Keep every
   file's frontmatter; when you merge, list the merged-from names in the body.
   Recently touched memories (under 3 days) stay put unless the user says so —
   another session may be writing them.

5. **Re-run the audit** and report before → after: lines loaded, chars, rules
   loaded, files archived. Done means `✓ whole index loads at startup` and zero
   rules below the cut.

## Workflow — session wrap

At the end of a session, file what the *next* session needs and nothing else:

1. Run the audit's headline (`audit.sh | head -4`) — if the index is already
   over the limit, say so and offer the cleanup instead of adding to the pile.
2. Pick one topic file: update the existing one for this workstream if the index
   has it, else create `<short-kebab-name>.md` with frontmatter
   (`name`, `description`, `type`). Put detail — branches, PR numbers, open
   questions, exact commands — in the body. Convert relative dates to absolute.
3. Add or replace **one** index line, ≤150 chars: `- [Title](file.md) — hook`.
   Rules (`feedback`/`user`) go in the Rules block at the top.
4. Do not save what the repo already records (code structure, git history,
   checked-in docs).

## References

- `references/layout.md` — the index layout this skill converges on, the load
  limits and how they were measured, and what counts as "finished".
