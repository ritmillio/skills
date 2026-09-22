#!/usr/bin/env python3
"""memory-hygiene audit — READ-ONLY report on a Claude Code auto-memory dir.

  audit.py [memory-dir] [--json]

memory-dir defaults to the dir for the current working directory:
~/.claude/projects/<cwd with / and . replaced by ->/memory
Load limits (what Claude Code reads of MEMORY.md at startup) default to 200 lines
and 25,000 characters; override with MEMORY_MAX_LINES / MEMORY_MAX_CHARS.
"""
import difflib, json, os, re, sys, time

MAX_LINES = int(os.environ.get("MEMORY_MAX_LINES", 200))
MAX_CHARS = int(os.environ.get("MEMORY_MAX_CHARS", 25000))
LONG = int(os.environ.get("MEMORY_LONG_LINE", 200))
FINISHED = re.compile(r"\b(DONE|MERGED|ENDED|SHIPPED|CLOSED|OBSOLETE|SUPERSEDED|contract-met)\b", re.I)
STILL_OPEN = re.compile(r"\b(LIVE|RUNNING|IN FLIGHT|BLOCKED)\b")
LINK = re.compile(r"\]\(([^)]+\.md)\)")
DATE = re.compile(r"[-_]?20\d\d-\d\d(-\d\d)?")


def default_dir():
    slug = re.sub(r"[/.]", "-", os.getcwd())
    return os.path.expanduser(f"~/.claude/projects/{slug}/memory")


def frontmatter(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end < 0:
        return None
    fm = {}
    for line in text[4:end].splitlines():
        m = re.match(r"^\s*([A-Za-z_]+):\s*(.*)$", line)
        if m and m.group(1) not in fm:
            fm[m.group(1)] = m.group(2).strip().strip('"')
    fm["_body"] = text[end + 4:]
    return fm


def audit(d):
    idx_path = os.path.join(d, "MEMORY.md")
    idx = open(idx_path).read() if os.path.exists(idx_path) else ""
    lines = idx.split("\n")
    loaded, n = 0, 0
    for i, line in enumerate(lines):
        n += len(line) + (1 if i else 0)
        if i >= MAX_LINES or n > MAX_CHARS:
            break
        loaded = i + 1
    r = {"dir": d, "index_lines": len(lines), "index_chars": len(idx),
         "index_bytes": len(idx.encode()), "loaded_lines": loaded,
         "cut_lines": max(0, len(lines) - loaded), "limit": [MAX_LINES, MAX_CHARS]}
    r["cut_from"] = lines[loaded][:120] if loaded < len(lines) else None
    r["long_lines"] = [(i + 1, len(l)) for i, l in enumerate(lines) if len(l) > LONG]

    linked = {}
    for i, l in enumerate(lines):
        for target in LINK.findall(l):
            linked.setdefault(target, []).append(i + 1)
    files = []
    for root, dirs, fs in os.walk(d):
        for f in fs:
            if f.endswith(".md") and f != "MEMORY.md":
                files.append(os.path.relpath(os.path.join(root, f), d))
    fileset = set(files)
    r["missing_targets"] = sorted((t, ls) for t, ls in linked.items() if t not in fileset)
    r["duplicate_links"] = sorted((t, ls) for t, ls in linked.items() if len(ls) > 1)
    r["orphans"] = sorted(f for f in files if f not in linked and not f.startswith("archive/"))

    bad_fm, types, finished, now = [], {}, [], time.time()
    for f in sorted(files):
        p = os.path.join(d, f)
        fm = frontmatter(open(p, errors="replace").read())
        if fm is None:
            bad_fm.append((f, "no frontmatter")); continue
        missing = [k for k in ("name", "description") if not fm.get(k)]
        if not fm.get("type"):
            missing.append("type")
        if missing:
            bad_fm.append((f, "missing " + ", ".join(missing)))
        t = fm.get("type", "?")
        types[t] = types.get(t, 0) + 1
        if f.startswith("archive/") or t in ("feedback", "user"):
            continue
        text = fm.get("description", "") + "\n" + fm["_body"][:3000]
        hit = FINISHED.search(text)
        if hit and not STILL_OPEN.search(fm.get("description", "")):
            age = int((now - os.path.getmtime(p)) / 86400)
            finished.append((f, hit.group(0), age, f in linked))
    r["frontmatter_errors"] = bad_fm
    r["types"] = types
    finished.sort(key=lambda x: -x[2])
    r["archive_candidates"] = finished

    stems = {}
    for f in files:
        s = DATE.sub("", os.path.basename(f)[:-3]).lower()
        stems.setdefault(s, []).append(f)
    dup = [v for v in stems.values() if len(v) > 1]
    keys = sorted(stems)
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            if abs(len(a) - len(b)) < 6 and difflib.SequenceMatcher(None, a, b).ratio() > 0.88:
                dup.append(stems[a] + stems[b])
    r["near_duplicates"] = dup

    # feedback/user memories should be indexed AND inside the loaded part
    must = []
    for f in files:
        fm = frontmatter(open(os.path.join(d, f), errors="replace").read()) or {}
        if fm.get("type") in ("feedback", "user"):
            ls = linked.get(f)
            if not ls:
                must.append((f, "not indexed"))
            elif min(ls) > loaded:
                must.append((f, f"indexed at line {min(ls)} — cut off"))
    r["rules_not_loaded"] = sorted(must)
    r["files"] = len(files)
    return r


def report(r):
    ok = r["cut_lines"] == 0
    print(f"memory-hygiene audit — {r['dir']}")
    print(f"  index: {r['index_lines']} lines, {r['index_chars']:,} chars ({r['index_bytes']:,} bytes); "
          f"limit {r['limit'][0]} lines / {r['limit'][1]:,} chars")
    if ok:
        print("  ✓ whole index loads at startup")
    else:
        print(f"  ✗ only {r['loaded_lines']} lines load — {r['cut_lines']} lines never reach the agent")
        print(f"    cut starts at: {r['cut_from']}")
    print(f"  files: {r['files']}  by type: " + ", ".join(f"{k} {v}" for k, v in sorted(r['types'].items())))

    def section(title, items, fmt, limit=15):
        print(f"\n{title}: {len(items)}")
        for it in items[:limit]:
            print("  " + fmt(it))
        if len(items) > limit:
            print(f"  … {len(items) - limit} more (--json for all)")

    section(f"index lines > {LONG} chars", r["long_lines"], lambda x: f"line {x[0]}: {x[1]} chars", 8)
    section("links to missing files", r["missing_targets"], lambda x: f"{x[0]} (line {x[1][0]})")
    section("files linked more than once", r["duplicate_links"], lambda x: f"{x[0]} (lines {x[1]})")
    section("orphans (file exists, not in index)", r["orphans"], lambda x: x)
    section("frontmatter errors", r["frontmatter_errors"], lambda x: f"{x[0]}: {x[1]}")
    section("feedback/user rules the agent never sees", r["rules_not_loaded"], lambda x: f"{x[0]}: {x[1]}")
    section("near-duplicate names", r["near_duplicates"], lambda x: " ≈ ".join(x), 10)
    section("archive candidates (finished project memories, oldest first)", r["archive_candidates"],
            lambda x: f"{x[0]}  [{x[1]}, {x[2]}d old{'' if x[3] else ', not indexed'}]", 20)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    d = os.path.expanduser(args[0]) if args else default_dir()
    if not os.path.isdir(d):
        sys.exit(f"no memory dir at {d}")
    res = audit(d)
    if "--json" in sys.argv:
        print(json.dumps(res, indent=2, ensure_ascii=False))
    else:
        report(res)
