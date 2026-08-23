#!/usr/bin/env bash
# reclaim/diagnose.sh — read-only. Prints the verdict, the CPU split, the real
# memory read, top consumers by process and by app family, a candidate reap
# list, and current concurrency. Never kills anything.
#
# Usage: diagnose.sh [--min-age-min N]   (default 30)
set -uo pipefail

MIN_AGE_MIN=30
while [ $# -gt 0 ]; do
  case "$1" in
    --min-age-min) MIN_AGE_MIN="${2:-30}"; shift 2 ;;
    *) shift ;;
  esac
done

hr() { printf '\n\033[1m%s\033[0m\n' "$1"; }

NCPU=$(sysctl -n hw.logicalcpu)

# One CPU sample, reused by the verdict and by section 1.
CPU_LINE=$(top -l 2 -n 0 -s 1 2>/dev/null | grep -E '^CPU usage' | tail -1)
LOAD1=$(sysctl -n vm.loadavg | awk '{print $2}')

hr "0. VERDICT"
# Three ways a machine gets slow, and they need opposite responses. Decide here
# before reading anything else.
python3 - "$CPU_LINE" "$LOAD1" "$NCPU" <<'PY'
import re, subprocess, sys, time

cpu_line = sys.argv[1] if len(sys.argv) > 1 else ""
load1 = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
ncpu = int(sys.argv[3]) if len(sys.argv) > 3 else 1
m = re.search(r"([\d.]+)%\s*user.*?([\d.]+)%\s*sys.*?([\d.]+)%\s*idle", cpu_line)
user, sysp, idle = (float(m.group(1)), float(m.group(2)), float(m.group(3))) if m else (0.0, 0.0, 100.0)

def sysctl(name):
    return subprocess.run(["sysctl", "-n", name], capture_output=True, text=True).stdout.strip()

def vmstat():
    out = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
    pg = int(re.search(r"page size of (\d+)", out).group(1))
    d = {}
    for line in out.splitlines()[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            v = v.strip().rstrip(".")
            if v.isdigit():
                d[k.strip()] = int(v)
    return pg, d

pg, vm = vmstat()
total = int(sysctl("hw.memsize"))
free_b = (vm.get("Pages free", 0) + vm.get("Pages speculative", 0)) * pg
compressor_b = vm.get("Pages occupied by compressor", 0) * pg

sw = sysctl("vm.swapusage")
def swf(key):
    mm = re.search(key + r"\s*=\s*([\d.]+)M", sw)
    return float(mm.group(1)) * 1024 * 1024 if mm else 0.0
sw_total, sw_used = swf("total"), swf("used")

# Live paging: lifetime counters say nothing about now. Sample the delta.
def swapouts():
    o = subprocess.run(["sysctl", "-n", "vm.compressor_swapouts" ], capture_output=True, text=True).stdout.strip()
    if o.isdigit():
        return int(o)
    _, v = vmstat()
    return v.get("Swapouts", 0)
s0 = swapouts(); time.sleep(2.0); s1 = swapouts()
swap_rate = (s1 - s0) / 2.0

GB = 1024 ** 3
free_pct = 100.0 * free_b / total
sw_pct = 100.0 * sw_used / sw_total if sw_total else 0.0
compressor_pct = 100.0 * compressor_b / total

# Stale swap is not pressure. A box that swapped hard yesterday still reports
# a full swap file today with 14 GB free — the pages only drain on reboot.
# Real pressure needs live evidence: little unused RAM, or paging right now.
tight = free_pct < 8
mem_bound = tight or swap_rate > 0 or (sw_pct > 50 and (tight or compressor_pct > 25))
stale_swap = sw_pct > 50 and not mem_bound

# Load far above core count while the CPU sits idle means threads queued on
# something that is not the CPU — almost always disk.
io_bound = load1 > 1.5 * ncpu and idle > 45

def count(pattern):
    out = subprocess.run(["ps", "-Ao", "comm="], capture_output=True, text=True).stdout
    return sum(1 for l in out.splitlines() if pattern in l)
mdworkers = count("mdworker_shared")
kernel_bound = sysp >= user and (user + sysp) > 25

print()
if mem_bound:
    print("  \033[1mMEMORY-BOUND\033[0m — the machine is short of RAM, not of CPU.")
    print(f"    {free_b/GB:.1f} GB unused of {total/GB:.0f} GB, "
          f"{compressor_b/GB:.1f} GB held by the compressor, swap {sw_pct:.0f}% full"
          + (f", swapping {swap_rate:.0f} pages/s RIGHT NOW" if swap_rate > 0 else "") + ".")
    print("    Capping test concurrency will not help. Free resident pages: reap")
    print("    idle watchers, then look at section 5 (by app family), then reboot.")
elif stale_swap:
    print("  \033[1mRECOVERED / STALE SWAP\033[0m — swap is "
          f"{sw_pct:.0f}% full but {free_b/GB:.1f} GB is unused and nothing is paging.")
    print("    Those swap pages drain on reboot, not before. Not a live problem;")
    print("    do not go hunting for a memory hog you already dealt with.")
elif io_bound:
    print("  \033[1mI/O-BOUND\033[0m — "
          f"load {load1:.1f} on {ncpu} cores while {idle:.0f}% idle.")
    print("    Those threads are queued on disk, not on the CPU. Nothing in a")
    print("    top-CPU list explains this; see the indexing section below.")
    if mdworkers > 8:
        print(f"    {mdworkers} mdworker_shared alive — Spotlight is the prime suspect.")
elif kernel_bound:
    print("  \033[1mKERNEL-BOUND\033[0m — the kernel is the load, not your work.")
    print(f"    sys {sysp:.0f}% vs user {user:.0f}%. Process-spawn churn or paging.")
    print("    Reaping barely helps. Go to step 4 of SKILL.md.")
elif user + sysp < 25:
    print("  \033[1mNOT CPU-BOUND\033[0m — "
          f"{idle:.0f}% idle. If it still feels slow, read section 2, not section 3.")
    print("    A machine can crawl at 80% idle. Memory and I/O do that; CPU% will not show it.")
else:
    print("  \033[1mUSER-BOUND\033[0m — your own compute is the load.")
    print(f"    user {user:.0f}% vs sys {sysp:.0f}%. Cap concurrency and reap watchers (steps 2-3).")
PY

hr "1. WHERE THE CPU ACTUALLY GOES"
echo "$CPU_LINE"
echo "logical cores: $NCPU"
echo "load average: $(sysctl -n vm.loadavg | tr -d '{}')"
echo "uptime:       $(uptime | sed 's/.*up //; s/,[^,]*users.*//')"
echo
echo "  A high load average with a low CPU% means processes blocked on I/O,"
echo "  which on a machine that is paging means memory. See section 2."

hr "2. MEMORY — WHAT IS ACTUALLY RESIDENT"
python3 - <<'PY'
import re, subprocess

def sysctl(n):
    return subprocess.run(["sysctl", "-n", n], capture_output=True, text=True).stdout.strip()

out = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
pg = int(re.search(r"page size of (\d+)", out).group(1))
vm = {}
for line in out.splitlines()[1:]:
    if ":" in line:
        k, v = line.split(":", 1)
        v = v.strip().rstrip(".")
        if v.isdigit():
            vm[k.strip()] = int(v)

GB = 1024 ** 3
total = int(sysctl("hw.memsize"))
free = (vm.get("Pages free", 0) + vm.get("Pages speculative", 0)) * pg
wired = vm.get("Pages wired down", 0) * pg
occupied = vm.get("Pages occupied by compressor", 0) * pg
stored = vm.get("Pages stored in compressor", 0) * pg

print(f"  installed        {total/GB:6.1f} GB")
print(f"  unused           {free/GB:6.1f} GB   ({100*free/total:.1f}%)")
print(f"  wired (kernel)   {wired/GB:6.1f} GB")
print(f"  compressor holds {occupied/GB:6.1f} GB of RAM", end="")
if occupied:
    print(f", storing {stored/GB:.1f} GB of anonymous memory ({stored/occupied:.2f}:1)")
else:
    print()
print("  " + subprocess.run(["sysctl", "vm.swapusage"], capture_output=True, text=True)
      .stdout.strip().replace("vm.swapusage: ", "swap             "))
print(f"  lifetime         swapins {vm.get('Swapins',0):,}  swapouts {vm.get('Swapouts',0):,}")
print()
print("  The compressor line is the one that matters. Every GB there is RAM spent")
print("  holding memory that no longer fits, and every access to it costs a")
print("  decompression. It is charged to no process, so it never appears in `top`.")
print()
print("  IGNORE `memory_pressure`'s \"free percentage\" — it counts compressed and")
print("  purgeable pages as free and will cheerfully report 65% on a box with")
print("  under a GB actually unused.")
PY

hr "3. TOP CPU"
ps -Ao pcpu=,rss=,etime=,comm= | sort -rn | head -10 \
  | awk '{n=split($4,p,"/"); printf "  %6s%%  %7.0f MB  %12s  %s\n", $1, $2/1024, $3, p[n]}'

hr "4. TOP RSS BY PROCESS"
ps -Ao rss=,pcpu=,etime=,comm= | sort -rn | head -10 \
  | awk '{n=split($4,p,"/"); printf "  %7.0f MB  %6s%%  %12s  %s\n", $1/1024, $2, $3, p[n]}'

hr "5. TOP RSS BY APP FAMILY"
# A browser is not one process, it is a hundred. Per-process ranking hides the
# single largest consumer on most dev machines behind its own helper pool.
python3 - <<'PY'
import collections, re, subprocess

rows = subprocess.run(["ps", "-Ao", "rss=,args="], capture_output=True, text=True).stdout.splitlines()
fam = collections.Counter()
cnt = collections.Counter()

def family(args):
    m = re.search(r"/([^/]+)\.app/", args)
    if m:
        return m.group(1)
    exe = args.split()[0] if args.split() else "?"
    base = exe.rsplit("/", 1)[-1]
    if base in ("node", "next-server", "webpack", "esbuild", "tsc", "vitest", "pnpm", "turbo"):
        return "node/dev toolchain"
    if base.startswith("mdworker") or base in ("mds", "mds_stores", "corespotlightd"):
        return "Spotlight indexing"
    return base

for line in rows:
    line = line.strip()
    if not line:
        continue
    rss, _, args = line.partition(" ")
    if not rss.isdigit():
        continue
    f = family(args.strip())
    fam[f] += int(rss)
    cnt[f] += 1

for f, kb in fam.most_common(10):
    print(f"  {kb/1024:7.0f} MB  {cnt[f]:4d} proc  {f}")
print()
print("  Resident totals double-count shared pages, so read these as an upper")
print("  bound and as a ranking, not as 'this much comes back if I quit it'.")
PY

hr "6. INDEXING STORM / FAT DEV SERVERS"
python3 - <<'PY2'
import collections, re, subprocess

# --- Spotlight ----------------------------------------------------------------
ps = subprocess.run(["ps", "-Ao", "pid=,pcpu=,rss=,comm="], capture_output=True, text=True).stdout
mdw = [l for l in ps.splitlines() if "mdworker_shared" in l]
mds = [l for l in ps.splitlines() if l.rstrip().endswith("/mds")]
mds_cpu = float(mds[0].split()[1]) if mds else 0.0
print(f"  mdworker_shared alive: {len(mdw)}    mds CPU: {mds_cpu:.0f}%")
if len(mdw) > 8 or mds_cpu > 40:
    print("  ^ INDEXING STORM. Spotlight re-scans anything that changes, and a dev")
    print("    machine changes constantly. Find what it is reading:")
    print("      lsof -c mdworker_shared | grep /Users")
    # Name the offender if we can catch one mid-read.
    hits = collections.Counter()
    try:
        out = subprocess.run(["lsof", "-c", "mdworker_shared"], capture_output=True,
                             text=True, timeout=20).stdout
        for m in re.finditer(r"(/Users/[^/]+/[^/]+/[^/\s]+)", out):
            hits[m.group(1)] += 1
    except Exception:
        pass
    for path, n in hits.most_common(3):
        print(f"      {n:4d} open  {path}")

# --- dev servers that have ballooned -----------------------------------------
rows = subprocess.run(["ps", "-Ao", "pid=,rss=,etime=,args="], capture_output=True, text=True).stdout
fat = []
for line in rows.splitlines():
    parts = line.split(None, 3)
    if len(parts) < 4:
        continue
    pid, rss, etime, args = parts
    if not rss.isdigit() or int(rss) < 3 * 1024 * 1024:   # under 3 GB
        continue
    if any(k in args for k in ("next-server", "next dev", "webpack", "vite", "tsc", "jest", "vitest")):
        fat.append((int(rss), pid, etime, args[:60]))
print()
if fat:
    for rss, pid, etime, args in sorted(fat, reverse=True):
        print(f"  {rss/1024/1024:5.1f} GB  pid {pid:<7} up {etime:<12} {args}")
    print()
    print("  A Next dev server is expected to sit around 1-3 GB. Past ~6 GB it has")
    print("  leaked, not grown: it will keep climbing and it does NOT shrink when")
    print("  idle. Restarting it costs one command and is the whole fix.")
else:
    print("  no build process over 3 GB")
PY2

hr "7. REAP CANDIDATES (dev watchers older than ${MIN_AGE_MIN}m)"
echo "  Build watchers hold RAM and a steady CPU trickle forever. Each one"
echo "  restarts with a single pnpm command."
echo
"$(dirname "$0")/reap.sh" --min-age-min "$MIN_AGE_MIN" --dry-run

hr "8. AGENT / TEST CONCURRENCY"
printf "  claude sessions: %s\n" "$(pgrep -x claude 2>/dev/null | wc -l | tr -d ' ')"
printf "  node processes:  %s\n" "$(pgrep -x node 2>/dev/null | wc -l | tr -d ' ')"
printf "  vitest workers:  %s\n" "$(ps -Ao args= | grep -c 'node ([v]itest' || true)"
printf "  tsc --noEmit:    %s\n" "$(ps -Ao args= | grep -c '[t]sc --noEmit' || true)"
printf "  relay drivers:   %s\n" "$(ps -Ao args= | grep '[r]elay\.sh' | grep -vc caffeinate || true)"
echo
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
try:
    env = json.load(open(p)).get("env", {})
except Exception:
    env = {}
for k in ("VITEST_MAX_FORKS", "VITEST_MAX_THREADS", "TURBO_CONCURRENCY"):
    print(f"  {k} = {env.get(k, 'UNSET  <-- uncapped')}")
PY
echo
echo "  vitest forks one worker PER CORE when uncapped, so on a ${NCPU}-core box"
echo "  one test run saturates the machine and N agents ask for N x that."
