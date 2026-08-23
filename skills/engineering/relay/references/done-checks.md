# The completion contract: ending on done, not on a clock

A duration is a budget. "Until the importer handles all three formats and the
suite is green" is a goal. The relay can run on either, but only one of them
answers the question the user actually has, which is *how long should I leave
this running*. The honest answer is: until these things are true.

A criterion becomes a file in `<worktree>/.loop/done.d/`. Any executable works.
Its exit code is the verdict, and a `# desc:` comment gives it a human name:

```bash
#!/usr/bin/env bash
# desc: auth e2e suite green
npm run test:e2e -- auth
```

`check-done.sh` runs them in filename order, from the worktree root, and exits 0
only when every one passes. The relay runs it around every iteration and stops
the moment it does. `--hours` becomes the safety cap it always should have been.

## Writing a criterion that means something

**The check is the criterion.** Not the sentence in the ledger — the file. If
`## Done when` says "the importer handles CSV, TSV and JSONL" and `done.d/` only
tests CSV, the run ends two thirds done and reports success. Whatever you write
in prose, write the check to match it exactly.

**Prefer a check that fails today.** A criterion that already passes when the
run starts is either done or not measuring anything. Run `check-done.sh` before
launching: every criterion should be red, and you should be able to say what
would turn each one green.

**Make it fail for the right reason.** `npm test` is green in a repo where the
mission's surface has no tests at all. Point the check at the thing the mission
is about, then confirm it goes red when you break that thing on purpose.

**Exit codes, not output.** `grep -c` exits 0 when it prints `0`. `cmd | tail`
reports `tail`'s status. Every trap in `gates.md` applies here and matters more,
because this exit code is what ends the run.

**Bound it.** Checks run inside a per-check timeout (`--check-timeout`, 900s by
default) and re-run around every iteration. A 40-minute e2e suite as a criterion
means most of the night is spent proving the same thing; raise `--check-every`
so it runs every third or fourth iteration instead.

## Criteria that cannot be expressed as a command

Some of what a user wants is real and not mechanical: "the empty states don't
look broken", "the README explains the thing". You have three options, in order
of preference:

1. **Make it mechanical.** Screenshot diff, an axe-core run, a link checker, a
   script that greps for the section headings a README must have. Most soft
   criteria have a hard proxy that is 80% as good and infinitely more honest.
2. **Turn it into the deliverable rather than the gate.** Leave it out of
   `done.d/`, put it in the ledger's `## For the founder` as something to review,
   and let the contract cover what it can.
3. **Say it cannot be checked.** Tell the user before launching. A criterion the
   relay cannot verify is a criterion the relay will claim it met.

What you must not do is write a check that reads the loop's own notes —
`grep -q "done" docs/ledger.md` is the loop marking its own homework, and it
turns the stop condition into a formality the loop can satisfy by typing.

## Rules the iterations inherit

The brief tells every iteration two things about the contract, and both matter:

- **Never edit, weaken, or delete a check to make it pass.** A red criterion
  that is wrong goes under `## For the founder`, and stays red.
- **A criterion with no check is not a criterion.** If `## Done when` names
  something `done.d/` does not cover, writing that check is the unit of work.

## What the founder sees

- Ended on the contract: `relay end (contract-met)`, every criterion listed as met.
- Ended on the cap: `relay end (budget)`, followed by `still open:` for each
  criterion that never went green. That list is the honest answer to "how far did
  it get", and it is the first thing to read in the morning.
