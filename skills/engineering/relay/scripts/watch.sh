#!/usr/bin/env bash
#
# watch.sh - what the relay is doing, right now, in your terminal.
#
# The relay is detached on purpose: it has to survive the terminal closing.
# That is also why it feels like nothing is happening. This reads the state the
# relay writes -- meta, status, done.status, live.log -- and redraws it.
#
# Usage:
#   watch.sh [--dir <worktree>] [--once] [--lines N] [--every SEC]
#
# --once prints a plain snapshot and exits (for scripts, and for an agent
# reporting in-session). Without it, and on a terminal, it redraws until you
# press Ctrl-C. Ctrl-C stops the watcher, never the relay.

set -uo pipefail

DIR=""; ONCE=0; LINES=14; EVERY=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)   DIR="$2"; shift 2 ;;
    --once)  ONCE=1; shift ;;
    --lines) LINES="$2"; shift 2 ;;
    --every) EVERY="$2"; shift 2 ;;
    *) echo "watch.sh: unknown flag: $1" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$DIR" ]]; then
  if [[ "$(basename "$HERE")" == ".loop" ]]; then DIR="$(dirname "$HERE")"; else DIR="$PWD"; fi
fi
STATE="$DIR/.loop"
[[ -d "$STATE" ]] || { echo "watch.sh: no relay state at $STATE" >&2; exit 2; }

[[ -t 1 ]] || ONCE=1

meta() { sed -n "s/^$1=//p" "$STATE/meta" 2>/dev/null | tail -1; }

hms() {  # seconds -> 3h07m
  local s="$1"
  (( s < 0 )) && s=0
  printf '%dh%02dm' $(( s / 3600 )) $(( (s % 3600) / 60 ))
}

render() {
  local branch pid deadline start hours iters landed cost now ended
  branch="$(meta BRANCH)"; pid="$(meta PID)"
  deadline="$(meta DEADLINE)"; start="$(meta START)"; hours="$(meta HOURS)"
  iters="$(meta ITER)"; landed="$(meta COMMITTED)"; cost="$(meta COST)"
  ended="$(meta ENDED)"; now=$(date +%s)
  # A finished run's elapsed time must stop growing after it finished.
  [[ "$ended" =~ ^[0-9]+$ ]] && now="$ended"

  local alive="not running"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then alive="pid $pid"; fi

  printf 'relay  %s  (%s)\n' "${branch:-?}" "$alive"
  printf '  %s\n' "$(cat "$STATE/status" 2>/dev/null || echo 'no status yet')"
  if [[ "$deadline" =~ ^[0-9]+$ && "$start" =~ ^[0-9]+$ ]]; then
    if [[ "$alive" == "not running" ]]; then
      printf '  ran %s   %s iterations, %s landed, $%s\n' \
        "$(hms $(( now - start )))" "${iters:-0}" "${landed:-0}" "${cost:-0}"
    else
      printf '  %s elapsed, %s left of %sh cap   %s iterations, %s landed, $%s\n' \
        "$(hms $(( now - start )))" "$(hms $(( deadline - now )))" "${hours:-?}" \
        "${iters:-0}" "${landed:-0}" "${cost:-0}"
    fi
  fi

  # The completion contract is the whole point of a run that ends on "done".
  if [[ -s "$STATE/done.status" ]] && grep -qv '^#' "$STATE/done.status" 2>/dev/null; then
    printf '\ndone when\n'
    while IFS=$'\t' read -r st name desc tail_line; do
      [[ "$st" == \#* || -z "${st:-}" ]] && continue
      if [[ "$st" == "PASS" ]]; then
        printf '  [x] %s\n' "$desc"
      else
        printf '  [ ] %s  -- %s\n' "$desc" "${tail_line:-$st}"
      fi
    done < "$STATE/done.status"
    printf '  %s\n' "$(grep -m1 '^# [0-9]' "$STATE/done.status" | sed 's/^# //')"
  fi

  if [[ -d "$DIR/.git" || -f "$DIR/.git" ]]; then
    printf '\nlanded\n'
    git -C "$DIR" log --oneline --no-decorate -5 2>/dev/null | sed 's/^/  /'
  fi

  printf '\nlive\n'
  if [[ -s "$STATE/live.log" ]]; then
    tail -n "$LINES" "$STATE/live.log" | sed 's/^/  /'
  else
    printf '  (nothing streamed yet)\n'
  fi
}

if (( ONCE )); then
  render
  exit 0
fi

trap 'printf "\nwatcher detached. the relay is still running -- stop it with: touch %s/STOP\n" "$STATE"; exit 0' INT TERM

while true; do
  printf '\033[H\033[2J'
  render
  printf '\n(refreshing every %ss -- Ctrl-C detaches, the relay keeps going)\n' "$EVERY"
  sleep "$EVERY"
done
