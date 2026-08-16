---
name: telegram-notify
description: Set up Telegram bot notifications for agent events — task finished (Stop hook), commits, and relay run events (start/landed/halt/limit/end). Ships the telegram-notify.sh sender script and walks through BotFather setup, chat id, config, and Claude Code hook wiring. Use when the user wants a Telegram ping when the agent finishes a task or lands commits.
---

# /telegram-notify — ping me when the agent is done

An agent that runs unattended needs a way to tap you on the shoulder. This
skill ships a small sender script (`scripts/telegram-notify.sh` beside this
file) and wires it into the places events happen: Claude Code hooks for
interactive sessions, and `relay`'s notifier contract for unattended runs.

The script is a pure observer: missing config, no network, a failed send — it
always exits 0 silently. A notification must never be able to break the thing
it reports on.

## Invocation

`/telegram-notify` — full setup. `/telegram-notify test` — send a test message
with the current config. `/telegram-notify off` — remove the hooks (config and
script stay).

## When to use this

- You run agents unattended or in the background and want to know when they
  finish, without watching the terminal.
- You run `relay` and want start/landed/halt/limit/end events on your phone.
- You want a ping when a session commits.

## When NOT to use this

- The user has no Telegram or wants a different channel. The script's modes
  are generic — `--relay` works for any sender — but this skill sets up
  Telegram only.

## Setup workflow

Do at most one `AskUserQuestion` round up front: do they already have a bot
token, and do they want per-commit pings in normal sessions too (relay runs
report commits themselves, so this only affects interactive sessions). Then
walk through:

### 1. Locate this skill's script

```bash
for d in "${CLAUDE_PLUGIN_ROOT:-}" ~/.agents/skills/telegram-notify \
         ./.agents/skills/telegram-notify ~/.claude/skills/telegram-notify \
         ~/.codex/skills/telegram-notify ./.claude/skills/telegram-notify; do
  [ -x "$d/scripts/telegram-notify.sh" ] && SKILL_DIR="$d" && break
done
```

If none match: `find ~ -name telegram-notify.sh -path '*telegram-notify/scripts/*' 2>/dev/null | head -1`.

### 2. Create the bot (user's hands, your guidance)

In Telegram, open **@BotFather** → `/newbot` → pick a name and username →
BotFather replies with a token like `123456:ABC-DEF...`. Ask the user to paste
it. Treat it as a secret: it goes into a 0600 config file, never into a repo
file or a commit.

### 3. Get the chat id

Ask the user to send any message to their new bot, then:

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq -r '.result[-1].message.chat.id'
```

For a group, add the bot to the group first; the chat id will be negative.

### 4. Write config and install the script

```bash
mkdir -p ~/.config/telegram-notify ~/.claude
umask 077
cat > ~/.config/telegram-notify/config <<EOF
TELEGRAM_BOT_TOKEN=<token>
TELEGRAM_CHAT_ID=<chat id>
EOF
chmod 600 ~/.config/telegram-notify/config
cp "$SKILL_DIR/scripts/telegram-notify.sh" ~/.claude/telegram-notify.sh
chmod +x ~/.claude/telegram-notify.sh
```

`~/.claude/telegram-notify.sh` is relay's default `RELAY_NOTIFY` path
(`skills/engineering/relay/scripts/relay.sh`), so relay notifications start
working with zero relay changes. Other setups can point `RELAY_NOTIFY` at the
script directly.

### 5. Send a test message

```bash
~/.claude/telegram-notify.sh "telegram-notify: setup OK"
```

Ask the user to confirm it arrived. Do not proceed to hooks until it did — a
miswired hook is a silent hook.

### 6. Wire the Claude Code hooks

Merge — never clobber — into `~/.claude/settings.json` with `jq`. The `Stop`
hook (agent finished a task) is the default; add the `PostToolUse` Bash hook
(per-commit pings) only if the user asked for it:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/.claude/telegram-notify.sh --hook" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "~/.claude/telegram-notify.sh --hook" } ] }
    ]
  }
}
```

The script reads the hook JSON on stdin and decides what to send: `Stop` →
"[done] agent finished in \<dir\>"; `PostToolUse` → stays silent unless the
Bash command contained `git commit`. When `CLAUDE_RELAY_ACTIVE=1` (exported by
relay) `--hook` exits silently — relay reports its own iterations, with commit
counts, and per-iteration hooks would only double-report.

The hook fires on the next session start (settings are read at launch). Tell
the user that.

## What fires when

| Event | Where | Message |
|---|---|---|
| Agent finishes a task | `Stop` hook | `[done] agent finished in <dir>` |
| `git commit` in a session | `PostToolUse` hook (opt-in) | `[commit] <dir>: <oneline>` |
| Relay start / landed / halt / limit / end | relay's `$RELAY_NOTIFY` | `[relay <event>] <body>` |
| Ad-hoc | `telegram-notify.sh "msg"` | the message |

## /telegram-notify off

Remove the two hook entries from `~/.claude/settings.json` with `jq` (leave
other hooks untouched) and say so. Leave the config and script in place —
removing secrets is the user's call.

## Rules

The token is a secret: 0600 config, never echoed into a repo file, never
committed. The script must always exit 0 — test a failure path (unset the
token, run it) before declaring setup done. Hook JSON parsing needs `jq`; if
the machine lacks it, `--hook` mode degrades to silence, so say that plainly
rather than pretending hooks work.
