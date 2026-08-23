---
name: safe-migration
description: "Run the safe Drizzle migration ritual for a repo with a fragile migration directory: pick the next free prefix, generate, grep the SQL for destructive operations, enforce IF EXISTS, run the migration check, and confirm schema lands with its migration in one commit. Use when the user changes a Drizzle schema file, says 'generate a migration', 'add a column/table', 'db:generate', or is about to ship a schema change."
allowed-tools: Read, Bash, Grep, Glob, Edit, AskUserQuestion
---

# /safe-migration — a schema change that can't silently break prod

A migration directory that has already been damaged once punishes the same
mistakes forever: a reused prefix, a `db:generate` that quietly emits a `DROP`,
a hand-written migration whose schema edit was forgotten, a `db:push` against
prod that skips the files entirely. Each of those has cost real downtime. This
skill is the fixed ritual that makes those failures impossible to reach by
accident. It is deliberately boring — the boring path is the one that ships.

It reads the host repo's own rules first (step 1) so it stays correct as the
project's conventions move, rather than hardcoding them.

## When to use this

- Any change to a Drizzle schema file, or the user says "generate a migration",
  "add a column / table / index", "db:generate", "alter the schema".
- Before shipping a branch that touches schema — as the pre-flight check.

## When NOT to use this

- Read-only query changes, seed scripts, or data backfills that touch no schema.
- A repo with a healthy, linear migration history and CI that enforces it — the
  full ritual is overhead there. Use it where a mistake is expensive.
- Applying migrations **to production** — this skill prepares and verifies; it
  does not run `db:migrate` against a shared/prod database. That is a human,
  deliberate, out-of-band step.

## The four failures this prevents

1. **Reused prefix** — a new `0034_…` when `0034` already exists. Derive the
   next number from what's on disk, never from memory.
2. **Silent destructive SQL** — `db:generate` emitting `DROP COLUMN`/`DROP TABLE`
   because a rename or removed field read as a deletion. Every generated file is
   grepped for destructive ops and shown to the user before it's kept.
3. **Schema/migration drift** — a hand-written `ALTER … DROP` with no matching
   edit to the schema file (the incident that broke prod for weeks). Schema and
   migration must land in the **same commit**; the skill refuses to finish
   otherwise.
4. **`db:push` to a shared DB** — skips the migration files and drifts schema vs
   DB. Never run against anything but a local dev database.

## Workflow

1. **Load the repo's rules.** Read the migrations directory's own README (search
   `**/migrations/README.md`) and the root `CLAUDE.md`/`AGENTS.md` migration
   section. They are the source of truth for prefix scheme, the check command,
   and repo-specific hazards. Where they differ from this file, they win.

2. **Find the next free prefix — from disk, not memory:**
   ```bash
   ls <migrations-dir>/*.sql | sed 's#.*/##' | sort | tail -5
   ```
   Next prefix is `lastNumber + 1`, zero-padded to the repo's width. If the
   directory has historical duplicate prefixes, tolerate them but do not add a
   new collision — scan before naming.

3. **Edit the schema file(s)** for the actual change, matching the file's
   existing conventions (read them; do not assume).

4. **Generate:**
   ```bash
   <pkg-manager> db:generate     # e.g. pnpm db:generate -> drizzle-kit generate
   ```
   Then find the file it wrote (newest `.sql`).

5. **Grep the generated SQL for destructive operations and SHOW the user:**
   ```bash
   grep -niE 'drop (table|column|constraint|index|type)|truncate|alter .*drop|delete from' <new.sql>
   ```
   Any hit is a stop-and-confirm. A `DROP` is only correct when the user
   genuinely intends to remove something; a `DROP` that surprises you is the
   `db:generate` hazard firing — do not keep the file, fix the schema and
   regenerate. See `references/hazards.md`.

6. **Harden hand-written SQL.** If you (not the generator) wrote any SQL, make
   every statement idempotent — `IF NOT EXISTS` / `IF EXISTS` — and confirm the
   schema file carries the matching change in this same working tree.

7. **Run the repo's migration check** (use what step 1 found, commonly):
   ```bash
   <pkg-manager> db:check-migrations   # or drizzle-kit check
   ```
   Historical-dupe / journal-drift **warnings** are expected on a damaged
   directory and are fine; a **failure** is not.

8. **Stage schema + migration together, in one commit.** List the staged files
   back to the user and confirm both are present before committing. Never commit
   a migration without its schema change, or vice versa.

## The prod boundary (state it every time)

- **Never** `db:push` / `db:migrate` against staging or prod from this skill.
- A migration must be **applied to prod before the code that depends on it
  deploys**, or the new column/table 500s the live app. Say this in the report;
  the apply itself is the user's deliberate step.
- If asked to check prod schema drift before shipping, do it **read-only** and
  say plainly you are only reading.

## Report format

- The change, the new migration filename, and the exact prefix reasoning.
- The destructive-op grep result — "none" is a result worth stating.
- Confirmation that schema + migration are staged together.
- The prod-apply reminder, and whether the check passed (warnings vs failures).

## References

- `references/hazards.md` — the real incident shapes (reused prefix, silent
  DROP, schema drift, db:push) and how each is caught here.
