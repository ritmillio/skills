#!/usr/bin/env bash
# reclaim/install-guard.sh — run guard.sh on a timer via launchd.
#
#   install-guard.sh                 # every 10 min, report-only
#   install-guard.sh --apply         # also reclaim idle renderers when tight
#   install-guard.sh --interval 300
#   install-guard.sh --uninstall
set -uo pipefail

LABEL="ai.clausis.reclaim-guard"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUARD="$(cd "$(dirname "$0")" && pwd)/guard.sh"
INTERVAL=600
ARGS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)     ARGS="$ARGS<string>--apply</string>"; shift ;;
    --dev-kill)  ARGS="$ARGS<string>--dev-kill</string>"; shift ;;
    --notify)    ARGS="$ARGS<string>--notify</string>"; shift ;;
    --interval)  INTERVAL="$2"; shift 2 ;;
    --uninstall)
      launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
      rm -f "$PLIST"
      echo "uninstalled $LABEL"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

[ -x "$GUARD" ] || { echo "guard.sh not executable at $GUARD" >&2; exit 1; }
mkdir -p "$(dirname "$PLIST")"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$GUARD</string>
    <string>--quiet</string>
    $ARGS
  </array>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/.claude/reclaim-guard.out</string>
  <key>StandardErrorPath</key><string>$HOME/.claude/reclaim-guard.err</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null \
  || launchctl load "$PLIST" 2>/dev/null
echo "installed $LABEL — every ${INTERVAL}s"
echo "  log:       ~/.claude/reclaim-guard.log"
echo "  uninstall: $0 --uninstall"
