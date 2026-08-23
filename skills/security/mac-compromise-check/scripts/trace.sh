#!/usr/bin/env bash
# mac-compromise-check/trace.sh — READ-ONLY. Trace an email / account / name
# across the machine, then reconstruct the browser sign-in timeline around it.
#
# The point: a scary account name (a Google prompt, a login alert) reports WHERE
# THE USER SAW IT, not where a problem is. This finds every place that string
# actually touches the disk — or proves it touches nothing — and shows the
# minute-by-minute browser flow so an "AddSession → rejected" sequence reads for
# what it is: the user's own research, not an intrusion.
#
# Reads only. Copies history/cookie SQLite DBs to a temp file before querying so
# a live browser lock never blocks it, and deletes the copy after.
#
# Usage: trace.sh "someone@gmail.com"
#        trace.sh "Some Name"          # also works for a person's name
set -uo pipefail

Q="${1:-}"
[ -n "$Q" ] || { echo "usage: trace.sh <email-or-name>" >&2; exit 2; }
# A search token for grep (local part of an email is the distinctive bit).
TOK="${Q%%@*}"

hr()  { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()  { printf '  \033[32m✓ %s\033[0m\n' "$1"; }
hit() { printf '  \033[31m! %s\033[0m\n' "$1"; }

printf '\033[1mTracing:\033[0m %s   (token: %s)\n' "$Q" "$TOK"

hr "1. FILESYSTEM (home dir, source trees excluded)"
printf '  scanning… (this is the slow section)\n' >&2
FS=$(cd "$HOME" && timeout 90 grep -ril "$TOK" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=Library \
  --exclude-dir=Caches --exclude-dir=.pnpm-store --exclude-dir=.next \
  --exclude-dir=.cache --exclude-dir=dist --exclude-dir=build --exclude-dir=.Trash \
  . 2>/dev/null | head -30)
[ -n "$FS" ] && { hit "found in files:"; echo "$FS" | sed 's/^/      ~\//'; } || ok "not found in home-directory files"

hr "2. SPOTLIGHT (full content index)"
SL=$(mdfind "$Q" 2>/dev/null | head -20)
[ -n "$SL" ] && { hit "Spotlight matches:"; echo "$SL" | sed 's/^/      /'; } || ok "no Spotlight matches"

hr "3. KEYCHAIN (metadata only — never dumps secrets)"
# Only checks whether an item is filed under this account; does not read values.
security find-internet-password -a "$Q" >/dev/null 2>&1 && hit "an internet-password item is stored for this account" || ok "no keychain item for this account"

hr "4. GIT COMMIT AUTHORS (across ~/Developer)"
GA=""
for r in "$HOME"/Developer/*/; do
  [ -d "$r/.git" ] || continue
  h=$(git -C "$r" log --all --format='%ae|%ce' 2>/dev/null | tr '|' '\n' | sort -u | grep -i "$TOK")
  [ -n "$h" ] && GA="$GA\n      $(basename "$r"): $h"
done
[ -n "$GA" ] && { hit "appears as a git author/committer:"; printf "$GA\n"; } || ok "never a git author/committer in ~/Developer"

hr "5. SHELL HISTORY"
SH=$(grep -i "$TOK" "$HOME"/.zsh_history "$HOME"/.bash_history 2>/dev/null | head -10)
[ -n "$SH" ] && { hit "in shell history:"; echo "$SH" | sed 's/^/      /'; } || ok "not in shell history"

hr "6. BROWSER — signed-in accounts, cookies, history"
CHROMIUM_PROFILES=(
  "$HOME/Library/Application Support/Google/Chrome/Default"
  "$HOME/Library/Application Support/Arc/User Data/Default"
  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default"
  "$HOME/Library/Application Support/Microsoft Edge/Default"
)
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for P in "${CHROMIUM_PROFILES[@]}"; do
  [ -d "$P" ] || continue
  label=$(echo "$P" | sed "s|$HOME/Library/Application Support/||; s|/Default||; s|/User Data||")
  printf '  \033[1m%s\033[0m\n' "$label"
  # Signed-in Google account (from Preferences).
  if [ -f "$P/Preferences" ]; then
    acct=$(python3 -c "import json,sys;print(', '.join(a.get('email','') for a in json.load(open(sys.argv[1])).get('account_info',[])) or 'none')" "$P/Preferences" 2>/dev/null)
    printf '      signed-in Google account(s): %s\n' "$acct"
  fi
  # The queried string in stored gmail addresses.
  grep -rhoE '[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+' "$P/Preferences" 2>/dev/null | sort -u | grep -i "$TOK" | sed 's/^/      pref email: /'
  # History rows mentioning the token.
  if [ -f "$P/History" ]; then
    cp "$P/History" "$TMP/h.db" 2>/dev/null
    rows=$(sqlite3 "$TMP/h.db" "select datetime(last_visit_time/1000000-11644473600,'unixepoch','localtime'), substr(url,1,120) from urls where url like '%$TOK%' order by last_visit_time desc limit 15;" 2>/dev/null)
    [ -n "$rows" ] && { echo "$rows" | sed 's/^/      visit: /'; } || printf '      no history URL contains the token\n'
    rm -f "$TMP/h.db"
  fi
done

hr "7. SIGN-IN TIMELINE (Arc + Chrome, most recent auth flow)"
# The interpretive payoff: shows the ordered flow so AddSession→rejected reads
# as "no session created". transition & 0xFF: 1=user typed URL, 0=clicked link,
# 7=form submit, 8=reload.
for P in "${CHROMIUM_PROFILES[@]}"; do
  [ -f "$P/History" ] || continue
  label=$(echo "$P" | sed "s|$HOME/Library/Application Support/||; s|/Default||; s|/User Data||")
  cp "$P/History" "$TMP/t.db" 2>/dev/null || continue
  tl=$(sqlite3 -separator '  ' "$TMP/t.db" "
    select datetime(v.visit_time/1000000-11644473600,'unixepoch','localtime'),
           v.transition & 0xFF, substr(u.url,1,110)
    from visits v join urls u on u.id=v.url
    where u.url like '%accounts.google%' or u.url like '%AddSession%'
       or u.url like '%signin%' or u.url like '%oauth%' or u.url like '%login.live%'
    order by v.visit_time desc limit 12;" 2>/dev/null)
  [ -n "$tl" ] && { printf '  \033[1m%s\033[0m (newest first; t=1 typed, 0 clicked, 7 submit)\n' "$label"; echo "$tl" | sed 's/^/      /'; }
  rm -f "$TMP/t.db"
done
printf '\n  Read a "…/signin/rejected" or "AddSession → identifier → pwd → rejected"\n'
printf '  sequence as: a sign-in was ATTEMPTED and DENIED — no session was created.\n'
printf '  See references/tracing.md.\n'
exit 0
