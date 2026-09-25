---
name: notion-worklog
description: "Record every piece of agent work in Notion before calling it done — code changes, fixes, QA passes, research, plans, rulings, incidents, long unattended runs — as the right kind of record (task, QA findings + summary page, doc linking the repo file, decision, incident) with a dated work-log entry saying what was done, why, how it was verified, links and open questions. Reads the target databases from a config file in the host repo. Use at the end of ANY task that changed something, found something or produced a decision; and when the user says 'log this', 'document this in Notion', 'put this in Notion', 'record what we did', 'add the QA findings to Notion', or 'update the task'."
---

# /notion-worklog — nothing is done until Notion says so

The repo records code. It does not record *why*, what was checked, what was
found and left, or what is waiting on a human. A founder or a team lead reads
Notion, not `git log`. This skill makes every agent session leave one honest,
findable record there — without turning the workspace into a commit mirror.

Access is through a **Notion MCP connector** (tools named like
`notion-search`, `notion-fetch`, `notion-create-pages`, `notion-update-page`,
`notion-query-data-sources`). If your agent has no Notion tools, jump to
[No connector](#no-connector).

## When to use this

- At the end of any task that changed code, config, infra or data.
- After a QA / testing / verification pass — even one that found nothing.
- After research, a plan, a spec or an analysis.
- When a human gave a ruling, or you need one.
- During a long unattended run: once per leg, plus a summary at the end.

## When NOT to use this

- Pure read-only Q&A that changed nothing and found nothing.
- Per commit. One record per **unit of work**; later commits, PRs and legs
  append to it.
- To mirror a repo doc. Link the file; never paste its body into Notion.

## Setup (once per repo)

Copy `config/notion-worklog.example.json` (next to this file) to
`.agents/notion-worklog.json` in the host repo — override the path with
`$NOTION_WORKLOG_CONFIG` — and fill the data-source ids. `notion-fetch` on each
database prints its `collection://…` id and the exact property names. Commit
it: ids are not secrets, and every agent on the repo needs the same targets.

No config file → **ask once** where records go, offer to write the config, and
until then create a private draft page and say so. Never guess a database.

Field names come from the config, never from memory. If a write fails with a
schema error, `notion-fetch` the data source, fix the config in the same
change, retry once.

## Where each kind of work goes

| Work | Record (config key) |
|---|---|
| Code change / fix / feature | `tasks` — one row per unit of work; reuse an existing id if the branch, PR title or user names one |
| QA / testing / verification | `tasks` — one row per **real** finding; plus `docs` — one summary page for the pass |
| Plan / spec / research | repo file as usual + `docs` row linking it (`spec` / `wiki` type) |
| Ruling given, or question needing one | `decisions` — `approved` if given, `proposed` if asked |
| Production outage | `incidents` |
| Relay / long run | one `tasks` row for the run; a log entry per leg; summary at the end |

Missing key in the config → fall back to `tasks` (or `docs` for write-ups) and
mention the gap in your reply.

## Workflow

1. **Find the home.** One wide query on the target data source (id, title,
   status, PR link; exclude done). Match by id in the branch/PR title first,
   then by title. Existing → update it. Queries may be metered: one wide
   query, filter in your head — never loop narrow ones.
2. **Create if none.** Short English title, detail in the body. Fill only what
   you know (status, assignee, config `defaults`); an empty property is
   honest, a guessed one is noise.
3. **Set state** with the config's status names: working → `in_progress`;
   PR open → `in_review` + PR link; `done` only when merged to the default
   branch or a human confirmed it.
4. **Append a work-log entry** to the page body — append, never rewrite
   earlier entries:

   ```
   ## <YYYY-MM-DD> — <agent> — <one-line outcome>
   - Did: …
   - Why: …
   - Verified: <tests / commands / live checks — or "not verified">
   - Links: PR …, branch …, commit …, <repo path to doc>
   - Open: <questions / next steps — or "none">
   ```
5. **QA passes:** summary page titled `QA — <area> — <date>` with scope,
   environment (prod/staging/local + commit), a pass/fail table, and links to
   each finding row. Findings carry reproduction steps and severity.
6. **Report** the Notion URL(s) — and the task id if the database has one —
   in the final reply to the user.

## Permission

- **Your own records** (created this session, or the task you were asked to
  do): create and update directly, no confirmation.
- **Anything derived** — changing status on rows you did not create, bulk
  edits, reconciling the database against the repo: print the diff, wait for
  a yes, then apply.
- **Never** delete or archive a row unless told, naming that row.

## Traps

- A full-page update can clear properties you omit. Send only what changed.
- Status is often a *select*, not Notion's status type — use the literal
  option names from the config.
- Relation properties take arrays of page URLs, not titles.
- Never write secrets, tokens, connection strings or customer personal data.
  Redact before logging a command that printed one.
- "Verified" means you ran something and saw it pass. Typecheck-only is
  "typecheck only"; say so.
- Do not restructure databases, views or properties as a side effect —
  additive only.

## No connector

Some agents (Codex, headless CI runs, a disconnected session) have no Notion
tools. Write the exact entry under a `## Notion (pending)` heading in the PR
description or the run ledger, and tell the user it still needs pushing. The
next session with a connector pushes pending entries and deletes the heading.
Never claim a record was written when it was not.

## Making it a rule

A skill only fires when an agent thinks of it. To make logging mandatory, add
a line to the repo's `AGENTS.md` / `CLAUDE.md`, e.g.:

> Every piece of work is recorded in Notion via the `notion-worklog` skill
> before it counts as done; the final reply includes the Notion link.

## Report format

One line per record touched: `<kind> <title> — <created|updated> — <url>`.
Then any config gap or pending entry.
