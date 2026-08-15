# Changelog

## Unreleased

- Categorised layout (`skills/<category>/<name>/`) with `in-progress/` and
  `deprecated/` lifecycle folders.
- Dropped the bespoke `scripts/install.sh` in favour of the community `skills`
  CLI, which already handles multi-agent installs, symlinking and updates.
- Documented that marketplace-installed skills are namespaced (`/relay:relay`),
  which the Claude Code docs imply is not the case.

## 0.1.0 — 2026-08-15

- `relay`: unattended autonomous work for a stated duration, run as fresh
  processes handing off a committed ledger.
