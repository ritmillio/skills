#!/usr/bin/env bash
# worktree-janitor/prune.sh — DRY RUN unless --apply. Re-checks every named
# worktree, stops only dev servers running inside it, then `git worktree remove`.
# Usage: prune.sh [repo] [--apply] [--delete-branch] [--force] PATH...
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/janitor.py" prune "$@"
