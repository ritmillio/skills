#!/usr/bin/env bash
# worktree-janitor/census.sh — READ-ONLY. One row per git worktree of a repo:
# branch, uncommitted, unpushed, age, PR state, dev server, verdict.
# Usage: census.sh [repo] [--json] [--only SAFE|ASK|KEEP]
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/janitor.py" census "$@"
