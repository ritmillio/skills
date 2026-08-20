---
name: relay
description: Run unattended autonomous work on a dedicated worktree, branch and draft PR, without context rot — for a stated duration (4h, 12h, 24h) or until a set of verifiable criteria all pass. Each iteration is a fresh process handing a committed ledger to the next. Use when the user says "work on X for the next N hours", "keep going until X, Y and Z are done", "keep iterating while I'm away", "leave it running", "work on this all night", or asks to watch, check on, stop, or report on a running relay.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, AskUserQuestion
---

# /relay — leave it running, come back to a reviewable PR

A long unattended run fails for one reason: the session doing the work is also
the thing remembering it. Hours in, the transcript is mostly its own exhaust,
compaction throws away the operating discipline along with the noise, and
iteration 30 re-litigates what iteration 4 already settled.

The name is the mechanism. Like a relay race, each leg is run by someone fresh,
and the only thing that crosses the handoff is the baton — here, a committed
ledger. No process lives long enough to rot. That holds identically at four
hours and at twenty-four.

## Invocation

`/relay <duration> <mission>` — the duration is the wall-clock budget and goes
straight to `--hours`. `/relay 4h`, `/relay 24h`, `/relay overnight` (treat as
8h unless told otherwise).

`/relay until <criteria>` — the run ends when every criterion is verified, and
the duration becomes the cap that stops a runaway rather than the goal. This is
the right form whenever the user knows what done looks like but not how long it
takes, which is most of the time. Ask for a cap if none is given and default to
12h: an unattended loop with no deadline is a runaway waiting to happen. Every
criterion has to become an executable check — step 4b below, and
`references/done-checks.md` for how to write one that cannot be gamed.

Also `/relay watch` (live dashboard), `/relay status` (one snapshot),
`/relay stop`, and `/relay report` when the user comes back.

If neither a duration nor criteria are given, ask. Everything is sized from it:
how much backlog to seed, how deep each item can be, whether the setup is worth it.

## When to use this

- The user is away for 2+ hours and wants real work landed, not a plan.
- The work is a long tail of similar units: an audit, a parity sweep, a defect
  hunt, a migration across many call sites, a quality bar applied surface by surface.
- The result should arrive as a draft PR plus a document that explains it.

## When NOT to use this

- One well-understood change. Just make it.
- Work needing a decision every few minutes. The relay will fill
  `## For the founder` and stall.
- Anything irreversible or outward-facing: merges, production data, deploys,
  emails. The relay is explicitly forbidden from these.

## The four pieces

| Piece | Where | Why |
|---|---|---|
| **Ledger** | `docs/<slug>.md`, committed | The run's entire memory, and the user's read when they return |
| **Brief** | `<worktree>/.loop/brief.md` | The prompt each fresh process gets; bounded by construction |
| **Relay** | `$SKILL_DIR/scripts/relay.sh`, detached | Starts processes, asserts invariants, records outcomes. Talks to no model |
| **Worktree** | sibling of the repo | Isolation. A shared checkout gets its branch flipped by another session |
| **Contract** | `<worktree>/.loop/done.d/*`, executable | What "done" means, as exit codes. Optional; without it the run ends on the clock |

Read `$SKILL_DIR/references/brief.md`, `compaction-brief.md`,
`ledger-template.md` and `gates.md` before writing any of them, and
`done-checks.md` before writing a completion contract.

## First: the host repo's gates

A relay is only as good as its idea of *done*. Before setting anything up, look
for **`.claude/relay.md`** in the repo being worked on. That file is the
project's half of this skill: the commands that count as proof, the conventions
a commit must honor, the things the loop must never touch.

If it is missing, derive a first version — read `package.json` scripts, the
Makefile, the CI workflow, `CONTRIBUTING.md`, any `CLAUDE.md` — propose it in
one block, and write it to `.claude/relay.md` once agreed. Every later run
inherits it, and it gets better each time something bites.
`references/gates.md` covers what makes a gate worth running and the traps that
are true in every repo.

## Workflow

### 0. Locate this skill on disk

The scripts live in `scripts/` beside this SKILL.md, but the path depends on
which agent loaded it. Resolve it once, then reuse `$SKILL_DIR`:

```bash
for d in "${CLAUDE_PLUGIN_ROOT:-}" ~/.agents/skills/relay ./.agents/skills/relay \
         ~/.claude/skills/relay ~/.codex/skills/relay \
         ~/.gemini/skills/relay ~/.cursor/skills/relay ./.claude/skills/relay; do
  [ -x "$d/scripts/relay.sh" ] && SKILL_DIR="$d" && break
done
```

If none match, the skill is installed somewhere non-standard: find it with
`find ~ -name relay.sh -path '*relay/scripts/*' 2>/dev/null | head -1`.

### 1. Settle the mission (short)

Infer what you can and propose it back in one block. Ask only what changes the
run, at most one `AskUserQuestion` round: mission in a sentence, scope boundary,
how it ends (a duration, or the criteria that end it and a cap), anything
explicitly out of scope. Do not interview someone who is trying to go to bed.

### 2. Seed a real backlog

**This decides whether the run is worth anything.** A relay launched with a
vague backlog wanders. Fan out `Explore` agents over the mission area and come
back with concrete, verifiable items ordered by value — roughly two per hour of
the cap, floor of 6. Each names the surface it touches and how you would know it
worked. Under a completion contract, every criterion also needs at least one
backlog item that would turn it green, or the run cannot finish. Iterations that
run dry end the run early, so a long run wants a deep backlog. If you cannot
find 6 real items, say so.

### 3. Set up

```bash
"$SKILL_DIR/scripts/setup.sh" --branch feat/<slug> --base main
```

Fresh worktree beside the repo, env files copied, deps installed, `.loop/`
created and locally excluded from git.

### 4. Write the ledger and the briefs

- Ledger from `references/ledger-template.md` → `<worktree>/docs/<slug>.md`,
  carrying the mission, scope, standing rules and the backlog from step 2.
- `<worktree>/.loop/brief.md` from `references/brief.md`.
- `<worktree>/.loop/compaction-brief.md` from `references/compaction-brief.md`.
- Replace **every** `{{PLACEHOLDER}}` — grep for `{{` afterwards. `{{GATES}}`
  comes from the host repo's `.claude/relay.md`.

Commit the ledger, push the branch, open the **draft** PR now, before launching,
so there is a URL even if the first iteration fails.

### 4b. Write the completion contract (only if the run ends on "done")

Each criterion becomes one executable file in `<worktree>/.loop/done.d/` with a
`# desc:` line naming it; its exit code is the verdict. Read
`references/done-checks.md` first — a check pointed at the wrong thing ends the
run early and reports success, which is worse than no contract at all. Mirror
them in prose under the ledger's `## Done when`, and set `{{ENDS_WHEN}}` in both
the ledger and the brief.

Then run the contract before launching and read the result back to the user:

```bash
"$SKILL_DIR/scripts/check-done.sh" --dir <worktree>
```

**Every criterion should be red.** One that is already green is either already
done or measuring nothing — say so rather than shipping it.

### 5. Launch detached

```bash
"$SKILL_DIR/scripts/launch.sh" \
  --dir <worktree> --ledger docs/<slug>.md --branch feat/<slug> \
  --hours <cap> --model opus --compact-every 8 --max-parallel 2 --watch
```

`--watch` attaches the dashboard once the relay is up; Ctrl-C detaches it and
the run continues, because the relay never had a terminal to lose. Drop it for a
truly fire-and-forget launch.

With a contract in `.loop/done.d/`, the relay runs it around every iteration and
stops the moment all of it passes. `--check-every N` runs it every N iterations
instead, for a suite too slow to repeat hourly; `--check-timeout` caps a single
check (900s default).

**Sharing the machine.** Every relay iteration runs the host repo's gate suite,
and test runners fork one worker per core by default -- two relays entering
their gates in the same minute ask for several times the cores the laptop has,
and the whole box thrashes, the human's interactive session included. The relay
holds one of `--max-parallel` machine-wide slots (default 2, or
`$RELAY_MAX_PARALLEL`) for the duration of each iteration, so relays queue
instead of colliding. Slots are `~/.claude/relay-slots/slot-N` directories
keyed by owner PID and reclaimed when an owner dies. The wait is bounded by
`--iter-timeout`: a lock must never be able to end the night, so a relay that
still cannot get a slot proceeds anyway and says so in the log. Set
`--max-parallel 1` for strict serialisation, `0` to disable the semaphore.

Cap the runners too. `VITEST_MAX_THREADS` / `VITEST_MAX_FORKS` (and
`TURBO_CONCURRENCY`) in `~/.claude/settings.json`'s `env` block reach every
iteration, because each one is a Claude Code session reading that file.

`launch.sh` picks the platform's sleep inhibitor and prints exactly what
protection the run has. **Read that line back to the user.** On macOS a closed
lid still sleeps; on Windows there is no guard at all. For anything past a few
hours this is the most likely way the run dies.

Then hand over the four lines that matter: PR URL, ledger path,
`.loop/watch.sh`, and `touch .loop/STOP`. The terminal can be closed.

### 5b. Watching a run

Each iteration streams its events as they happen, so a run in progress is
legible rather than silent. Three views, in decreasing altitude:

| Command | Shows |
|---|---|
| `<worktree>/.loop/watch.sh` | Live dashboard: contract state, budget, commits, the stream. Redraws until Ctrl-C |
| `.loop/watch.sh --once` | One plain snapshot, no redraw. This is what `/relay status` prints, and what to use from inside a session |
| `tail -f .loop/live.log` | Every tool call and every line the model narrates, timestamped |

`.loop/relay.log` remains the high-altitude record: one block per iteration,
what it landed, what the contract said. That is the file to read in the morning,
not the stream.

**Notifications.** If `$RELAY_NOTIFY` (default `~/.claude/telegram-notify.sh`) is
executable, the relay calls it as `RELAY_EVENT=<start|landed|halt|limit|end>
<notifier> --relay "<body>"` on run start, on every iteration that lands
commits, on a halt, on a usage-limit wait, and at the end. It is backgrounded
and its exit code ignored, so a broken notifier cannot end a run; if the file is
missing the relay is simply silent. The relay also exports
`CLAUDE_RELAY_ACTIVE=1`, which a notifier should read to stay quiet on the
per-iteration `claude -p`'s own Stop and commit hooks - the relay's message is
strictly better, since it knows the iteration number and the commit count.

### 6. On their return

`/relay report`: run `.loop/watch.sh --once`, then read the relay log and the
ledger's `## For the founder` and `## Health`. Lead with why the run ended: a
contract met is a finished mission, a budget exhausted is a progress report. Lead with what landed and what needs a
decision. Verify against `git log` before repeating a claim — a ledger entry is
a claim, a commit is evidence.

## Stop conditions

The completion contract passing in full (the good ending), the `STOP` file, the
hour cap, the iteration cap, three consecutive iterations that landed no commit,
or a branch drift. The relay logs which one ended the run — `relay end
(contract-met)` versus `relay end (budget)` — and a gated run that ended any
other way lists each criterion it never met under `still open:`. It pushes after every
iteration that commits, so the PR stays current even if the run ends badly.

An exhausted usage window is deliberately **not** a stop condition. A
limit-reached failure is not a dry iteration — nothing was attempted — so the
relay waits for the window to reset (probing every 15 minutes when the reset
time is unknown, honoring `STOP` throughout, capped at 12h of cumulative
waiting), extends the deadline by exactly the time it waited, and continues.
For a run launched before this behavior existed, `scripts/limit-watchdog.sh
--dir <worktree>` relaunches a limit-starved run with its remaining hours.

## If the relay cannot run

Fall back to in-session: keep the main session thin and delegate each iteration
to a subagent with `.loop/brief.md` as its prompt. Main context then grows by
one short report per iteration instead of a full iteration's tool output.

If a single interactive session is truly unavoidable, start it with
`claude --dangerously-skip-permissions --autocompact 200000`. On a large-context
model auto-compaction otherwise does not fire until the context is already mush.
A mitigation, not a fix.

## Rules that hold in any repo

Never merge a PR. Never push to a protected branch. Never touch production data.
Commits assert the branch in the same command and add explicit paths, because
the checkout may be shared. Anything irreversible goes to the user, not through
the loop. The host repo's `.claude/relay.md` adds to these; it never removes one.
