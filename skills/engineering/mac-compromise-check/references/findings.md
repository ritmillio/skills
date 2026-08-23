# Reading the findings — benign vs. worrying

`scan.sh` flags signals; it does not judge them. Almost every FINDING has a
common innocent explanation. Escalate only when the innocent one is ruled out.
Confirm, never assume.

## Accounts (§1)

| Signal | Usually benign | Worrying when |
|---|---|---|
| Extra local account (uid≥500) | A second personal account, `_mbsetupuser` | An account the user never created, especially in the admin group |
| Admin group membership | `root`, the user, `_mbsetupuser` | An unfamiliar name |

## Login history (§2)

A remote row (non-blank host, not `tty`/`console`) is high-signal. Benign only
if the user knowingly SSHes into their own Mac. Otherwise investigate.

## Remote access (§3)

- **`~/.ssh/authorized_keys` present** — the highest-signal file in the whole
  scan. Every key in it can log in. If the user didn't add it, that's serious.
- **Third-party agent loaded** (TeamViewer/AnyDesk/…) — benign if the user
  installed it for support; a red flag if unrecognized.
- **sshd / screensharing / ARD loaded** (sudo pass) — benign if the user turned
  on Remote Login / Screen Sharing in System Settings deliberately.

## Listening ports (§4)

`node *:3000`, a Vite/Next dev server, a database on `*:5432` — normal on a dev
Mac. What matters: a listener owned by a binary the user can't name, or bound
externally with no reason. Loopback (`127.0.0.1` / `[::1]`) listeners are not
network-reachable and are almost always fine.

## Persistence — launchd (§5) & cron (§6)

The autostart surface. Benign entries are legion: `com.google.keystone`
(Chrome updater), `com.github.facebook.watchman`, Homebrew services, Raycast,
Docker, your own agents. Worrying: a plist whose `ProgramArguments` points at a
script in `/tmp`, `~/Library/Application Support/<random>`, a base64 blob, or a
`curl … | sh`. Always resolve the label to its program:
`defaults read <plist> ProgramArguments`.

## Browser extensions (§7)

`<all_urls>` permission means the extension can read every page — normal for
uBlock Origin, ColorZilla, Wappalyzer, a password manager. Worrying: an
extension with broad permissions that the user doesn't recognize, or one
sideloaded outside the store. Match each ID to a name; look up unknowns.

## MDM / profiles (§8)

On a personally-owned Mac, "no configuration profiles" is the expected and good
result. Any profile the user didn't install can silently enforce settings,
install certs, or route traffic — investigate its source. A work Mac enrolled in
the employer's MDM is expected; a personal Mac enrolled in an unknown MDM is not.

## Hardening (§9)

FileVault **On**, SIP **enabled**, Gatekeeper **enabled**, firewall **on** — the
baseline. Any of these off is not compromise by itself, but it's the posture a
compromise would exploit, so note it and offer to turn it back on (in System
Settings — this skill does not change settings).

## The meta-rule

A single finding is a question, not a conclusion. Compromise usually shows
**several** at once — a remote login *and* an authorized_key *and* a strange
LaunchDaemon telling one story. One unfamiliar-but-signed launch agent on an
otherwise pristine machine is almost always benign software.
