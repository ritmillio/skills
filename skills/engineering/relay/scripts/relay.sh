#!/usr/bin/env bash
#
# relay.sh - drive an unattended run as a series of FRESH claude processes,
# one per iteration. Duration is set by --hours; 4 or 24 works the same way.
#
# Context rot is structurally impossible here. No process lives long enough to
# rot: each iteration is a new `claude -p` whose entire memory is the ledger
# file on disk plus the last few git commits. The relay itself never talks to a
# model; it only starts processes, asserts invariants, and records outcomes.
#
# Usage:
#   relay.sh --dir <worktree> --ledger <path-rel-to-dir> --branch <name> [opts]
#
# Stop it at any time:  touch <worktree>/.loop/STOP
# Watch it:             tail -f <worktree>/.loop/relay.log

set -uo pipefail   # deliberately NOT -e: one failed iteration must not end the night

DIR=""; LEDGER=""; BRANCH=""
HOURS=8; MODEL="opus"; FALLBACK="sonnet"
MAX_ITERS=200; COMPACT_EVERY=8; DRY_LIMIT=3
ITER_TIMEOUT=2700          # 45 min per iteration
BUDGET=""                  # optional --max-budget-usd per iteration
SETTLE=5                   # seconds between iterations

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)           DIR="$2"; shift 2 ;;
    --ledger)        LEDGER="$2"; shift 2 ;;
    --branch)        BRANCH="$2"; shift 2 ;;
    --hours)         HOURS="$2"; shift 2 ;;
    --model)         MODEL="$2"; shift 2 ;;
    --fallback)      FALLBACK="$2"; shift 2 ;;
    --max-iters)     MAX_ITERS="$2"; shift 2 ;;
    --compact-every) COMPACT_EVERY="$2"; shift 2 ;;
    --dry-limit)     DRY_LIMIT="$2"; shift 2 ;;
    --iter-timeout)  ITER_TIMEOUT="$2"; shift 2 ;;
    --budget)        BUDGET="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$DIR" && -n "$LEDGER" && -n "$BRANCH" ]] || {
  echo "relay.sh: --dir, --ledger and --branch are required" >&2; exit 2; }
[[ -d "$DIR" ]] || { echo "relay.sh: no such directory: $DIR" >&2; exit 2; }

# A loop must never be pointed at a protected branch, whatever the caller says.
case "$BRANCH" in
  main|master|staging|development)
    echo "relay.sh: refusing to run on protected branch '$BRANCH'" >&2; exit 2 ;;
esac

STATE="$DIR/.loop"
mkdir -p "$STATE/iter"
BRIEF="$STATE/brief.md"
COMPACT_BRIEF="$STATE/compaction-brief.md"
RELAY_LOG="$STATE/relay.log"
[[ -f "$BRIEF" ]] || { echo "relay.sh: missing $BRIEF (run setup first)" >&2; exit 2; }
[[ -f "$COMPACT_BRIEF" ]] || COMPACT_EVERY=0

# `timeout` is not on macOS by default; use whatever exists, else run bare.
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$RELAY_LOG"; }
status() { printf '%s\n' "$*" > "$STATE/status"; }

STOPPING=0
trap 'STOPPING=1; log "signal received, finishing after this iteration"' INT TERM

START=$(date +%s)
DEADLINE=$(( START + HOURS * 3600 ))
iter=0; dry=0; committed=0; failed=0; cost_total=0

log "=== relay start ==="
log "dir=$DIR branch=$BRANCH ledger=$LEDGER model=$MODEL hours=$HOURS"
log "stop with: touch $STATE/STOP"

while true; do
  iter=$(( iter + 1 ))
  now=$(date +%s)

  if [[ -f "$STATE/STOP" ]]; then log "STOP file present, ending"; break; fi
  if (( STOPPING )); then log "stopping on signal"; break; fi
  if (( now >= DEADLINE )); then log "wall-clock budget of ${HOURS}h reached"; break; fi
  if (( iter > MAX_ITERS )); then log "max iterations ($MAX_ITERS) reached"; break; fi
  if (( dry >= DRY_LIMIT )); then log "$dry consecutive no-progress iterations, ending"; break; fi

  # The single most dangerous thing in a shared checkout is a branch flip
  # underneath a running loop. Assert it every single iteration.
  cur="$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo UNKNOWN)"
  if [[ "$cur" != "$BRANCH" ]]; then
    log "FATAL branch drift: expected '$BRANCH', found '$cur'. Refusing to continue."
    status "HALTED branch-drift $cur"
    break
  fi

  if (( COMPACT_EVERY > 0 && iter % COMPACT_EVERY == 0 )); then
    kind="compact"; brief_file="$COMPACT_BRIEF"
  else
    kind="work"; brief_file="$BRIEF"
  fi

  n="$(printf '%03d' "$iter")"
  out="$STATE/iter/$n.json"; err="$STATE/iter/$n.err"
  head_before="$(git -C "$DIR" rev-parse HEAD)"
  remaining_min=$(( (DEADLINE - now) / 60 ))

  prompt="You are iteration ${iter} (${kind}) of an unattended loop. About ${remaining_min} minutes remain in the run.

$(cat "$brief_file")"

  log "--- iteration $iter ($kind) start ---"
  status "RUNNING iter=$iter kind=$kind since=$(date '+%H:%M:%S')"

  cmd=(claude -p "$prompt"
       --dangerously-skip-permissions
       --model "$MODEL"
       --output-format json
       --no-session-persistence)
  [[ -n "$FALLBACK" ]] && cmd+=(--fallback-model "$FALLBACK")
  [[ -n "$BUDGET"   ]] && cmd+=(--max-budget-usd "$BUDGET")

  if [[ -n "$TIMEOUT_BIN" ]]; then
    ( cd "$DIR" && "$TIMEOUT_BIN" "$ITER_TIMEOUT" "${cmd[@]}" ) >"$out" 2>"$err"
  else
    ( cd "$DIR" && "${cmd[@]}" ) >"$out" 2>"$err"
  fi
  rc=$?

  head_after="$(git -C "$DIR" rev-parse HEAD)"
  is_error="$(jq -r '.is_error // "true"' "$out" 2>/dev/null || echo true)"
  cost="$(jq -r '.total_cost_usd // 0' "$out" 2>/dev/null || echo 0)"
  result="$(jq -r '.result // ""' "$out" 2>/dev/null || echo '')"
  cost_total="$(awk -v a="$cost_total" -v b="$cost" 'BEGIN{printf "%.4f", a+b}')"

  if (( rc == 124 )); then
    log "iteration $iter TIMED OUT after ${ITER_TIMEOUT}s"
  elif (( rc != 0 )); then
    log "iteration $iter exited rc=$rc  $(head -c 300 "$err" | tr '\n' ' ')"
  fi

  if [[ "$head_before" != "$head_after" ]]; then
    dry=0; committed=$(( committed + 1 ))
    landed="$(git -C "$DIR" log --oneline "$head_before..$head_after" | wc -l | tr -d ' ')"
    log "iteration $iter landed $landed commit(s)  cost=\$$cost  total=\$$cost_total"
    git -C "$DIR" log --oneline "$head_before..$head_after" | sed 's/^/    /' | tee -a "$RELAY_LOG" >/dev/null

    # Push so the draft PR reflects the night's progress while it is still running.
    if git -C "$DIR" push -q origin "$BRANCH" 2>>"$err"; then
      log "    pushed $BRANCH"
    else
      log "    push failed (non-fatal, will retry next iteration)"
    fi
  else
    dry=$(( dry + 1 ))
    if [[ "$is_error" == "true" || $rc -ne 0 ]]; then failed=$(( failed + 1 )); fi
    log "iteration $iter produced no commit (dry $dry/$DRY_LIMIT)  cost=\$$cost"
  fi

  # Keep the last line of the model's own report in the relay log: it is the
  # only place a human sees why an iteration decided what it decided.
  [[ -n "$result" ]] && printf '    report: %s\n' "$(printf '%s' "$result" | tr '\n' ' ' | cut -c1-400)" >> "$RELAY_LOG"

  sleep "$SETTLE"
done

elapsed=$(( ( $(date +%s) - START ) / 60 ))
# Every break path leaves `iter` one past the last iteration that actually ran.
ran=$(( iter - 1 ))
log "=== relay end: ${ran} iterations, ${committed} landed, ${failed} failed, ${elapsed} min, \$${cost_total} ==="
status "DONE iters=$ran landed=$committed failed=$failed cost=$cost_total"
