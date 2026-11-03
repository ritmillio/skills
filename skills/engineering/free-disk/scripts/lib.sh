#!/usr/bin/env bash
# Shared helpers. Sourced, not run.

# Volume that holds user data: the APFS Data volume on macOS, / elsewhere.
data_volume() { if [ -d /System/Volumes/Data ]; then echo /System/Volumes/Data; else echo /; fi; }
free_gb() { df -Pk "$(data_volume)" | awk 'NR==2{printf "%d", $4/1048576}'; }
used_gb() { df -Pk "$(data_volume)" | awk 'NR==2{printf "%d", $3/1048576}'; }

# Working directories of running dev processes (node, next, vite, turbo, cargo, rustc, tauri).
live_cwds() {
  command -v lsof >/dev/null || return 0
  for p in $(pgrep -f 'node|next|vite|turbo|cargo|rustc|tauri' 2>/dev/null); do
    lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
  done | sort -u
}

size_of() { du -sk "$1" 2>/dev/null | awk '{printf "%6.1fG", $1/1048576}'; }

# Regenerable build-output directories under a root, one per line. Never descends
# into node_modules or .git. Rust "target" counts only next to a Cargo.toml.
build_dirs() {
  local root="$1"
  find "$root" -maxdepth "${FREE_DISK_DEPTH:-6}" \
    \( -name node_modules -o -name .git \) -prune -o \
    -type d \( -name .next -o -name .turbo -o -name .nuxt -o -name .svelte-kit -o -name .parcel-cache \) -print -prune 2>/dev/null
  find "$root" -maxdepth "${FREE_DISK_DEPTH:-6}" \
    \( -name node_modules -o -name .git \) -prune -o \
    -type d -name target -print -prune 2>/dev/null \
    | while IFS= read -r t; do [ -f "$(dirname "$t")/Cargo.toml" ] && echo "$t"; done
  # Extra shared dirs the user listed (e.g. a common CARGO_TARGET_DIR), one glob per line.
  local cfg="${FREE_DISK_CONFIG:-$HOME/.config/free-disk/extra-dirs}"
  [ -n "${CARGO_TARGET_DIR:-}" ] && [ -d "$CARGO_TARGET_DIR" ] && echo "$CARGO_TARGET_DIR"
  [ -f "$cfg" ] && while IFS= read -r g; do
    case "$g" in ''|\#*) continue;; esac
    for x in $(eval echo "$g"); do [ -d "$x" ] && echo "$x"; done
  done < "$cfg"
}

# Package-manager caches that re-download on demand.
cache_dirs() {
  for d in "$HOME/Library/Caches/Homebrew" "$HOME/.cache/Homebrew" "$HOME/.npm" \
           "$HOME/Library/pnpm" "$HOME/.local/share/pnpm" "$HOME/Library/Caches/pip" \
           "$HOME/.cache/pip" "$HOME/Library/Caches/node-gyp" "$HOME/.cache/node-gyp" \
           "$HOME/.cache/uv" "$HOME/Library/Caches/Yarn" "$HOME/.cache/yarn"; do
    [ -d "$d" ] && echo "$d"
  done
}
