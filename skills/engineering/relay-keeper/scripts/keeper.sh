#!/usr/bin/env bash
#
# keeper.sh - watch every running relay and the machine under them, and keep
# the box from crashing.
#
# Reads: RAM pressure, unused RAM, swap, live paging, CPU load per core, free
# SSD space, and every relay's own state files (.loop/meta, status, live.log).
# Acts (only with --apply) in the gentlest order that works:
#
#   1. THROTTLE  hold relay CPU slots so no NEW iteration starts. Relays already
#                queue on ~/.claude/relay-slots; a slot whose owner PID is dead
#                is reclaimed, so if this daemon dies every hold vanishes. Works
#                on relays of any version, with no change to them. A running
#                iteration is never touched: it drains.
#   2. PRUNE     delete old raw iteration streams (.loop/iter/*.jsonl) when the
#                disk is short.
#   3. REVIVE    (--revive) relaunch a relay that died without ending (reboot,
#                OOM, killed terminal) with the hours it had left.
#
# Never kills a process. Never touches a relay mid-iteration. Never stops a run.
#
#   keeper.sh                    # one report, changes nothing
#   keeper.sh --loop 60 --apply  # daemon: report, throttle, prune every 60 s
#   keeper.sh --apply --revive   # one pass that also relaunches dead relays
#   keeper.sh --release          # drop every hold a keeper owns
#
# Holds need a process that stays alive (--loop), because the hold IS that PID.
# A one-shot --apply can prune and revive but cannot throttle.
#
# Portable: macOS is the primary target; Linux gets /proc equivalents.

set -o pipefail

APPLY=0; LOOP=0; TICKS=0; REVIVE=0; NOTIFY=0; QUIET=0; RELEASE=0
KDIR="${RELAY_KEEPER_DIR:-$HOME/.claude/relay-keeper}"
SLOTS="${RELAY_SLOTS_DIR:-$HOME/.claude/relay-slots}"
NOTIFIER="${RELAY_NOTIFY:-$HOME/.claude/telegram-notify.sh}"
ROOTS="${RELAY_KEEPER_ROOTS:-$HOME/Developer}"      # colon-separated, scanned for dead relays

# Thresholds. Load is per core; RAM and swap are GB; disk is free GB.
LOAD_WARN="${KEEPER_LOAD_WARN:-1.2}";  LOAD_CRIT="${KEEPER_LOAD_CRIT:-2.0}"
SWAP_WARN="${KEEPER_SWAP_WARN:-8}";    SWAP_CRIT="${KEEPER_SWAP_CRIT:-24}"
PAGEOUT_CRIT="${KEEPER_PAGEOUT_CRIT:-50}"                  # pages/s; swap only reaches CRIT while this is live
DISK_WARN="${KEEPER_DISK_WARN:-60}";   DISK_CRIT="${KEEPER_DISK_CRIT:-25}"
WEDGE_MIN="${KEEPER_WEDGE_MIN:-30}"                     # a RUNNING relay silent this long is suspect
BAD_NEEDED="${KEEPER_BAD_NEEDED:-2}";   OK_NEEDED="${KEEPER_OK_NEEDED:-3}"      # hysteresis, in ticks

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)   APPLY=1; shift ;;
    --loop)    LOOP="$2"; shift 2 ;;
    --ticks)   TICKS="$2"; shift 2 ;;   # stop after N ticks (tests)
    --revive)  REVIVE=1; shift ;;
    --notify)  NOTIFY=1; shift ;;
    --quiet)   QUIET=1; shift ;;
    --release) RELEASE=1; shift ;;
    --load-crit) LOAD_CRIT="$2"; shift 2 ;;
    --swap-crit) SWAP_CRIT="$2"; shift 2 ;;
    --disk-crit) DISK_CRIT="$2"; shift 2 ;;
    *) echo "keeper.sh: unknown flag: $1" >&2; exit 2 ;;
  esac
done

OS="$(uname -s)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$KDIR" "$SLOTS"
STATEF="$KDIR/state"; LOGF="$KDIR/keeper.log"
say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# --- tiny key=value state, rewritten atomically ------------------------------
sget() { sed -n "s/^$1=//p" "$STATEF" 2>/dev/null | tail -1; }
sset() {
  { grep -v "^$1=" "$STATEF" 2>/dev/null; printf '%s=%s\n' "$1" "$2"; } > "$STATEF.tmp" \
    && mv -f "$STATEF.tmp" "$STATEF"
}

# --- holds: slot dirs owned by THIS process ----------------------------------
held() { local d; for d in "$SLOTS"/slot-*; do
  [ -d "$d" ] && [ "$(cat "$d/pid" 2>/dev/null)" = "$$" ] && echo "$d"; done; }
nheld() { held | wc -l | tr -d ' '; }

hold_one() {   # take the lowest free slot; relays scan 1..N so low numbers bind everyone
  local i d owner
  for (( i = 1; i <= SLOTN; i++ )); do
    d="$SLOTS/slot-$i"
    if mkdir "$d" 2>/dev/null; then echo $$ > "$d/pid"; return 0; fi
    owner="$(cat "$d/pid" 2>/dev/null)"
    if ! [[ "$owner" =~ ^[0-9]+$ ]] || ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$d"; mkdir "$d" 2>/dev/null && { echo $$ > "$d/pid"; return 0; }
    fi
  done
  return 1
}
release_one() { local d; d="$(held | sort -t- -k2 -n | tail -1)"; [ -n "$d" ] && rm -rf "$d"; }
release_all() { local d; for d in $(held); do rm -rf "$d"; done; }

if [ "$RELEASE" = 1 ]; then   # manual escape hatch: any keeper's holds, not just ours
  n=0
  for d in "$SLOTS"/slot-*; do
    [ -d "$d" ] || continue
    p="$(cat "$d/pid" 2>/dev/null)"
    if ps -o args= -p "$p" 2>/dev/null | grep -q 'keeper\.sh'; then rm -rf "$d"; n=$((n+1)); fi
  done
  echo "released $n keeper hold(s); the daemon (if running) will take them again, stop it first"
  exit 0
fi

# --- machine metrics ---------------------------------------------------------
metrics() {
  local sw
  if [ "$OS" = Darwin ]; then
    NCPU="$(sysctl -n hw.ncpu)"
    LOAD1="$(sysctl -n vm.loadavg | tr -d '{},' | awk '{gsub(",","."); print $1}')"
    PRESSURE="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)"
    read -r UNUSED PAGEOUTS < <(vm_stat | awk '
      /page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") pg = $(i+1) }
      /^Pages free/        { f = $3 + 0 }
      /^Pages speculative/ { s = $3 + 0 }
      /^Pages inactive/    { n = $3 + 0 }
      /^Pages purgeable/   { u = $3 + 0 }
      /^Pageouts/          { po = $2 + 0 }
      END { printf "%.1f %d\n", (f + s + n + u) * pg / 1073741824, po }')
    sw="$(sysctl -n vm.swapusage | sed -n 's/.*used = \([0-9.,]*\)\([MGK]\).*/\1 \2/p' | tr , .)"
    SWAP="$(printf '%s' "$sw" | awk '{u = $1; if ($2 == "M") u /= 1024; else if ($2 == "K") u /= 1048576; printf "%.1f", u}')"
    DISKPATH="/System/Volumes/Data"; [ -d "$DISKPATH" ] || DISKPATH="/"
  else
    NCPU="$(nproc 2>/dev/null || echo 1)"
    LOAD1="$(awk '{print $1}' /proc/loadavg)"
    UNUSED="$(awk '/MemAvailable/ {printf "%.1f", $2 / 1048576}' /proc/meminfo)"
    SWAP="$(awk '/SwapTotal/ {t = $2} /SwapFree/ {f = $2} END {printf "%.1f", (t - f) / 1048576}' /proc/meminfo)"
    PAGEOUTS="$(awk '/^pswpout/ {print $2}' /proc/vmstat)"
    PRESSURE=1
    gt "$UNUSED" "$(awk '/MemTotal/ {printf "%.1f", $2 * 0.10 / 1048576}' /proc/meminfo)" || PRESSURE=2
    DISKPATH="/"
  fi
  LOADPC="$(awk -v l="$LOAD1" -v n="$NCPU" 'BEGIN{printf "%.2f", l / n}')"
  local now prev_po prev_ts; now="$(date +%s)"
  prev_po="$(sget po)"; prev_ts="$(sget po_ts)"
  POUT_RATE=0
  if [ -n "$prev_po" ] && [ -n "$prev_ts" ] && [ "$now" -gt "$prev_ts" ] && [ "$PAGEOUTS" -ge "$prev_po" ]; then
    POUT_RATE=$(( (PAGEOUTS - prev_po) / (now - prev_ts) ))
  fi
  sset po "$PAGEOUTS"; sset po_ts "$now"
}
disk_free() { df -Pk "$1" 2>/dev/null | awk 'NR == 2 {printf "%.0f", $4 / 1048576}'; }

# --- relay discovery ---------------------------------------------------------
# One line per live relay: <dir>\t<max-parallel>. Deduped by dir, because the
# relay shows up as a bash, a caffeinate wrapper and a pipeline subshell.
discover() {
  ps -Ao args= | grep 'relay/scripts/relay\.sh' | grep -v grep | while IFS= read -r a; do
    d="$(printf '%s' "$a" | sed -n 's/.*relay\.sh .*--dir \([^ ]*\).*/\1/p')"
    [ -n "$d" ] || continue
    mp="$(printf '%s' "$a" | sed -n 's/.* --max-parallel \([0-9]*\).*/\1/p')"
    printf '%s\t%s\n' "$d" "${mp:-${RELAY_MAX_PARALLEL:-2}}"
  done | sort -u -k1,1
}
meta() { sed -n "s/^$2=//p" "$1/.loop/meta" 2>/dev/null | tail -1; }

# --- one tick ----------------------------------------------------------------
tick() {
  LEVEL=0; REASONS=""
  raise() { [ "$1" -gt "$LEVEL" ] && LEVEL="$1"
    REASONS="${REASONS}  $([ "$1" = 2 ] && echo CRIT || echo WARN)  $2"$'\n'; }
  metrics

  local live dirs=() mps=() line d mp
  live="$(discover)"
  SLOTN=2
  while IFS=$'\t' read -r d mp; do
    [ -n "$d" ] || continue
    dirs+=("$d"); mps+=("$mp"); [ "$mp" -gt "$SLOTN" ] && SLOTN="$mp"
  done <<< "$live"
  local nlive="${#dirs[@]}" hi
  hi="$(ls "$SLOTS" 2>/dev/null | sed -n 's/^slot-//p' | sort -n | tail -1)"
  [ -n "$hi" ] && [ "$hi" -gt "$SLOTN" ] && SLOTN="$hi"

  # --- machine verdict
  [ "$PRESSURE" -ge 4 ] && raise 2 "kernel memory pressure is critical"
  [ "$PRESSURE" = 2 ]   && raise 1 "kernel memory pressure is elevated"
  # Free pages alone mean nothing on macOS (it fills RAM with cache on purpose);
  # the kernel's own pressure level and live paging are the RAM verdict.
  if ge "$SWAP" "$SWAP_CRIT" && { [ "$POUT_RATE" -ge "$PAGEOUT_CRIT" ] || [ "$PRESSURE" -ge 2 ]; }; then
    raise 2 "swap ${SWAP} GB and still paging (${POUT_RATE} pages/s)"
  elif ge "$SWAP" "$SWAP_WARN"; then raise 1 "swap ${SWAP} GB in use (${POUT_RATE} pages/s paging)"; fi
  [ "$POUT_RATE" -ge "$PAGEOUT_CRIT" ] && raise 2 "live paging ${POUT_RATE} pages/s"
  if   ge "$LOADPC" "$LOAD_CRIT"; then raise 2 "load ${LOAD1} on ${NCPU} cores (${LOADPC}x)"
  elif ge "$LOADPC" "$LOAD_WARN"; then raise 1 "load ${LOAD1} on ${NCPU} cores (${LOADPC}x)"; fi
  DISKFREE="$(disk_free "$DISKPATH")"
  for d in "${dirs[@]}"; do
    local f; f="$(disk_free "$d")"; [ -n "$f" ] && [ "$f" -lt "$DISKFREE" ] && DISKFREE="$f"
  done
  if   [ "$DISKFREE" -lt "$DISK_CRIT" ]; then raise 2 "SSD free ${DISKFREE} GB (< ${DISK_CRIT})"
  elif [ "$DISKFREE" -lt "$DISK_WARN" ]; then raise 1 "SSD free ${DISKFREE} GB (< ${DISK_WARN})"; fi

  # --- per-relay table + findings
  local now rows="" i name st age left iter landed cost pid wedged
  now="$(date +%s)"
  for (( i = 0; i < nlive; i++ )); do
    d="${dirs[$i]}"; name="$(basename "$d")"
    st="$(head -c 200 "$d/.loop/status" 2>/dev/null | cut -c1-48)"; [ -n "$st" ] || st="?"
    age=$(( (now - $(mtime "$d/.loop/live.log")) / 60 ))
    left=$(( ( $(meta "$d" DEADLINE) - now ) / 60 )) 2>/dev/null
    iter="$(meta "$d" ITER)"; landed="$(meta "$d" COMMITTED)"; cost="$(meta "$d" COST)"
    wedged=""
    case "$st" in RUNNING*) [ "$age" -ge "$WEDGE_MIN" ] && {
      wedged=" <- silent ${age}m, possibly wedged"; raise 1 "$name: RUNNING but silent for ${age} min"; } ;; esac
    pid="$(meta "$d" PID)"
    if [ "$OS" = Darwin ] && ! ps -Ao args= | grep -F 'caffeinate' | grep -qF -- "--dir $d"; then
      raise 1 "$name: not under caffeinate, it will die when the Mac sleeps"
    fi
    rows="${rows}$(printf '  %-34s %-26s it %-3s landed %-3s $%-7s %4sm left%s' \
      "$name" "$st" "$iter" "$landed" "$cost" "$left" "$wedged")"$'\n'
  done

  # --- dead relays: pid gone, never wrote an end line, no STOP
  local roots r m dd dead="" DEAD_DIRS=""
  roots="$(printf '%s\n' "$ROOTS" | tr ':' '\n')"
  for r in $roots; do
    for m in "$r"/*/.loop/meta; do
      [ -f "$m" ] || continue
      dd="$(dirname "$(dirname "$m")")"
      case " ${dirs[*]} " in *" $dd "*) continue ;; esac
      [ -z "$(meta "$dd" ENDED)" ] || continue
      [ -f "$dd/.loop/STOP" ] && continue
      pid="$(meta "$dd" PID)"
      [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && continue
      grep -q '=== relay end' "$dd/.loop/relay.log" 2>/dev/null && continue
      [ "$(( $(meta "$dd" DEADLINE) - now ))" -gt 1800 ] || continue
      dead="${dead}  $(basename "$dd")  (ended without a goodbye, $(( ($(meta "$dd" DEADLINE) - now) / 60 )) min of budget left)"$'\n'
      DEAD_DIRS="${DEAD_DIRS}${dd}"$'\n'
      raise 1 "$(basename "$dd") died unexpectedly"
    done
  done

  # --- hysteresis + actions
  local bad ok holds; bad="$(sget bad)"; ok="$(sget ok)"; bad=${bad:-0}; ok=${ok:-0}
  if [ "$LEVEL" -ge 1 ]; then bad=$((bad+1)); ok=0; else ok=$((ok+1)); bad=0; fi
  holds="$(nheld)"; local acted=""
  if [ "$APPLY" = 1 ] && [ "$LOOP" -gt 0 ]; then
    if [ "$LEVEL" = 2 ] && [ "$bad" -ge "$BAD_NEEDED" ]; then
      while hold_one; do :; done; acted="drained: holding every free slot"
    elif [ "$LEVEL" -ge 1 ] && [ "$bad" -ge "$BAD_NEEDED" ] && [ "$(nheld)" -lt $((SLOTN-1)) ]; then
      hold_one && acted="throttled: holding one more slot"
    elif [ "$LEVEL" = 0 ] && [ "$ok" -ge "$OK_NEEDED" ] && [ "$holds" -gt 0 ]; then
      release_one; ok=0; acted="recovered: released one slot"
    fi
  fi
  sset bad "$bad"; sset ok "$ok"
  holds="$(nheld)"

  if [ "$APPLY" = 1 ] && [ "$LEVEL" -ge 1 ]; then   # prune raw streams only when it helps
    local freed=0 f
    for d in "${dirs[@]}"; do
      [ -d "$d/.loop/iter" ] || continue
      for f in $(ls -t "$d/.loop/iter"/*.jsonl 2>/dev/null | tail -n +11); do
        freed=$(( freed + $(wc -c < "$f") )); rm -f "$f"
      done
    done
    [ "$freed" -gt 0 ] && acted="${acted:+$acted; }pruned $((freed / 1048576)) MB of old iteration streams"
  fi

  if [ "$APPLY" = 1 ] && [ "$REVIVE" = 1 ] && [ "$LEVEL" = 0 ] && [ -n "$DEAD_DIRS" ]; then
    local relaunch k
    relaunch="$(dirname "$HERE")/../relay/scripts/launch.sh"
    [ -x "$relaunch" ] || relaunch="$HOME/.claude/skills/relay/scripts/launch.sh"
    while IFS= read -r dd; do
      [ -n "$dd" ] || continue
      k="rev_$(printf '%s' "$dd" | cksum | cut -d' ' -f1)"
      [ "$(sget "$k")" -ge 2 ] 2>/dev/null && continue          # two revives per relay, then a human looks
      local ban br le mo hrs
      ban="$(grep 'dir=.* branch=.* ledger=.* model=.* hours=' "$dd/.loop/relay.log" | tail -1)"
      br="$(sed -E 's/.* branch=([^ ]+).*/\1/' <<<"$ban")"; le="$(sed -E 's/.* ledger=([^ ]+).*/\1/' <<<"$ban")"
      mo="$(sed -E 's/.* model=([^ ]+).*/\1/' <<<"$ban")"
      hrs=$(( ( $(meta "$dd" DEADLINE) - now + 3599 ) / 3600 ))
      if [ -x "$relaunch" ] && [ -n "$br" ] && [ -n "$le" ]; then
        "$relaunch" --dir "$dd" --ledger "$le" --branch "$br" --hours "$hrs" --model "${mo:-opus}" \
          --compact-every 8 >>"$LOGF" 2>&1
        sset "$k" $(( $(sget "$k" || echo 0) + 1 ))
        acted="${acted:+$acted; }revived $(basename "$dd") for ${hrs}h"
      fi
    done <<< "$DEAD_DIRS"
  fi

  # --- report
  local word=OK; [ "$LEVEL" = 1 ] && word=WARN; [ "$LEVEL" = 2 ] && word=CRIT
  say "relay-keeper  $(date '+%Y-%m-%d %H:%M:%S')   level: $word   ($nlive live relay(s), $holds slot(s) held by keeper)"
  say "  load ${LOAD1}/${NCPU} (${LOADPC}x)  pressure ${PRESSURE}  reclaimable ${UNUSED} GB  swap ${SWAP} GB  paging ${POUT_RATE}/s  SSD free ${DISKFREE} GB"
  [ -n "$REASONS" ] && say "$(printf '%s' "$REASONS")"
  [ -n "$rows" ] && say "$(printf '%s' "$rows")"
  [ -n "$dead" ] && say "dead relays:" && say "$(printf '%s' "$dead")" && \
    [ "$REVIVE" = 0 ] && say "  relaunch with: keeper.sh --apply --revive (needs level OK)"
  [ -n "$acted" ] && say "action: $acted"
  [ "$APPLY" = 1 ] && [ "$LOOP" = 0 ] && [ "$LEVEL" -ge 1 ] && \
    say "note: throttling needs the daemon (--loop N --apply); this one-shot pass can only prune and revive"
  printf '%s level=%s load=%s unused=%s swap=%s pout=%s disk=%s relays=%s holds=%s %s\n' \
    "$(date '+%F %T')" "$word" "$LOADPC" "$UNUSED" "$SWAP" "$POUT_RATE" "$DISKFREE" "$nlive" "$holds" "$acted" >> "$LOGF"

  # --- notify on change only
  if [ "$NOTIFY" = 1 ] && [ -x "$NOTIFIER" ] && [ "$word" != "$(sget last_word)" ]; then
    RELAY_EVENT=keeper "$NOTIFIER" --relay "$(printf 'keeper: %s -> %s\n%s%s' "$(sget last_word)" "$word" "$REASONS" "${acted:+action: $acted}")" >/dev/null 2>&1 &
  fi
  sset last_word "$word"
  return "$LEVEL"
}

if [ "$LOOP" -gt 0 ]; then
  trap 'release_all' EXIT
  trap 'exit 0' INT TERM
  n=0
  while :; do tick; n=$((n+1)); [ "$TICKS" -gt 0 ] && [ "$n" -ge "$TICKS" ] && break; sleep "$LOOP"; done
else
  tick
fi
