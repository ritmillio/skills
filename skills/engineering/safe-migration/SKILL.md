---
name: safe-migration
description: "Run the safe Drizzle migration ritual for a repo with a fragile migration directory: read the repo's own rule first (a frozen journal means hand-written SQL, never the generator), pick the next free prefix from disk and the default branch, grep the SQL for destructive operations, enforce IF [NOT] EXISTS, run the migration check, and confirm schema lands with its migration in one commit. Use when the user changes a Drizzle schema file, says 'generate a migration', 'add a column/table', 'db:generate', or is about to ship a schema change."
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
   because a rename or removed field read as a deletion, or because the journal
   it diffs against is frozen and stale. Repos that froze their journal forbid the
   generator outright; the preflight finds that rule and the skill hand-writes the
   SQL instead. Every migration is grepped for destructive ops either way.
3. **Schema/migration drift** — a hand-written `ALTER … DROP` with no matching
   edit to the schema file (the incident that broke prod for weeks). Schema and
   migration must land in the **same commit**; the skill refuses to finish
   otherwise.
4. **`db:push` to a shared DB** — skips the migration files and drifts schema vs
   DB. Never run against anything but a local dev database.

## Workflow

1. **Preflight — let the repo tell you its rules:**
   ```bash
   bash "$SKILL_DIR/scripts/preflight.sh" <repo> [migrations-dir]
   ```
   It finds the migrations directory, greps `AGENTS.md`, `CLAUDE.md` and the
   migrations `README.md` for a frozen-journal / "do not run generate" rule,
   derives the next free prefix from the disk **and** the remote default branch
   (a migration merged to `main` since you branched still counts), lists the
   historical duplicate prefixes, and names the repo's check script. Then read
   those rule files yourself — the script only finds them; where they differ from
   this skill, they win.

2. **Pick the mode the preflight printed.**
   - `mode: hand` — the repo forbids the generator (typically: the Drizzle
     journal is frozen, so `drizzle-kit generate` diffs against a stale snapshot
     and emits duplicate or destructive SQL). **Do not run `db:generate` /
     `drizzle-kit generate`, not even "just to see".** Go to 3, then 4a.
   - `mode: generate` — no such rule. Go to 3, then 4b.

3. **Edit the schema file(s)** for the actual change, matching the file's
   existing conventions (read them; do not assume). If the repo has two schema
   trees, change the one its rules call canonical.

4a. **Hand-write the forward migration** (`mode: hand`):
   - Name it `<next-prefix>_<snake_case_what>.sql` in the migrations directory.
     Do not touch the journal or snapshot files.
   - Every statement idempotent: `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT
     EXISTS`, `CREATE INDEX IF NOT EXISTS`, `DROP … IF EXISTS`. For a constraint
     or type that has no `IF NOT EXISTS`, wrap it in a `DO $$ … EXCEPTION WHEN
     duplicate_object THEN NULL; END $$;` block.
   - Match the exact column types, defaults and names the schema edit declares —
     read the schema diff and the SQL side by side.
   - If the repo has a forward runner with a floor prefix (read its README), make
     sure the new prefix is above the floor, or it will never be applied.

4b. **Generate** (`mode: generate` only):
   ```bash
   <pkg-manager> db:generate     # e.g. pnpm db:generate -> drizzle-kit generate
   ```
   Find the file it wrote (newest `.sql`) and rename it if its prefix collides.

5. **Grep the SQL for destructive operations and SHOW the user** (both modes):
   ```bash
   grep -niE 'drop (table|column|constraint|index|type)|truncate|alter .*drop|delete from' <new.sql>
   ```
   Any hit is a stop-and-confirm. A `DROP` is only correct when the user
   genuinely intends to remove something; a `DROP` that surprises you is the
   generator hazard firing — do not keep the file, fix the schema and redo it.
   A column drop also needs the field removed from the schema in the same commit.
   See `references/hazards.md`.

6. **Run the repo's migration check** (the preflight named it; commonly
   `pnpm db:check-migrations` or `drizzle-kit check`). Historical-dupe /
   journal-drift **warnings** are expected on a damaged directory and are fine; a
   **failure** is not.

7. **Stage schema + migration together, in one commit.** List the staged files
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

- The mode (hand-written vs generated) and the rule that decided it.
- The change, the new migration filename, and the exact prefix reasoning.
- The destructive-op grep result — "none" is a result worth stating.
- Confirmation that schema + migration are staged together.
- The prod-apply reminder, and whether the check passed (warnings vs failures).

## References

- `scripts/preflight.sh` — read-only: migrations dir, generator rule, next free
  prefix (disk + remote default branch), duplicate prefixes, check script.
- `references/hazards.md` — the real incident shapes (reused prefix, silent
  DROP, schema drift, db:push) and how each is caught here.
