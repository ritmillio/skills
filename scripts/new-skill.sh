#!/usr/bin/env bash
#
# new-skill.sh - scaffold a new skill and register it everywhere it needs to be.
#
#   ./scripts/new-skill.sh my-skill --category engineering --description "..."
#
# Categories: engineering, productivity, in-progress (not ready), deprecated (retired).
#
# Creates skills/my-skill/ with a SKILL.md, adds the Claude Code plugin
# manifest, and appends the entry to the marketplace so `/plugin install
# my-skill@ritmillio-tools` works on the next push.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${1:-}"; shift || true
DESC=""; CAT="engineering"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --description) DESC="$2"; shift 2 ;;
    --category)    CAT="$2";  shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$NAME" ]] || { echo "usage: new-skill.sh <name> [--description '...']" >&2; exit 2; }
[[ "$NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "name must be kebab-case" >&2; exit 2; }
DIR="$REPO/skills/$CAT/$NAME"
[[ -e "$DIR" ]] && { echo "skills/$CAT/$NAME already exists" >&2; exit 2; }
[[ -n "$DESC" ]] || DESC="TODO: one sentence saying what this does AND when to invoke it."

mkdir -p "$DIR/.claude-plugin" "$DIR/references" "$DIR/scripts"

cat > "$DIR/SKILL.md" <<EOF
---
name: $NAME
description: $DESC
---

# /$NAME — one-line hook

One paragraph: what problem this solves, and why it exists.

## When to use this

- 

## When NOT to use this

- 

## Workflow

1. 

## Report format

What the skill says back when it finishes.
EOF

cat > "$DIR/.claude-plugin/plugin.json" <<EOF
{
  "name": "$NAME",
  "description": "$DESC",
  "version": "0.1.0",
  "author": { "name": "Zoltan Fodor", "url": "https://github.com/ritmillio" },
  "homepage": "https://github.com/ritmillio/skills",
  "repository": "https://github.com/ritmillio/skills",
  "license": "MIT"
}
EOF

# Register in the marketplace so it is installable, not just present.
tmp="$(mktemp)"
jq --arg n "$NAME" --arg d "$DESC" --arg c "$CAT" \
  '.plugins += [{name:$n, source:("./skills/" + $c + "/" + $n), description:$d, version:"0.1.0"}]' \
  "$REPO/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$REPO/.claude-plugin/marketplace.json"

rmdir "$DIR/references" "$DIR/scripts" 2>/dev/null || true

echo "created skills/$CAT/$NAME/SKILL.md"
echo "registered in .claude-plugin/marketplace.json"
echo
echo "next: write the SKILL.md, then"
echo "  npx skills@latest add ritmillio/skills --skill $NAME   # into every agent"
echo "  claude plugin validate ./skills/$CAT/$NAME"
