#!/usr/bin/env bash
# reclaim/reap.sh — kill stale dev watchers. DRY RUN unless --yes.
#
# Only ever targets build/dev watchers that restart with one command. It will
# not touch an agent, a relay driver, an editor or a language server, and it
# refuses to guess about anything else.
#
# Usage:
#   reap.sh                      # dry run, 30m threshold
#   reap.sh --dry-run            # same, explicit
#   reap.sh --yes                # actually kill
#   reap.sh --min-age-min 120 --yes
set -uo pipefail

MIN_AGE_MIN=30
DO_KILL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)        DO_KILL=1; shift ;;
    --dry-run)       DO_KILL=0; shift ;;
    --min-age-min)   MIN_AGE_MIN="${2:-30}"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
MIN_AGE_S=$((MIN_AGE_MIN * 60))

# etime is [[dd-]hh:]mm:ss
age_seconds() {
  awk -v t="$1" 'BEGIN{
    d=0; split(t,a,"-");
    if (length(a)>1) { d=a[1]; t=a[2] } else { t=a[1] }
    n=split(t,b,":");
    if (n==3) s=b[1]*3600+b[2]*60+b[3];
    else if (n==2) s=b[1]*60+b[2];
    else s=b[1];
    print d*86400+s
  }'
}

TOTAL_KB=0
COUNT=0
PIDS=""

while IFS='|' read -r pid et rss args; do
  [ -n "${pid:-}" ] || continue

  # Protect list first — an agent or its driver is never a reap target, and
  # killing a relay mid-iteration loses uncommitted work.
  case "$args" in
    *claude*|*relay.sh*|*caffeinate*|*Code\ Helper*|*cursor*|*tsserver*|\
    *language-server*|*Electron*|*ssh-agent*) continue ;;
  esac

  # Allow list — long-lived watchers, each trivially restartable.
  case "$args" in
    *"next dev"*|*next-server*) label="next dev" ;;
    *"trigger dev"*)            label="trigger dev" ;;
    *esbuild*--service*--ping*) label="orphan esbuild service" ;;
    *word:dev*)                 label="word:dev" ;;
    *outlook:dev*)              label="outlook:dev" ;;
    *"pnpm run dev-server"*)    label="addin dev-server" ;;
    *webpack-loaders.js*)       label="next webpack helper" ;;
    *postcss.js*)               label="next postcss helper" ;;
    *"turbo dev"*)              label="turbo dev" ;;
    *"pnpm dev"*|*"pnpm run dev"*|*dev:web*|*dev:mobile*) label="pnpm dev" ;;
    *) continue ;;
  esac

  secs=$(age_seconds "$et")
  [ "$secs" -ge "$MIN_AGE_S" ] || continue

  printf "  pid %-7s %-12s %6s MB  %-22s %s\n" \
    "$pid" "$et" "$((rss / 1024))" "$label" "$(printf '%s' "$args" | cut -c1-70)"
  TOTAL_KB=$((TOTAL_KB + rss))
  COUNT=$((COUNT + 1))
  PIDS="$PIDS $pid"
done < <(ps -Ao pid=,etime=,rss=,args= | awk '{pid=$1; et=$2; rss=$3; $1=$2=$3=""; sub(/^ +/,""); print pid "|" et "|" rss "|" $0}')

echo
if [ "$COUNT" -eq 0 ]; then
  echo "  nothing stale (threshold ${MIN_AGE_MIN}m)"
  exit 0
fi
echo "  $COUNT processes, ~$((TOTAL_KB / 1024)) MB"

if [ "$DO_KILL" -eq 0 ]; then
  echo "  DRY RUN — re-run with --yes to kill"
  exit 0
fi

# SIGTERM first so watchers flush and remove their sockets; SIGKILL only the
# ones that ignore it.
# shellcheck disable=SC2086
kill $PIDS 2>/dev/null
sleep 3
STUBBORN=""
for p in $PIDS; do kill -0 "$p" 2>/dev/null && STUBBORN="$STUBBORN $p"; done
if [ -n "$STUBBORN" ]; then
  # shellcheck disable=SC2086
  kill -9 $STUBBORN 2>/dev/null
  echo "  SIGKILLed:$STUBBORN"
fi
echo "  reaped $COUNT processes, ~$((TOTAL_KB / 1024)) MB"
echo "  load now: $(sysctl -n vm.loadavg | tr -d '{}')"
