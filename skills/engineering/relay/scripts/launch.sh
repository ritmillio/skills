#!/usr/bin/env bash
#
# launch.sh - start the relay detached, so it survives the terminal closing.
#
# Usage: launch.sh --dir <worktree> --ledger docs/<slug>.md --branch <name> [relay flags...]
#
# --watch attaches the live dashboard once the relay is up. Detaching from it
# (Ctrl-C) does not stop the run; the relay never had a terminal to lose.

set -euo pipefail

DIR=""; WATCH=0
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch) WATCH=1; shift ;;
    --dir)   DIR="$2"; args+=("$1" "$2"); shift 2 ;;
    *)       args+=("$1"); shift ;;
  esac
done
[[ -n "$DIR" ]] || { echo "launch.sh: --dir is required" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$DIR/.loop"
mkdir -p "$STATE"
rm -f "$STATE/STOP"

# A long run dies of sleep far more often than of anything interesting.
# The inhibitor is the one OS-specific piece here; keep-awake.sh owns it.
KEEP_AWAKE_NOTE=""
# shellcheck source=keep-awake.sh
. "$HERE/keep-awake.sh"
CAFF=()
while IFS= read -r line; do [[ -n "$line" ]] && CAFF+=("$line"); done < <(keep_awake_prefix)

nohup "${CAFF[@]}" "$HERE/relay.sh" "${args[@]}" >>"$STATE/relay.stdout" 2>&1 &
PID=$!
echo "$PID" > "$STATE/relay.pid"
disown "$PID" 2>/dev/null || true

sleep 2
cat <<INFO
relay running detached, pid $PID
  $KEEP_AWAKE_NOTE

  watch : $STATE/watch.sh          (live dashboard: contract, commits, stream)
  stream: tail -f $STATE/live.log  (every tool call as it happens)
  log   : tail -f $STATE/relay.log (one line per iteration)
  status: $STATE/watch.sh --once   (one snapshot, no redraw)
  stop  : touch $STATE/STOP        (finishes the current iteration, then exits)
  kill  : kill $PID                (only if it is wedged)

Safe to close this terminal.
INFO

if (( WATCH )); then
  # relay.sh copies the helpers into .loop on startup; give it a moment.
  for _ in 1 2 3 4 5; do [[ -x "$STATE/watch.sh" ]] && break; sleep 1; done
  [[ -x "$STATE/watch.sh" ]] && exec "$STATE/watch.sh" --dir "$DIR"
fi
