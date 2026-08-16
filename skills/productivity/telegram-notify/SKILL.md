---
name: telegram-notify
description: Set up Telegram bot notifications for agent events — turn finished, turn failed, commits, pushes, blocked-on-permission, and relay run events (start/landed/halt/limit/end). Ships the telegram-notify.sh sender script and walks through BotFather setup, chat id, config, hook wiring, and a --doctor check. Use when the user wants a Telegram ping when the agent finishes, commits, gets stuck, or dies.
---

# /telegram-notify — ping me when the agent needs me

An agent that runs unattended needs a way to tap you on the shoulder. This
skill ships a sender script (`scripts/telegram-notify.sh` beside this file) and
wires it into the places events happen: Claude Code hooks for interactive
sessions, and `relay`'s notifier contract for unattended runs.

The script is a pure observer. Missing config, missing `python3`, no network, a
failed send — every path exits 0 and the send is backgrounded. A notification
must never be able to break the thing it reports on.

**That silence is also the trap.** An unconfigured setup and a working one look
identical from the terminal: both print nothing. `--doctor` is the only mode
that says out loud whether the thing is alive. Use it, and do not declare setup
finished on the strength of an exit code — the script *always* exits 0.

## Invocation

- `/telegram-notify` — full setup
- `/telegram-notify test` — `--doctor` plus a real message with the live config
- `/telegram-notify off` — remove the hooks (config and script stay)

## When to use this

- You run agents unattended or in the background and want to know when they
  finish, stall on a permission prompt, or die — without watching the terminal.
- You run `relay` and want start/landed/halt/limit/end events on your phone.
- You want a ping when a session commits or pushes.

## When NOT to use this

- The user has no Telegram or wants a different channel. The script's `--relay`
  contract is generic enough for any sender, but this skill sets up Telegram only.

## The script's four modes

Read this before touching hooks — the mode boundaries are load-bearing.

| Invocation | Mode | Notes |
|---|---|---|
| `telegram-notify.sh` (no args, JSON on stdin) | hook | **Hooks pass no arguments.** The event comes from `hook_event_name` in the payload. |
| `RELAY_EVENT=<kind> telegram-notify.sh --relay "<body>"` | relay | relay composes the body; the script adds the icon and title. |
| `telegram-notify.sh "message"` | ad-hoc | Setup tests and scripts. Warns on stderr if unconfigured. |
| `telegram-notify.sh --doctor` | doctor | Reports config state and validates the token via `getMe`. |

**Never add a required flag to hook mode.** Hook mode is the no-argument case
on purpose. If you change that, every hook in `settings.json` must be rewired in
the same edit, or all five go silently dead.

`TELEGRAM_NOTIFY_DRY_RUN=1` prints the composed message instead of sending it —
the seam that makes hook payloads testable without a bot.

## Setup workflow

Do at most one `AskUserQuestion` round up front: do they already have a bot
token, and which events they want (the knobs in the config default to all on).
Then walk through:

### 1. Locate this skill's script

```bash
for d in "${CLAUDE_PLUGIN_ROOT:-}" ~/.claude/skills/telegram-notify \
         ~/.agents/skills/telegram-notify ./.agents/skills/telegram-notify \
         ~/.codex/skills/telegram-notify ./.claude/skills/telegram-notify; do
  [ -x "$d/scripts/telegram-notify.sh" ] && SKILL_DIR="$d" && break
done
```

If none match: `find ~ -name telegram-notify.sh -path '*telegram-notify/scripts/*' 2>/dev/null | head -1`.

### 2. Check for an existing install first

```bash
[ -f ~/.claude/telegram-notify.sh ] && ~/.claude/telegram-notify.sh --doctor
```

If a script is already there, **diff it before copying over it** — a previous
install may be a different generation with local fixes. Copying blind is how a
working setup gets replaced by a worse one. If it is already configured and
`--doctor` is green, skip to step 6.

### 3. Create the bot (user's hands, your guidance)

In Telegram, open **@BotFather** → `/newbot` → pick a name and username →
BotFather replies with a token like `123456:ABC-DEF...`. Ask the user to paste
it. Treat it as a secret: it goes into a 0600 file, never into a repo file,
never into `settings.json`, never into a commit, never echoed back in full.

### 4. Get the chat id

Ask the user to send any message to their new bot, then:

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"][-1]["message"]["chat"]["id"])'
```

Empty `result` means the user has not messaged the bot yet — ask again rather
than guessing. For a group, add the bot to the group first; the id is negative.

### 5. Install the script and config

```bash
mkdir -p ~/.claude
cp "$SKILL_DIR/scripts/telegram-notify.sh" ~/.claude/telegram-notify.sh
chmod +x ~/.claude/telegram-notify.sh
[ -f ~/.claude/telegram.env ] || cp "$SKILL_DIR/telegram.env.example" ~/.claude/telegram.env
chmod 600 ~/.claude/telegram.env
# then fill TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in ~/.claude/telegram.env
```

`~/.claude/telegram-notify.sh` is relay's default `RELAY_NOTIFY` path
(`skills/engineering/relay/scripts/relay.sh`), so relay notifications start
working with zero relay changes. Other setups point `RELAY_NOTIFY` at it directly.

### 6. Prove it works

```bash
~/.claude/telegram-notify.sh --doctor          # must print "getMe : ok, bot is @..."
~/.claude/telegram-notify.sh "telegram-notify: setup OK"
```

Ask the user to confirm the message arrived on their phone. **Do not proceed to
hooks until it did.** A miswired hook is a silent hook, and so is an empty token.

### 7. Wire the Claude Code hooks

Merge — never clobber — into `~/.claude/settings.json` with `jq` or `python3`.
All five call the script with **no arguments**:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "~/.claude/telegram-notify.sh", "async": true, "timeout": 10 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/.claude/telegram-notify.sh", "async": true, "timeout": 15 } ] }
    ],
    "StopFailure": [
      { "hooks": [ { "type": "command", "command": "~/.claude/telegram-notify.sh", "async": true, "timeout": 15 } ] }
    ],
    "PostToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "~/.claude/telegram-notify.sh", "async": true, "timeout": 15 } ] }
    ],
    "Notification": [
      { "matcher": "permission_prompt|idle_prompt|agent_needs_input|agent_completed",
        "hooks": [ { "type": "command", "command": "~/.claude/telegram-notify.sh", "async": true, "timeout": 15 } ] }
    ]
  }
}
```

`UserPromptSubmit` is not a notification — it stamps when the turn began so
`Stop` can filter out quick answers. Drop it and the turn-length gate goes with it.

Hooks are read at launch, so they fire from the **next** session on. Say that.

## What fires when

| Event | Where | Message |
|---|---|---|
| Turn finished (longer than `TELEGRAM_MIN_TURN_SECONDS`) | `Stop` | 🟢 Done · repo · branch (2m 14s) + last message |
| Turn died (rate limit, API error) | `StopFailure` | 🔴 Turn failed · repo · branch + error |
| `git commit` / `git push` | `PostToolUse` / Bash | ✅ Commit · repo · branch + subject line |
| Blocked on permission / idle / subagent | `Notification` | ⏸️ Waiting · repo · branch |
| Relay start / landed / halt / limit / end | relay's `$RELAY_NOTIFY` | 🚀 ✅ 🛑 ⏳ 🏁 + relay's own body |
| Ad-hoc | `telegram-notify.sh "msg"` | the message |

Every message carries a `repo · branch` header, so you know which of three
running checkouts pinged you.

## /telegram-notify off

Remove the hook entries from `~/.claude/settings.json` (leave other hooks
untouched) and say so. Leave the config and script in place — deleting secrets
is the user's call. To silence individual events without unwiring anything, set
the `TELEGRAM_NOTIFY_*` knobs to `0` in `~/.claude/telegram.env` instead.

## Rules and traps

**The token is a secret.** 0600 config, never in a repo file, never in
`settings.json`, never committed, never echoed in full — `--doctor` prints only
the bot-id prefix and a length for exactly this reason.

**Never trust the exit code.** Every path exits 0 by design. `--doctor` and a
confirmed message on the user's phone are the only proof of life.

**Tab is IFS whitespace.** `IFS=$'\t' read -r a b c …` collapses runs of tabs,
so one empty field silently shifts every later field by one. The field
separator here is `\x1f` for that reason. Do not "simplify" it to a tab.

**A relay iteration is a `claude -p`** and fires the user's own global hooks, so
a relay would double-notify. `relay.sh` exports `CLAUDE_RELAY_ACTIVE=1` and hook
mode exits early on it — relay's own message is better because it knows the
iteration number and commit count.

**Commit detection matches `*git*commit*` loosely on purpose.** `git -C
<worktree> commit` contains no `git commit` substring, and that shape is
everywhere in unattended work. The subject line is read from `git log -1` in the
`-C` directory: a commit is evidence, tool output is only a claim.

**Hook-mode parsing needs `python3`.** Without it, hook mode degrades to
silence. Say that plainly rather than pretending hooks work.
