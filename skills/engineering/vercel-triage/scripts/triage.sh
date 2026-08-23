#!/usr/bin/env bash
# vercel-triage/triage.sh — READ-ONLY. Pull production runtime logs for the
# linked Vercel project, dedupe the CLI's repeated events, and group what's left
# by status + path with counts. Changes nothing on Vercel.
#
# Must be run from a `vercel link`-ed project root. Saves the raw pull to a temp
# file (path printed) so you can grep deeper without re-pulling.
#
# Usage:
#   triage.sh                 # all statuses, default window
#   triage.sh --status 500    # only 5xx (or a specific code / prefix like 50)
#   triage.sh --raw           # also echo the deduped raw lines
set -uo pipefail

STATUS=""; SHOW_RAW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --status) STATUS="${2:-}"; shift 2 ;;
    --raw) SHOW_RAW=1; shift ;;
    *) shift ;;
  esac
done

hr() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
die() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

command -v vercel >/dev/null 2>&1 || die "vercel CLI not found — npm i -g vercel"
vercel whoami >/dev/null 2>&1 || die "not logged in — run: vercel login"
[ -f .vercel/project.json ] || die "not a linked project — run: vercel link"

RAW="$(mktemp -t vercel-triage.XXXXXX)"
printf 'vercel-triage — pulling production runtime logs (read-only)\n'
printf 'raw saved to: %s\n' "$RAW"

# Resolve the current production deployment URL. `vercel ls --prod` output shape
# varies by CLI version, so grab the first vercel.app URL it prints.
PROD_URL="$(vercel ls --prod 2>/dev/null | grep -oE 'https://[a-z0-9.-]+\.vercel\.app' | head -1)"
[ -n "$PROD_URL" ] || PROD_URL="$(vercel inspect --prod 2>/dev/null | grep -oE 'https://[a-z0-9.-]+\.vercel\.app' | head -1)"
[ -n "$PROD_URL" ] || die "couldn't resolve a production deployment URL from 'vercel ls --prod'"
printf 'production: %s\n' "$PROD_URL"

# Pull logs. `vercel logs` streams; cap it with a timeout so it returns. Try JSON
# first (newer CLI), fall back to text.
hr "PULLING (bounded window)"
timeout 45 vercel logs "$PROD_URL" --json > "$RAW" 2>/dev/null || \
timeout 45 vercel logs "$PROD_URL"        > "$RAW" 2>/dev/null || true
LINES=$(wc -l < "$RAW" | tr -d ' ')
printf 'pulled %s raw lines (before dedupe — the CLI repeats events)\n' "$LINES"
[ "$LINES" -gt 0 ] || { printf '\nNo log lines returned. Either the window is quiet, or retention (~24h) has aged them out.\n'; exit 0; }

# Dedupe + group. Handles both JSON and plain-text lines: extract a
# (status, method, path) signature where present; fall back to the whole line.
hr "TOP EVENTS (deduped, count-ranked, 5xx first)"
python3 - "$RAW" "$STATUS" <<'PY'
import json, re, sys
from collections import Counter, defaultdict

raw, want = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
seen = set()
counts = Counter()
last = {}
meta = {}

def sig(status, method, path):
    return f"{status}\t{method}\t{path}"

for line in open(raw, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if not line.strip():
        continue
    status = method = path = ts = ""
    # JSON line?
    try:
        j = json.loads(line)
        status = str(j.get("statusCode") or j.get("status") or j.get("proxy", {}).get("statusCode") or "")
        method = str(j.get("method") or j.get("proxy", {}).get("method") or "")
        path   = str(j.get("path") or j.get("requestPath") or j.get("proxy", {}).get("path") or "")
        ts     = str(j.get("timestamp") or j.get("time") or "")
        # dedupe on request id if present, else on full payload
        dedupe_key = str(j.get("requestId") or j.get("id") or line)
    except Exception:
        m = re.search(r'\b(\d{3})\b', line)
        status = m.group(1) if m else ""
        mm = re.search(r'\b(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b', line)
        method = mm.group(1) if mm else ""
        pm = re.search(r'(/[^\s"?]*)', line)
        path = pm.group(1) if pm else ""
        dedupe_key = line

    if dedupe_key in seen:
        continue
    seen.add(dedupe_key)

    if want:
        if not status.startswith(want):
            continue
    s = sig(status or "?", method or "?", path or "?")
    counts[s] += 1
    last[s] = ts

def rank(item):
    (s, _c) = item
    status = s.split("\t", 1)[0]
    is5xx = status.startswith("5")
    return (0 if is5xx else 1, -_c)

rows = sorted(counts.items(), key=rank)
if not rows:
    print("  no matching events after dedupe" + (f" (filter: status ~ {want})" if want else ""))
else:
    print(f"  {'count':>6}  {'status':<6} {'method':<7} path    (last-seen)")
    for s, c in rows[:40]:
        status, method, path = (s.split("\t") + ["", "", ""])[:3]
        mark = "\033[31m" if status.startswith("5") else ("\033[33m" if status.startswith("4") else "")
        reset = "\033[0m" if mark else ""
        print(f"  {c:>6}  {mark}{status:<6}{reset} {method:<7} {path[:60]}  ({last.get(s,'')[:19]})")

fivexx = sum(c for s, c in counts.items() if s.split('\t',1)[0].startswith('5'))
print()
if fivexx == 0:
    print("  \033[32mVERDICT: no 5xx in this window — prod clean.\033[0m")
else:
    distinct = sum(1 for s in counts if s.split('\t',1)[0].startswith('5'))
    print(f"  \033[31mVERDICT: {fivexx} 5xx event(s) across {distinct} distinct route(s) — investigate the top rows.\033[0m")
PY

if [ "$SHOW_RAW" -eq 1 ]; then hr "RAW (deduped by request id where present)"; sort -u "$RAW" | head -60; fi
printf '\nGrep deeper without re-pulling:  grep <path> %s\n' "$RAW"
printf 'Note: Vercel runtime logs retain ~24h. For older, use a log drain / observability provider.\n'
