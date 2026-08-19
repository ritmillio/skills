#!/usr/bin/env bash
# reclaim/guard.sh — the preventive half. Runs on a timer, catches the four
# things that make a dev Mac unusable BEFORE the fan spins up.
#
# Report-only unless --apply. Designed for launchd (see install-guard.sh) or a
# /loop. Every run appends one line to the log whether or not it acted.
#
#   guard.sh                    # check and report
#   guard.sh --apply            # also reclaim idle browser renderers
#   guard.sh --apply --dev-kill # also kill dev servers over the size cap
#   guard.sh --notify           # ping Telegram when it finds something
set -uo pipefail

APPLY=0; DEV_KILL=0; NOTIFY=0; QUIET=0
FREE_MIN_GB=6        # act when unused RAM drops below this
DEV_MAX_GB=6         # a next dev / webpack past this has leaked
ARC_MIN_MB=150       # ignore small renderers; not worth a tab reload
UPTIME_WARN_DAYS=14
LOG="$HOME/.claude/reclaim-guard.log"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --dev-kill) DEV_KILL=1; shift ;;
    --notify) NOTIFY=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --free-min-gb) FREE_MIN_GB="$2"; shift 2 ;;
    --dev-max-gb) DEV_MAX_GB="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

say() { [ "$QUIET" = "1" ] || printf '%s\n' "$*"; }
FINDINGS=""
add() { FINDINGS="${FINDINGS}$1"$'\n'; }

phys() { top -l 1 -n 0 2>/dev/null | grep PhysMem; }
free_gb() {
  python3 - <<'PY'
import re, subprocess
o = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
pg = int(re.search(r"page size of (\d+)", o).group(1))
d = {}
for l in o.splitlines()[1:]:
    if ":" in l:
        k, v = l.split(":", 1); v = v.strip().rstrip(".")
        if v.isdigit(): d[k.strip()] = int(v)
print(f"{(d.get('Pages free',0)+d.get('Pages speculative',0))*pg/1024**3:.1f}")
PY
}

FREE=$(free_gb)
say "unused RAM: ${FREE} GB"

# --- 1. browser renderers ----------------------------------------------------
# The single biggest reclaimable pool on a dev Mac, and it refills every day.
IDLE_MB=$(ps -Ao pcpu=,rss=,args= | awk -v m="$ARC_MIN_MB" \
  '/Browser Helper \(Renderer\)/ && $1<1.0 && $2/1024>m {s+=$2} END {printf "%.0f", s/1024}')
IDLE_MB=${IDLE_MB:-0}
IDLE_N=$(ps -Ao pcpu=,rss=,args= | awk -v m="$ARC_MIN_MB" \
  '/Browser Helper \(Renderer\)/ && $1<1.0 && $2/1024>m {n++} END {print n+0}')
if [ "$IDLE_MB" -gt 2000 ]; then
  add "browser: ${IDLE_N} idle renderers holding ${IDLE_MB} MB"
  say "browser: ${IDLE_N} idle renderers holding ${IDLE_MB} MB"
  # Only reclaim when memory is actually tight — a tab reload is a real cost.
  if [ "$APPLY" = "1" ] && [ "${FREE%.*}" -lt "$FREE_MIN_GB" ]; then
    ps -Ao pid=,pcpu=,rss=,args= | awk -v m="$ARC_MIN_MB" \
      '/Browser Helper \(Renderer\)/ && $2<1.0 && $3/1024>m {print $1}' > /tmp/.guard_arc
    if [ -s /tmp/.guard_arc ]; then
      xargs kill -TERM < /tmp/.guard_arc 2>/dev/null
      sleep 3
      ps -Ao pid= | tr -d ' ' | grep -Fxf /tmp/.guard_arc 2>/dev/null | xargs kill -9 2>/dev/null
      add "  -> reclaimed ${IDLE_MB} MB from ${IDLE_N} renderers"
      say "  -> reclaimed ${IDLE_MB} MB"
    fi
  fi
fi

# --- 2. dev servers that have leaked ----------------------------------------
# Expected 1-3 GB. These do not shrink when idle, so waiting does not help.
ps -Ao pid=,rss=,etime=,args= | awk -v cap="$DEV_MAX_GB" '
  $2/1048576 > cap && /next-server|next dev|webpack|vite/ {
    printf "%s %.1f %s\n", $1, $2/1048576, $3 }' > /tmp/.guard_dev
if [ -s /tmp/.guard_dev ]; then
  while read -r pid gb et; do
    add "dev server: pid ${pid} at ${gb} GB (up ${et}) — leaked, restart it"
    say "dev server: pid ${pid} at ${gb} GB (up ${et})"
    if [ "$APPLY" = "1" ] && [ "$DEV_KILL" = "1" ]; then
      kill -TERM "$pid" 2>/dev/null; sleep 2; kill -9 "$pid" 2>/dev/null
      add "  -> killed pid ${pid}"
    fi
  done < /tmp/.guard_dev
fi

# --- 3. indexing storm -------------------------------------------------------
# Cannot be fixed without root, so this only ever reports. Loudly.
MDW=$(ps -Ao comm= | grep -c mdworker_shared)
if [ "$MDW" -gt 8 ]; then
  add "spotlight: ${MDW} mdworkers — indexing storm, load will run high at low CPU"
  add "  fix once, needs your password:  sudo mdutil -i off /System/Volumes/Data"
  say "spotlight: ${MDW} mdworkers — storm"
fi

# --- 4. uptime ---------------------------------------------------------------
# WindowServer leaks monotonically and nothing but a restart reclaims it.
DAYS=$(uptime | sed -n 's/.*up \([0-9]*\) day.*/\1/p'); DAYS=${DAYS:-0}
if [ "$DAYS" -ge "$UPTIME_WARN_DAYS" ]; then
  WS=$(ps -Ao rss=,comm= | awk '/WindowServer/{printf "%.0f", $1/1024}')
  add "uptime: ${DAYS} days, WindowServer at ${WS} MB — only a reboot clears this"
  say "uptime: ${DAYS} days (WindowServer ${WS} MB)"
fi

# --- report ------------------------------------------------------------------
TS=$(date '+%Y-%m-%d %H:%M:%S')
mkdir -p "$(dirname "$LOG")"
if [ -n "$FINDINGS" ]; then
  { echo "[$TS] free=${FREE}GB"; printf '%s' "$FINDINGS"; } >> "$LOG"
  if [ "$NOTIFY" = "1" ]; then
    N="$(dirname "$0")/../../../productivity/telegram-notify/scripts/telegram-notify.sh"
    [ -x "$N" ] && printf 'reclaim guard — free %s GB\n%s' "$FREE" "$FINDINGS" \
      | "$N" --stdin 2>/dev/null || true
  fi
  exit 1   # non-zero = something to look at
else
  echo "[$TS] free=${FREE}GB clean" >> "$LOG"
  say "clean"
fi
