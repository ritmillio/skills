#!/usr/bin/env bash
# mac-compromise-check/scan.sh — READ-ONLY macOS compromise triage.
#
# Walks the places persistence and remote access actually live and prints what
# is there. It never kills a process, deletes a file, changes a setting, or
# makes a network request. Every command here observes; none mutate.
#
# Two sections (firewall state, root-level launchd) need sudo for full coverage.
# Without sudo they print what the user session can see and say so — the script
# runs fine unprivileged and is more useful that way for a quick pass.
#
# Lines prefixed "  ! FINDING:" are worth a human's attention. Everything else,
# including the reassuring negatives, is context for the verdict.
#
# Usage: scan.sh            # user-level pass
#        sudo scan.sh       # adds firewall + root daemon coverage
set -uo pipefail

hr()   { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
note() { printf '    %s\n' "$1"; }
find_() { printf '  \033[31m! FINDING:\033[0m %s\n' "$1"; FINDINGS=$((FINDINGS+1)); }

FINDINGS=0
ME="$(id -un)"
HAVE_SUDO=0; [ "$(id -u)" -eq 0 ] && HAVE_SUDO=1

printf '\033[1mmac-compromise-check\033[0m — read-only triage on %s (%s)\n' "$(hostname -s)" "$(sw_vers -productVersion 2>/dev/null)"
[ "$HAVE_SUDO" -eq 1 ] && printf 'running as root — full coverage\n' || printf 'running as %s — firewall/root-daemon sections limited (re-run with sudo for those)\n' "$ME"

# ---------------------------------------------------------------------------
hr "1. ACCOUNTS"
# Extra local accounts, and who holds admin, are the first thing to check.
USERS=$(dscl . -list /Users UniqueID 2>/dev/null | awk '$2>=500{print $1}')
NUSERS=$(echo "$USERS" | grep -c .)
note "local accounts (uid>=500): $(echo $USERS | tr '\n' ' ')"
ADMINS=$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | sed 's/GroupMembership: //')
note "admin group: $ADMINS"
[ "$NUSERS" -le 2 ] && ok "no unexpected local accounts" || note "review the account list above"

hr "2. LOGIN HISTORY"
# In `last` output a real login row is "user  ttyNNN/console  <host-or-date>…".
# For a LOCAL login the token after the tty is a weekday (the date, no host);
# for a REMOTE login it is a hostname/IP. Pseudo-rows (reboot/shutdown/wtmp) are
# not logins at all. Flag only rows with a host present.
REMOTE=$(last -100 2>/dev/null | awk '
  $1!="reboot" && $1!="shutdown" && $1!="wtmp" && $2 ~ /^(ttys?|console)/ \
  && $3!="" && $3 !~ /^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)$/ {print}' | head -10)
if [ -n "$REMOTE" ]; then find_ "remote login rows present (a host/IP in the login line):"; echo "$REMOTE" | sed 's/^/      /'
else ok "no remote logins in recent history (all console/tty local)"; fi

hr "3. REMOTE ACCESS SERVICES"
# SSH, Screen Sharing, ARD/VNC, and third-party remote tools. authorized_keys
# is the single highest-signal file here.
if [ -f "$HOME/.ssh/authorized_keys" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
  find_ "~/.ssh/authorized_keys exists and is non-empty — anyone holding a matching key can SSH in:"
  sed 's/^/      /' "$HOME/.ssh/authorized_keys"
else ok "no ~/.ssh/authorized_keys (nobody can SSH into this user)"; fi
RT=$(launchctl list 2>/dev/null | grep -iE 'teamviewer|anydesk|realvnc|logmein|chromeremote|nomachine|splashtop' )
[ -n "$RT" ] && { find_ "third-party remote-access agent loaded:"; echo "$RT" | sed 's/^/      /'; } || ok "no third-party remote-access agents (TeamViewer/AnyDesk/etc.)"
if [ "$HAVE_SUDO" -eq 1 ]; then
  for s in com.openssh.sshd com.apple.screensharing com.apple.RemoteDesktop.agent; do
    launchctl print system/$s >/dev/null 2>&1 && find_ "system service loaded: $s" || note "$s not loaded"
  done
else note "(re-run with sudo to confirm sshd/screensharing/ARD daemon state)"; fi

hr "4. LISTENING PORTS"
# A listener bound to anything other than loopback is reachable from the network.
EXT=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 && $9 !~ /127\.0\.0\.1|\[::1\]/ {print "      "$1" (pid "$2") "$9}' | sort -u)
if [ -n "$EXT" ]; then note "non-loopback listeners (verify each is yours):"; echo "$EXT"
  note "a dev server on *:PORT is normal; an unknown binary is not"
else ok "no non-loopback listeners"; fi

hr "5. PERSISTENCE — launchd"
# The classic autostart vector. Anything in these dirs runs automatically.
for d in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
  [ -d "$d" ] || continue
  n=$(ls -1 "$d"/*.plist 2>/dev/null | wc -l | tr -d ' ')
  note "$d : $n plist(s)"
  ls -1 "$d"/*.plist 2>/dev/null | sed 's|.*/|        |'
done
note "cross-check any unfamiliar label against its Program/ProgramArguments:"
note "  defaults read <plist> ProgramArguments 2>/dev/null"

hr "6. PERSISTENCE — cron & periodic"
CRON=$(crontab -l 2>/dev/null)
[ -n "$CRON" ] && { find_ "user crontab is set:"; echo "$CRON" | sed 's/^/      /'; } || ok "no user crontab"

hr "7. BROWSER EXTENSIONS"
# Malicious extensions with broad host permissions are a common exfil path.
for base in "$HOME/Library/Application Support/Google/Chrome/Default/Extensions" \
            "$HOME/Library/Application Support/Arc/User Data/Default/Extensions" \
            "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Extensions" \
            "$HOME/Library/Application Support/Microsoft Edge/Default/Extensions"; do
  [ -d "$base" ] || continue
  note "$(echo "$base" | sed "s|$HOME/Library/Application Support/||; s|/Default/Extensions||"):"
  for dir in "$base"/*/; do
    id=$(basename "$dir")
    m=$(find "$dir" -maxdepth 2 -name manifest.json 2>/dev/null | head -1)
    [ -n "$m" ] || continue
    nm=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('name',''))" "$m" 2>/dev/null)
    perms=$(python3 -c "import json,sys;j=json.load(open(sys.argv[1]));print(','.join(j.get('permissions',[])+j.get('host_permissions',[]))[:80])" "$m" 2>/dev/null)
    flag=""; echo "$perms" | grep -q '<all_urls>' && flag="  \033[33m(all_urls)\033[0m"
    printf "        %s  %s%b\n" "$id" "$nm" "$flag"
  done
done
note "verify each extension is one you installed; <all_urls> = can read every page"

hr "8. MDM / CONFIGURATION PROFILES"
# A profile you didn't install can control the machine. DEP/MDM enrollment too.
PROF=$(profiles list -type configuration 2>/dev/null)
echo "$PROF" | grep -qi 'no configuration profiles' && ok "no configuration profiles installed" || { find_ "configuration profile(s) present:"; echo "$PROF" | sed 's/^/      /'; }
profiles status -type enrollment 2>/dev/null | sed 's/^/    /'

hr "9. SYSTEM HARDENING"
FV=$(fdesetup status 2>/dev/null); echo "$FV" | grep -qi 'On' && ok "FileVault: $FV" || find_ "FileVault: $FV"
SIP=$(csrutil status 2>/dev/null | sed 's/^.*: //'); echo "$SIP" | grep -qi enabled && ok "SIP: $SIP" || find_ "SIP: $SIP"
GK=$(spctl --status 2>/dev/null); echo "$GK" | grep -qi enabled && ok "Gatekeeper: $GK" || find_ "Gatekeeper: $GK"
if [ "$HAVE_SUDO" -eq 1 ]; then
  FW=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
  case "$FW" in 1|2) ok "Application firewall: on ($FW)";; 0) note "Application firewall: off";; *) note "Application firewall: unknown";; esac
else note "(re-run with sudo to read application firewall state)"; fi

# ---------------------------------------------------------------------------
hr "VERDICT"
if [ "$FINDINGS" -eq 0 ]; then
  printf '  \033[32mNo findings.\033[0m Nothing here indicates compromise. This raises the floor;\n'
  printf '  it does not certify a clean machine (not a malware scanner).\n'
else
  printf '  \033[31m%d finding(s) above need a human decision.\033[0m Read each in context —\n' "$FINDINGS"
  printf '  most have a benign explanation (see references/findings.md). Confirm, don'"'"'t assume.\n'
fi
[ "$HAVE_SUDO" -eq 0 ] && printf '  For firewall + root-daemon coverage, re-run: sudo %s\n' "$0"
exit 0
