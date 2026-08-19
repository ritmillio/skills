---
name: relay
description: Run unattended autonomous work for a stated duration (4h, 12h, 24h) on a dedicated worktree, branch and draft PR, without context rot. Each iteration is a fresh process handing a committed ledger to the next. Use when the user says "work on X for the next N hours", "keep iterating while I'm away", "leave it running", "work on this all night", or asks to check on, stop, or report on a running relay.
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

`/relay <duration> <mission>` — the duration is the hard wall-clock budget and
goes straight to `--hours`. `/relay 4h`, `/relay 24h`, `/relay overnight` (treat
as 8h unless told otherwise). Also `/relay status` and `/relay stop` for a run
already going, and `/relay report` when the user comes back.

If no duration is given, ask for one. Everything is sized from it: how much
backlog to seed, how deep each item can be, whether the setup is worth it.

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

Read `$SKILL_DIR/references/brief.md`, `compaction-brief.md`,
`ledger-template.md` and `gates.md` before writing any of them.

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
duration, anything explicitly out of scope. Do not interview someone who is
trying to go to bed.

### 2. Seed a real backlog

**This decides whether the run is worth anything.** A relay launched with a
vague backlog wanders. Fan out `Explore` agents over the mission area and come
back with concrete, verifiable items ordered by value — roughly two per hour of
the stated duration, floor of 6. Each names the surface it touches and how you
would know it worked. Iterations that run dry end the run early, so a long run
wants a deep backlog. If you cannot find 6 real items, say so.

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

### 5. Launch detached

```bash
"$SKILL_DIR/scripts/launch.sh" \
  --dir <worktree> --ledger docs/<slug>.md --branch feat/<slug> \
  --hours <duration> --model opus --compact-every 8 --max-parallel 2
```

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
`tail -f .loop/relay.log`, and `touch .loop/STOP`. The terminal can be closed.

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

`/relay report`: read `.loop/status`, the relay log, and the ledger's
`## For the founder` and `## Health`. Lead with what landed and what needs a
decision. Verify against `git log` before repeating a claim — a ledger entry is
a claim, a commit is evidence.

## Stop conditions

The `STOP` file, the hour budget, the iteration cap, three consecutive
iterations that landed no commit, or a branch drift. It pushes after every
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
