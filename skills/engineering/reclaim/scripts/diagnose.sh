#!/usr/bin/env bash
# reclaim/diagnose.sh — read-only. Prints the split, the pressure, and a
# candidate reap list. Never kills anything.
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

hr "1. WHERE THE CPU ACTUALLY GOES"
# The first number to read. System% > User% means the kernel is the load, and
# killing your own processes will barely move it.
top -l 2 -n 0 -s 1 2>/dev/null | grep -E '^CPU usage' | tail -1
NCPU=$(sysctl -n hw.logicalcpu)
echo "logical cores: $NCPU"
echo "load average: $(sysctl -n vm.loadavg | tr -d '{}')"
echo "uptime:       $(uptime | sed 's/.*up //; s/,[^,]*users.*//')"

hr "2. MEMORY PRESSURE (a full swap surfaces as System%, not User%)"
sysctl vm.swapusage | sed 's/vm.swapusage: /swap: /'
echo "installed: $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB"
memory_pressure 2>/dev/null | grep -i 'free percentage' || true

hr "3. TOP CPU"
ps -Ao pcpu=,rss=,etime=,comm= | sort -rn | head -10 \
  | awk '{printf "  %6s%%  %7.0f MB  %12s  %s\n", $1, $2/1024, $3, $4}'

hr "4. TOP RSS"
ps -Ao rss=,pcpu=,etime=,comm= | sort -rn | head -10 \
  | awk '{printf "  %7.0f MB  %6s%%  %12s  %s\n", $1/1024, $2, $3, $4}'

hr "5. REAP CANDIDATES (dev watchers older than ${MIN_AGE_MIN}m)"
echo "  Build watchers hold RAM and a steady CPU trickle forever. Each one"
echo "  restarts with a single pnpm command."
echo
"$(dirname "$0")/reap.sh" --min-age-min "$MIN_AGE_MIN" --dry-run

hr "6. AGENT / TEST CONCURRENCY"
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
