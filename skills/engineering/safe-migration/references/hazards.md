# Migration hazards — the incident shapes and how the ritual catches each

A migration directory earns this skill by having been broken before. These are
the concrete ways it happened, so the steps in SKILL.md read as prevention, not
ceremony.

## 1. Reused prefix

**Shape:** a new file `0034_add_x.sql` created when `0034_something_else.sql`
already exists. Tools that order by filename now have two "0034"s; apply order
becomes ambiguous and the journal disagrees with the disk.

**Caught by:** step 2 derives the next number from `ls | sort | tail`, never from
memory or from "the number in my head." Known historical duplicates are
tolerated by the check but you never *add* one.

## 2. Silent destructive SQL from db:generate

**Shape:** you rename a column, or remove a field, and `drizzle-kit generate`
can't tell a rename from a drop-plus-add — so it emits `DROP COLUMN old` +
`ADD COLUMN new`, silently destroying data on apply. Or a refactor removes a
field you meant to keep and the generator writes a `DROP` you never intended.

**Caught by:** step 5 greps every generated file for `DROP`/`TRUNCATE`/
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

**Caught by:** step 6 and step 8. Any hand-written destructive SQL must be paired
with the matching schema edit *in the same working tree*, and step 8 refuses to
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

## The one-line invariant

Prefix from disk · grep every generated file · schema and migration in one commit
· never push to a shared DB · apply to prod before the dependent code deploys.
