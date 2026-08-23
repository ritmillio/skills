# Reading Vercel logs — act vs. ignore

The triage script surfaces count-ranked events. This is how to judge them.

## Status codes for this stack

| Status | Meaning | Act? |
|---|---|---|
| **500** | Unhandled server error | **Yes** — a real break. Get the trace. |
| **502 / 503 / 504** | Upstream/timeout (function timeout, cold-start, DB unreachable) | **Yes** if repeated on one route — usually a slow query, a hung external call, or a function exceeding its duration. |
| 401 / 403 | Unauthorized / forbidden | Mostly expected (auth gate doing its job). Investigate only if a route that should be public returns it, or a spike coincides with a deploy. |
| 404 | Not found | Mostly expected (bots, stale links). A **500 that surfaces as "Not found" to the user** is the trap — confirm by the trace, not the status the user saw. |
| 429 | Rate limited | Act if it's your own users, not scrapers — points at a limiter set too low or a burst. |
| 2xx / 3xx | Success / redirect | Ignore for triage. |

## The dedupe rule

Never report a raw line count as an error count. The CLI emits the same event
many times; the script dedupes on request id (or full payload) before counting.
"50 lines mentioning 500" might be **one** request logged 50 times, or 50 real
failures — only the deduped count tells you which.

## Turning a 5xx into a root cause

1. Note the failing `method path` from the top row.
2. `grep <path> <raw-file>` (the script prints the raw file path).
3. Read the surrounding lines for the stack trace / thrown error / the last log
   before the failure.
4. Report the cause in one line — "`/api/chat` 500s: DB pool exhausted after the
   pooler GUC leak", not a pasted stack.

## Questions this surface can NOT answer

- **Older than ~24h** — runtime logs don't retain it. Set up a log drain
  (Datadog/Axiom/etc.) or an observability integration for history.
- **Build / deploy failures** — those are deployment logs, not runtime:
  `vercel inspect <url> --logs`, or the deploy's page in the dashboard.
- **Aggregate latency / traffic trends** — that's Vercel Analytics / Speed
  Insights or your observability provider, not the log stream.

## Known local traps (from prior audits)

- The CLI has duplicated each event ~20x in past pulls — the dedupe is not
  optional.
- Large `--until` windows get rejected; pull in a bounded window (the script
  timeboxes the stream).
- A user seeing "Not found" in the app has, in the past, actually been a 5xx
  server error surfaced as a friendly message — trust the log status over the
  UI copy.
