<!-- Template for .loop/compaction-brief.md. Setup replaces every {{PLACEHOLDER}}. -->

You are the **compaction iteration** of an unattended loop. You write no
feature code. Your job is to keep the loop's memory small, true, and useful,
and to prove the branch is still healthy.

This is the step that replaces conversational compaction. The loop never
compacts a transcript, because no transcript survives an iteration. What needs
compacting is `{{LEDGER}}` — and unlike a transcript summary, you can check it
against the repository and correct it.

- LEDGER: `{{LEDGER}}`
- BRANCH: `{{BRANCH}}`
- MISSION: {{MISSION}}

## Do exactly this

1. Read `{{LEDGER}}` in full and run `git log --oneline {{BASE}}..HEAD`.
2. **Reconcile.** Every commit on the branch must be represented in the ledger,
   and every ledger claim must correspond to a commit. Fix both directions.
   Claims that no commit supports are the loop's version of a hallucinated
   summary: delete them or downgrade them to backlog items.
3. **Run the full gate suite** (not the per-iteration subset):
{{GATES}}
   Record the result verbatim in `## Health`, with the date and the branch head.
   If a gate is red, add a P0 backlog item at the very top and say so plainly.
4. **Compact the ledger.**
   - Collapse `## Iteration log` entries older than the last 5 into one-line
     bullets under `## Landed`, grouped by theme, each keeping its short sha.
   - Delete backlog items that are done, no longer true, or out of scope.
   - Re-order `## Backlog` by value to the mission, highest first, and mark
     anything blocked with `BLOCKED:` and the reason.
   - Merge duplicate or overlapping items.
   - Promote any lesson that has now bitten twice into `## Standing rules`.
   - Target: the whole file reads in under two minutes. If `## Landed` is
     getting long, summarise by theme rather than by commit.
5. **Sanity-check the mission.** If the iterations have drifted from
   `{{MISSION}}`, say so at the top of `## For the founder` and re-point the
   backlog at the mission.
6. Commit the ledger (`git add {{LEDGER}}` — explicit path only) and exit.

## Hard rules

- Do not change feature code in this iteration. Ledger and docs only.
- Do not delete `## For the founder` entries. They are the founder's inbox and
  only the founder clears them.
- Never merge, never push to a protected branch, never touch production.

## Your final message

At most 8 lines: gate results, how much the ledger shrank, and the top three
backlog items now.
