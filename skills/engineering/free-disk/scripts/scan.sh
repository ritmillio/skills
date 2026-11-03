#!/usr/bin/env bash
# Read-only. What is eating the disk, split into regenerable and needs-a-decision.
# Usage: scan.sh [root ...]      (default: ~/Developer, ~/code, ~/src, ~/projects that exist)
set -uo pipefail
. "$(dirname "$0")/lib.sh"
roots=("$@"); [ ${#roots[@]} -eq 0 ] && for r in "$HOME/Developer" "$HOME/code" "$HOME/src" "$HOME/projects"; do [ -d "$r" ] && roots+=("$r"); done

echo "== Disk ($(data_volume)) =="
echo "  used $(used_gb)G, free $(free_gb)G"

echo; echo "== Live dev processes (clean.sh skips their trees) =="
live_cwds | sed 's/^/  /'

echo; echo "== Regenerable build output (top 30) =="
for r in "${roots[@]}"; do build_dirs "$r"; done | sort -u \
  | while IFS= read -r d; do du -sk "$d" 2>/dev/null; done | sort -rn | head -30 \
  | awk '{s=$1; $1=""; printf "  %6.1fG %s\n", s/1048576, $0}'

echo; echo "== Package-manager caches =="
cache_dirs | while IFS= read -r d; do echo "  $(size_of "$d")  $d"; done

echo; echo "== Needs a decision (never auto-deleted) =="
for d in "$HOME/.cache/huggingface" "$HOME/.ollama" "$HOME/Downloads" "$HOME/Movies" \
         "$HOME/Library/Containers/com.docker.docker" "$HOME/Library/Developer/Xcode/DerivedData" \
         "$HOME/Library/Developer/CoreSimulator"; do
  [ -d "$d" ] && echo "  $(size_of "$d")  $d"
done
for r in "${roots[@]}"; do
  n=$(find "$r" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  echo "  $n checkouts in $r (sibling worktrees: see the worktree-janitor skill)"
done
