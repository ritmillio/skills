---
name: worktree-janitor
description: "Census and clean up a repo's git worktrees: one table with branch, uncommitted and unpushed work, last commit age, PR state (merged/closed/open/draft/none), any dev server running inside it, and a SAFE / ASK / KEEP verdict — then remove only the ones the user picks, after re-checking each. Use when the user says 'clean up worktrees', 'too many worktrees', 'which worktrees can I delete', 'prune worktrees', 'what's running on port 3xxx', 'free disk', or has dozens of sibling <repo>-* checkouts."
allowed-tools: Read, Bash, AskUserQuestion
---

# /worktree-janitor — eighty checkouts, one table, nothing lost

Agent-heavy work leaves a trail: every relay, review and side quest gets its own
worktree, most get a dev server, and a month later there are eighty sibling
`<repo>-*` directories, a dozen Next.js servers holding ports 3000–3200 and
gigabytes of `node_modules`. Nobody deletes them, because nobody knows which one
still holds the only copy of something.

This skill answers that question first and deletes second. The census is
read-only and fast (one `gh` call, not one per branch). Removal is a separate,
explicit step on paths the user picked, and it re-checks every one before it
touches it.

## When to use this

- "Clean up worktrees", "which of these can I delete", "prune worktrees".
- A port is taken and you need to know *which checkout* is serving it.
- Disk is filling up and the repo's parent directory is full of checkouts.

## When NOT to use this

- Deleting **branches on the remote** — this never touches the remote.
- A worktree someone else's session is actively using. If a relay or agent is
  live in it, it shows as KEEP; do not work around that.

## Workflow

1. **Census (read-only):**
   ```bash
   bash "$SKILL_DIR/scripts/census.sh" <repo>            # table, SAFE first
   bash "$SKILL_DIR/scripts/census.sh" <repo> --only SAFE
   bash "$SKILL_DIR/scripts/census.sh" <repo> --json     # for further filtering
   ```
   `<repo>` is any checkout of the repository — the script finds every worktree
   from the shared git dir. Takes ~15 s for 100 worktrees of a large monorepo.

2. **Show the user the summary, not the dump.** Counts per verdict, then the
   SAFE list and the ASK list with their reason. KEEP rows only get a one-line
   total unless asked ("47 kept: 30 uncommitted, 9 open PRs, 5 unpushed, …").

3. **Ask which to remove** with `AskUserQuestion` (multiSelect). Offer "all SAFE"
   as the first, recommended option, then ASK groups by reason ("merged but dev
   server running", "no PR, everything pushed"). Never pre-select a KEEP row.

4. **Dry run, then apply:**
   ```bash
   bash "$SKILL_DIR/scripts/prune.sh" <repo> <path> <path> …            # dry run
   bash "$SKILL_DIR/scripts/prune.sh" <repo> --apply <path> …
   bash "$SKILL_DIR/scripts/prune.sh" <repo> --apply --delete-branch <path> …
   ```
   `prune.sh` re-runs the census and skips anything that became dirty, unpushed,
   locked, relay-live or PR-open since step 1. It stops only the dev servers whose
   working directory is inside that worktree (SIGTERM), runs `git worktree remove`
   (no `--force`), and finally `git worktree prune`. `--delete-branch` deletes the
   local branch with `git branch -d` only when its PR merged.

5. **Report**: removed N, skipped M with the reason each, ports freed.

## The verdicts

| Verdict | Means |
|---|---|
| **SAFE** | PR merged or closed, no uncommitted files, no commits missing from the remote, no commits after the PR closed, no dev server. Everything in it already lives on the remote. |
| **ASK** | Nothing would be lost, but something needs a human call: a dev server is running, the branch has no PR, the head is detached, or commits landed after the PR closed. |
| **KEEP** | Would lose or disrupt work: uncommitted files, unpushed commits, open or draft PR, a live relay (`.loop/relay.pid` or `watchdog.pid` alive), a locked worktree, or the main checkout. |

"Closed" is SAFE, not ASK, because the census also requires zero unpushed
commits: a closed PR's branch still exists on the remote. Details and edge cases
in `references/verdicts.md`.

## Rules

- **`--force` only when the user says so, for that path.** It discards
  uncommitted work.
- Never stop a process whose cwd is outside the worktree being removed, even on
  a port you would like back.
- Never delete a branch whose PR is not merged. `git branch -d` refuses unmerged
  branches anyway; do not escalate to `-D`.

## References

- `references/verdicts.md` — how each column is computed, the edge cases
  (squash merges, reused branch names, detached heads, worktrees outside the
  parent dir), and what the census cannot see.
