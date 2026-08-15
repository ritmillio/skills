# Installation

## Where each agent looks

User scope applies everywhere on your machine. Project scope applies to one
repository and travels with it if you commit the directory.

| Agent | User scope | Project scope |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |
| OpenAI Codex | `~/.codex/skills/` | `.codex/skills/` |
| Gemini CLI | `~/.gemini/skills/` | `.gemini/skills/` |
| Cursor | `~/.cursor/skills/` | `.cursor/skills/` |

`./scripts/install.sh` writes to the user scope by default and only touches
agents it can actually find. `--scope project` switches to the project form,
relative to your current directory.

Any other agent that reads the standard works too — copy the skill folder into
whatever directory it scans.

## Claude Code: plugin vs skills directory

Two routes, and it is worth understanding which one you are on:

**Plugin marketplace** — versioned, updates with `/plugin update`:

```
/plugin marketplace add ritmillio/skills
/plugin install relay@ritmillio-tools
```

Skills installed this way are **namespaced**: the command is `/relay:relay`,
not `/relay`. The documentation suggests a single-skill plugin with `SKILL.md`
at its root escapes the namespace via the frontmatter `name`; on Claude Code
2.1.x it does not. Verify with any new plugin rather than trusting the name you
expected — ask a fresh session to list skills matching your skill's name.

**Skills directory** — what `install.sh` does. The command keeps its plain
name (`/relay`), edits to your clone take effect at once, and there is no
version tracking. Better while you are writing a skill, and better if you care
about the command reading well.

Installing both is harmless — the two names coexist rather than one overriding
the other — but you pay the skill's token cost twice in every session. If you develop skills in this repo, register
the marketplace from your local clone rather than from GitHub, so edits apply
without a push:

```
claude plugin marketplace add /absolute/path/to/skills
```

A marketplace name can only be registered once, so the local registration and
the GitHub one are mutually exclusive.

## Verifying

```bash
./scripts/install.sh --list
claude plugin validate ./skills/relay      # Claude Code manifests
```

In a fresh agent session, ask it to list its available skills. A skill that
does not appear is almost always in the wrong directory or missing its
frontmatter `description`.

## Uninstalling

```bash
./scripts/install.sh --uninstall           # all tools, all skills
./scripts/install.sh --uninstall --tool cursor relay
```

Only removes what this installer put there; a directory you wrote yourself is
never clobbered.
