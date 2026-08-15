<!-- Template for the loop ledger. Lives at docs/<slug>.md and is COMMITTED:
     it is the deliverable the founder reads in the morning, and it is also the
     only memory any iteration has. Setup replaces every {{PLACEHOLDER}}. -->

# {{TITLE}}

**Mission.** {{MISSION}}

**Run.** Started {{DATE}} on branch `{{BRANCH}}` (worktree `{{WORKTREE}}`),
forked from `{{BASE}}` @ `{{BASE_SHA}}`. Draft PR {{PR}}.
Time budget {{HOURS}}h. Driver: the `relay` plugin.

**In scope.** {{SCOPE}}
**Out of scope.** {{OUT_OF_SCOPE}}

**How to read this.** `## For the founder` is your inbox, read it first.
`## Health` is the current gate status. `## Landed` is what shipped.
`## Backlog` is what the loop would do next if it kept running.

---

## For the founder

<!-- Decisions, spends, irreversible actions, and ambiguities the loop refused
     to resolve alone. Iterations only append here; only the founder clears it. -->

_(nothing yet)_

## Health

<!-- Filled by each compaction iteration: gate results, verbatim, with a sha. -->

_(no compaction iteration has run yet)_

## Standing rules

<!-- Lessons the loop learned the hard way. Every iteration inherits these.
     Promote a rule here the second time something bites. -->

- Findings come from running the thing, not from reading the source.
- Commit before exiting. An uncommitted change does not survive the iteration.

## Backlog

<!-- Ordered, highest value first. Mark blocked items `BLOCKED: <reason>`. -->

- [ ] {{FIRST_ITEM}}

## Iteration log

<!-- Append-only, at most 6 lines per iteration, newest last. Compaction
     collapses everything older than the last 5 into `## Landed`. -->

## Landed

<!-- One line per shipped change, grouped by theme, each keeping its short sha. -->
