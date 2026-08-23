---
name: vercel-triage
description: "Pull, dedupe, and triage Vercel production logs down to genuine failures, working around the CLI's traps (events duplicated many times, short --until windows, ~24h retention). Use when the user says 'check the vercel logs', 'is prod erroring', 'triage production', 'why are users seeing errors', or wants a production health read."
allowed-tools: Read, Bash, Grep, AskUserQuestion
---

# /vercel-triage — is prod actually erroring, or is it log noise?

A raw `vercel logs` dump is almost useless for triage: the same event is emitted
many times over, the retention window is short, and 4xx noise drowns the handful
of 5xx that are real user-facing failures. Every manual pass re-learns the same
workarounds. This skill bakes them in: pull once, dedupe, and surface only the
errors that mean something — with counts, so a spike is obvious.

Read-only. It reads logs and reports; it changes no deployment and no config.

## When to use this

- "Check the Vercel logs", "is prod down / erroring", "triage production".
- A user report of errors and you need to know if it's real and how widespread.
- A post-deploy health read.

## When NOT to use this

- You need history older than ~24h — Vercel runtime logs don't retain it. Use a
  log drain / observability provider instead, and say so.
- The question is build failures, not runtime — that's `vercel inspect` /
  deployment logs, a different surface (see references).

## Prerequisites (check first, fail clear)

```bash
command -v vercel || echo "install: npm i -g vercel"
vercel whoami            # authed?
[ -f .vercel/project.json ] || echo "run: vercel link"
```
If any fails, tell the user the one command to fix it and stop — don't guess a
project.

## Workflow

1. **Run the triage script** from the linked project root:
   ```bash
   bash "$SKILL_DIR/scripts/triage.sh"           # last window, prod
   bash "$SKILL_DIR/scripts/triage.sh --status 500   # only 5xx"
   ```
   It resolves the current production deployment, pulls its runtime logs,
   **dedupes** identical events, and groups what's left by status and path with
   counts. Raw output is saved to a temp file it names, so you can grep deeper
   without re-pulling.

2. **Read the summary, not the raw stream.** The script prints, most-frequent
   first: `<count>  <status>  <method> <path>  <last-seen>`. A single 500 is a
   blip; the same 500 fifty times on one route is an incident.

3. **Filter to real failures.** 5xx are the ones that mean the app broke. Treat
   4xx as signal only when the user is chasing a specific auth/not-found report —
   most 401/403/404 are expected. `references/reading-logs.md` maps common
   statuses to "act vs ignore" for this stack.

4. **For a real 5xx, get the trace.** Grep the saved raw file for the path and
   read the surrounding lines for the stack / error message. Turn that into a
   one-line root cause, not a paste of the whole trace.

5. **Report** (see format below). If nothing real surfaced, say "prod clean in
   the last window" plainly — a quiet result is the product.

## The CLI traps (why the script exists)

- **Duplicated events** — the same log line arrives many times; naive `wc -l`
  massively overcounts. The script dedupes on the event signature before it
  counts anything. Never report a raw line count as an error count.
- **Short `--until` window** — large `--until` values are rejected; the script
  pulls in a bounded window and says what window it covered.
- **~24h retention** — anything older is simply gone from this surface. If the
  user asks about yesterday-plus, name the limit and point at the drain.
- **Only 5xx = user-facing break** — 4xx is mostly expected traffic.

## Report format

- **Verdict:** clean / N distinct 5xx / active incident — one line.
- **Top errors:** the count-ranked table, 5xx first.
- **Root cause** for each real one: the failing path + the one-line reason from
  the trace.
- **Window & limits:** what time range this covered, and that >24h isn't here.

## References

- `references/reading-logs.md` — status-by-status act-vs-ignore, and where build
  logs / drains live for the questions this surface can't answer.
