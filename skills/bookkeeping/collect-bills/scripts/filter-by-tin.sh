#!/usr/bin/env bash
#
# filter-by-tin.sh - split a folder of invoice PDFs into company invoices and the rest.
#
# An invoice counts as a company invoice only if the company tax number appears in
# its text. Matching is done on the digit core, so both the local format
# (12345678-1-41) and the EU VAT format (HU12345678) are caught.
#
#   filter-by-tin.sh <dir> [--tax-id <core>] [--apply]
#
# Tax id resolution order:
#   1. --tax-id flag
#   2. $COLLECT_BILLS_TAX_ID
#   3. "taxIdCore" in ./.collect-bills.json
#
# Dry run by default. --apply moves non-company files to <dir>/_no-tax-number/.
#
# Requires: pdftotext (poppler). macOS: brew install poppler
#           Debian/Ubuntu: apt-get install poppler-utils

set -euo pipefail

DIR=""; TIN=""; APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --tax-id) TIN="${2:-}"; shift 2 ;;
    --apply)  APPLY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *)  DIR="$1"; shift ;;
  esac
done

[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "usage: $(basename "$0") <dir> [--tax-id <core>] [--apply]" >&2; exit 2; }

# Resolve the tax id if it was not passed explicitly.
if [ -z "$TIN" ]; then
  TIN="${COLLECT_BILLS_TAX_ID:-}"
fi
if [ -z "$TIN" ] && [ -f ./.collect-bills.json ]; then
  TIN=$(sed -n 's/.*"taxIdCore"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ./.collect-bills.json | head -1)
fi
[ -n "$TIN" ] || {
  echo "no tax id. Pass --tax-id <core>, set COLLECT_BILLS_TAX_ID," >&2
  echo "or add \"taxIdCore\" to ./.collect-bills.json" >&2
  exit 2
}

command -v pdftotext >/dev/null 2>&1 || {
  echo "pdftotext not found. macOS: brew install poppler | Debian: apt-get install poppler-utils" >&2
  exit 3
}

# Reduce whatever was passed to the stable core: the longest run of digits.
# "12345678-1-41" and "HU12345678" both reduce to "12345678". Concatenating all
# digits instead would produce "12345678141", which fails to match the EU VAT
# form and silently classifies valid invoices as personal.
CORE=$(printf '%s' "$TIN" | tr -c '0-9' '\n' | awk '{ if (length($0) > length(best)) best=$0 } END { print best }')
[ -n "$CORE" ] || { echo "tax id contains no digits: $TIN" >&2; exit 2; }
[ ${#CORE} -ge 6 ] || { echo "tax id core '$CORE' looks too short to be safe" >&2; exit 2; }

keep=0; drop=0; bad=0
dropped_file=$(mktemp); trap 'rm -f "$dropped_file"' EXIT

shopt -s nullglob
for f in "$DIR"/*.pdf "$DIR"/*.PDF; do
  [ -e "$f" ] || continue

  # An error page saved with a .pdf extension is not a PDF. Catch it first.
  if ! head -c4 "$f" | grep -q '%PDF'; then
    echo "NOT-A-PDF  $(basename "$f")"
    bad=$((bad + 1))
    continue
  fi

  text=$(pdftotext -layout "$f" - 2>/dev/null || true)

  # Strip separators so 12345678-1-41 and HU12345678 both reduce to the core.
  if printf '%s' "$text" | tr -cd '0-9' | grep -q "$CORE"; then
    keep=$((keep + 1))
  else
    drop=$((drop + 1))
    vendor=$(printf '%s' "$text" | sed -n '3,14p' \
      | grep -oE '[A-Z][A-Za-z0-9.,&'"'"' ]*(Inc|Corporation|Corp|PBC|LTD|Ltd|LLC|GmbH|B\.V\.|Kft)\.?' \
      | head -1 | sed 's/[[:space:]]*$//')
    [ -n "$vendor" ] || vendor="(unknown vendor)"
    printf '%s\t%s\n' "$(basename "$f")" "$vendor" >> "$dropped_file"
  fi
done

echo "company invoices (tax id $CORE present): $keep"
echo "no company tax id                      : $drop"
[ "$bad" -gt 0 ] && echo "not valid PDFs                         : $bad"

if [ "$drop" -gt 0 ]; then
  echo
  echo "=== excluded ==="
  awk -F'\t' '{printf "  %-30s %s\n", $1, $2}' "$dropped_file"
  echo
  echo "=== vendors billing a person, fix these billing profiles ==="
  cut -f2 "$dropped_file" | sort | uniq -c | sort -rn | sed 's/^/  /'
fi

if [ "$APPLY" -eq 1 ] && [ "$drop" -gt 0 ]; then
  out="$DIR/_no-tax-number"
  mkdir -p "$out"
  moved=0
  while IFS=$'\t' read -r name _; do
    mv -f "$DIR/$name" "$out/" 2>/dev/null && moved=$((moved + 1))
  done < "$dropped_file"
  echo
  echo "moved $moved file(s) to $out/"
fi
