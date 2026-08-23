#!/usr/bin/env bash
# scaffold-scraper/scaffold.sh — stamp a new country x vertical scraper package
# from templates. Creates files only; wires nothing outside the new directory
# (root scripts / cron / workspace are printed as follow-up edits). Refuses to
# overwrite an existing package directory.
#
# Usage:
#   scaffold.sh --country czechia --code cz --vertical laws --alias law \
#     --type legislation --prefix cz/laws --source "CZ/Sbirka" \
#     --url "https://www.zakonyprolidi.cz" --repo /path/to/clausis-scrapers
set -euo pipefail

COUNTRY="" CODE="" VERTICAL="" ALIAS="" TYPE="legislation" PREFIX="" SOURCE="" URL="" REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --country) COUNTRY="$2"; shift 2 ;;
    --code) CODE="$2"; shift 2 ;;
    --vertical) VERTICAL="$2"; shift 2 ;;
    --alias) ALIAS="$2"; shift 2 ;;
    --type) TYPE="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 2; }
[ -n "$COUNTRY" ] || die "--country required"
[ -n "$CODE" ]    || die "--code required (ISO, e.g. cz)"
[ -n "$VERTICAL" ]|| die "--vertical required (e.g. laws)"
[ -n "$ALIAS" ]   || die "--alias required (script alias, e.g. law)"
[ -n "$PREFIX" ]  || PREFIX="$CODE/$VERTICAL"
[ -n "$SOURCE" ]  || SOURCE="$(echo "$CODE" | tr "[:lower:]" "[:upper:]")/${VERTICAL}"
[ -n "$REPO" ]    || REPO="$(pwd)"
[ -f "$REPO/pnpm-workspace.yaml" ] || die "$REPO doesn't look like the scrapers monorepo (no pnpm-workspace.yaml)"
case "$TYPE" in legislation|case_law) ;; *) die "--type must be legislation or case_law";; esac

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TPL="$SELF_DIR/../templates"
[ -d "$TPL" ] || die "templates dir not found at $TPL"

DEST="$REPO/$COUNTRY/$VERTICAL"
[ -e "$DEST" ] && die "$DEST already exists — refusing to overwrite"

# Derived tokens.
COUNTRY_LC="$(echo "$COUNTRY" | tr '[:upper:]' '[:lower:]')"
# Portable CamelCase helpers (BSD sed has no \U; macOS bash is 3.2, no ${x^^}).
ucfirst() { echo "$1" | awk '{print toupper(substr($0,1,1)) substr($0,2)}'; }
lcfirst() { echo "$1" | awk '{print tolower(substr($0,1,1)) substr($0,2)}'; }
camel()   { echo "$1" | awk -F'[-_]' '{s="";for(i=1;i<=NF;i++){s=s toupper(substr($i,1,1)) substr($i,2)}; print s}'; }
COUNTRY_TITLE="$(ucfirst "$COUNTRY_LC")"
VNAME="$(camel "$VERTICAL")"
TYPE_NAME="${COUNTRY_TITLE}${VNAME}Doc"
VAR="$(lcfirst "${COUNTRY_LC}${VNAME}")"
if [ "$TYPE" = "legislation" ]; then VERTICAL_TITLE="Legislation"; else VERTICAL_TITLE="Case Law"; fi

mkdir -p "$DEST/src"

render() { # <template> <dest>
  sed -e "s#__COUNTRY__#${COUNTRY_TITLE}#g" \
      -e "s#__COUNTRY_LC__#${COUNTRY_LC}#g" \
      -e "s#__CC__#${CODE}#g" \
      -e "s#__VERTICAL__#${VERTICAL}#g" \
      -e "s#__VERTICAL_TITLE__#${VERTICAL_TITLE}#g" \
      -e "s#__ALIAS__#${ALIAS}#g" \
      -e "s#__DOCTYPE__#${TYPE}#g" \
      -e "s#__R2_PREFIX__#${PREFIX}#g" \
      -e "s#__SOURCE__#${SOURCE}#g" \
      -e "s#__URL__#${URL}#g" \
      -e "s#__TYPE_NAME__#${TYPE_NAME}#g" \
      -e "s#__VAR__#${VAR}#g" \
      "$1" > "$2"
}

render "$TPL/package.json.tmpl"          "$DEST/package.json"
render "$TPL/cli.ts.tmpl"                "$DEST/src/cli.ts"
render "$TPL/scraper.ts.tmpl"           "$DEST/src/scraper.ts"
render "$TPL/extraction-schema.ts.tmpl" "$DEST/src/extraction-schema.ts"
render "$TPL/r2-keys.ts.tmpl"           "$DEST/src/r2-keys.ts"
render "$TPL/scraper.test.ts.tmpl"      "$DEST/src/scraper.test.ts"

echo "✓ stamped $COUNTRY/$VERTICAL  (pkg @clausis/${COUNTRY_LC}-${VERTICAL}, type ${TYPE_NAME})"
echo
echo "NOW WIRE (see references/wiring.md):"
echo
echo "1) root package.json — add these scripts:"
for cmd in test sample bootstrap update; do
  echo "     \"${COUNTRY_LC}:${ALIAS}:${cmd}\": \"tsx ${COUNTRY}/${VERTICAL}/src/cli.ts ${cmd}\","
done
echo
echo "2) scripts/cron.sh — add a case arm:"
echo "     ${COUNTRY_LC}-${ALIAS}) CMD=(pnpm ${COUNTRY_LC}:${ALIAS}:update --since \"\${SINCE}\") ;;"
echo
if ! grep -q "$COUNTRY/\*" "$REPO/pnpm-workspace.yaml"; then
  echo "3) pnpm-workspace.yaml — NEW country, add:"
  echo "     - \"${COUNTRY}/*\""
else
  echo "3) pnpm-workspace.yaml — existing country glob covers this vertical (no change)."
fi
echo
echo "4) Fill bespoke logic: copy the nearest existing ${TYPE} vertical's scraper.ts"
echo "   into src/scraper.ts (keep the exported names), then:"
echo "     pnpm install && pnpm --filter @clausis/${COUNTRY_LC}-${VERTICAL} exec tsc --noEmit"
