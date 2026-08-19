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
#
# Usage limits: an exhausted usage window is NOT a dry iteration. The relay
# detects the limit-reached error, waits for the window to reset (STOP still
# honored), extends the deadline by the time it waited, and carries on.

set -uo pipefail   # deliberately NOT -e: one failed iteration must not end the night

DIR=""; LEDGER=""; BRANCH=""
HOURS=8; MODEL="opus"; FALLBACK="sonnet"
MAX_ITERS=200; COMPACT_EVERY=8; DRY_LIMIT=3
ITER_TIMEOUT=2700          # 45 min per iteration
MAX_PARALLEL="${RELAY_MAX_PARALLEL:-2}"   # relay iterations allowed to run at once, machine-wide
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
    --max-parallel)  MAX_PARALLEL="$2"; shift 2 ;;
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

# Optional outbound notifier. Any executable taking `--relay <body>` with the
# event kind in $RELAY_EVENT works; unset or missing means the relay is silent.
# Backgrounded and never checked: a notification must not be able to end a run.
NOTIFY="${RELAY_NOTIFY:-$HOME/.claude/telegram-notify.sh}"
notify() {  # notify <start|landed|halt|limit|end> <body>
  [[ -x "$NOTIFY" ]] || return 0
  ( RELAY_EVENT="$1" "$NOTIFY" --relay "$2" >/dev/null 2>&1 & ) >/dev/null 2>&1
  return 0
}
# Each iteration is a `claude -p` that would fire the user's own Stop/commit
# hooks. Suppress those; the relay reports iterations itself, with commit counts.
export CLAUDE_RELAY_ACTIVE=1

# --- machine-wide iteration semaphore ---------------------------------------
# Several relays on one laptop each run a full gate suite -- vitest, tsc at an
# 8GB heap, webpack add-in builds. Vitest alone forks one worker per core, so
# two relays entering their gates in the same minute ask for several times the
# cores the machine has; the box thrashes at load 60+ and every iteration gets
# slower, including the interactive session the human is using.
#
# Slots are directories: mkdir is atomic, so winning one is race-free. Each
# holds the PID of its owner, and a slot whose owner died is reclaimed. A relay
# that cannot get a slot waits, but only for a bounded time -- a lock must
# never be able to end the night, so after ITER_TIMEOUT it proceeds anyway.
SLOTS="$HOME/.claude/relay-slots"
MY_SLOT=""
mkdir -p "$SLOTS"

slot_release() {
  [[ -n "$MY_SLOT" && -d "$MY_SLOT" ]] && rm -rf "$MY_SLOT"
  MY_SLOT=""
}

slot_try() {   # one pass over the slots; sets MY_SLOT on success
  local i d owner
  for (( i = 1; i <= MAX_PARALLEL; i++ )); do
    d="$SLOTS/slot-$i"
    if mkdir "$d" 2>/dev/null; then
      echo $$ > "$d/pid"; MY_SLOT="$d"; return 0
    fi
    # Occupied: reclaim it if the owner is gone (crash, kill -9, reboot).
    owner="$(cat "$d/pid" 2>/dev/null || echo 0)"
    if [[ ! "$owner" =~ ^[0-9]+$ ]] || ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$d"
      if mkdir "$d" 2>/dev/null; then
        echo $$ > "$d/pid"; MY_SLOT="$d"; return 0
      fi
    fi
  done
  return 1
}

slot_acquire() {
  (( MAX_PARALLEL <= 0 )) && return 0
  local waited=0 announced=0
  while ! slot_try; do
    [[ -f "$STATE/STOP" ]] && return 1
    (( STOPPING )) && return 1
    if (( announced == 0 )); then
      log "waiting for a CPU slot ($MAX_PARALLEL in use machine-wide)"
      status "WAITING cpu-slot since=$(date '+%H:%M:%S')"
      announced=1
    fi
    if (( waited >= ITER_TIMEOUT )); then
      log "no CPU slot after ${ITER_TIMEOUT}s, proceeding anyway"
      return 0
    fi
    # Jitter, so relays that fell into lockstep do not keep colliding.
    local nap=$(( 20 + RANDOM % 25 ))
    sleep "$nap"; waited=$(( waited + nap ))
  done
  return 0
}

# Never leave a slot behind, whatever ends this relay.
trap 'slot_release' EXIT

STOPPING=0
trap 'STOPPING=1; log "signal received, finishing after this iteration"' INT TERM

START=$(date +%s)
DEADLINE=$(( START + HOURS * 3600 ))
iter=0; dry=0; committed=0; failed=0; cost_total=0
limit_waited=0; LIMIT_WAIT_CAP=43200   # give up after 12h of cumulative limit waits

log "=== relay start ==="
log "dir=$DIR branch=$BRANCH ledger=$LEDGER model=$MODEL hours=$HOURS"
log "max-parallel=$MAX_PARALLEL (machine-wide relay iteration slots)"
log "stop with: touch $STATE/STOP"
notify start "$(printf 'branch: %s\nledger: %s\nmodel: %s, budget: %sh\ndir: %s' \
  "$BRANCH" "$LEDGER" "$MODEL" "$HOURS" "$DIR")"

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
    notify halt "$(printf 'Branch drift on %s.\nExpected %s, found %s. Run stopped.' \
      "$(basename "$DIR")" "$BRANCH" "$cur")"
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

  if ! slot_acquire; then log "stopping while waiting for a CPU slot"; break; fi

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
  slot_release

  head_after="$(git -C "$DIR" rev-parse HEAD)"
  is_error="$(jq -r '.is_error // "true"' "$out" 2>/dev/null || echo true)"
  cost="$(jq -r '.total_cost_usd // 0' "$out" 2>/dev/null || echo 0)"
  result="$(jq -r '.result // ""' "$out" 2>/dev/null || echo '')"
  cost_total="$(awk -v a="$cost_total" -v b="$cost" 'BEGIN{printf "%.4f", a+b}')"

  # --- usage-limit wait ------------------------------------------------------
  # An exhausted usage window makes `claude -p` fail in seconds. That is not a
  # dry iteration -- nothing was attempted -- so it must not burn the dry
  # budget. Wait for the window to reset, give the paused time back to the
  # deadline, and retry. STOP is honored during the wait.
  limit_msg=""
  if [[ "$head_before" == "$head_after" && ( "$is_error" == "true" || $rc -ne 0 ) ]]; then
    limit_msg="$( { printf '%s\n' "$result"; head -c 2000 "$out" 2>/dev/null; \
                    head -c 2000 "$err" 2>/dev/null; } \
                  | grep -iE 'usage limit|rate limit|session limit|weekly limit|limit reached|hit your limit|reached your limit|resets [0-9]|try again (later|in)' | head -1 )"
  fi
  if [[ -n "$limit_msg" ]]; then
    # Claude Code appends the reset time as "...|<epoch>" when it knows it.
    reset_epoch="$( { printf '%s\n' "$result"; head -c 2000 "$out" 2>/dev/null; } \
                    | grep -oE '\|[0-9]{9,10}' | head -1 | tr -d '|' )"
    now=$(date +%s)
    if [[ -n "$reset_epoch" ]] && (( reset_epoch > now )); then
      wait_s=$(( reset_epoch - now + 120 ))
    else
      wait_s=900   # reset time unknown: probe again in 15 minutes
    fi
    (( wait_s > 21600 )) && wait_s=21600
    if (( limit_waited + wait_s > LIMIT_WAIT_CAP )); then
      log "cumulative usage-limit waits would exceed $(( LIMIT_WAIT_CAP / 3600 ))h, ending"
      status "HALTED usage-limit-wait-cap"
      notify halt "Usage-limit waiting cap reached on $BRANCH. Run stopped."
      break
    fi
    log "iteration $iter blocked by usage limit: $(printf '%s' "$limit_msg" | tr '\n' ' ' | cut -c1-160)"
    log "waiting ${wait_s}s for the window to reset (touch $STATE/STOP to end)"
    notify limit "$(printf 'Iteration %s hit the usage limit on %s.\nWaiting %s min, then carrying on. Deadline extended.' \
      "$iter" "$BRANCH" "$(( wait_s / 60 ))")"
    status "WAITING usage-limit ${wait_s}s from $(date '+%H:%M:%S')"
    waited=0
    while (( waited < wait_s )); do
      [[ -f "$STATE/STOP" ]] && break
      (( STOPPING )) && break
      sleep 60; waited=$(( waited + 60 ))
    done
    limit_waited=$(( limit_waited + waited ))
    DEADLINE=$(( DEADLINE + waited ))   # the pause must not eat working hours
    iter=$(( iter - 1 ))                # a blocked probe is not an iteration
    continue
  fi
  # ---------------------------------------------------------------------------

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
    notify landed "$(printf 'iteration %s on %s landed %s commit(s)  ($%s so far)\n\n%s' \
      "$iter" "$BRANCH" "$landed" "$cost_total" \
      "$(git -C "$DIR" log --oneline --no-decorate "$head_before..$head_after")")"
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
notify end "$(printf '%s: %s iterations, %s landed, %s failed, %s min, $%s\n\n%s' \
  "$BRANCH" "$ran" "$committed" "$failed" "$elapsed" "$cost_total" \
  "$(git -C "$DIR" log --oneline --no-decorate -12 2>/dev/null)")"
