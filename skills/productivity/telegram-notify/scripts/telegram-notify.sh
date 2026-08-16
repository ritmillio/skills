#!/usr/bin/env bash
#
# telegram-notify.sh — send a Telegram message through a bot. Three modes:
#
#   telegram-notify.sh "message"          ad-hoc send
#   telegram-notify.sh --relay "<body>"   relay's contract; event kind in $RELAY_EVENT
#   telegram-notify.sh --hook             read a Claude Code hook JSON payload on stdin
#
# Config: $TELEGRAM_BOT_TOKEN and $TELEGRAM_CHAT_ID from the environment, or
# from ~/.config/telegram-notify/config (override with $TELEGRAM_NOTIFY_CONFIG).
#
# This script is an observer. It must never break what it observes: missing
# config, missing jq, a failed send — all exit 0 silently.

set -u

CONFIG="${TELEGRAM_NOTIFY_CONFIG:-$HOME/.config/telegram-notify/config}"
[[ -f "$CONFIG" ]] && . "$CONFIG"

send() { # send <text>
  [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || return 0
  curl -sS -m 5 -o /dev/null \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" 2>/dev/null || true
  return 0
}

mode="${1:-}"
case "$mode" in
  --relay)
    event="${RELAY_EVENT:-event}"
    send "[relay ${event}] ${2:-}"
    ;;

  --hook)
    # A relay reports its own iterations with commit counts; the per-iteration
    # sessions' hooks must stay quiet.
    [[ "${CLAUDE_RELAY_ACTIVE:-}" == "1" ]] && exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    payload="$(cat)"
    event="$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)"
    cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
    case "$event" in
      Stop)
        send "[done] agent finished in ${cwd:+$(basename "$cwd")}"
        ;;
      PostToolUse)
        cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
        printf '%s' "$cmd" | grep -qE 'git( -C +[^ ]+)? +commit' || exit 0
        last=""
        [[ -n "$cwd" ]] && last="$(git -C "$cwd" log -1 --oneline 2>/dev/null)"
        send "[commit] ${cwd:+$(basename "$cwd")}: ${last:-commit landed}"
        ;;
      *)
        : # any other hook event stays silent
        ;;
    esac
    ;;

  "")
    : # no message, nothing to do
    ;;

  *)
    send "$*"
    ;;
esac

exit 0
