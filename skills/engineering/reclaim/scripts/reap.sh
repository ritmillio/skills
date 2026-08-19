#!/usr/bin/env bash
# reclaim/reap.sh — kill stale dev watchers and everything they spawned.
# DRY RUN unless --yes.
#
# Only ever targets build/dev watchers that restart with one command. It will
# not touch an agent, a relay driver, an editor or a language server, and it
# refuses to guess about anything else.
#
# Two safeguards worth knowing about:
#   * Descendants go with their parent. A `pnpm word:dev` wrapper is 39 MB; the
#     `webpack` it spawned is 1.2 GB. Killing only what the pattern matched
#     leaves the fat child orphaned and holding the memory you came for.
#   * A watcher on a LISTENING port may be serving something you are using
#     right now (a Word add-in pane, a browser tab). Those are flagged and
#     skipped unless you pass --include-listening.
#
# Usage:
#   reap.sh                        # dry run, 30m threshold
#   reap.sh --dry-run              # same, explicit
#   reap.sh --yes                  # actually kill
#   reap.sh --min-age-min 120 --yes
#   reap.sh --include-listening --yes
set -uo pipefail

MIN_AGE_MIN=30
DO_KILL=0
INCLUDE_LISTENING=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)             DO_KILL=1; shift ;;
    --dry-run)            DO_KILL=0; shift ;;
    --include-listening)  INCLUDE_LISTENING=1; shift ;;
    --min-age-min)        MIN_AGE_MIN="${2:-30}"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

export MIN_AGE_MIN DO_KILL INCLUDE_LISTENING

python3 - <<'PY'
import os, re, signal, subprocess, sys, time

MIN_AGE_S = int(os.environ["MIN_AGE_MIN"]) * 60
DO_KILL = os.environ["DO_KILL"] == "1"
INCLUDE_LISTENING = os.environ["INCLUDE_LISTENING"] == "1"

# --- snapshot ---------------------------------------------------------------
raw = subprocess.run(["ps", "-Ao", "pid=,ppid=,etime=,rss=,args="],
                     capture_output=True, text=True).stdout
procs = {}
children = {}
for line in raw.splitlines():
    parts = line.split(None, 4)
    if len(parts) < 5:
        continue
    pid, ppid, etime, rss, args = parts
    if not pid.isdigit():
        continue
    pid, ppid, rss = int(pid), int(ppid), int(rss)
    procs[pid] = {"ppid": ppid, "etime": etime, "rss": rss, "args": args}
    children.setdefault(ppid, []).append(pid)

def age_seconds(et):
    # etime is [[dd-]hh:]mm:ss
    d, _, rest = et.partition("-")
    if not rest:
        d, rest = "0", d
    p = [int(x) for x in rest.split(":")]
    s = p[0] * 3600 + p[1] * 60 + p[2] if len(p) == 3 else (
        p[0] * 60 + p[1] if len(p) == 2 else p[0])
    return int(d) * 86400 + s

# --- protect ----------------------------------------------------------------
# An agent or its driver is never a reap target, and killing a relay
# mid-iteration loses uncommitted work. Applied to descendants too, so a
# protected process is never swept up by its parent.
PROTECT = ("claude", "relay.sh", "caffeinate", "Code Helper", "cursor",
           "tsserver", "language-server", "Electron", "ssh-agent")

def protected(args):
    return any(p in args for p in PROTECT)

# --- allow ------------------------------------------------------------------
# Long-lived watchers, each trivially restartable.
RULES = [
    ("next dev",               ("next dev", "next-server")),
    ("trigger dev",            ("trigger dev",)),
    ("word:dev",               ("word:dev",)),
    ("outlook:dev",            ("outlook:dev",)),
    ("addin dev-server",       ("pnpm run dev-server",)),
    ("next webpack helper",    ("webpack-loaders.js",)),
    ("next postcss helper",    ("postcss.js",)),
    ("turbo dev",              ("turbo dev",)),
    ("pnpm dev",               ("pnpm dev", "pnpm run dev", "dev:web", "dev:mobile")),
]

def match(args):
    if "esbuild" in args and "--service" in args and "--ping" in args:
        return "orphan esbuild service"
    for label, needles in RULES:
        if any(n in args for n in needles):
            return label
    return None

seeds = {}
for pid, p in procs.items():
    if protected(p["args"]):
        continue
    label = match(p["args"])
    if label and age_seconds(p["etime"]) >= MIN_AGE_S:
        seeds[pid] = label

# --- expand to descendants --------------------------------------------------
# No age check here: a helper respawned two minutes ago under a stale parent
# dies with it either way, and it is usually where the memory is.
selected = dict(seeds)
frontier = list(seeds)
while frontier:
    pid = frontier.pop()
    for kid in children.get(pid, []):
        if kid in selected or kid not in procs:
            continue
        if protected(procs[kid]["args"]):
            continue
        selected[kid] = f"child of {seeds.get(pid, selected.get(pid, 'watcher'))}"
        frontier.append(kid)

if not selected:
    print(f"  nothing stale (threshold {MIN_AGE_S // 60}m)")
    sys.exit(0)

# --- listening-port guard ---------------------------------------------------
listening = {}
try:
    out = subprocess.run(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pn"],
                         capture_output=True, text=True, timeout=15).stdout
    cur = None
    for line in out.splitlines():
        if line.startswith("p"):
            cur = int(line[1:])
        elif line.startswith("n") and cur is not None:
            port = line[1:].rsplit(":", 1)[-1]
            listening.setdefault(cur, set()).add(port)
except Exception:
    pass  # no lsof, no guard — say so below

# One listening process protects its whole selected tree, in both directions:
# killing an ancestor takes the server down just as surely as killing the
# server itself, and killing a sibling helper leaves it broken.
def root_of(pid):
    seen = set()
    while pid not in seen:
        seen.add(pid)
        parent = procs.get(pid, {}).get("ppid")
        if parent not in selected:
            return pid
        pid = parent
    return pid

roots_serving = {root_of(pid) for pid in selected if listening.get(pid)}
serving = {pid for pid in selected if root_of(pid) in roots_serving}

# --- report -----------------------------------------------------------------
kill_set, skip_set = [], []
for pid in sorted(selected):
    (skip_set if (pid in serving and not INCLUDE_LISTENING) else kill_set).append(pid)

def show(pids, mark):
    total = 0
    for pid in pids:
        p = procs[pid]
        ports = ",".join(sorted(listening.get(pid, [])))
        port_s = f" :{ports}" if ports else ""
        print(f"  {mark} pid {pid:<7} {p['etime']:<12} {p['rss']//1024:>6} MB  "
              f"{selected[pid]:<22}{port_s} {p['args'][:64]}")
        total += p["rss"]
    return total

kb = 0
if kill_set:
    kb = show(kill_set, " ")
if skip_set:
    print()
    print("  SKIPPED — listening, and something may be using it right now:")
    show(skip_set, "!")
    print("  (a live add-in pane or browser tab dies with these — "
          "pass --include-listening to reap them anyway)")

print()
if not listening:
    print("  NOTE: no lsof data, so nothing was checked for being in use.")
if not kill_set:
    print("  nothing reapable that is not in use")
    sys.exit(0)

print(f"  {len(kill_set)} processes, ~{kb // 1024} MB resident")
print("  (resident counts shared pages once per process — an upper bound on")
print("   what actually comes back)")

if not DO_KILL:
    print("  DRY RUN — re-run with --yes to kill")
    sys.exit(0)

# --- kill -------------------------------------------------------------------
# SIGTERM first so watchers flush and remove their sockets; SIGKILL only the
# ones that ignore it. Children first, so a supervisor does not respawn them.
for pid in sorted(kill_set, key=lambda p: -len(children.get(p, []))):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(3)
stubborn = []
for pid in kill_set:
    try:
        os.kill(pid, 0)
        stubborn.append(pid)
    except OSError:
        pass
for pid in stubborn:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
if stubborn:
    print("  SIGKILLed: " + " ".join(str(p) for p in stubborn))
print(f"  reaped {len(kill_set)} processes")
PY

if [ "$DO_KILL" = "1" ]; then
  # Give the compressor a moment before quoting a number at anyone.
  sleep 2
  echo "  load now:   $(sysctl -n vm.loadavg | tr -d '{}')"
  echo "  memory now: $(top -l 1 -n 0 2>/dev/null | grep PhysMem)"
fi
