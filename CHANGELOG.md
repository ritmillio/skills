# Changelog

## Unreleased

- Marketplace passthrough for `mattpocock/skills`: a remote-source entry, so
  `/plugin install mattpocock-skills@ritmillio-tools` pulls from his repo and
  `/plugin update` keeps it in sync. No vendored copy.
- `draft-plan`: turn an investigation or conversation into a written plan doc —
  verified diagnosis, explicit scope, workstreams with proofs of done,
  sequencing gates, open questions. Chains into `shred-plan`.
- `telegram-notify`: Telegram bot pings for agent events (Stop hook, commits,
  relay start/landed/halt/limit/end), with a sender script that satisfies
  relay's `RELAY_NOTIFY` contract and a setup walkthrough for BotFather, chat
  id and Claude Code hook wiring.
- `shred-plan`: adversarial stress-test of a written plan — verifies codebase
  claims with evidence via parallel subagents, then hunts hidden dependencies,
  missing failure modes, scope leaks and unverifiable done-criteria.
- Categorised layout (`skills/<category>/<name>/`) with `in-progress/` and
  `deprecated/` lifecycle folders.
- Dropped the bespoke `scripts/install.sh` in favour of the community `skills`
  CLI, which already handles multi-agent installs, symlinking and updates.
- Documented that marketplace-installed skills are namespaced (`/relay:relay`),
  which the Claude Code docs imply is not the case.

## 0.1.0 — 2026-08-15

- `relay`: unattended autonomous work for a stated duration, run as fresh
  processes handing off a committed ledger.
