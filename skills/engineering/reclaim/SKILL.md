---
name: reclaim
description: Diagnose and fix a dev machine pinned at high CPU, high RAM or high load average — read the verdict before touching anything, free resident memory, reap stale build watchers, cap test-runner concurrency, and tell the user when only a reboot will do. Use when the user says the CPU/RAM/fan/load is out of control, shows a system-monitor screenshot, asks to free up memory, or asks why the machine is slow while agents are running.
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /reclaim — give the machine back

A dev box that feels slow while several agents run looks like an obvious
problem with an obvious fix: find the fat process, kill it. That read is wrong
often enough to be the main thing this skill exists to correct.

**The process at the top of the list is usually a symptom.** `launchservicesd`
at 337%, `WindowServer` at 138%, `kernel_task` climbing — none of those are
work anyone asked for. They are what the OS does *downstream* of something
else. Killing them is impossible, chasing them is wasted time, and the actual
cause is one layer down.

**And the slowness is often not CPU at all.** A machine can crawl at 80% idle.
Read the verdict before forming a theory.

## The verdict decides everything

```bash
scripts/diagnose.sh
```

Section 0 branches four ways. Report it to the user **before** proposing
anything; if you skip to a kill list you will confidently fix the wrong thing.

| Verdict | What it means | What to do |
|---|---|---|
| **MEMORY-BOUND** | Little unused RAM, a fat compressor, or live paging | Free resident pages — the memory chapter below |
| **I/O-BOUND** | Load far above core count while the CPU is idle | Disk, not CPU — the indexing-storm section |
| **KERNEL-BOUND** | System% ≥ User%: paging or process-registration churn | Reaping barely helps. Go to step 4 |
| **USER-BOUND** | Your own compute really is the load | Cap concurrency, reap watchers (steps 2–3) |
| **NOT CPU-BOUND** | Mostly idle and still slow | It is memory or I/O. Read section 2, not section 3 |

Two things drive a high System%:

- **Swap under pressure.** The kernel compresses and pages constantly, and
  that work is charged to System.
- **Process-spawn churn.** Every agent Bash call spawns a shell; hundreds of
  short-lived process registrations per minute thrash the LaunchServices
  database. This gets monotonically worse with uptime and **does not recover
  on its own** — it is the classic 60-days-uptime symptom.

## When memory is the load

### Read the compressor, not the free percentage

`memory_pressure` reports a "System-wide memory free percentage" that counts
compressed and purgeable pages as free. It will cheerfully say **65%** on a box
with 871 MB actually unused. Do not quote it. Do not believe it.

The numbers that mean something, all printed by section 2:

- **unused** — real, uncommitted RAM.
- **compressor holds N GB, storing M GB (M/N:1)** — RAM spent holding memory
  that no longer fits. It is charged to no process, so it never appears in
  `top` or `ps`, and on a squeezed machine it is often the largest single
  consumer. Every access to it costs a decompression.
- **live swap rate** — sampled over 2s. Lifetime swapin/swapout counters say
  nothing about now; a machine 64 days up has millions of both regardless.

**Stale swap is not pressure.** A box that swapped hard yesterday still shows a
full swap file today with 14 GB free. Those pages drain on reboot and not
before. The diagnose verdict calls this out as RECOVERED / STALE SWAP
specifically so nobody goes hunting for a hog that is already gone.

### Rank by app family, not by process

A browser is not one process, it is a hundred. Per-process ranking puts four
560 MB renderers in the top ten and hides the fact that they belong to one
application holding **19.7 GB across 103 processes** — larger than everything
else on the machine combined. Section 5 aggregates by `.app` bundle and by
toolchain, which is usually the moment the real answer appears.

Resident totals count shared pages once per process. Read them as a ranking and
an upper bound, never as "this much comes back".

### What actually returns pages

In order of payoff on a typical dev machine:

1. **Idle browser renderers.** Chromium-family browsers keep a process per
   backgrounded tab, each holding hundreds of MB indefinitely. Killing a
   renderer costs a tab reload on next click and any unsaved form input in it;
   it does not close the tab or lose the session. On a real machine this
   returned **16 GB from 94 processes**, and the compressor fell 14 GB → 8 GB
   on top of that. This is the single biggest lever and it is **the user's
   browser** — use `AskUserQuestion`, and offer a graduated option (all idle
   renderers / only the fattest ten / quit the app) rather than a yes-no.
2. **Stale dev watchers** — step 2. Real but bounded: 1–3 GB.
3. **Reboot** — step 4. The only thing that reclaims swap and a leaked
   `WindowServer`.

`sudo purge` only flushes the file cache, needs a password, and can stall the
machine for seconds. It is not worth offering.

### Killing a list of PIDs: use xargs

Ad-hoc kills usually run under **zsh, which does not word-split unquoted
variables**. `kill $PIDS` and `for p in $PIDS` both pass the entire newline-
joined list as a single argument and fail with `illegal pid`. With stderr
suppressed this looks exactly like a successful kill, and a follow-up
`kill -0 $p` fails the same way, so the verification agrees. Two rounds can go
by before anyone notices nothing died.

```bash
ps -Ao pid,%cpu,args | grep '[B]rowser Helper (Renderer)' \
  | awk '$2<1.0 {print $1}' > /tmp/pids.txt
xargs kill -TERM < /tmp/pids.txt
```

Verify against `ps`, not `pgrep -f`: parentheses in a `pgrep -f` pattern are
regex groups, so `pgrep -f 'Browser Helper (Renderer)'` matches nothing and
reports a confident zero.

Always quote the before/after `PhysMem` line. It is the only proof.

## Two failure modes that look like nothing in a CPU list

### The indexing storm

**Symptom:** load average several times the core count while the CPU is mostly
idle, and intermittent UI lag with no process to blame. Load 25 on 15 cores at
59% idle means ~25 threads queued on **disk**, not on the CPU.

**Cause:** Spotlight re-scans anything that changes, and a dev machine changes
constantly. One real box had **3.39 million files in `node_modules` across 56
worktrees**; dev servers rewrote them continuously, so the index never
converged. 32 `mdworker_shared` were alive at once, respawning every 1–4
seconds — which is also where a `launchservicesd` spike comes from, since every
one of those spawns is a process registration.

Confirm by catching a worker mid-read:

```bash
lsof -c mdworker_shared | grep /Users
```

Seeing `.../node_modules/effect/src/Context.ts` scroll past is the whole
diagnosis.

**What does not work, in the order you will try it:**

- `.metadata_never_index` in each `node_modules` — officially only honoured at
  a **volume root**. 686 markers changed nothing; workers kept indexing the
  exact directories that had been marked.
- `sudo killall mds` — `mds` is SIP-protected. It survives, same PID, and the
  only clue is that `etime` never resets. Check the PID before believing it.
- `mdutil` — **volume-level only**. There is no per-directory CLI exclusion.

**What works:** System Settings → Spotlight → Search Privacy → add the parent
directory. Doing it at `~/Developer` rather than per-worktree is what makes it
cover worktrees that do not exist yet. The cost is Spotlight file search over
your code, which is no cost if you already search with ripgrep and your editor.

### The dev server that ate the machine

A Next dev server is expected to sit at 1–3 GB. Past ~6 GB it has leaked, and
it **does not shrink when idle**. Observed on one machine: 7 GB at 55 seconds,
**13.4 GB at 14 minutes**, at 0% CPU the whole time.

This is invisible to every CPU-ordered view — the process is idle. Only a
top-RSS scan finds it, which is why section 6 flags any build process over
3 GB by name and age.

Before killing one, walk the parent chain. A dev server respawning seconds
after you kill it is usually **another agent session** restarting it, not a
supervisor:

```bash
ps -o ppid=,args= -p <pid>   # repeat up the chain to launchd
```

Landing on `claude --dangerously-skip-permissions` means another session owns
that server, and killing it again will not stick.

## Prevention

Everything above is a cure. These are the four things that stop the calls
coming back, in payoff order:

1. **Exclude the code root from Spotlight** — one action, covers every future
   worktree, removes millions of files from the index permanently.
2. **One dev server at a time, and restart it when it crosses ~6 GB.** Several
   worktrees each running `next dev` is several times 3–13 GB. `diagnose.sh`
   section 6 names them.
3. **Prune worktrees.** 56 checkouts is 3.4M dependency files, and every one of
   them is disk, index churn, and a place to run a forgotten dev server.
4. **Reboot on a schedule.** `WindowServer` leaks monotonically with uptime and
   nothing else reclaims it or the swap file. At 64 days it was 1.3 GB.

**The tell for a leaked `WindowServer`: the volume HUD lags.** Changing volume
costs essentially no CPU and no disk — it is pure compositing. When *that*
stutters, stop looking for a busy process; the compositor itself is sick, and
only a restart fixes it.

## Procedure

### 1. Diagnose (always first, always read-only)

```bash
scripts/diagnose.sh
```

Prints the verdict, the CPU split, the real memory read, top CPU, top RSS by
process and by app family, a candidate reap list, and current agent/test
concurrency with the relevant settings.json caps. Nothing is killed.

### 2. Reap stale watchers

Dev servers and build watchers are immortal by design: started once, never
noticed again, each holding hundreds of MB and a steady CPU trickle. A machine
that has been used for a week accumulates several.

```bash
scripts/reap.sh                 # dry run, anything older than 30m
scripts/reap.sh --yes           # do it
scripts/reap.sh --min-age-min 120 --yes
scripts/reap.sh --include-listening --yes
```

What it targets — all trivially restartable with one command:

`next dev` / `next-server` and its `webpack-loaders.js` / `postcss.js` helper
pool · `trigger dev` · orphaned `esbuild --service --ping` daemons (these leak
and can hold >1 GB) · `word:dev` / `outlook:dev` webpack servers · `turbo dev`
· `pnpm dev*`.

What it will never touch: `claude`, `relay.sh`, `caffeinate`, editors, language
servers — as ancestors *or* as descendants.

Two behaviours worth understanding before you trust the output:

- **Descendants go with their parent.** A `pnpm word:dev` wrapper is 39 MB; the
  `webpack` it spawned is 1.2 GB and matches no pattern of its own. Reaping
  only what matched leaves the fat child orphaned and still holding the memory
  you came for.
- **A listening server may be in use right now.** `:3443` serving a Word add-in
  pane you are actively testing looks identical to a forgotten watcher. Any
  process bound to a TCP port protects its whole selected tree, in both
  directions, and is skipped unless you pass `--include-listening`. When the
  dry run says *"nothing reapable that is not in use"*, that is the real
  answer: the memory is in servers the user is using, and reaping is the wrong
  lever. Say so instead of forcing the flag.

This is real but bounded. It will **not** rescue a machine whose problem is
step 4 or a 19 GB browser.

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

A live test run belonging to *another agent's session* is work in progress, not
garbage. Let it finish.

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
- **`WindowServer` over 100%** — browser and terminal rendering, and it leaks
  steadily with uptime on a high-DPI display. Real, but it is downstream of the
  user's browser, not yours to close without asking.
- **`kernel_task` high** — thermal throttling. The machine is defending itself
  against heat; the fix is upstream, in whatever is generating the load.
- **A high load average with low CPU** — processes blocked on I/O, which on a
  swapping machine means paging. Same cure as the memory chapter.
- **A load spike right after you reap** — tearing down 90 processes is itself
  work, and load average lags by a minute. Wait before quoting a number.
- **A build watcher spiking to 191%** — a rebuild burst, not a leak. Sample it
  twice before blaming it; `ps` %CPU is a lifetime average and a monitor's
  top-process list is a single instant, and neither is the steady state.

## Reporting

Lead with the verdict and what it rules out, then what you reclaimed with
measured numbers, then what remains and why. Something like:

> Not CPU — 66% idle. 871 MB unused of 48 GB with 14 GB in the compressor.
> Ranked by app family the browser was 19.7 GB across 103 processes; killing
> the 94 idle renderers took unused 1.7 → 13.8 GB and the compressor 14 → 8 GB.
> The two dev servers are on listening ports serving the add-in you are testing,
> so they stayed. Swap is still 67% full and `WindowServer` has leaked to
> 1.4 GB over 64 days; neither clears without a restart.

Never claim a fix you have not measured. Re-run `diagnose.sh` after acting and
quote the new numbers — and check that the processes actually died, because a
silently failed kill reads exactly like a successful one.
