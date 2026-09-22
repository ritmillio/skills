#!/usr/bin/env bash
# memory-hygiene/audit.sh — READ-ONLY. Reports how much of MEMORY.md actually
# loads, broken/orphan/duplicate entries, frontmatter errors, and finished
# project memories that could move to archive/.
# Usage: audit.sh [memory-dir] [--json]
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/audit.py" "$@"
