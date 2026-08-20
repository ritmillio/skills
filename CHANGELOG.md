# Changelog

## Unreleased

- `relay`: a run can now end on **done** instead of on the clock. Each criterion
  becomes an executable check in `.loop/done.d/`; `check-done.sh` runs them all
  and the relay stops the moment every one exits 0, with `--hours` demoted to
  the safety cap. A gated run that ends any other way lists what is `still open:`.
- `relay`: iterations **stream**. They ran under `--output-format json`, which
  emits nothing until the process exits, so 45 minutes of real work was
  indistinguishable from a hang. Events now flow through `progress.sh` into
  `.loop/live.log` as they happen, and `watch.sh` renders contract, budget,
  commits and stream as a live dashboard (`launch.sh --watch` attaches it).
- `relay`: fixed `.is_error // "true"` — jq's `//` fires on `false` as well as
  `null`, so every clean iteration was counted as failed and pushed through the
  usage-limit probe. Also replaced `sed` tab patterns that BSD sed does not read.

- `reclaim`: diagnose and fix a dev machine pinned at high CPU/RAM/load.
  Leads with the System-vs-User split, because a top-of-list process is
  usually a symptom — `launchservicesd` at 300% is spawn churn, not work.
  Ships a read-only `diagnose.sh` and a protect-listed `reap.sh` (dry-run by
  default) for stale `next dev` / `trigger dev` / orphan-esbuild watchers,
  plus the vitest-forks-one-worker-per-core cap and a safe relay wind-down.
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
