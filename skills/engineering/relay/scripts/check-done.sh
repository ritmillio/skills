#!/usr/bin/env bash
#
# check-done.sh - run the run's completion contract and say what is left.
#
# A duration is a budget, not a goal. When the user says "run until X, Y and Z
# are done", each of X, Y and Z becomes one executable check in
# <worktree>/.loop/done.d/. This script runs them all and exits 0 only when
# every one passes -- that exit code is what ends the run.
#
# A check is any executable file. Its exit code is the verdict; a `# desc:`
# comment on any line gives it a human name:
#
#     #!/usr/bin/env bash
#     # desc: auth e2e suite green
#     npm run test:e2e -- auth
#
# Usage:
#   check-done.sh [--dir <worktree>] [--timeout <sec>] [--quiet]
#
# Called with no --dir from inside <worktree>/.loop it finds the worktree itself,
# so an iteration can just run `.loop/check-done.sh`.
#
# Exit: 0 every check passed   1 at least one failed   2 no checks defined

set -uo pipefail

DIR=""; TIMEOUT_S="${RELAY_CHECK_TIMEOUT:-900}"; QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     DIR="$2"; shift 2 ;;
    --timeout) TIMEOUT_S="$2"; shift 2 ;;
    --quiet)   QUIET=1; shift ;;
    *) echo "check-done.sh: unknown flag: $1" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$DIR" ]]; then
  if [[ "$(basename "$HERE")" == ".loop" ]]; then DIR="$(dirname "$HERE")"; else DIR="$PWD"; fi
fi
[[ -d "$DIR" ]] || { echo "check-done.sh: no such directory: $DIR" >&2; exit 2; }

STATE="$DIR/.loop"
DONE_DIR="$STATE/done.d"
OUT_DIR="$STATE/done.out"
STATUS="$STATE/done.status"
mkdir -p "$OUT_DIR"

TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"

checks=()
if [[ -d "$DONE_DIR" ]]; then
  while IFS= read -r f; do checks+=("$f"); done < <(
    find "$DONE_DIR" -maxdepth 1 -type f -perm -u+x ! -name '*.md' ! -name '.*' | sort
  )
fi

if (( ${#checks[@]} == 0 )); then
  (( QUIET )) || echo "no completion contract: $DONE_DIR holds no executable checks"
  printf '# no checks defined\n' > "$STATUS"
  exit 2
fi

pass=0; fail=0
tmp="$STATUS.tmp"
: > "$tmp"
printf '# checked %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$tmp"

for f in "${checks[@]}"; do
  name="$(basename "$f")"
  desc="$(sed -n 's/^[[:space:]]*#[[:space:]]*desc:[[:space:]]*//p' "$f" 2>/dev/null | head -1)"
  [[ -n "$desc" ]] || desc="$name"
  log="$OUT_DIR/$name.log"

  # Checks run from the worktree root: a check is a claim about the repository,
  # not about the directory it happens to live in.
  if [[ -n "$TIMEOUT_BIN" ]]; then
    ( cd "$DIR" && "$TIMEOUT_BIN" "$TIMEOUT_S" "$f" ) >"$log" 2>&1
  else
    ( cd "$DIR" && "$f" ) >"$log" 2>&1
  fi
  rc=$?

  case $rc in
    0)   state="PASS" ;;
    124) state="TIMEOUT" ;;
    *)   state="FAIL" ;;
  esac
  [[ "$state" == "PASS" ]] && pass=$(( pass + 1 )) || fail=$(( fail + 1 ))

  # The last non-empty line is nearly always the one that says why.
  tail_line="$(grep -v '^[[:space:]]*$' "$log" 2>/dev/null | tail -1 | tr '\t\n' '  ' | cut -c1-160)"
  [[ "$state" == "TIMEOUT" ]] && tail_line="no verdict after ${TIMEOUT_S}s"

  printf '%s\t%s\t%s\t%s\n' "$state" "$name" "$desc" "$tail_line" >> "$tmp"

  if (( QUIET == 0 )); then
    if [[ "$state" == "PASS" ]]; then
      printf '  [x] %-28s %s\n' "$name" "$desc"
    else
      printf '  [ ] %-28s %s  -- %s (%s)\n' "$name" "$desc" "$state" "${log/#$DIR\//}"
    fi
  fi
done

printf '# %s/%s passing\n' "$pass" "${#checks[@]}" >> "$tmp"
mv -f "$tmp" "$STATUS"

(( QUIET )) || printf '  %s/%s criteria met\n' "$pass" "${#checks[@]}"
(( fail == 0 )) && exit 0 || exit 1
