#!/usr/bin/env bash
#
# keep-awake.sh - print the command prefix that stops this machine sleeping
# through a long run, or nothing if the platform has no usable inhibitor.
#
# Sourced by launch.sh. Kept separate because "which inhibitor" is the one
# genuinely OS-specific thing in this skill, and it is where a published tool
# most often lies to its user.
#
#   macOS    caffeinate -ims   holds while the child lives. Cannot beat a
#                              closed lid: a laptop that gets shut sleeps.
#   Linux    systemd-inhibit   can also block the lid switch, so a systemd
#                              box really does survive a closed lid.
#   Windows  nothing reliable from a shell. We say so instead of pretending.

keep_awake_prefix() {
  case "$(uname -s)" in
    Darwin)
      if command -v caffeinate >/dev/null 2>&1; then
        printf 'caffeinate\n-ims\n'
        KEEP_AWAKE_NOTE="caffeinate holds off idle sleep; a closed lid still sleeps"
      else
        KEEP_AWAKE_NOTE="no sleep guard: caffeinate not found"
      fi ;;
    Linux)
      if command -v systemd-inhibit >/dev/null 2>&1; then
        printf 'systemd-inhibit\n--what=idle:sleep:handle-lid-switch\n--who=relay\n--why=unattended relay run\n'
        KEEP_AWAKE_NOTE="systemd-inhibit holds off idle, sleep and the lid switch"
      else
        KEEP_AWAKE_NOTE="no sleep guard: systemd-inhibit not found (a headless box usually does not sleep)"
      fi ;;
    MINGW*|MSYS*|CYGWIN*)
      KEEP_AWAKE_NOTE="no sleep guard on Windows. Before a long run: powercfg /change standby-timeout-ac 0 (and monitor-timeout if the screen matters), or turn on Presentation mode. Windows will otherwise suspend the run." ;;
    *)
      KEEP_AWAKE_NOTE="no sleep guard: unrecognised platform $(uname -s)" ;;
  esac
}
