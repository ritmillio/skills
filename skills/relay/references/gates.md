# Gates: what counts as proof

A gate is a command with an exit code that an iteration can run unattended.
"I read the code and it looks right" is not a gate. The relay's whole claim to
being trustworthy overnight rests on this distinction.

## Choosing gates for a repo

Write them into the host repo's `.claude/relay.md` so every run inherits them.
Two tiers:

- **Per-iteration** — fast enough to run on every commit. Typecheck of the
  touched package, the unit tests for the surface, a build if it is quick.
- **Full** — run only by the compaction iteration. The whole suite, the whole
  typecheck, the whole build.

Prefer a gate that fails loudly on the exact thing the mission is about. A run
aimed at UI quality that only gates on unit tests will happily ship a broken
screen.

## Traps that are true in every repo

- **`cmd | tail` reports `tail`'s exit code.** A failing build reads as green.
  Use `cmd; echo "EXIT=$?"`, or check `PIPESTATUS`.
- **A build is not a typecheck.** Many bundlers strip types without checking them.
- **A subshell `(cd sub && ...)` does not move the outer cwd.** The next bare
  command runs somewhere else, often exiting 1 with no output.
- **A fresh worktree has no untracked config.** `.env` and friends are not in
  git, so every gate that reads config fails for the wrong reason until they
  are copied in. `setup.sh` does this; check it found them.
- **Type checkers on big repos run out of heap** before they run out of errors.
  A V8 SIGABRT reads like a type error and is not one. Raise the heap
  (`NODE_OPTIONS=--max-old-space-size=8192`) before believing the failure.
- **`git stash` is a no-op on committed work**, and `git add -A` in a shared
  checkout sweeps up another session's files. Always add explicit paths.
- **A red CI check is not always a red change.** If preview deploys fail by
  design in this repo, say so in `.claude/relay.md` so iterations do not chase it.

## Schema and data

If the mission can touch a database schema, say so explicitly in
`.claude/relay.md`: which command generates a migration, whether generated SQL
must be read by a human before committing, and which databases are off limits.
The relay is forbidden from production regardless.
