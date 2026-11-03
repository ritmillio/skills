---
name: free-disk
description: Free disk space on a dev machine without losing work. Scans what is eating the SSD, deletes only regenerable output (Next.js .next, .turbo, Nuxt/SvelteKit/Parcel caches, Rust target dirs, brew/npm/pnpm/yarn/uv/pip caches) while skipping any checkout with a live dev server, then offers worktree removal via worktree-janitor. Use when the user says 'my mac is full', 'disk full', 'free up space', 'what is taking space on the SSD', 'clean the disk', or a build fails with ENOSPC / 'no space left on device'.
allowed-tools: Bash, Read, AskUserQuestion
---

# /free-disk: get the SSD back without losing work

On an agent-heavy machine the disk does not fill up with code. It fills up
with build output nobody remembers: every worktree gets a dev server, every
dev server writes a `.next` cache, and a single Next.js cache reaches tens of
gigabytes. On the machine this skill was written on, 697 GB were in use; 350 GB
of that was `.next` caches across ~45 sibling worktrees, and 46 GB was Rust
`target` dirs. Deleting both lost nothing and took two minutes.

So delete regenerable output first, and only then consider deleting checkouts.

## When NOT to use this

- To delete source checkouts or branches. That decision belongs to
  `worktree-janitor`, which checks for uncommitted and unpushed work first.
- On a CI runner or a shared server: the caches there are warm on purpose.

## Workflow

### 0. Locate this skill on disk

```bash
for d in "${CLAUDE_PLUGIN_ROOT:-}" ~/.agents/skills/free-disk ./.agents/skills/free-disk \
         ~/.claude/skills/free-disk ~/.codex/skills/free-disk \
         ~/.gemini/skills/free-disk ~/.cursor/skills/free-disk ./.claude/skills/free-disk; do
  [ -x "$d/scripts/clean.sh" ] && SKILL_DIR="$d" && break
done
```

### 1. Scan (read-only)

```bash
bash "$SKILL_DIR/scripts/scan.sh"              # default roots: ~/Developer ~/code ~/src ~/projects
bash "$SKILL_DIR/scripts/scan.sh" ~/work       # or name the roots
```

Report free space and the top consumers in a few lines, not the dump. A full
`du` of a large code root can take minutes: run it in the background and give
the user a one-line status while it runs.

### 2. Delete regenerable output

The user asked for space, so this step needs no extra confirmation. Dry run,
then apply:

```bash
bash "$SKILL_DIR/scripts/clean.sh" [roots]           # dry run
bash "$SKILL_DIR/scripts/clean.sh" --apply [roots]
```

What it deletes: `.next`, `.turbo`, `.nuxt`, `.svelte-kit`, `.parcel-cache`;
any `target` dir next to a `Cargo.toml`; `$CARGO_TARGET_DIR`; extra dirs listed
one glob per line in `~/.config/free-disk/extra-dirs` (for a shared Rust target
outside a checkout). Then `brew cleanup`, `npm cache clean`, `pnpm store prune`,
`yarn cache clean`, `uv cache prune`, and the pip and node-gyp caches.

What it skips: any checkout that holds the cwd of a running node, next, vite,
turbo, cargo, rustc or tauri process. Deleting `.next` under a live dev server
breaks it. Rust targets are skipped entirely while cargo or rustc is running.

### 3. Need more? Ask.

Use `AskUserQuestion` (multiSelect, recommendation first). Each option says how
much space it frees and what could be lost:

- **Worktrees whose work is all on the remote** (PR merged/closed, or no PR and
  nothing unpushed): run the `worktree-janitor` skill's census, then prune the
  SAFE and ASK paths the user picks. Removal is slow on large monorepos, so run
  it in the background.
- **Model caches** (`~/.cache/huggingface`, `~/.ollama`), **Xcode DerivedData
  and simulators**, **Docker data**, **Downloads**: only on an explicit pick.

### 4. Report

Free space before and after, what went, and what was skipped and why.

## Rules

- Never delete source, uncommitted work, unpushed commits, `node_modules` that
  a running server uses, or anything `worktree-janitor` marks KEEP.
- Never `git worktree remove --force` unless the user names that path.
- Never touch the Trash, `~/Library/Application Support`, `~/Documents`, or
  anything synced to iCloud or another cloud drive.
- Measure before and after with `df`. A `du` total of hard-linked
  `node_modules` overstates what deleting them frees.
