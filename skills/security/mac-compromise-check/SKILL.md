---
name: mac-compromise-check
description: "Run a read-only compromise triage on a macOS machine: accounts, remote access, listening ports, launchd/cron persistence, code signatures of every launch item and process, DYLD injection, TCC privacy grants, browser extensions, MDM/config profiles, system hardening (FileVault/SIP/Gatekeeper/firewall), and the Claude hooks / MCP / Chrome agent surface. Trace a specific email or account across the machine. Use when the user says 'is my Mac hacked', 'check if my Mac is compromised', 'did someone access my machine', shows a suspicious sign-in, or wants a security audit of their laptop."
allowed-tools: Read, Bash, Grep, Glob, AskUserQuestion
---

# /mac-compromise-check — is this Mac actually compromised?

Most "I've been hacked" scares are not compromise. They are a stranger's name in
a Google account-picker, a login-alert email, a fan spinning, a browser signed
into someone else's session. Panic skips the boring evidence. This skill walks
the places persistence and remote access actually live, reports what is there,
and — crucially — **traces the thing that scared the user to its real source**
before pronouncing a verdict.

Everything here is **read-only**. The scan never kills a process, deletes a file,
changes a setting, or touches the network. It observes and reports. Remediation
is proposed to the user, never performed silently.

## When to use this

- "Is my Mac hacked?", "did someone get into my machine?", "check for malware".
- A suspicious sign-in prompt, login alert, or unfamiliar account name appeared.
- The user wants a security once-over of their laptop before travel / after loss.

## When NOT to use this

- The concern is a **cloud account** (Gmail/GitHub/iCloud) with no on-device
  angle — that is the provider's security-checkup flow, not a machine scan. You
  can still run `trace.sh <email>` to prove the credential isn't on the Mac.
- Linux or Windows. This is macOS-specific (launchd, TCC, `spctl`, `fdesetup`).
- An active, confirmed intrusion in progress. Then it's containment (pull
  network, preserve evidence, involve IR), not a leisurely triage.

## The one trap that matters

**A scary symptom is not a location.** The user reports *where they saw
something* (a Google prompt, an email), not *where the problem is*. Do not
conclude "clean" or "compromised" until you have traced that specific symptom.
In practice the account-picker draws from Google's own cookies, not from
anything synced to the Mac, and a rejected `AddSession` flow means no session was
ever created. Reconstruct it from browser history before you rule. See
`references/tracing.md`.

## Workflow

1. **Resolve the skill directory** (portable — do not assume `$CLAUDE_PLUGIN_ROOT`):
   ```bash
   SKILL_DIR="$(cd "$(dirname "$0" 2>/dev/null || echo .)" && pwd)"
   ```
   When invoked as a skill, the scripts sit next to this file under `scripts/`.

2. **Run the read-only scan** and read it top to bottom:
   ```bash
   bash "$SKILL_DIR/scripts/scan.sh"
   ```
   It prints a verdict line first, then each section (accounts, remote access,
   ports, persistence, browser, MDM, hardening) with FINDINGS flagged inline.
   Two sections need `sudo` for full coverage — the scan says so and degrades
   gracefully without it. Offer to re-run those with `sudo` only if something
   upstream looks off.

3. **Run the deep pass** when the quick scan is clean but the user is still worried, or whenever a finding needs an owner:
   ```bash
   bash "$SKILL_DIR/scripts/deep.sh"            # 30-day recent-change window
   bash "$SKILL_DIR/scripts/deep.sh" --days 7
   ```
   It verifies the code signature of every LaunchAgent/Daemon executable and every
   non-Apple running process (`APPLE` / `DEVID(name)` / `APPSTORE` are normal;
   `ADHOC` is normal under Homebrew and dev toolchains, a lead anywhere else;
   `UNSIGNED` outside those paths is a strong lead), and adds what `scan.sh`
   does not cover: DYLD injection, login hooks, PrivilegedHelperTools, `~/.ssh/rc`,
   shell-profile `curl | sh` patterns, all-user listeners with owners via
   `netstat`, sshd / Screen Sharing state without sudo, TCC grants (needs Full
   Disk Access on the terminal), quarantine download history, executables in
   `/tmp` and `/Users/Shared`, and the agent surface: Claude hooks, MCP servers,
   Chrome native-messaging hosts. `[WARN]` is a lead, not a verdict — every WARN
   must be explained in the report by naming its owner or calling it unexplained.
   `[ROOT]` lines are the sudo commands the user can run with the `!` prefix.
   Save the full output to the scratchpad; the terminal shows only a few lines.

4. **If the user named an email, account, or name, trace it:**
   ```bash
   bash "$SKILL_DIR/scripts/trace.sh" "someone@gmail.com"
   ```
   This greps disk, Spotlight, Keychain metadata, both Chromium browsers'
   history + cookies + prefs, git authors, and shell history — then prints a
   minute-by-minute browser timeline around any sign-in flow for that term.
   Read `references/tracing.md` for how to interpret an `AddSession` / `rejected`
   sequence.

5. **Interpret, don't dump.** Turn FINDINGS into a short verdict. The default
   posture for a well-kept dev Mac is *clean* — say so plainly when it's true,
   with the evidence. Only escalate on a real finding (an `authorized_keys` you
   can't account for, a LaunchDaemon you don't recognize, an externally-bound
   listener, an MDM profile, an SSH key on a linked service whose private half
   isn't local). `references/findings.md` maps each signal to benign-vs-worrying.

6. **Propose remediation as choices, never act.** Use `AskUserQuestion` with
   concrete options (rotate this token / delete that key / disable that service).
   The user clicks. This skill's tools cannot change state and must not try.

## Report format

- **Verdict** in one line: clean / one item to check / active concern.
- **What was checked**, grouped, with the reassuring negatives stated (no
  authorized_keys, no remote logins, FileVault on) — absence of evidence is the
  product here, so name it.
- **Findings**, if any, each with: what it is, why it may or may not matter, and
  the exact command to remediate — offered, not run.
- **The traced symptom**, resolved to its real source, when the user named one.

## Coverage & limits

- Full section-by-section coverage and the exact commands: `references/checklist.md`.
- What each script reads and why it's safe: header comments in `scripts/*.sh`.
- This finds **persistence, remote access, and known-shape tampering**. It is not
  a malware scanner and cannot prove a clean machine — it raises the floor, it
  doesn't certify. Say that in the verdict.
