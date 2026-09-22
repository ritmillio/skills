#!/usr/bin/env python3
"""worktree-janitor: census (read-only) and prune (dry run unless --apply) for
every git worktree of one repository.

  janitor.py census [repo] [--json] [--only SAFE|KEEP|ASK]
  janitor.py prune  [repo] [--apply] [--force] [--delete-branch] PATH...

Only python3 stdlib, git, lsof and (optionally) an authed `gh` are used.
"""
import json, os, signal, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor


def sh(args, cwd=None, check=False):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}: {p.stderr.strip()}")
    return p.returncode, p.stdout.strip()


def git(wt, *args):
    return sh(["git", "-C", wt, *args])


def main_worktree(repo):
    rc, common = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if rc != 0:
        sys.exit(f"not a git repo: {repo}")
    return os.path.dirname(common) if common.endswith("/.git") else common


def list_worktrees(main):
    _, out = git(main, "worktree", "list", "--porcelain")
    wts, cur = [], {}
    for line in out.splitlines() + [""]:
        if not line:
            if cur:
                wts.append(cur)
            cur = {}
            continue
        key, _, val = line.partition(" ")
        if key == "worktree":
            cur["path"] = val
        elif key == "branch":
            cur["branch"] = val.replace("refs/heads/", "", 1)
        elif key == "HEAD":
            cur["head"] = val
        elif key in ("detached", "prunable", "locked", "bare"):
            cur[key] = val or True
    return wts


def default_branch(main):
    rc, ref = git(main, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    return ref.split("/", 1)[1] if rc == 0 and "/" in ref else "main"


def pr_index(main):
    """headRefName -> the most relevant PR (an open one wins, else the newest)."""
    rc, _ = sh(["gh", "auth", "status"])
    if rc != 0:
        return None
    rc, out = sh(["gh", "pr", "list", "--state", "all", "--limit", "1000", "--json",
                  "number,state,isDraft,headRefName,headRefOid,updatedAt"], cwd=main)
    if rc != 0:
        return None
    idx = {}
    for pr in json.loads(out or "[]"):
        old = idx.get(pr["headRefName"])
        rank = (pr["state"] == "OPEN", pr["updatedAt"])
        if old is None or rank > (old["state"] == "OPEN", old["updatedAt"]):
            idx[pr["headRefName"]] = pr
    return idx


def listening_servers():
    """[(pid, port, cwd)] for every TCP listener owned by this user."""
    rc, out = sh(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-u", str(os.getuid()), "-Fpn"])
    ports, pid = {}, None
    for line in out.splitlines():
        if line.startswith("p"):
            pid = int(line[1:])
        elif line.startswith("n") and pid:
            port = line.rsplit(":", 1)[-1]
            if port.isdigit():
                ports.setdefault(pid, set()).add(int(port))
    res = []
    for pid, ps in ports.items():
        _, c = sh(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"])
        cwd = next((l[1:] for l in c.splitlines() if l.startswith("n")), "")
        res.append((pid, sorted(ps), os.path.realpath(cwd) if cwd else ""))
    return res


def relay_live(path):
    for name in ("relay.pid", "watchdog.pid"):
        f = os.path.join(path, ".loop", name)
        try:
            pid = int(open(f).read().split()[0])
            os.kill(pid, 0)
            return pid
        except Exception:
            pass
    return None


def inspect(wt, main, prs, servers, base):
    path = wt["path"]
    r = {"path": path, "branch": wt.get("branch") or "(detached)", "main": path == main,
         "notes": []}
    if wt.get("prunable") or not os.path.isdir(path):
        r.update(verdict="SAFE", dirty=0, unpushed=0, age="-", pr="-", server="-")
        r["notes"].append("directory gone (prunable)")
        return r
    _, st = git(path, "status", "--porcelain")
    r["dirty"] = len(st.splitlines()) if st else 0
    _, n = git(path, "rev-list", "--count", "HEAD", "--not", "--remotes")
    r["unpushed"] = int(n or 0)
    _, r["age"] = git(path, "log", "-1", "--format=%cr")
    r["age"] = r["age"].replace(" ago", "")
    real = os.path.realpath(path)
    mine = [(pid, ports) for pid, ports, cwd in servers
            if cwd and (cwd == real or cwd.startswith(real + os.sep))]
    r["server"] = ",".join(f"{p[0]}:{'/'.join(map(str, p[1]))}" for p in mine) or "-"
    r["server_pids"] = [p[0] for p in mine]
    rl = relay_live(path)
    if rl:
        r["notes"].append(f"relay live pid {rl}")
    pr = prs.get(r["branch"]) if prs is not None else None
    if prs is None:
        r["pr"] = "?"
    elif pr is None:
        r["pr"] = "none"
    else:
        state = "DRAFT" if pr["state"] == "OPEN" and pr["isDraft"] else pr["state"]
        r["pr"] = f"#{pr['number']} {state.lower()}"
        r["pr_state"], r["pr_head"] = state, pr["headRefOid"]
    # commits beyond the PR head after it merged/closed = work the PR never saw
    if pr and pr["state"] in ("MERGED", "CLOSED"):
        _, headsha = git(path, "rev-parse", "HEAD")
        if headsha != pr["headRefOid"]:
            rc, _ = git(path, "merge-base", "--is-ancestor", "HEAD", pr["headRefOid"])
            if rc != 0:
                r["notes"].append("commits after the PR closed")
    # verdict
    keep = []
    if r["main"]: keep.append("main checkout")
    if wt.get("locked"): keep.append("locked")
    if r["dirty"]: keep.append(f"{r['dirty']} uncommitted")
    if r["unpushed"]: keep.append(f"{r['unpushed']} unpushed")
    if rl: keep.append("relay running")
    if pr and pr["state"] == "OPEN": keep.append("PR open")
    if keep:
        r["verdict"] = "KEEP"
        r["notes"] = keep + [n for n in r["notes"] if not n.startswith("relay")]
    elif pr and pr["state"] in ("MERGED", "CLOSED") and not mine \
            and "commits after the PR closed" not in r["notes"]:
        r["verdict"] = "SAFE"
    else:
        r["verdict"] = "ASK"
        if mine: r["notes"].append("dev server running")
        if prs is not None and pr is None: r["notes"].append("no PR for this branch")
        if prs is None: r["notes"].append("gh not authed: PR state unknown")
    return r


def census(repo):
    main = main_worktree(repo)
    base = default_branch(main)
    with ThreadPoolExecutor(3) as ex:
        f_prs = ex.submit(pr_index, main)
        f_srv = ex.submit(listening_servers)
        wts = list_worktrees(main)
        prs, servers = f_prs.result(), f_srv.result()
    with ThreadPoolExecutor(8) as ex:
        rows = list(ex.map(lambda w: inspect(w, main, prs, servers, base), wts))
    order = {"SAFE": 0, "ASK": 1, "KEEP": 2}
    rows.sort(key=lambda r: (order[r["verdict"]], r["path"]))
    return main, rows


def short(path, main):
    parent = os.path.dirname(main)
    return os.path.relpath(path, parent) if path.startswith(parent) else path


def print_table(main, rows):
    cols = [("VERDICT", 7), ("WORKTREE", 34), ("BRANCH", 34), ("DIRTY", 5), ("UNPUSH", 6),
            ("AGE", 12), ("PR", 12), ("SERVER pid:port", 16)]
    print("  ".join(n.ljust(w) for n, w in cols) + "  NOTES")
    for r in rows:
        vals = [r["verdict"], short(r["path"], main), r["branch"], str(r["dirty"]),
                str(r["unpushed"]), r["age"], r["pr"], r["server"]]
        print("  ".join((v if len(v) <= w else v[: w - 1] + "…").ljust(w)
                        for v, (_, w) in zip(vals, cols)) + "  " + "; ".join(r["notes"]))
    c = {k: sum(1 for r in rows if r["verdict"] == k) for k in ("SAFE", "ASK", "KEEP")}
    print(f"\n{len(rows)} worktrees — SAFE {c['SAFE']} · ASK {c['ASK']} · KEEP {c['KEEP']}"
          f"   (repo {main})")


def prune(repo, paths, apply, force, delete_branch):
    main, rows = census(repo)
    by = {os.path.realpath(r["path"]): r for r in rows}
    mode = "APPLY" if apply else "DRY RUN"
    print(f"worktree-janitor prune — {mode}")
    removed = 0
    for p in paths:
        r = by.get(os.path.realpath(os.path.expanduser(p)))
        if r is None:
            print(f"  skip {p}: not a worktree of {main}"); continue
        if r["main"]:
            print(f"  skip {p}: main checkout"); continue
        blockers = [n for n in r["notes"] if n.endswith("uncommitted") or n.endswith("unpushed")
                    or n in ("relay running", "locked", "PR open")]
        if blockers and not force:
            print(f"  skip {p}: {', '.join(blockers)}"); continue
        steps = []
        if r.get("server_pids"):
            steps.append(f"stop dev server pid {','.join(map(str, r['server_pids']))}")
        steps.append("git worktree remove" + (" --force" if force else ""))
        merged = r.get("pr_state") == "MERGED" and "commits after the PR closed" not in r["notes"]
        if delete_branch and r["branch"] != "(detached)":
            steps.append(f"git branch -d {r['branch']}" if merged
                         else f"keep branch {r['branch']} (PR not merged)")
        print(f"  {short(r['path'], main)}: " + " → ".join(steps))
        if not apply:
            continue
        for pid in r.get("server_pids", []):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if r.get("server_pids"):
            time.sleep(2)
        args = ["git", "-C", main, "worktree", "remove"] + (["--force"] if force else []) + [r["path"]]
        rc, out = sh(args)
        if rc != 0:
            print(f"    FAILED: {out or 'see git output'}"); continue
        removed += 1
        if delete_branch and merged and r["branch"] != "(detached)":
            sh(["git", "-C", main, "branch", "-d", r["branch"]])
    if apply:
        sh(["git", "-C", main, "worktree", "prune"])
        print(f"removed {removed}; ran git worktree prune")
    else:
        print("dry run — nothing changed. Re-run with --apply to do it.")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] not in ("census", "prune"):
        sys.exit(__doc__)
    cmd, a = a[0], a[1:]
    flags = {x for x in a if x.startswith("--")}
    only = None
    if "--only" in a:
        i = a.index("--only"); only = a[i + 1].upper(); a = a[:i] + a[i + 2:]
    pos = [x for x in a if not x.startswith("--")]
    if cmd == "census":
        repo = os.path.expanduser(pos[0]) if pos else os.getcwd()
        main, rows = census(repo)
        if only:
            rows = [r for r in rows if r["verdict"] == only]
        if "--json" in flags:
            print(json.dumps(rows, indent=2))
        else:
            print_table(main, rows)
    else:
        repo = os.getcwd()
        if pos and os.path.isdir(os.path.join(os.path.expanduser(pos[0]), ".git")) and len(pos) > 1:
            repo, pos = os.path.expanduser(pos[0]), pos[1:]
        if not pos:
            sys.exit("prune: name at least one worktree path")
        prune(repo, pos, "--apply" in flags, "--force" in flags, "--delete-branch" in flags)
