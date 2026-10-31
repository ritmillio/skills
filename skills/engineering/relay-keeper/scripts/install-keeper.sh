#!/usr/bin/env bash
# relay-keeper/install-keeper.sh - keep the keeper daemon alive with launchd.
#
#   install-keeper.sh                    # watch + throttle + prune, every 60 s
#   install-keeper.sh --revive           # also relaunch relays that died unexpectedly
#   install-keeper.sh --notify           # ping the relay notifier when the level changes
#   install-keeper.sh --interval 30
#   install-keeper.sh --status | --uninstall
#
# The daemon is one long-lived process on purpose: a throttle hold IS its PID,
# so if it dies the relays reclaim every slot by themselves.
set -uo pipefail

LABEL="ai.clausis.relay-keeper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
KEEPER="$(cd "$(dirname "$0")" && pwd)/keeper.sh"
INTERVAL=60
EXTRA=""

while [ $# -gt 0 ]; do
  case "$1" in
    --revive)   EXTRA="$EXTRA<string>--revive</string>"; shift ;;
    --notify)   EXTRA="$EXTRA<string>--notify</string>"; shift ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --status)
      launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -E 'state|pid' | head -3 \
        || echo "not installed"
      tail -3 "$HOME/.claude/relay-keeper/keeper.log" 2>/dev/null
      exit 0 ;;
    --uninstall)
      launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
      rm -f "$PLIST"
      echo "uninstalled $LABEL (its holds vanish with it; relays reclaim the slots)"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

[ "$(uname -s)" = Darwin ] || { echo "launchd is macOS only; on Linux run: $KEEPER --apply --loop $INTERVAL --quiet under systemd or nohup" >&2; exit 1; }
[ -x "$KEEPER" ] || { echo "keeper.sh not executable at $KEEPER" >&2; exit 1; }
mkdir -p "$(dirname "$PLIST")" "$HOME/.claude/relay-keeper"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$KEEPER</string>
    <string>--apply</string>
    <string>--loop</string><string>$INTERVAL</string>
    <string>--quiet</string>
    $EXTRA
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/.claude/relay-keeper/keeper.out</string>
  <key>StandardErrorPath</key><string>$HOME/.claude/relay-keeper/keeper.err</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>5</integer>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null
echo "installed $LABEL - every ${INTERVAL}s, report + throttle + prune${EXTRA:+ (+ options)}"
echo "  log:       ~/.claude/relay-keeper/keeper.log"
echo "  status:    $0 --status"
echo "  uninstall: $0 --uninstall"
