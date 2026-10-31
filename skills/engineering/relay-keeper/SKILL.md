---
name: relay-keeper
description: Watch every running relay and the machine under them (RAM, swap, CPU load, SSD) and throttle, drain or flag them before the box crashes. Use when several relays run at once, the Mac is slow or swapping while relays run, a relay seems stuck or died overnight, the user asks to watch or babysit all relays, or before leaving relays running unattended.
allowed-tools: Bash, Read, AskUserQuestion
---

# /relay-keeper - one watcher over all relays and the machine

`/relay` guards one run. Nothing guards the machine when four of them start an
iteration in the same minute: every iteration runs the host repo's gates, test
runners fork a worker per core, the load average hits 2x the cores, swap fills,
and the whole box (the human's session included) crawls or dies. The relay's own
slot semaphore limits concurrency but cannot see RAM, swap, SSD or a dead peer.
This skill is that missing eye, and a hand on the only brake that is safe.

## What it does and does not do

| It does | It never does |
|---|---|
| Reads kernel memory pressure, swap, live paging, load per core, free SSD | Kill a process |
| Reads every relay's `.loop/` state: status, iteration, cost, silence | Touch a relay mid-iteration |
| **Throttles**: holds relay CPU slots so no *new* iteration starts | End a run (`STOP` is yours) |
| **Prunes** old raw iteration streams when the SSD is short | Delete anything but `.loop/iter/*.jsonl` |
| **Revives** (opt-in) a relay that died without ending | Revive more than twice per relay |
| Flags a wedged relay, a relay not under `caffeinate` | Decide a wedged relay is dead |

The throttle needs no change to any relay. Relays already queue on
`~/.claude/relay-slots/slot-N`, and a slot whose owner PID is dead is reclaimed.
The keeper daemon takes free slots with its own PID. Iterations in flight drain;
the next ones wait. If the daemon dies, every hold disappears with it.

## Invocation

`/relay-keeper` (or "watch the relays") - report. `/relay-keeper on` - install the
daemon. `/relay-keeper off` - remove it.

## Workflow

### 0. Locate the scripts

```bash
for d in "${CLAUDE_PLUGIN_ROOT:-}" ~/.agents/skills/relay-keeper ./.agents/skills/relay-keeper \
         ~/.claude/skills/relay-keeper ~/.codex/skills/relay-keeper ./.claude/skills/relay-keeper; do
  [ -x "$d/scripts/keeper.sh" ] && KEEPER_DIR="$d" && break
done
```

### 1. Report first (read-only, always)

```bash
"$KEEPER_DIR/scripts/keeper.sh"
```

Read the level back to the user: OK, WARN or CRIT, with each reason, then the
relay table (state, iteration, landed, cost, minutes left). Exit code is the
level (0/1/2). Lead with what is wrong, not with the table.

### 2. Decide the response

| Level | Meaning | Response |
|---|---|---|
| OK | Headroom | Nothing. Offer the daemon if several relays run |
| WARN | Load >= 1.2x cores, swap >= 8 GB, SSD < 60 GB, elevated pressure, a silent or dead relay | Daemon holds one more slot per tick (after 2 bad ticks) |
| CRIT | Load >= 2x, kernel pressure critical, swap >= 24 GB *and* paging, SSD < 25 GB | Daemon holds every free slot: no new iteration until it recovers |

Recovery is slow on purpose: 3 clean ticks release one slot, so the load ramps
back instead of spiking.

### 3. Turn it on

```bash
"$KEEPER_DIR/scripts/install-keeper.sh" [--revive] [--notify]
```

One launchd job, `KeepAlive`, every 60 s. `--revive` relaunches a relay whose
process died without writing `=== relay end` (reboot, OOM, closed terminal) and
which still has 30+ minutes of budget, only while the level is OK. `--notify`
pings `$RELAY_NOTIFY` when the level changes. Check it with `install-keeper.sh
--status`; tail `~/.claude/relay-keeper/keeper.log`.

Linux has no launchd: run `keeper.sh --apply --loop 60 --quiet` under systemd.

### 4. Tell the user the limits

- A relay waiting for a slot gives up after its `--iter-timeout` (45 min) and
  proceeds anyway. That is the relay's rule ("a lock must never end the night"),
  and the keeper does not override it. A CRIT that lasts over 45 min stops
  slowing the relays down.
- Holds bite only on **new** iterations. A machine already thrashing recovers
  as running iterations finish, which can take up to 45 minutes.
- The real fix for a box that is always CRIT is fewer relays or a lower
  `--max-parallel`. Say so rather than letting the daemon hide it.

## Traps

- **Free RAM is meaningless on macOS.** It fills memory with cache on purpose;
  "0.2 GB free" with 40 GB reclaimable and pressure level 1 is a healthy Mac.
  The keeper trusts `kern.memorystatus_vm_pressure_level` and live paging.
- **Swap used is a history, not a state.** 22 GB can sit in swap long after the
  pressure ended. Swap is WARN alone and CRIT only while pages are still going out.
- **One relay is several processes** (bash, caffeinate, a pipeline subshell).
  The keeper dedupes by `--dir`; do not count `pgrep` lines.
- **A silent RUNNING relay is not necessarily dead.** A single long test run
  can be quiet for 20+ minutes. It is flagged after 30 and never killed.
- Editing `relay.sh` while relays run can corrupt them (bash reads scripts
  incrementally). Write a temp file and `mv` it over.

Thresholds are env vars (`KEEPER_LOAD_CRIT`, `KEEPER_SWAP_CRIT`, `KEEPER_DISK_CRIT`,
...); `keeper.sh --release` drops holds by hand.
