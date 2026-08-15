# skills

Agent skills for long-running engineering work. Written once as `SKILL.md`,
usable in every agent that reads the open standard — Claude Code, Codex,
Gemini CLI, Cursor and others.

No conversion step and no per-tool copies. A skill here is a folder with a
`SKILL.md` in it, which is exactly what each of those tools already looks for.
The installer's whole job is putting the folder where each one looks.

## The skills

| Skill | What it does |
|---|---|
| [`relay`](skills/relay) | Unattended autonomous work for a stated duration — 4 hours or 24 — on its own worktree and draft PR. Each iteration is a fresh process handing a committed ledger to the next, so nothing lives long enough to suffer context rot. |

## Install

Every agent on your machine, in one command:

```bash
git clone https://github.com/ritmillio/skills.git
cd skills
./scripts/install.sh
```

It detects which agents you have, symlinks the skills into each, and tells you
what it did. Because they are symlinks, `git pull` updates every tool at once.

```bash
./scripts/install.sh --list              # what is installed where
./scripts/install.sh --tool codex        # just one agent
./scripts/install.sh --scope project     # into ./.<tool>/skills of the current repo
./scripts/install.sh --copy relay        # standalone copy instead of a symlink
./scripts/install.sh --uninstall         # take them back out
```

Claude Code users can skip the clone entirely and install through the plugin
marketplace, which also handles updates:

```
/plugin marketplace add ritmillio/skills
/plugin install relay@ritmillio-tools
```

Per-tool paths and project-vs-user scope: [INSTALLATION.md](INSTALLATION.md).

## What "works everywhere" actually means

`SKILL.md` is an open format: YAML frontmatter with a `name` and a
`description`, then Markdown instructions, optionally beside `references/`,
`scripts/` and `assets/`. Agents read the description to decide when a skill is
relevant, then load the body.

That much is genuinely portable. Two things are not, and this repo is explicit
about both rather than papering over them:

- **Slash-command invocation** is a Claude Code convenience. In other agents you
  ask for the skill by name or let the description trigger it.
- **Bundled scripts** need an absolute path, and the skill directory sits
  somewhere different in each tool. Skills here resolve it at runtime instead of
  assuming, and `relay` shows the pattern.

## Add your own

```bash
./scripts/new-skill.sh my-skill --description "What it does and when to use it"
```

Scaffolds `skills/my-skill/SKILL.md`, writes the Claude Code plugin manifest,
and registers it in the marketplace so it is installable rather than merely
present. Then write the body and run `./scripts/install.sh my-skill`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for what makes a skill worth writing.

## License

MIT
