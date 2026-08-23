#!/usr/bin/env bash
# morning-brief/brief.sh — READ-ONLY. Assemble the internal (git/PR/relay) and
# external (RSS/Atom news) sections of a morning brief. Fetches public feeds and
# reads local repos; changes nothing.
#
# Config dir: $MORNING_BRIEF_CONFIG, else ~/.config/morning-brief, else the
# shipped config/*.example.txt next to this script.
#
# Usage: brief.sh [--since 24h|48h|7d] [--internal] [--news]
set -uo pipefail

SINCE="24h"; DO_INT=1; DO_NEWS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:-24h}"; shift 2 ;;
    --internal) DO_NEWS=0; shift ;;
    --news) DO_INT=0; shift ;;
    *) shift ;;
  esac
done

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CFG="${MORNING_BRIEF_CONFIG:-$HOME/.config/morning-brief}"
REPOS_FILE="$CFG/repos.txt";     [ -f "$REPOS_FILE" ]   || REPOS_FILE="$SELF_DIR/../config/repos.example.txt"
SOURCES_FILE="$CFG/sources.txt"; [ -f "$SOURCES_FILE" ] || SOURCES_FILE="$SELF_DIR/../config/sources.example.txt"

hr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
sub() { printf '  \033[36m%s\033[0m\n' "$1"; }

# git's --since accepts "24 hours ago"; translate our shorthand.
case "$SINCE" in
  *h) GSINCE="${SINCE%h} hours ago" ;;
  *d) GSINCE="${SINCE%d} days ago" ;;
  *)  GSINCE="$SINCE" ;;
esac

DATE="$(date '+%Y-%m-%d %H:%M')"
printf '\033[1m☀️  Morning brief — %s, last %s\033[0m\n' "$DATE" "$SINCE"
printf '   config: %s\n' "$CFG"
[ -f "$CFG/repos.txt" ] || printf '   \033[33m(using shipped example config — copy it to %s and edit)\033[0m\n' "$CFG"

# ---------------------------------------------------------------- INTERNAL
if [ "$DO_INT" -eq 1 ]; then
  hr "INTERNAL"
  HAVE_GH=0; command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && HAVE_GH=1
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs)"; [ -n "$line" ] || continue
    repo="$line"
    [ -d "$repo/.git" ] || { sub "$repo — not a git repo, skipping"; continue; }
    name="$(basename "$repo")"
    branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
    ncommits="$(git -C "$repo" log --since="$GSINCE" --oneline 2>/dev/null | wc -l | tr -d ' ')"
    ndirty="$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    sub "$name  —  $ncommits commit(s), branch '$branch', $ndirty uncommitted"
    git -C "$repo" log --since="$GSINCE" --pretty='      %h %an: %s' 2>/dev/null | head -12
    # Open PRs authored by the current user.
    if [ "$HAVE_GH" -eq 1 ]; then
      prs="$(cd "$repo" && gh pr list --state open --limit 10 --json number,title,isDraft,headRefName \
              -q '.[] | "      #\(.number) \(if .isDraft then "[draft] " else "" end)\(.title)  («\(.headRefName)»)"' 2>/dev/null)"
      [ -n "$prs" ] && { printf '    open PRs:\n'; echo "$prs"; }
    fi
    # Running relay? (relay skill writes .loop/live.log while active.)
    if [ -f "$repo/.loop/live.log" ] || ls "$repo"/../*/.loop/live.log >/dev/null 2>&1; then
      printf '    \033[33m⚠ relay artifacts present (.loop) — check if a run is live\033[0m\n'
    fi
  done < "$REPOS_FILE"
  [ "$HAVE_GH" -eq 1 ] || sub "(gh not authed — PR list skipped; run: gh auth login)"
fi

# ---------------------------------------------------------------- EXTERNAL
if [ "$DO_NEWS" -eq 1 ]; then
  hr "EXTERNAL  (your sources)"
  # Hours for the window filter.
  case "$SINCE" in *h) HOURS="${SINCE%h}";; *d) HOURS=$(( ${SINCE%d} * 24 ));; *) HOURS=24;; esac
  python3 - "$SOURCES_FILE" "$HOURS" <<'PY'
import sys, urllib.request, xml.etree.ElementTree as ET
from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime

sources_file, hours = sys.argv[1], int(sys.argv[2])
cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "morning-brief/1.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.read()

def parse_date(s):
    if not s: return None
    for fn in (parsedate_to_datetime,):
        try:
            d = fn(s)
            return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
        except Exception: pass
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d"):
        try:
            d = datetime.strptime(s, fmt)
            return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
        except Exception: pass
    return None

any_source = False
for raw in open(sources_file, encoding="utf-8"):
    raw = raw.split("#", 1)[0].strip()
    if not raw: continue
    if "|" in raw:
        label, url = [x.strip() for x in raw.split("|", 1)]
    else:
        label, url = raw, raw
    any_source = True
    # Non-feed page: let the agent handle it via WebFetch.
    ul = url.lower()
    if not (url.endswith((".xml", ".rss", ".atom")) or "rss" in ul or "feed" in ul or "atom" in ul):
        print(f"  \033[1m{label}\033[0m")
        print(f"      NEEDS-WEBFETCH: {url}")
        continue
    try:
        data = get(url)
        root = ET.fromstring(data)
    except Exception as e:
        print(f"  \033[1m{label}\033[0m")
        print(f"      (could not fetch/parse: {str(e)[:60]})")
        continue
    items = []
    # RSS
    for it in root.iter("item"):
        t = (it.findtext("title") or "").strip()
        link = (it.findtext("link") or "").strip()
        d = parse_date(it.findtext("pubDate"))
        items.append((d, t, link))
    # Atom
    ns = "{http://www.w3.org/2005/Atom}"
    for it in root.iter(f"{ns}entry"):
        t = (it.findtext(f"{ns}title") or "").strip()
        le = it.find(f"{ns}link")
        link = le.get("href") if le is not None else ""
        d = parse_date(it.findtext(f"{ns}updated") or it.findtext(f"{ns}published"))
        items.append((d, t, link))
    recent = [x for x in items if x[0] is None or x[0] >= cutoff]
    recent.sort(key=lambda x: (x[0] or cutoff), reverse=True)
    print(f"  \033[1m{label}\033[0m  ({len(recent)} in window)")
    if not recent:
        print("      (nothing new in the window)")
    for d, t, link in recent[:6]:
        stamp = d.strftime("%m-%d %H:%M") if d else "     ?"
        print(f"      • {t[:90]}  [{stamp}]")
        if link: print(f"        {link}")

if not any_source:
    print("  (no sources configured — edit sources.txt)")
PY
fi

printf '\n\033[2m— assembled read-only; personalise config at %s —\033[0m\n' "$CFG"
