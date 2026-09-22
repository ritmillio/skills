# worktree-janitor — how the census decides

## Columns

- **DIRTY** — `git status --porcelain` line count, untracked files included.
- **UNPUSH** — `git rev-list --count HEAD --not --remotes`: commits reachable
  from HEAD that no remote-tracking ref contains. Needs a recent `git fetch` to
  be exact; a stale remote only makes it *more* cautious (shows more unpushed).
- **AGE** — committer date of HEAD, relative.
- **PR** — one `gh pr list --state all --limit 1000` per run, joined on
  `headRefName`. When a branch name was reused, an OPEN PR wins, else the most
  recently updated. `?` means `gh` is missing or not authed; every row then
  lands in ASK at best.
- **SERVER** — every TCP listener owned by the current user (`lsof -iTCP
  -sTCP:LISTEN`), matched to a worktree when the process's cwd is inside it.
  A server started from a parent directory will not match; check the port by
  hand before assuming it is free.

## Notes a row can carry

- **commits after the PR closed** — HEAD is not an ancestor of the PR's last
  head SHA, so someone kept working after merge/close. ASK, never SAFE.
- **relay live pid N** — `.loop/relay.pid` or `.loop/watchdog.pid` names a live
  process (the relay skill writes these). Always KEEP.
- **directory gone (prunable)** — git still lists it but the folder was deleted.
  SAFE; `git worktree prune` clears it.

## Edge cases

- **Squash-merged PRs** — the branch's commits are not in `main`, but they are
  on the remote branch, so UNPUSH is 0 and the PR says MERGED: SAFE is right.
- **PR folded into another branch and closed** — same reasoning, CLOSED + 0
  unpushed = the work lives on the remote branch.
- **Detached HEAD** — no branch, so no PR: ASK. If UNPUSH is 0 the commit is on
  the remote and removal loses nothing.
- **Worktrees in `/tmp` or `.claude/worktrees/`** — listed with their full path;
  temp worktrees vanish on reboot and show up as prunable.

## What it cannot see

- Stashes (`git stash list` is shared per repo, not per worktree) — they survive
  worktree removal anyway.
- Ignored files (`.env.local`, build outputs, local databases). If a worktree
  holds a hand-made `.env.local` you want, copy it before removing.
- Docker containers or processes that do not listen on TCP.
