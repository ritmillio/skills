# Full checklist — what scan.sh covers, and manual extras

`scan.sh` automates §1–§9 below. This file is the reference for what each check
is and the raw commands, so the scan can be reproduced, extended, or run by hand
on a machine where the script isn't present.

## Automated by scan.sh

| # | Section | Core command(s) |
|---|---|---|
| 1 | Local accounts & admins | `dscl . -list /Users UniqueID`; `dscl . -read /Groups/admin GroupMembership` |
| 2 | Login history (remote?) | `last -100`; `who` |
| 3 | Remote access | `~/.ssh/authorized_keys`; `launchctl list \| grep -i vnc/ssh/…`; (sudo) `launchctl print system/com.openssh.sshd` |
| 4 | Listening ports | `lsof -nP -iTCP -sTCP:LISTEN` |
| 5 | launchd persistence | `ls ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons` |
| 6 | cron | `crontab -l` |
| 7 | Browser extensions | parse `…/Extensions/*/manifest.json` |
| 8 | MDM / profiles | `profiles list -type configuration`; `profiles status -type enrollment` |
| 9 | Hardening | `fdesetup status`; `csrutil status`; `spctl --status`; (sudo) `defaults read /Library/Preferences/com.apple.alf globalstate` |

## Worth adding by hand when something looks off

- **TCC (privacy) grants** — who has Accessibility / Full Disk / Screen
  Recording. Requires the DB be readable (often not, by design):
  `sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db 'select service,client,auth_value from access;'`
- **Login items** — `osascript -e 'tell application "System Events" to get the name of every login item'`
- **Internet Accounts** (Mail/Calendar attached to the OS) —
  `sqlite3 ~/Library/Accounts/Accounts4.sqlite 'select ZUSERNAME,ZACCOUNTDESCRIPTION from ZACCOUNT;'`
- **Recently modified apps** — `find /Applications -maxdepth 1 -mtime -30`
- **Unsigned / tampered app** — `codesign -dv --verbose=2 /Applications/Suspect.app`
  and `spctl -a -vvv /Applications/Suspect.app`
- **Linked-service keys whose private half isn't local** — e.g. compare
  `ssh-keygen -lf ~/.ssh/*.pub` fingerprints against `gh api user/keys`. A key
  registered on GitHub with no matching private key on this Mac lives on another
  machine; decide whether that machine is trusted.
- **Persistence in less-common spots** — `~/Library/Application Support` for
  odd top-level dirs; `/etc/periodic`, `/etc/cron.d`; `sudo ls /Library/StartupItems`.
- **Recent process spawns / network** — `ps -axo user,pid,ppid,%cpu,command`;
  `nettop -m tcp -l 1` (interactive) or `lsof -i -nP` for live connections.

## Order of operations

1. Run `scan.sh` unprivileged first — it's fast and covers most ground.
2. If the user named an account, run `trace.sh <account>` in parallel.
3. Only re-run `scan.sh` with `sudo` if §3/§9 hinted at something, or the user
   wants firewall + root-daemon certainty.
4. Reserve the manual extras for a specific lead — don't dump all of them.
