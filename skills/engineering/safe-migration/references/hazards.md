# Migration hazards — the incident shapes and how the ritual catches each

A migration directory earns this skill by having been broken before. These are
the concrete ways it happened, so the steps in SKILL.md read as prevention, not
ceremony.

## 1. Reused prefix

**Shape:** a new file `0034_add_x.sql` created when `0034_something_else.sql`
already exists. Tools that order by filename now have two "0034"s; apply order
becomes ambiguous and the journal disagrees with the disk.

**Caught by:** the preflight (step 1) derives the next number from the disk *and*
the remote default branch (`ls` + `git ls-tree`), never from
memory or from "the number in my head." Known historical duplicates are
tolerated by the check but you never *add* one.

## 2. Silent destructive SQL from db:generate

**Shape:** you rename a column, or remove a field, and `drizzle-kit generate`
can't tell a rename from a drop-plus-add — so it emits `DROP COLUMN old` +
`ADD COLUMN new`, silently destroying data on apply. Or a refactor removes a
field you meant to keep and the generator writes a `DROP` you never intended.

**Caught by:** step 5 greps every migration file for `DROP`/`TRUNCATE`/
`ALTER … DROP`/`DELETE` and shows the hits to the user *before the file is kept*.
A surprising `DROP` means: discard the file, fix the schema (use the generator's
rename prompt, or restore the field), regenerate. A `DROP` is only kept when the
user confirms they intend to remove that thing.

## 3. Schema/migration drift (the weeks-long outage)

**Shape:** someone hand-writes `ALTER TABLE … DROP COLUMN compiled_prompt` in a
migration but forgets to remove the field from the schema `.ts`. Now the schema
says the column exists, the DB says it doesn't, and every query drizzle builds
references a dead column — prod throws until someone finds it. (This is a real
incident; it ran for weeks.)

**Caught by:** steps 4a and 7. Any hand-written destructive SQL must be paired
with the matching schema edit *in the same working tree*, and step 7 refuses to
finish unless both the schema file and the migration file are staged in the same
commit. The invariant is: **schema and migration are never separated.**

## 4. db:push against a shared database

**Shape:** `drizzle-kit push` diffs the schema straight onto the DB and skips the
migration files entirely. Run against prod or staging, it drifts the DB away from
what the migration history records — which is the root cause of a directory
getting into this state in the first place.

**Caught by:** the prod boundary. `db:push` is local-dev-only, full stop. This
skill never runs it against anything shared, and says so.

## 5. Bootstrapping from a damaged directory

**Shape:** `db:migrate` on a fresh environment silently skips migrations past the
point where the journal stops (e.g. journal has 100 entries, disk has 208 files)
— the new environment comes up missing ~half its schema and nobody notices until
a feature breaks.

**Caught by:** awareness, not automation. If asked to stand up a new environment,
do NOT run the directory forward from zero — restore from a known-good snapshot,
then apply only forward migrations. Read the migrations README's incident log
before touching bootstrap.

## 6. Running the generator against a frozen journal

**Shape:** the repo froze its Drizzle journal (it stops at some index while
hand-written files keep landing past it). `drizzle-kit generate` diffs the schema
against the *last snapshot in the journal*, months stale, so it emits a file that
re-creates tables that already exist, re-adds columns, or drops things added by
hand since. Applied, it fails at best and destroys data at worst — and it also
appends to the journal the repo meant to keep frozen.

**Caught by:** the preflight greps the repo's own rule files for the frozen-journal
/ "do not run generate" rule and prints `mode: hand`. In that mode the skill never
runs the generator and hand-writes idempotent forward SQL (step 4a). If a
generated file and a journal/snapshot change appear anyway, delete both before
anything else.

## The one-line invariant

Repo rule first · prefix from disk and main · grep every migration · schema and migration in one commit
· never push to a shared DB · apply to prod before the dependent code deploys.
