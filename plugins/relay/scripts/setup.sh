#!/usr/bin/env bash
#
# setup.sh - prepare an isolated worktree for a relay run.
#
# Does only the mechanical parts: fresh worktree, branch off origin, env files,
# and the .loop state directory. The mission, ledger and briefs are written by
# the interactive session, because they need judgement.
#
# Usage: setup.sh --branch feat/<slug> [--base main] [--root <dir>] [--name <dir-name>]
#
# Defaults put the worktree beside the repo: <repo-parent>/<repo>-<slug>.

set -euo pipefail

BRANCH=""; BASE="main"; ROOT=""; NAME=""; INSTALL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --base)   BASE="$2";   shift 2 ;;
    --root)   ROOT="$2";   shift 2 ;;
    --name)   NAME="$2";   shift 2 ;;
    --install) INSTALL="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$BRANCH" ]] || { echo "setup.sh: --branch is required" >&2; exit 2; }
case "$BRANCH" in
  main|master|staging|development) echo "setup.sh: refusing protected branch" >&2; exit 2 ;;
esac
REPO="$(git rev-parse --show-toplevel)"
# Worktree lands beside the repo unless told otherwise, so it inherits whatever
# the user already decided about where their code lives.
[[ -n "$ROOT" ]] || ROOT="$(dirname "$REPO")"
[[ -n "$NAME" ]] || NAME="$(basename "$REPO")-$(basename "$BRANCH")"
WT="$ROOT/$NAME"
[[ -e "$WT" ]] && { echo "setup.sh: $WT already exists; pick another --name" >&2; exit 2; }

echo "==> fetching origin"
git -C "$REPO" fetch origin "$BASE" --quiet

echo "==> creating worktree $WT on $BRANCH from origin/$BASE"
git -C "$REPO" worktree add -b "$BRANCH" "$WT" "origin/$BASE"
BASE_SHA="$(git -C "$WT" rev-parse --short HEAD)"

# A fresh worktree has no env files, and every gate that reads config then
# fails for the wrong reason. Copy them across, never symlink.
echo "==> copying env files"
copied=0
while IFS= read -r -d '' f; do
  rel="${f#"$REPO"/}"
  mkdir -p "$WT/$(dirname "$rel")"
  cp "$f" "$WT/$rel" && copied=$((copied+1))
done < <(find "$REPO" -maxdepth 3 -name ".env*" -not -path "*/node_modules/*" -type f -print0)
echo "    $copied env file(s)"

# Guessing the package manager beats hardcoding one: a published skill lands in
# repos that use none of them.
if [[ -z "$INSTALL" ]]; then
  if   [[ -f "$WT/pnpm-lock.yaml"    ]]; then INSTALL="pnpm install"
  elif [[ -f "$WT/yarn.lock"         ]]; then INSTALL="yarn install"
  elif [[ -f "$WT/bun.lockb"         ]]; then INSTALL="bun install"
  elif [[ -f "$WT/package-lock.json" ]]; then INSTALL="npm install"
  elif [[ -f "$WT/package.json"      ]]; then INSTALL="npm install"
  elif [[ -f "$WT/poetry.lock"       ]]; then INSTALL="poetry install"
  elif [[ -f "$WT/uv.lock"           ]]; then INSTALL="uv sync"
  elif [[ -f "$WT/Cargo.toml"        ]]; then INSTALL="cargo fetch"
  elif [[ -f "$WT/go.mod"            ]]; then INSTALL="go mod download"
  fi
fi
if [[ -n "$INSTALL" && "$INSTALL" != "none" ]]; then
  echo "==> installing dependencies ($INSTALL)"
  ( cd "$WT" && $INSTALL ) || echo "    install failed; the first iteration will have to fix this"
else
  echo "==> no dependency install (pass --install '<cmd>' to force one)"
fi

echo "==> preparing .loop state directory"
mkdir -p "$WT/.loop/iter"
# Local-only exclude: the loop's machine state must never reach a commit.
grep -qxF '.loop/' "$WT/.git/info/exclude" 2>/dev/null \
  || echo '.loop/' >> "$(git -C "$WT" rev-parse --git-path info/exclude)"

cat <<INFO

worktree : $WT
branch   : $BRANCH
base     : origin/$BASE @ $BASE_SHA
state    : $WT/.loop

Next: write $WT/.loop/brief.md, $WT/.loop/compaction-brief.md and the ledger,
then launch with scripts/launch.sh.
INFO
