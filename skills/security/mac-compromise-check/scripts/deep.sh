#!/bin/bash
# mac-compromise-check/deep.sh — READ-ONLY deep pass: verifies code signatures on every launch item and non-Apple process, and checks DYLD injection, TCC grants, login hooks, quarantine history, all-user listeners, and the Claude/MCP/Chrome agent surface. Never modifies anything.
# tampering and weak security posture on a Mac. Never modifies anything.
# Usage: check.sh [--days N]   (recent-change window, default 30)
DAYS=30
[ "${1:-}" = "--days" ] && DAYS="${2:-30}"
export LC_ALL=C
H="$HOME"

hdr() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()   { printf '  [OK]   %s\n' "$1"; }
info() { printf '  [INFO] %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }
need_root() { printf '  [ROOT] %s\n' "$1"; }

# Signature classification for a binary path
sig() {
  local p="$1"
  [ -e "$p" ] || { echo "MISSING"; return; }
  local out; out=$(codesign -dv --verbose=2 "$p" 2>&1)
  if echo "$out" | grep -q "not signed"; then echo "UNSIGNED"; return; fi
  if echo "$out" | grep -q "Signature=adhoc"; then echo "ADHOC"; return; fi
  local auth; auth=$(echo "$out" | grep '^Authority=' | head -1 | cut -d= -f2-)
  case "$auth" in
    "Software Signing") echo "APPLE";;
    "Apple Mac OS Application Signing") echo "APPSTORE";;
    "Developer ID Application:"*) echo "DEVID(${auth#Developer ID Application: })";;
    "") echo "UNKNOWN";;
    *) echo "OTHER($auth)";;
  esac
}
is_brew() { case "$1" in /opt/homebrew/*|/usr/local/Cellar/*|/usr/local/bin/*|/usr/local/opt/*) return 0;; esac; return 1; }
is_devtool() { case "$1" in "$H"/.nvm/*|"$H"/.bun/*|"$H"/.cargo/*|"$H"/.rustup/*|"$H"/.local/share/pnpm/*|"$H"/.volta/*|"$H"/go/*|*/node_modules/*|"$H"/Library/pnpm/*|"$H"/.pyenv/*|"$H"/.deno/*) return 0;; esac; return 1; }

echo "mac-compromise-check  $(date '+%Y-%m-%d %H:%M %Z')  host=$(hostname)  user=$USER"
echo "macOS $(sw_vers -productVersion) build $(sw_vers -buildVersion)  uptime:$(uptime | sed 's/.*up/up/;s/,.*//')"

# ---------------------------------------------------------------- posture
hdr "Security posture"
sip=$(csrutil status 2>/dev/null); echo "$sip" | grep -q enabled && ok "SIP: $sip" || warn "SIP: $sip"
gk=$(spctl --status 2>&1); echo "$gk" | grep -q enabled && ok "Gatekeeper: $gk" || warn "Gatekeeper: $gk"
fv=$(fdesetup status 2>&1); echo "$fv" | grep -q "is On" && ok "$fv" || warn "$fv"
fw=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1); echo "$fw" | grep -qi enabled && ok "Firewall: $fw" || warn "Firewall: $fw"
xp=$(defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString 2>/dev/null); info "XProtect signatures version: ${xp:-unknown}"
xpr=$(defaults read /Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null); info "XProtect Remediator version: ${xpr:-unknown}"
info "Last software updates:"; softwareupdate --history 2>/dev/null | tail -n 4 | sed 's/^/         /'
if launchctl print system/com.openssh.sshd >/dev/null 2>&1; then warn "Remote Login (sshd) is ENABLED"; else ok "Remote Login (sshd) off"; fi
if launchctl print system/com.apple.screensharing >/dev/null 2>&1; then warn "Screen Sharing is ENABLED"; else ok "Screen Sharing off"; fi
pgrep -q ARDAgent && warn "ARDAgent (Remote Management) running" || ok "Remote Management agent not running"
[ -f /Library/Preferences/com.apple.RemoteManagement.plist ] && info "Remote Management prefs file exists (/Library/Preferences/com.apple.RemoteManagement.plist)"
en=$(profiles status -type enrollment 2>&1 | tr '\n' ' '); echo "$en" | grep -qi "Enrolled via DEP: No" && echo "$en" | grep -qi "MDM enrollment: No" && ok "No MDM enrollment" || warn "MDM/DEP: $en"
pl=$(profiles list 2>&1 | grep -v "^There are no"); [ -n "$pl" ] && { warn "User configuration profiles present:"; echo "$pl" | sed 's/^/         /'; } || ok "No user configuration profiles"

# ---------------------------------------------------------------- kexts / sysexts
hdr "Kernel & system extensions"
k=$(kmutil showloaded --show-not-apple 2>/dev/null | grep -v '^No variant' | tail -n +2)
[ -n "$k" ] && { warn "Non-Apple kernel extensions loaded:"; echo "$k" | sed 's/^/         /'; } || ok "No third-party kexts loaded"
se=$(systemextensionsctl list 2>/dev/null | grep -E '^\s*\*|enabled' | grep -v '^---')
[ -n "$se" ] && { info "System extensions:"; systemextensionsctl list 2>/dev/null | grep -E '^\s+(\*|[a-z0-9])' | grep -vi 'enabled	active' | sed 's/^/         /'; } || ok "No system extensions"

# ---------------------------------------------------------------- launch items
hdr "LaunchAgents / LaunchDaemons (non-Apple locations)"
for d in "$H/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
  [ -d "$d" ] || continue
  for f in "$d"/*.plist; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    if [ ! -r "$f" ]; then info "$f  (root-only readable; inspect with: sudo plutil -p '$f')"; continue; fi
    if [ ! -s "$f" ]; then info "$f  (empty file, inert)"; continue; fi
    prog=$(plutil -extract ProgramArguments.0 raw -o - "$f" 2>/dev/null || plutil -extract Program raw -o - "$f" 2>/dev/null)
    args=$(plutil -extract ProgramArguments json -o - "$f" 2>/dev/null | tr -d '\n' | cut -c1-160)
    ral=$(plutil -extract RunAtLoad raw -o - "$f" 2>/dev/null)
    env=$(plutil -extract EnvironmentVariables json -o - "$f" 2>/dev/null | grep -io 'DYLD[A-Z_]*' | head -1)
    mtime=$(stat -f '%Sm' -t '%Y-%m-%d' "$f")
    s=$(sig "$prog")
    flag=""
    case "$base" in com.apple.*) flag="IMPERSONATES-APPLE ";; esac
    [ -n "$env" ] && flag="${flag}DYLD-INJECTION "
    case "$prog" in /tmp/*|/private/tmp/*|/var/folders/*|/Users/Shared/*|*/.*) flag="${flag}SUSPICIOUS-PATH ";; esac
    case "$s" in UNSIGNED|ADHOC|MISSING|UNKNOWN) is_brew "$prog" || is_devtool "$prog" || flag="${flag}${s} ";; esac
    line="$f  mtime=$mtime  runAtLoad=${ral:-?}  sig=$s  exec=$prog"
    if [ -n "$flag" ]; then warn "$flag$line"; echo "           args=$args"; else info "$line"; fi
  done
done
info "Loaded non-Apple launchd jobs for this user:"
launchctl list 2>/dev/null | awk 'NR>1 && $3 !~ /^com\.apple\./ {printf "         pid=%-6s status=%-4s %s\n",$1,$2,$3}'
need_root "system-wide loaded jobs: sudo launchctl list | grep -v com.apple"
need_root "Login/background items registry: sudo sfltool dumpbtm"

# ---------------------------------------------------------------- other persistence
hdr "Other persistence vectors"
c=$(crontab -l 2>/dev/null); [ -n "$c" ] && { warn "User crontab present:"; echo "$c" | sed 's/^/         /'; } || ok "No user crontab"
for f in /etc/crontab /usr/lib/cron/tabs/*; do [ -f "$f" ] && warn "cron file exists: $f ($(stat -f '%Sm' "$f"))"; done
need_root "root crontab: sudo crontab -l"
a=$(atq 2>/dev/null); [ -n "$a" ] && warn "at jobs queued: $a" || ok "No at jobs"
lh=$(defaults read com.apple.loginwindow LoginHook 2>/dev/null); [ -n "$lh" ] && warn "User LoginHook: $lh" || ok "No user LoginHook"
lh=$(defaults read /Library/Preferences/com.apple.loginwindow LoginHook 2>/dev/null); [ -n "$lh" ] && warn "System LoginHook: $lh" || ok "No system LoginHook"
for d in /Library/StartupItems /Library/ScriptingAdditions /Library/PrivilegedHelperTools /etc/emond.d/rules; do
  if [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ]; then
    info "$d:"; for f in "$d"/*; do echo "         $(stat -f '%Sm' -t '%Y-%m-%d' "$f")  $(sig "$f" 2>/dev/null)  $f"; done
  fi
done
pr=$(find /etc/periodic -type f -newerct "-${DAYS}d" 2>/dev/null); [ -n "$pr" ] && warn "Recently changed periodic scripts: $pr" || ok "No recently changed /etc/periodic scripts"
dy=$(launchctl getenv DYLD_INSERT_LIBRARIES 2>/dev/null); [ -n "$dy" ] && warn "DYLD_INSERT_LIBRARIES set in launchd env: $dy" || ok "No DYLD_INSERT_LIBRARIES in launchd env"
if command -v brew >/dev/null 2>&1; then
  bs=$(brew services list 2>/dev/null | awk 'NR>1 && $2!="none"'); [ -n "$bs" ] && { info "Homebrew services running:"; echo "$bs" | sed 's/^/         /'; } || ok "No Homebrew services running"
fi

# ---------------------------------------------------------------- shell / ssh
hdr "Shell profiles & SSH"
for f in "$H"/.zshrc "$H"/.zprofile "$H"/.zshenv "$H"/.zlogin "$H"/.bash_profile "$H"/.bashrc "$H"/.profile /etc/zshrc /etc/zprofile /etc/zshenv /etc/profile /etc/bashrc; do
  [ -f "$f" ] || continue
  m=$(stat -f '%Sm' -t '%Y-%m-%d' "$f")
  recent=""; [ -n "$(find "$f" -newerct "-${DAYS}d" 2>/dev/null)" ] && recent=" (modified within ${DAYS}d)"
  sus=$(grep -nE 'curl[^|]*\|\s*(ba)?sh|wget[^|]*\|\s*(ba)?sh|base64\s+(-d|--decode)|nohup|DYLD_INSERT|LD_PRELOAD|/tmp/\.|/var/folders/.*\.sh|python[23]?\s+-c\s+.import\s+socket|nc\s+-e|bash\s+-i\s+>&' "$f" 2>/dev/null | head -5)
  if [ -n "$sus" ]; then warn "$f mtime=$m$recent — suspicious lines:"; echo "$sus" | sed 's/^/           /'; else info "$f mtime=$m$recent"; fi
done
if [ -d "$H/.ssh" ]; then
  for f in "$H"/.ssh/authorized_keys "$H"/.ssh/config "$H"/.ssh/rc; do
    [ -f "$f" ] || continue
    m=$(stat -f '%Sm' -t '%Y-%m-%d' "$f")
    case "$f" in
      */authorized_keys) n=$(grep -cE '^(ssh-|ecdsa-|sk-)' "$f"); warn "authorized_keys: $n key(s), mtime=$m"; awk '/^(ssh-|ecdsa-|sk-)/{print "           " $1 " ... " $NF}' "$f";;
      */rc) warn "~/.ssh/rc exists (runs on every SSH login), mtime=$m";;
      *) info "$f mtime=$m"; grep -nE 'ProxyCommand|LocalCommand|PermitLocalCommand' "$f" | sed 's/^/           /';;
    esac
  done
  ls -la "$H/.ssh" 2>/dev/null | awk 'NR>1 && $1 !~ /^d/ {print "         " $1 "  " $6" "$7" "$8 "  " $9}'
fi
ls -la /etc/ssh/sshd_config.d 2>/dev/null | awk 'NR>3{print "         sshd_config.d: "$9}'

# ---------------------------------------------------------------- network
hdr "Network: listeners & connections"
info "Listening TCP (all users):"
netstat -anvW -p tcp 2>/dev/null | awk '$6=="LISTEN"{split($11,a,":"); print $4, a[2], a[1]}' | sort -u | while read -r addr pid name; do
  cmd=$(ps -o args= -p "$pid" 2>/dev/null | cut -c1-120); case "$addr" in \*.*|0.0.0.0.*) tag="[all-interfaces] ";; *) tag="";; esac; echo "         $tag$addr  pid=$pid  $name  ${cmd}"
done
info "Listening UDP (excluding mDNS/Bonjour):"
netstat -anvW -p udp 2>/dev/null | awk 'NR>2 && $4!~/\*\.\*$/ && $4 !~ /\.(5353|137|138)$/ {split($10,a,":"); print $4, a[2], a[1]}' | sort -u | head -30 | while read -r addr pid name; do
  echo "         $addr  pid=$pid  $name"
done
info "Established outbound connections by process (count):"
netstat -anvW -p tcp 2>/dev/null | awk '$6=="ESTABLISHED"{print $11}' | sort | uniq -c | sort -rn | head -15 | while read -r n proc; do
  printf '         %4s  %s\n' "$n" "$proc"
done
info "Outbound connections on unusual ports (not 80/443/22/53):"
netstat -anvW -p tcp 2>/dev/null | awk '$6=="ESTABLISHED" && $5 !~ /^127\.0\.0\.1\./ && $5 !~ /^::1\./ {split($5,a,"."); port=a[length(a)]; if(port!=443&&port!=80&&port!=22&&port!=53) print $5, $11}' | sort -u | head -20 | while read -r peer proc; do
  echo "         $peer  <- $proc"
done
info "DNS resolvers: $(scutil --dns 2>/dev/null | grep nameserver | awk '{print $3}' | sort -u | tr '\n' ' ')"
px=$(scutil --proxy 2>/dev/null | grep -E 'Enable : 1|ProxyAutoConfigURLString'); [ -n "$px" ] && warn "Proxy configured: $(echo "$px" | tr '\n' ' ')" || ok "No system proxy"
hh=$(grep -vE '^\s*(#|$)' /etc/hosts | grep -vE '^(127\.0\.0\.1\s+localhost|255\.255\.255\.255\s+broadcasthost|::1\s+localhost)\s*$'); [ -n "$hh" ] && { warn "/etc/hosts has custom entries:"; echo "$hh" | sed 's/^/         /'; } || ok "/etc/hosts is default"

# ---------------------------------------------------------------- processes
hdr "Running processes: signatures & locations"
ps -axo pid=,user=,comm= | awk '$3 ~ /^\//' | sort -k3 -u | while read -r pid user cmd; do
  case "$cmd" in /System/*|/usr/libexec/*|/usr/sbin/*|/usr/bin/*|/sbin/*|/bin/*|/Library/Apple/*) continue;; esac
  s=$(sig "$cmd")
  flag=""
  case "$cmd" in /tmp/*|/private/tmp/*|/var/folders/*|/Users/Shared/*|/private/var/tmp/*|"$H"/.[!.]*|"$H"/Library/Caches/*|"$H"/Downloads/*) flag="SUSPICIOUS-PATH ";; esac
  case "$s" in UNSIGNED|ADHOC|MISSING|UNKNOWN) is_brew "$cmd" || is_devtool "$cmd" || flag="${flag}$s ";; esac
  if [ -n "$flag" ]; then warn "${flag}pid=$pid user=$user $cmd"; fi
done
info "Non-Apple process count by signer:"
ps -axo comm= | awk '$1 ~ /^\// && $1 !~ /^\/(System|usr|sbin|bin|Library\/Apple)/' | sort -u | while read -r cmd; do sig "$cmd" | sed -E 's/\(.*//'; done | sort | uniq -c | sort -rn | sed 's/^/         /'

# ---------------------------------------------------------------- users
hdr "Accounts"
info "Local users (uid 0 or >=500):"
dscl . -list /Users UniqueID 2>/dev/null | awk '$2==0 || $2>=500 {printf "         uid=%-6s %s\n",$2,$1}'
odd=$(dscl . -list /Users UniqueID 2>/dev/null | awk '$2>0 && $2<500 && $1 !~ /^_/ && $1 !~ /^(daemon|nobody|root)$/'); [ -n "$odd" ] && warn "Non-underscore system-range users: $odd" || ok "No odd low-uid users"
info "admin group: $(dscl . -read /Groups/admin GroupMembership 2>/dev/null | cut -d: -f2)"
hu=$(defaults read /Library/Preferences/com.apple.loginwindow HiddenUsersList 2>/dev/null); [ -n "$hu" ] && warn "Hidden users configured: $hu" || ok "No HiddenUsersList"
info "Recent logins:"; last -10 2>/dev/null | grep -v '^$' | grep -v wtmp | sed 's/^/         /'
info "sudo usage in last 24h (last 12):"
log show --last 24h --style compact --predicate 'process == "sudo"' 2>/dev/null | grep -E 'COMMAND=|authentication|incorrect' | tail -12 | cut -c1-200 | sed 's/^/         /'

# ---------------------------------------------------------------- TCC
hdr "Privacy permissions (TCC)"
tdb="$H/Library/Application Support/com.apple.TCC/TCC.db"
if out=$(sqlite3 "$tdb" "select service, client, datetime(last_modified,'unixepoch') from access where auth_value=2 and service in ('kTCCServiceAccessibility','kTCCServiceScreenCapture','kTCCServiceListenEvent','kTCCServiceMicrophone','kTCCServiceCamera','kTCCServiceAppleEvents','kTCCServiceSystemPolicyAllFiles','kTCCServicePostEvent') order by last_modified desc" 2>&1); then
  info "User-level grants (Accessibility / ScreenCapture / InputMonitoring / Mic / Camera / AppleEvents):"
  echo "$out" | sed 's/kTCCService//; s/^/         /'
else
  need_root "user TCC.db not readable (grant this terminal Full Disk Access, or run: sudo sqlite3 \"$tdb\" ...)"
fi
need_root "System TCC (Full Disk Access, Input Monitoring for all users): sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' \"select service,client,datetime(last_modified,'unixepoch') from access where auth_value=2 order by last_modified desc\""

# ---------------------------------------------------------------- recent changes
hdr "Recently changed (last ${DAYS} days) in sensitive locations"
find "$H/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons /Library/PrivilegedHelperTools /Library/ScriptingAdditions /Library/StartupItems \
     "$H/.ssh" /etc/ssh /etc/sudoers.d /etc/pam.d /etc/hosts /etc/profile /etc/zshrc /etc/zprofile /etc/bashrc \
     -maxdepth 2 -type f -newerct "-${DAYS}d" 2>/dev/null | while read -r f; do echo "         $(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$f")  $f"; done
hx=$(find "$H" -maxdepth 2 -name '.*' -type f -perm -u+x -not -name '.DS_Store' 2>/dev/null | head -20); [ -n "$hx" ] && { warn "Hidden executables in home (depth<=2):"; echo "$hx" | sed 's/^/         /'; } || ok "No hidden executables at home depth<=2"
tx=$(find /tmp /private/tmp /Users/Shared -maxdepth 2 -type f -perm -u+x 2>/dev/null | head -20); [ -n "$tx" ] && { warn "Executables in /tmp or /Users/Shared:"; echo "$tx" | sed 's/^/         /'; } || ok "No executables in /tmp or /Users/Shared"
info "Last 12 quarantined downloads:"
sqlite3 "$H/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2" "select datetime(LSQuarantineTimeStamp+978307200,'unixepoch'), LSQuarantineAgentName, substr(coalesce(LSQuarantineDataURLString,LSQuarantineOriginURLString,''),1,110) from LSQuarantineEvent order by LSQuarantineTimeStamp desc limit 12" 2>/dev/null | sed 's/^/         /'

# ---------------------------------------------------------------- agent / browser surface
hdr "Agent & browser attack surface"
for f in "$H/.claude/settings.json" "$H/.claude/settings.local.json"; do
  [ -f "$f" ] && { hk=$(python3 -c "import json,sys;d=json.load(open('$f'));h=d.get('hooks',{});print('\n'.join(f'{k}: '+str(v)[:150] for k,v in h.items()))" 2>/dev/null); [ -n "$hk" ] && { info "Claude hooks in $f:"; echo "$hk" | sed 's/^/         /'; } || ok "No hooks in $f"; }
done
[ -f "$H/.claude.json" ] && { ms=$(python3 -c "import json;d=json.load(open('$H/.claude.json'));m=d.get('mcpServers',{});print('\n'.join(f'{k}: '+(v.get('command','')+' '+' '.join(v.get('args',[])) if v.get('command') else v.get('url','?'))[:140] for k,v in m.items()))" 2>/dev/null); [ -n "$ms" ] && { info "Global MCP servers:"; echo "$ms" | sed 's/^/         /'; }; }
nm="$H/Library/Application Support/Google/Chrome/NativeMessagingHosts"; [ -d "$nm" ] && { info "Chrome native messaging hosts:"; for f in "$nm"/*.json; do [ -e "$f" ] && echo "         $(basename "$f" .json) -> $(python3 -c "import json;print(json.load(open('$f')).get('path'))" 2>/dev/null)"; done; }
ext="$H/Library/Application Support/Google/Chrome/Default/Extensions"; [ -d "$ext" ] && { info "Chrome extensions (Default profile):"; for d in "$ext"/*/; do id=$(basename "$d"); v=$(ls -1 "$d" | tail -1); n=$(python3 -c "import json;print(json.load(open('$d/$v/manifest.json')).get('name'))" 2>/dev/null); echo "         $id  $n"; done; }

hdr "Done"
echo "  Lines marked [ROOT] need sudo; run them with the ! prefix if you want the full picture."
