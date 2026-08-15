# relay

A Claude Code skill for unattended work that runs for hours without rotting.

You give it a duration and a mission. It builds an isolated git worktree, seeds
a backlog, opens a draft PR, and then works — landing commits and keeping a
ledger — until the clock runs out or you stop it. You come back to a reviewable
PR and a document that explains it.

```
/relay 4h  fix the settings UI to match the design system
/relay 24h audit the API surface for auth gaps
/relay status
/relay stop
```

## The problem it solves

A long unattended session fails for one reason: the session doing the work is
also the thing remembering it. Hours in, the transcript is mostly its own
exhaust. Compaction throws away the operating discipline along with the noise,
and iteration 30 re-litigates what iteration 4 already settled.

The name is the mechanism. Like a relay race, each leg is run by someone fresh,
and the only thing that crosses the handoff is the baton:

```
iteration 1     iteration 2     iteration 8      iteration 9
fresh process   fresh process   compaction       fresh process
     |               |               |                |
   exits           exits           exits            exits
─────────────────────────────────────────────────────────────
  docs/<slug>.md  — read, appended, committed — persists
```

No arrow runs between the processes. Each one is a new `claude -p` that learns
what happened by reading the ledger and `git log`, does exactly one unit of
work, commits, and dies. Nothing lives long enough to rot, at four hours or at
twenty-four.

**Compaction moves from the transcript to the ledger.** Every eighth iteration
writes no code: it reconciles the ledger against `git log`, runs the full gate
suite, and shrinks the file. Unlike a transcript summary, this one is checkable
— a claim no commit supports gets deleted instead of inherited.

## Install

```
/plugin marketplace add ritmillio/claude-relay
/plugin install relay@ritmillio-tools
```

Or try it without installing:

```
claude --plugin-dir /path/to/claude-relay/plugins/relay
```

Requires `git`, `jq`, and the `claude` CLI on `PATH`. `gh` if you want the draft
PR opened for you.

## Configure it for your repo

A relay is only as good as its idea of *done*. Create **`.claude/relay.md`** in
your repository:

```markdown
## Gates

Per-iteration:  npm test -- --run <touched area>
Full (compaction): npm run typecheck && npm test && npm run build

## Conventions

- Branch names: feat/<slug>
- Conventional commits
- Never touch db/migrations without a generated migration in the same commit

## Never

- Deploy, publish, or email
- The staging database
```

The skill reads it before every run. If it is missing, it derives a first
version from your `package.json`, CI config and `CLAUDE.md`, shows it to you,
and writes it once you agree. It never removes a safety rule — only adds.

## Keeping the machine awake

The most common way a long run dies is not context rot. It is the machine going
to sleep. What you get depends on the platform, and the launcher prints exactly
which one you have:

| Platform | Guard | Survives a closed lid? |
|---|---|---|
| macOS | `caffeinate -ims`, held for the life of the run | **No.** A shut laptop sleeps regardless |
| Linux (systemd) | `systemd-inhibit` on idle, sleep and the lid switch | Yes |
| Linux (no systemd) | none; headless boxes usually do not sleep | n/a |
| Windows | **none available from a shell** | No |

On Windows, set this yourself before a long run:

```
powercfg /change standby-timeout-ac 0
```

The skill will not pretend it has a guard it does not have.

## What it will never do

Enforced in the brief every single iteration, not just at setup:

- Never merge a pull request
- Never push to a protected branch
- Never write to a shared or production database
- Never take an irreversible or outward-facing action — those go into a
  `## For the founder` section of the ledger for you to decide

It also asserts the expected branch on **every** iteration and halts on drift,
because in a shared checkout another session can move it underneath you.

## How the pieces fit

| Piece | Where | Role |
|---|---|---|
| Ledger | `docs/<slug>.md`, committed | The run's entire memory, and your read when you return |
| Brief | `<worktree>/.loop/brief.md` | The prompt each fresh process gets |
| Relay | `scripts/relay.sh`, detached | Starts processes, asserts invariants, records outcomes. Talks to no model |
| Worktree | beside your repo | Isolation from whatever else you have checked out |

Watch it with `tail -f <worktree>/.loop/relay.log`. Stop it with
`touch <worktree>/.loop/STOP` — it finishes the current iteration and exits.

The relay ends on any of: the stop file, the hour budget, the iteration cap,
three consecutive iterations that landed no commit, or a branch drift. It pushes
after every iteration that commits, so the PR stays current even if the run ends
badly.

## Cost

Each iteration is a separate model session, so spend scales with iteration count
rather than session length. Budget accordingly before a 24-hour run; there is a
per-iteration `--budget` flag and no total ceiling.

## License

MIT
