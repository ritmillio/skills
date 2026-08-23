#!/usr/bin/env bash
#
# progress.sh - turn a `claude -p --output-format stream-json` stream into one
# human line per thing that happened, while it is happening.
#
# A relay iteration can run for 45 minutes. With --output-format json nothing
# leaves the process until it is over, so a detached run looks identical to a
# hung one for most of its life. Streaming the events and formatting them here
# is what makes `tail -f` and watch.sh worth looking at.
#
# Reads JSONL on stdin, writes plain text on stdout. Never fails and never
# blocks: if jq is missing or a line is unparseable, the stream still drains.
#
# Usage:  claude -p ... --output-format stream-json --verbose | progress.sh 007

set -uo pipefail

TAG="${1:-}"
WIDTH="${RELAY_PROGRESS_WIDTH:-200}"

command -v jq >/dev/null 2>&1 || { cat >/dev/null; exit 0; }

# One event can produce several lines (an assistant turn holds several content
# blocks), so the filter streams rather than returning a single string.
FILTER='
def clean: (. // "") | gsub("\n+"; " ") | gsub("  +"; " ");
def blocks: if (.message.content | type) == "array" then .message.content[] else empty end;

if .type == "system" and .subtype == "init" then
  "> start" + (if .model then " model=" + .model else "" end)

elif .type == "assistant" then
  blocks |
    if .type == "tool_use" then
      .name as $n | (.input // {}) as $i |
      if   $n == "Bash"        then "$ " + ($i.command | clean)
      elif $n == "Edit" or $n == "Write" or $n == "MultiEdit" or $n == "NotebookEdit"
                               then "edit " + ($i.file_path // $i.notebook_path // "?")
      elif $n == "Read"        then "read " + ($i.file_path // "?")
      elif $n == "Grep" or $n == "Glob"
                               then "find " + (($i.pattern // $i.query // "") | clean)
      elif $n == "Task" or $n == "Agent"
                               then "agent " + (($i.description // $i.prompt // "") | clean)
      elif $n == "TodoWrite"   then empty
      else "tool " + $n + " " + (($i | tostring) | clean) end
    elif .type == "text" then
      (.text | clean) | select(length > 0) | ". " + .
    else empty end

elif .type == "user" then
  blocks |
    select(.type == "tool_result" and .is_error == true) |
    "! " + ((.content | if type == "array" then (map(.text // "") | join(" ")) else (. // "" | tostring) end) | clean)

elif .type == "result" then
  "= end " + (.subtype // "?")
  + " turns=" + ((.num_turns // 0) | tostring)
  + " cost=$" + ((.total_cost_usd // 0) | tostring)
  + (if .is_error == true then "  ERROR" else "" end)

else empty end
'

# One jq per event rather than one long-lived jq: at a few hundred events per
# iteration the cost is nothing, and it keeps every line timestamped with the
# moment it actually happened instead of the moment jq flushed.
while IFS= read -r ev; do
  [[ -n "$ev" ]] || continue
  ts="$(date '+%H:%M:%S')"
  printf '%s\n' "$ev" | jq -r "$FILTER" 2>/dev/null | while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s  %s  %.*s\n' "$ts" "$TAG" "$WIDTH" "$line"
  done
done

exit 0
