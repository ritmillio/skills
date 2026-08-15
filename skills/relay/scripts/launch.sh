#!/usr/bin/env bash
#
# launch.sh - start the relay detached, so it survives the terminal closing.
#
# Usage: launch.sh --dir <worktree> --ledger docs/<slug>.md --branch <name> [relay flags...]

set -euo pipefail

DIR=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  [[ "${args[$i]}" == "--dir" ]] && DIR="${args[$((i+1))]}"
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

nohup "${CAFF[@]}" "$HERE/relay.sh" "$@" >>"$STATE/relay.stdout" 2>&1 &
PID=$!
echo "$PID" > "$STATE/relay.pid"
disown "$PID" 2>/dev/null || true

sleep 2
cat <<INFO
relay running detached, pid $PID
  $KEEP_AWAKE_NOTE

  watch : tail -f $STATE/relay.log
  status: cat $STATE/status
  stop  : touch $STATE/STOP        (finishes the current iteration, then exits)
  kill  : kill $PID                (only if it is wedged)

Safe to close this terminal.
INFO
