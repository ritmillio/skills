#!/usr/bin/env bash
#
# install.sh - install these skills into any agent that reads the SKILL.md
# open standard.
#
# The skills themselves are tool-agnostic: one SKILL.md per skill, no
# conversion step. All this script does is put them where each agent looks.
#
#   ./scripts/install.sh                      every detected tool, every skill
#   ./scripts/install.sh --tool codex         one tool
#   ./scripts/install.sh --scope project      into ./.<tool>/skills of this repo
#   ./scripts/install.sh --copy relay         copy instead of symlink
#   ./scripts/install.sh --uninstall          remove what we installed
#   ./scripts/install.sh --list               show tools and what is installed

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/skills"

TOOLS_ALL=(claude codex gemini cursor)
tool_home() {            # where the agent keeps user-level config
  case "$1" in
    claude) printf '%s\n' "$HOME/.claude" ;;
    codex)  printf '%s\n' "$HOME/.codex"  ;;
    gemini) printf '%s\n' "$HOME/.gemini" ;;
    cursor) printf '%s\n' "$HOME/.cursor" ;;
  esac
}

TOOL="auto"; SCOPE="user"; MODE="link"; ACTION="install"; SKILLS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)      TOOL="$2"; shift 2 ;;
    --scope)     SCOPE="$2"; shift 2 ;;
    --copy)      MODE="copy"; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --list)      ACTION="list"; shift ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    -*)          echo "unknown flag: $1" >&2; exit 2 ;;
    *)           SKILLS+=("$1"); shift ;;
  esac
done

# No skills named means all of them.
if [[ ${#SKILLS[@]} -eq 0 ]]; then
  while IFS= read -r d; do SKILLS+=("$(basename "$d")"); done \
    < <(find "$SRC" -mindepth 1 -maxdepth 1 -type d | sort)
fi

targets=()
if [[ "$TOOL" == "auto" || "$TOOL" == "all" ]]; then
  for t in "${TOOLS_ALL[@]}"; do
    # "auto" installs only where the agent already lives; "all" forces every one
    if [[ "$TOOL" == "all" || -d "$(tool_home "$t")" || "$SCOPE" == "project" ]]; then
      targets+=("$t")
    fi
  done
else
  targets=("$TOOL")
fi

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No supported agent found in \$HOME. Pass --tool <name> to force one."
  echo "Supported: ${TOOLS_ALL[*]}"
  exit 1
fi

dest_dir() {
  local t="$1"
  if [[ "$SCOPE" == "project" ]]; then printf '%s\n' "$PWD/.$t/skills"
  else printf '%s\n' "$(tool_home "$t")/skills"; fi
}

if [[ "$ACTION" == "list" ]]; then
  printf '%-10s %-8s %s\n' TOOL PRESENT "SKILLS DIR"
  for t in "${TOOLS_ALL[@]}"; do
    d="$(dest_dir "$t")"
    printf '%-10s %-8s %s\n' "$t" "$([[ -d "$(tool_home "$t")" ]] && echo yes || echo no)" "$d"
    for s in "${SKILLS[@]}"; do
      [[ -e "$d/$s" ]] && printf '           installed: %s%s\n' "$s" "$([[ -L "$d/$s" ]] && echo ' (link)')"
    done
  done
  exit 0
fi

for t in "${targets[@]}"; do
  d="$(dest_dir "$t")"
  mkdir -p "$d" || { echo "cannot create $d" >&2; continue; }
  for s in "${SKILLS[@]}"; do
    [[ -d "$SRC/$s" ]] || { echo "no such skill: $s" >&2; continue; }
    if [[ "$ACTION" == "uninstall" ]]; then
      if [[ -e "$d/$s" || -L "$d/$s" ]]; then rm -rf "$d/$s"; echo "removed  $t  $s"; fi
      continue
    fi
    # Refuse to clobber a real directory the user may have written themselves.
    if [[ -d "$d/$s" && ! -L "$d/$s" ]]; then
      echo "skipped  $t  $s  (a real directory is already there)"; continue
    fi
    rm -f "$d/$s"
    if [[ "$MODE" == "copy" ]]; then cp -R "$SRC/$s" "$d/$s"; else ln -s "$SRC/$s" "$d/$s"; fi
    echo "installed $t  $s  ->  $d/$s"
  done
done

if [[ "$ACTION" == "install" && "$MODE" == "link" ]]; then
  echo
  echo "Symlinked, so a git pull updates every tool at once. Use --copy for standalone copies."
fi
