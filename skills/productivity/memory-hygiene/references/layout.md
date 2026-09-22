# memory-hygiene — layout and limits

## The load limits

Claude Code injects `MEMORY.md` into the system prompt at session start and
truncates it. Measured on Claude Code 2.x: the cut lands at **200 lines or about
25,000 characters, whichever comes first**, and a startup warning names the first
line that was dropped. With typical 200–500-char index lines the character limit
wins at 50–100 lines. The audit defaults to these values; override with
`MEMORY_MAX_LINES` / `MEMORY_MAX_CHARS` if a newer version changes them.

Topic files are not loaded at startup — the agent reads them when an index line
makes them look relevant. So the index line is the only part that is always
seen, and it must carry the hook, not the detail.

## The index shape this skill converges on

```markdown
# Memory Index

## Rules
- [Ask with selectable answers](ask-with-selectable-answers.md) — decisions via AskUserQuestion, recommendation first
- [Never merge PRs](never-merge.md) — prepare the PR, the user clicks merge

## Active
- [Billing migration 09-22](billing-migration.md) — draft PR #601, worktree x, open = tax field ruling
- …

## Reference
- [Prod DB read-only recipe](prod-db-readonly.md) — read-only role, table cheat-sheet

- [Archive](archive/) — 212 finished projects; grep here before re-investigating
```

- Rules first: they are the memories whose loss changes behaviour.
- One line per memory, ≤150 chars: `[Title](file.md) — hook`.
- Finished work lives in `archive/`, still greppable, off the startup budget.

## What counts as finished

A `project` memory whose description or body says DONE, MERGED, ENDED, SHIPPED,
CLOSED, obsolete, superseded or contract-met, and whose description does not say
LIVE, RUNNING, IN FLIGHT or BLOCKED. That is a keyword heuristic — confirm by
reading the description. A memory that says "merged; open = X" still carries an
open item: shorten it, don't archive it, or move X into the active memory it
belongs to.

`feedback`, `user` and `reference` memories are never archive candidates.

## Frontmatter

```markdown
---
name: short-kebab-slug
description: one line, used to decide relevance
metadata:
  type: user | feedback | project | reference
---
```

The audit accepts `type:` at top level or under `metadata:`.
