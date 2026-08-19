---
name: reclaim
description: Diagnose and fix a dev machine pinned at high CPU, high RAM or high load average — read the System-vs-User split first, reap stale build watchers, cap test-runner concurrency, and tell the user when only a reboot will do. Use when the user says the CPU/RAM/fan/load is out of control, shows a system-monitor screenshot, asks to free up memory, or asks why the machine is slow while agents are running.
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /reclaim — give the machine back

A dev box pinned at 90% while several agents run looks like an obvious problem
with an obvious fix: find the fat process, kill it. That read is wrong often
enough to be the main thing this skill exists to correct.

**The process at the top of the list is usually a symptom.** `launchservicesd`
at 337%, `WindowServer` at 138%, `kernel_task` climbing — none of those are
work anyone asked for. They are what the OS does *downstream* of something
else. Killing them is impossible, chasing them is wasted time, and the actual
cause is one layer down.

## The one number that decides everything

Read the **System% vs User%** split before touching anything.

| Split | What it means | What to do |
|---|---|---|
| **User% dominates** | Your own compute really is the load — tests, builds, type-checks | Cap concurrency, reap watchers (steps 2–3) |
| **System% ≥ User%** | The *kernel* is the load: paging, or process-registration churn | Reaping barely helps. Go to step 4 |

A machine reporting `System 52% / User 33%` is spending two thirds of its CPU
on itself. Every minute spent hunting for a greedy Node process there is a
minute wasted.

Two things drive a high System%:

- **Swap under pressure.** Check `sysctl vm.swapusage`. A swap file near full
  with a large `Pageins` count means the kernel is compressing and paging
  constantly, and that work is charged to System.
- **Process-spawn churn.** Every agent Bash call spawns a shell; hundreds of
  short-lived process registrations per minute thrash the LaunchServices
  database. This gets monotonically worse with uptime and **does not recover
  on its own** — it is the classic 60-days-uptime symptom.

## Procedure

### 1. Diagnose (always first, always read-only)

```bash
scripts/diagnose.sh
```

Prints the CPU split, swap and memory pressure, top CPU and top RSS, a
candidate reap list, and current agent/test concurrency with the relevant
settings.json caps. Nothing is killed.

Report the split and the swap line to the user **before** proposing anything.
If you skip straight to a kill list you will confidently fix the wrong thing.

### 2. Reap stale watchers

Dev servers and build watchers are immortal by design: started once, never
noticed again, each holding hundreds of MB and a steady CPU trickle. A machine
that has been used for a week accumulates several.

```bash
scripts/reap.sh                 # dry run, anything older than 30m
scripts/reap.sh --yes           # do it
scripts/reap.sh --min-age-min 120 --yes
```

What it targets — all trivially restartable with one command:

`next dev` / `next-server` and its `webpack-loaders.js` / `postcss.js` helper
pool · `trigger dev` · orphaned `esbuild --service --ping` daemons (these leak
and can hold >1 GB) · `word:dev` / `outlook:dev` webpack servers · `turbo dev`
· `pnpm dev*`.

What it will never touch: `claude`, `relay.sh`, `caffeinate`, editors, language
servers.

This is real but bounded — expect 1–3 GB and a few percent of steady CPU. It
will **not** rescue a machine whose problem is step 4.

### 3. Cap the test runner

**Vitest forks one worker per core when uncapped.** On a 15-core box a single
`vitest run` spawns 14 workers, so one agent already saturates the machine and
N agents ask for N times the machine. Verify in `~/.claude/settings.json`:

```json
"env": {
  "VITEST_MAX_THREADS": "4", "VITEST_MIN_THREADS": "1",
  "VITEST_MAX_FORKS": "4",   "VITEST_MIN_FORKS": "1",
  "TURBO_CONCURRENCY": "3"
}
```

**Put this in settings.json, not in `vitest.config.ts`.** Agents and relays run
in separate worktrees on their own branches, so a repo-side config edit does not
reach the checkouts actually generating the load. The settings.json `env` block
reaches every session, including each relay's `claude -p`.

Also worth knowing: `tsc --noEmit` on a large monorepo runs at an 8 GB heap. Two
of those concurrently, on a machine whose swap is already full, is what turns a
busy machine into an unusable one. Serialize gates rather than lowering the
heap — it OOMs below 8 GB.

### 4. When only a restart will do

If System% dominates, swap is near full, and uptime is measured in weeks, no
amount of process-killing fixes it. Say so plainly rather than reaping twice
and hoping.

Before recommending a reboot, **check what it would kill**:

```bash
ps -Ao pid=,etime=,args= | grep '[r]elay\.sh'          # unattended runs
git -C <each active worktree> status --porcelain       # uncommitted work
git -C <each active worktree> log --oneline @{u}..HEAD # unpushed commits
```

Then use `AskUserQuestion` — a reboot that silently kills an 18-hour unattended
run is not a decision to make for someone.

**Winding a relay down safely** (never `kill -9` one mid-iteration):

1. `kill` the `relay.sh` driver and its `caffeinate` wrapper — this stops the
   *next* iteration from starting.
2. Let the in-flight `claude -p` finish. Watch its ledger with
   `stat -f %m <ledger>` until the mtime stops moving.
3. Commit and push whatever it left uncommitted, so the next run resumes from a
   real handoff point rather than a half-written file.
4. Record the exact relaunch command from `ps -o args= -p <driver pid>` and hand
   it to the user.

## Things that look like the cause and are not

- **`launchservicesd` at 300%+** — process-registration churn from agent Bash
  calls, compounded by uptime. Not killable, not configurable. Reboot.
- **`WindowServer` over 100%** — browser and terminal rendering. Real, but it
  is the user's browser, not yours to close without asking.
- **`kernel_task` high** — thermal throttling. The machine is defending itself
  against heat; the fix is upstream, in whatever is generating the load.
- **A high load average with low CPU** — processes blocked on I/O, which on a
  swapping machine means paging. Same cure as step 4.

## Reporting

Lead with the split and what it rules out, then what you reclaimed with numbers,
then what remains and why. Something like:

> System 52% vs User 33% — two thirds of the CPU is the kernel, not your work.
> Reaped 4 stale watcher trees (node 23 → 1, ~2.7 GB). What's left is
> `launchservicesd` at 337% and swap at 73% on 64 days uptime; neither clears
> without a restart.

Never claim a fix you have not measured. Re-run `diagnose.sh` after reaping and
quote the new numbers — load average lags by a minute, so give it time before
declaring a result.
