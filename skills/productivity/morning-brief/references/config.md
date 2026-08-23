# morning-brief — configuration

Two files, both plain text, `#` comments ignored, one entry per line. Default
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
