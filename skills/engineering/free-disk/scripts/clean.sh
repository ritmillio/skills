#!/usr/bin/env bash
# Delete ONLY regenerable files: framework build caches (.next, .turbo, ...), Rust
# target dirs, package-manager caches. Never source, git state, node_modules or models.
# Any tree that contains (or sits inside) a live dev process's cwd is skipped.
# Usage: clean.sh [--apply] [root ...]     (dry run without --apply)
set -uo pipefail
. "$(dirname "$0")/lib.sh"
APPLY=0; [ "${1:-}" = "--apply" ] && { APPLY=1; shift; }
roots=("$@"); [ ${#roots[@]} -eq 0 ] && for r in "$HOME/Developer" "$HOME/code" "$HOME/src" "$HOME/projects"; do [ -d "$r" ] && roots+=("$r"); done
LIVE="$(live_cwds)"
BEFORE=$(free_gb)
RUST_BUSY=0; { pgrep -x cargo || pgrep -x rustc; } >/dev/null 2>&1 && RUST_BUSY=1

# Top-level checkout under a root that holds this path (live servers usually run from a subdir).
checkout_of() { local p="$1" r; for r in "${roots[@]}"; do case "$p" in "$r"/*)
  local rest="${p#"$r"/}"; echo "$r/${rest%%/*}"; return; esac; done; dirname "$p"; }

is_live() { local proj; proj="$(checkout_of "$1")"
  while IFS= read -r c; do [ -n "$c" ] || continue
    case "$c/" in "$proj"/*) return 0;; esac
    case "$proj/" in "$c"/*) return 0;; esac
  done <<<"$LIVE"; return 1; }

echo "== Build output =="
for r in "${roots[@]}"; do build_dirs "$r"; done | sort -u | while IFS= read -r d; do
  if is_live "$d"; then echo "  skip (dev process running in $(checkout_of "$d")) $d"; continue; fi
  if [ "$(basename "$d")" = target ] || [ "$d" = "${CARGO_TARGET_DIR:-}" ]; then
    [ $RUST_BUSY = 1 ] && { echo "  skip (cargo/rustc running) $d"; continue; }
  fi
  if [ $APPLY = 1 ]; then rm -rf "$d" && echo "  deleted $d"
  else echo "  would delete $(size_of "$d")  $d"; fi
done

echo "== Package caches =="
if [ $APPLY = 1 ]; then
  command -v brew >/dev/null && brew cleanup -s --prune=all >/dev/null 2>&1 && echo "  brew cleanup"
  command -v npm  >/dev/null && npm cache clean --force >/dev/null 2>&1 && echo "  npm cache clean"
  command -v pnpm >/dev/null && pnpm store prune >/dev/null 2>&1 && echo "  pnpm store prune"
  command -v yarn >/dev/null && yarn cache clean >/dev/null 2>&1 && echo "  yarn cache clean"
  command -v uv   >/dev/null && uv cache prune >/dev/null 2>&1 && echo "  uv cache prune"
  for d in "$HOME/Library/Caches/pip" "$HOME/.cache/pip" "$HOME/Library/Caches/node-gyp" "$HOME/.cache/node-gyp"; do
    [ -d "$d" ] && rm -rf "$d" && echo "  removed $d"
  done
else
  echo "  would run: brew cleanup, npm cache clean, pnpm store prune, yarn cache clean, uv cache prune; remove pip + node-gyp caches"
fi

if [ $APPLY = 1 ]; then echo "free: ${BEFORE}G -> $(free_gb)G"
else echo "(dry run; free now ${BEFORE}G; re-run with --apply)"; fi
