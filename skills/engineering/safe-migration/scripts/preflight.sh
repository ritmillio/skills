#!/usr/bin/env bash
# safe-migration/preflight.sh — READ-ONLY. Works out, from the repo itself:
#   - the migrations directory (or takes it as $2)
#   - whether the repo forbids the generator (frozen journal / "do not run generate")
#   - the next free numeric prefix, and any historical duplicate prefixes
#   - the repo's migration-check script, if package.json has one
# Usage: preflight.sh [repo] [migrations-dir]
set -uo pipefail
REPO="${1:-$PWD}"; REPO="$(cd "$REPO" && pwd)"
MIG="${2:-}"

if [ -z "$MIG" ]; then
  # Directory holding the most NNNN_*.sql files, outside node_modules.
  MIG="$(find "$REPO" -path '*/node_modules' -prune -o -type f -name '[0-9][0-9][0-9][0-9]_*.sql' -print 2>/dev/null \
        | xargs -n1 dirname 2>/dev/null | sort | uniq -c | sort -rn | head -1 | awk '{ $1=""; sub(/^ /,""); print }')"
fi
[ -n "$MIG" ] && [ -d "$MIG" ] || { echo "no migrations directory found (pass it as the 2nd argument)"; exit 1; }

echo "repo:            $REPO"
echo "migrations dir:  ${MIG#$REPO/}"

# ---- the repo's own rule about the generator
RULE_FILES=""
for f in "$REPO/AGENTS.md" "$REPO/CLAUDE.md" "$MIG/README.md"; do [ -f "$f" ] && RULE_FILES="$RULE_FILES $f"; done
PAT='journal[^.]{0,40}frozen|frozen[^.]{0,40}journal|(do not|don.t|never)[^.]{0,30}(run[^.]{0,10})?`?(pnpm |npm run |yarn )?(db:generate|drizzle-kit generate)'
HITS=""
[ -n "$RULE_FILES" ] && HITS="$(grep -niE "$PAT" $RULE_FILES 2>/dev/null | head -5)"
if [ -n "$HITS" ]; then
  echo "generator:       FORBIDDEN by the repo — hand-write the SQL"
  echo "$HITS" | sed "s#$REPO/##; s/^/                 /" | cut -c1-200
  MODE=hand
else
  echo "generator:       allowed (no frozen-journal rule found in AGENTS.md/CLAUDE.md/migrations README)"
  MODE=generate
fi

# ---- prefixes: the disk AND the default branch on the remote, so a migration
# that landed on main since this branch was cut is not reused.
REL="${MIG#$REPO/}"
BASE="$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
names() {
  ls "$MIG"
  git -C "$REPO" ls-tree --name-only "$BASE" -- "$REL/" 2>/dev/null | sed 's#.*/##'
}
PREFIXES="$(names | grep -E '^[0-9]{4}_.*[.]sql$' | sort -u | cut -c1-4 | sort)"
LAST="$(echo "$PREFIXES" | tail -1)"
DUPES="$(echo "$PREFIXES" | uniq -d | tr '\n' ' ')"
NEXT="$(printf '%04d' $((10#$LAST + 1)))"
echo "last prefix:     $LAST   (on disk or on $BASE: $(names | grep -E "^${LAST}_" | sort -u | tr '\n' ' '))"
echo "next prefix:     $NEXT"
[ -n "$DUPES" ] && echo "historical dupes: $DUPES (tolerate, never add another)"

# ---- check command
check_scripts() {
  python3 - "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])).get("scripts", {})
print("\n".join(k for k in d if "check" in k and ("migrat" in k or k.startswith("db:"))))
EOF
}
CHECK=""
for pj in "$REPO/package.json" "$REPO"/apps/*/package.json; do
  [ -f "$pj" ] || continue
  s="$(check_scripts "$pj" 2>/dev/null | head -1)"
  [ -n "$s" ] && CHECK="$CHECK $s [${pj#$REPO/}]"
done
echo "check script:    ${CHECK:- none found - use drizzle-kit check or the repo CI job}"
echo "mode:            $MODE"
