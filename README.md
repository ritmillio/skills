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
| [`relay`](skills/engineering/relay) | Unattended autonomous work for a stated duration — 4 hours or 24 — on its own worktree and draft PR. Each iteration is a fresh process handing a committed ledger to the next, so nothing lives long enough to suffer context rot. |
| [`shred-plan`](skills/productivity/shred-plan) | The adversarial pass between "here's the plan" and "let's build it". Verifies every codebase claim in a plan with evidence, then hunts hidden dependencies, missing failure modes, scope leaks and unverifiable done-criteria — findings ranked by severity, no mercy. |
| [`draft-plan`](skills/engineering/draft-plan) | Turn an investigation or conversation into a written plan doc: verified diagnosis, explicit in/out scope, workstreams with proofs of done, sequencing gates, open questions. The doc shape `shred-plan` was built to check — chain them. |
| [`reclaim`](skills/engineering/reclaim) | Give a pinned dev machine back. Reads the System-vs-User CPU split first, because the process at the top of the list is usually a symptom — `launchservicesd` at 300% is churn, not work. Reaps stale build watchers, caps the test runner, and says plainly when only a reboot will do. |
| [`telegram-notify`](skills/productivity/telegram-notify) | Telegram bot pings when an agent finishes a task (Stop hook), lands a commit, or a relay run starts/lands/halts/ends. Ships the sender script and walks through BotFather setup and hook wiring. |

## Install

One command, every agent you have. This uses the community
[`skills`](https://www.npmjs.com/package/skills) CLI, which resolves the repo,
symlinks each skill into every agent directory it detects, and records a
lockfile so `update` works later:

```bash
npx skills@latest add ritmillio/skills
```

```bash
npx skills@latest add ritmillio/skills --list          # see what is here first
npx skills@latest add ritmillio/skills --skill relay   # just one
npx skills@latest add ritmillio/skills --all           # every skill, every agent
npx skills@latest list                                 # what you have installed
npx skills@latest update                               # pull newer versions
```

Claude Code can also install through the plugin marketplace, which gives you
versioned updates via `/plugin update`:

```
/plugin marketplace add ritmillio/skills
/plugin install relay@ritmillio-tools
```

**One catch, verified rather than assumed:** a marketplace-installed skill is
namespaced, so it invokes as `/relay:relay`. Skills installed by the CLI keep
the plain `/relay`. The documentation implies a single-skill plugin escapes the
namespace; on Claude Code 2.1.x it does not.

## Companion packs

The marketplace also passes through [Matt Pocock's skills](https://github.com/mattpocock/skills)
(`grill-me`, `tdd`, `to-spec`, `to-tickets`, `implement`, `code-review`, …) as a
remote-source entry — no vendored copy, nothing to drift:

```
/plugin install mattpocock-skills@ritmillio-tools   # pulled from his repo, synced by /plugin update
```

Skills CLI users get the same pack straight from the source instead:

```bash
npx skills@latest add mattpocock/skills
```

His pack is read-only either way. If you want to hack on one of his skills,
copy it into `skills/` here, keep the credit, and make it your own.

## Layout

```
skills/
  engineering/     shipped, code-facing
  productivity/    shipped, everything else
  in-progress/     written but not trustworthy yet
  deprecated/      retired, kept because the reasoning is still worth reading
```

A skill is a folder with a `SKILL.md`, optionally beside `references/`,
`scripts/` and `assets/`. Nothing else is required, and the category is just a
directory: installers find skills by scanning, not by path.

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
