#!/usr/bin/env bash
#
# telegram-notify.sh — push Claude Code progress to Telegram.
#
# Four modes:
#   telegram-notify.sh                    hook mode: hook JSON on stdin, event read from it
#   RELAY_EVENT=<kind> ... --relay "<body>"   relay.sh's contract
#   telegram-notify.sh "message"          ad-hoc send (setup tests, scripts)
#   telegram-notify.sh --doctor           report config state, validate the token
#
# Claude Code hooks invoke this with NO arguments. Do not add a required flag
# to hook mode without rewiring every hook in settings.json at the same time.
#
# It must never break a session: every path exits 0 and the send is backgrounded,
# so Telegram being slow or down costs the turn nothing.
#
# Config lives in ~/.claude/telegram.env (chmod 600), never in settings.json.

set -u

CONF="${CLAUDE_TELEGRAM_ENV:-$HOME/.claude/telegram.env}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

: "${TELEGRAM_BOT_TOKEN:=}"
: "${TELEGRAM_CHAT_ID:=}"
: "${TELEGRAM_MIN_TURN_SECONDS:=120}"   # Stop pings only for turns longer than this
: "${TELEGRAM_NOTIFY_COMMIT:=1}"
: "${TELEGRAM_NOTIFY_PUSH:=1}"
: "${TELEGRAM_NOTIFY_TURN:=1}"
: "${TELEGRAM_NOTIFY_WAITING:=1}"
: "${TELEGRAM_NOTIFY_FAILURE:=1}"

# Unconfigured is a silent no-op, so the hooks are harmless before setup.
# --doctor and ad-hoc mode are the exceptions: a human ran those on purpose and
# deserves to be told why nothing arrived. Silence is the right default for a
# hook and the wrong one for a test.
configured() { [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; }

esc() { printf '%s' "${1:-}" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

send() {  # send <html-body>
  [ -n "${1:-}" ] || return 0
  configured || return 0
  # A backgrounded send cannot be asserted on, so tests need a seam.
  if [ "${TELEGRAM_NOTIFY_DRY_RUN:-0}" = "1" ]; then
    printf -- '--- telegram send ---\n%s\n' "$1"
    return 0
  fi
  ( curl -sS --max-time 10 \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "parse_mode=HTML" \
      -d "disable_web_page_preview=true" \
      --data-urlencode "text=$1" >/dev/null 2>&1 & ) >/dev/null 2>&1
  return 0
}

# "clausis.ai · feat/foo" — the header every message carries, so you know which
# checkout pinged you when three sessions are running.
where() {
  local d="${1:-$PWD}" top br
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || { basename "$d"; return; }
  br="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  printf '%s · %s' "$(basename "$top")" "$br"
}

trim() {  # trim <text> <max-chars>
  printf '%s' "${1:-}" | awk -v n="${2:-500}" '
    { buf = buf $0 "\n" }
    END { if (length(buf) > n) printf "%s…", substr(buf, 1, n); else printf "%s", buf }'
}

# ---------------------------------------------------------------------------
# Doctor: the mode that would have caught an empty token. Every other path is
# deliberately silent, which means a broken setup looks exactly like a quiet
# one. This is the only place that says so out loud.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--doctor" ]; then
  echo "config file : $CONF $([ -f "$CONF" ] && echo '(exists)' || echo '(MISSING)')"
  echo "bot token   : $([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "set, ${#TELEGRAM_BOT_TOKEN} chars, bot id ${TELEGRAM_BOT_TOKEN%%:*}" || echo 'EMPTY -- nothing will ever send')"
  echo "chat id     : ${TELEGRAM_CHAT_ID:-EMPTY -- nothing will ever send}"
  configured || { echo; echo "Not configured. Fill in $CONF, then re-run --doctor."; exit 0; }
  echo -n "getMe       : "
  curl -sS -m 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("unreadable response"); sys.exit(0)
if d.get("ok"):
    print("ok, bot is @%s" % d.get("result", {}).get("username", "?"))
else:
    print("FAILED %s %s -- token is wrong or revoked" % (d.get("error_code"), d.get("description")))
' 2>/dev/null || echo "no network"
  exit 0
fi

# ---------------------------------------------------------------------------
# Relay mode: relay.sh knows more than any hook does (commits landed, cost,
# iteration number), so it composes its own body and we only add the chrome.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--relay" ]; then
  case "${RELAY_EVENT:-}" in
    start)  icon="🚀"; title="Relay started" ;;
    landed) icon="✅"; title="Relay progress" ;;
    halt)   icon="🛑"; title="Relay HALTED" ;;
    limit)  icon="⏳"; title="Relay waiting on usage limit" ;;
    end)    icon="🏁"; title="Relay finished" ;;
    *)      icon="🔁"; title="Relay" ;;
  esac
  send "$(printf '%s <b>%s</b>\n\n%s' "$icon" "$title" "$(esc "${2:-}")")"
  exit 0
fi

# ---------------------------------------------------------------------------
# Ad-hoc: any other argument is the message. Used by setup tests and scripts.
# Hooks never pass arguments, so this cannot shadow hook mode.
# ---------------------------------------------------------------------------
if [ -n "${1:-}" ]; then
  if ! configured; then
    echo "telegram-notify: not configured ($CONF) -- nothing sent. Run --doctor." >&2
    exit 0
  fi
  send "$(esc "$*")"
  exit 0
fi

# ---------------------------------------------------------------------------
# Hook mode
# ---------------------------------------------------------------------------
configured || exit 0
INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

# A relay iteration is a `claude -p` and would fire these hooks too. relay.sh
# already sends a better message per iteration, so stay quiet inside one.
[ "${CLAUDE_RELAY_ACTIVE:-0}" = "1" ] && exit 0

EVENT="$(printf '%s' "$INPUT" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$EVENT" ] || exit 0

# Cheap pre-filter: PostToolUse fires on every Bash call, and almost none of
# them are interesting. Bail before spending a python process.
if [ "$EVENT" = "PostToolUse" ]; then
  # Loose on purpose: `git -C <worktree> commit` has no "git commit" substring.
  case "$INPUT" in
    *git*commit*|*git*push*) : ;;
    *) exit 0 ;;
  esac
fi

# One python pass for every field we might need. The separator is \x1f, not a
# tab: tab counts as IFS whitespace, so runs of empty fields would collapse and
# silently shift every later field by one.
FIELDS="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def g(*path):
    v = d
    for k in path:
        if not isinstance(v, dict):
            return ""
        v = v.get(k)
    return "" if v is None else str(v).replace("\x1f", " ").replace("\n", "\\n")
print("\x1f".join([
    g("cwd"), g("session_id"), g("tool_name"), g("tool_input", "command"),
    g("last_assistant_message"), g("stop_reason"), g("notification_type"),
    g("error_type"), g("error_message"),
]))' 2>/dev/null)"
[ -n "$FIELDS" ] || exit 0

IFS=$'\037' read -r CWD SESSION TOOL CMD LASTMSG STOPREASON NOTIFTYPE ERRTYPE ERRMSG <<< "$FIELDS"
CWD="${CWD:-$PWD}"
# python escaped real newlines as literal \n so the fields stay one per line.
unesc() { printf '%b' "${1:-}"; }

STAMP_DIR="${TMPDIR:-/tmp}"
STAMP="$STAMP_DIR/claude-turn-${SESSION:-unknown}"

case "$EVENT" in

  # Only records when the turn began, so Stop can filter out quick answers.
  UserPromptSubmit)
    date +%s > "$STAMP" 2>/dev/null
    ;;

  PostToolUse)
    did_commit=0; did_push=0
    case "$CMD" in *git*commit*) did_commit=1 ;; esac
    case "$CMD" in *git*push*)   did_push=1 ;; esac
    [ "$TELEGRAM_NOTIFY_COMMIT" = "1" ] || did_commit=0
    [ "$TELEGRAM_NOTIFY_PUSH"   = "1" ] || did_push=0

    # `git -C <dir>` means the commit landed somewhere other than the session
    # cwd - a relay worktree, usually. Report the repo that actually moved.
    gitdir="$CWD"
    case "$CMD" in
      *"git -C "*)
        p="${CMD#*git -C }"; p="${p%% *}"
        p="${p%\'}"; p="${p#\'}"; p="${p%\"}"; p="${p#\"}"
        [ -d "$p" ] && gitdir="$p"
        ;;
    esac

    if [ "$did_commit" = 1 ]; then
      # The commit itself is the evidence; the tool output is only a claim.
      subj="$(git -C "$gitdir" log -1 --pretty='%s' 2>/dev/null)"
      [ -n "$subj" ] || exit 0
      [ "$did_push" = 1 ] && hdr="Commit + push" || hdr="Commit"
      send "$(printf '✅ <b>%s</b> · %s\n\n<code>%s</code>' \
        "$hdr" "$(esc "$(where "$gitdir")")" "$(esc "$subj")")"
    elif [ "$did_push" = 1 ]; then
      send "$(printf '⬆️ <b>Pushed</b> · %s' "$(esc "$(where "$gitdir")")")"
    fi
    ;;

  Stop)
    [ "$TELEGRAM_NOTIFY_TURN" = "1" ] || exit 0
    started="$(cat "$STAMP" 2>/dev/null || echo 0)"
    rm -f "$STAMP" 2>/dev/null
    [ "$started" -gt 0 ] 2>/dev/null || exit 0
    elapsed=$(( $(date +%s) - started ))
    # A 20-second answer does not deserve a phone buzz.
    [ "$elapsed" -ge "$TELEGRAM_MIN_TURN_SECONDS" ] || exit 0
    mins=$(( elapsed / 60 )); secs=$(( elapsed % 60 ))
    send "$(printf '🟢 <b>Done</b> · %s <i>(%dm %ds)</i>\n\n%s' \
      "$(esc "$(where "$CWD")")" "$mins" "$secs" \
      "$(esc "$(trim "$(unesc "$LASTMSG")" 700)")")"
    ;;

  StopFailure)
    [ "$TELEGRAM_NOTIFY_FAILURE" = "1" ] || exit 0
    rm -f "$STAMP" 2>/dev/null
    send "$(printf '🔴 <b>Turn failed</b> · %s\n\n<b>%s</b>\n%s' \
      "$(esc "$(where "$CWD")")" "$(esc "${ERRTYPE:-unknown}")" \
      "$(esc "$(trim "$(unesc "$ERRMSG")" 400)")")"
    ;;

  Notification)
    [ "$TELEGRAM_NOTIFY_WAITING" = "1" ] || exit 0
    case "$NOTIFTYPE" in
      permission_prompt) body="Claude needs a permission decision." ;;
      idle_prompt)       body="Claude has been idle waiting for you." ;;
      agent_needs_input) body="A subagent needs input." ;;
      agent_completed)   body="A background agent finished." ;;
      *) exit 0 ;;
    esac
    send "$(printf '⏸️ <b>Waiting</b> · %s\n\n%s' "$(esc "$(where "$CWD")")" "$(esc "$body")")"
    ;;
esac

exit 0
