# morning-brief — configuration

Two files (plus an optional third for the BUSINESS section), all plain text, `#` comments ignored, one entry per line. Default
dir `~/.config/morning-brief/`; override with `$MORNING_BRIEF_CONFIG`. If neither
exists the skill falls back to the shipped `config/*.example.txt` and says so.

## repos.txt

Absolute paths to the repos you want summarised:

```
/Users/you/Developer/clausis.ai
/Users/you/Developer/clausis-scrapers
```

Per repo the brief reports commits in the window, current branch, uncommitted
count, and — if `gh` is authed — open PRs. It also flags a live relay (`.loop/`).

## business.txt (optional)

Its presence turns on the BUSINESS section. One line per source:

```
section | provider | options
inbox   | microsoft365  | unread needing a reply, top 5
revenue | stripe        | new subscriptions, cancellations, failed payments
product | posthog       | signups and active users vs the day before
prod    | vercel-triage | production errors, deduped
tasks   | notion        | the task board: due today, overdue, in progress
tasks   | file          | ~/notes/TODO.md
```

- `tasks | file | <path>` is read by the script: markdown checkboxes (`- [ ]`),
  with `due: YYYY-MM-DD`, `@YYYY-MM-DD` or `📅 YYYY-MM-DD` dates; it prints open,
  overdue and due-soon counts.
- Every other line is printed as `AGENT-FILL: <section> via <provider>`. The agent
  answers it with its connected tools (MCP servers, or an authed CLI such as
  `stripe`). No credentials live in this file or in the script.
- Not connected = one "not connected" line in the brief. Delete a line to stop
  asking for it.
- Providers are free text; name what your agent has (`gmail`, `hubspot`,
  `linear`, `plausible` …) and the agent maps it to a tool.

## sources.txt

```
Label | https://feed-url
```

- **RSS/Atom feeds** (URL ends in `.xml`/`.rss`/`.atom`, or contains `rss`/`feed`)
  are fetched and parsed by the script: title, link, and date, filtered to the
  window, newest first.
- **Plain web pages** are printed as `NEEDS-WEBFETCH: <url>` — the agent fetches
  them with the WebFetch tool and extracts headlines. Use this for sites without
  a feed.

Finding a feed: many sites expose `/feed`, `/rss`, `/atom.xml`, or a
`<link rel="alternate" type="application/rss+xml">` in their HTML `<head>`.

## Window

`--since 24h` (default), `48h`, `7d`. Applies to both the git window and the news
cutoff. Items with no parseable date are kept (shown with `?`) rather than
dropped, so a feed with bad dates still surfaces.

## Telegram delivery (optional)

If the `telegram-notify` skill is set up (bot token + chat id in its config), the
brief can be pushed to your phone. The morning-brief SKILL.md shows the pipe; if
telegram-notify isn't configured, delivery is skipped silently — the brief still
prints to the terminal.

## Scheduling (optional)

To get the brief without asking, wire it to a scheduler:
- macOS: a `launchd` LaunchAgent running `brief.sh` at, say, 07:00, piping to the
  Telegram sender.
- Or the `loop`/`schedule` Claude Code skills, if you want the agent to
  summarise it rather than get raw script output.

Keep raw output for the terminal; let the agent do the summarise-to-one-screen
step for the version a human reads.
