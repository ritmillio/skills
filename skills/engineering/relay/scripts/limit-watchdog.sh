#!/usr/bin/env bash
#
# limit-watchdog.sh - babysit a relay that was launched with a relay.sh that
# did not yet know how to wait out usage limits. If the relay dies because
# limit-reached failures burned its dry budget, relaunch it with the hours the
# original run had left; the relaunch executes the current relay.sh, which
# waits out limits itself, so one relaunch is normally all it ever does.
#
# It never resurrects a run that ended for a real reason (STOP, hour budget,
# genuinely out of work, branch drift).
#
# Usage: limit-watchdog.sh --dir <worktree>
# Stop:  kill $(cat <worktree>/.loop/watchdog.pid)

set -uo pipefail

DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$DIR" && -d "$DIR" ]] || { echo "limit-watchdog.sh: --dir required" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$DIR/.loop"
LOG="$STATE/relay.log"
WLOG="$STATE/watchdog.log"
echo $$ > "$STATE/watchdog.pid"
wlog() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$WLOG"; }

# Recover the original run's parameters from its own start banner.
banner="$(grep 'dir=.* branch=.* ledger=.* model=.* hours=' "$LOG" 2>/dev/null | tail -1)"
[[ -n "$banner" ]] || { echo "limit-watchdog.sh: no run banner in $LOG" >&2; exit 2; }
BRANCH="$(sed -E 's/.* branch=([^ ]+).*/\1/' <<<"$banner")"
LEDGER="$(sed -E 's/.* ledger=([^ ]+).*/\1/' <<<"$banner")"
MODEL="$(sed -E 's/.* model=([^ ]+).*/\1/' <<<"$banner")"
HOURS="$(sed -E 's/.* hours=([0-9]+).*/\1/' <<<"$banner")"
start_ts="$(grep '=== relay start ===' "$LOG" | tail -1 | awk '{print $1" "$2}')"
START_EPOCH="$(date -j -f '%Y-%m-%d %H:%M:%S' "$start_ts" +%s 2>/dev/null \
               || date -d "$start_ts" +%s 2>/dev/null)"
[[ -n "$START_EPOCH" ]] || { echo "limit-watchdog.sh: cannot parse start time" >&2; exit 2; }
DEADLINE=$(( START_EPOCH + HOURS * 3600 ))

relaunches=0
wlog "watching $DIR  branch=$BRANCH  original deadline in $(( (DEADLINE - $(date +%s)) / 60 )) min"

while true; do
  sleep 300
  now=$(date +%s)
  if (( now > DEADLINE + 43200 )); then wlog "12h past deadline, exiting"; break; fi

  pid="$(cat "$STATE/relay.pid" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then continue; fi

  # The relay is dead. Resurrect ONLY a limit-starved run.
  if [[ -f "$STATE/STOP" ]]; then wlog "STOP file present, exiting"; break; fi
  if ! tail -5 "$LOG" 2>/dev/null | grep -q 'consecutive no-progress iterations'; then
    wlog "relay ended for a non-dry reason, exiting"; break
  fi
  recent="$(ls -t "$STATE"/iter/* 2>/dev/null | head -6)"
  sig=0
  if [[ -n "$recent" ]]; then
    sig="$(printf '%s\n' "$recent" | xargs -I{} tail -c 4000 {} 2>/dev/null \
           | grep -icE 'usage limit|rate limit|limit reached' || true)"
  fi
  if [[ -z "$sig" || "$sig" == "0" ]]; then
    wlog "relay ran dry with no limit signature (genuinely out of work), exiting"; break
  fi

  remaining=$(( DEADLINE - now ))
  if (( remaining < 900 )); then wlog "under 15 min of budget left, exiting"; break; fi
  if (( relaunches >= 3 )); then wlog "3 relaunches used, exiting"; break; fi

  hrs=$(( (remaining + 3599) / 3600 ))
  relaunches=$(( relaunches + 1 ))
  wlog "relay died limit-starved; relaunch #$relaunches with --hours $hrs"
  "$HERE/launch.sh" --dir "$DIR" --ledger "$LEDGER" --branch "$BRANCH" \
    --hours "$hrs" --model "$MODEL" --compact-every 8 >>"$WLOG" 2>&1
  sleep 60
done
