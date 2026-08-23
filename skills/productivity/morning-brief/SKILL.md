---
name: morning-brief
description: "Produce a one-screen morning brief: an INTERNAL section (git activity, open PRs, and relay ledgers across the user's repos) and an EXTERNAL section (news pulled from sources listed in a config file), optionally delivered to Telegram. Use when the user says 'morning brief', 'daily digest', 'catch me up', 'what happened overnight', 'get the news', or wants a start-of-day summary without browsing."
allowed-tools: Read, Bash, Grep, WebFetch, AskUserQuestion
---

# /morning-brief — start the day in one screen, not ten tabs

A solo builder loses the first half hour of the day reconstructing state: what
moved in the repos overnight, which PRs are waiting, and what happened in the
world worth knowing. This skill collapses that into one read. Two sections:
**internal** (your own work, from git and GitHub) and **external** (news from
sources *you* list, so it's your feed, not a generic one). Optionally it lands in
Telegram so the brief is waiting on your phone.

Read-only. It observes repos and fetches public feeds; it changes nothing.

## When to use this

- "Morning brief", "daily digest", "catch me up", "what happened overnight".
- "Get me the news" / "what's new in <topic>" without opening a browser.
- Start of day, or after time away, to reload context fast.

## First run: set up config (one time)

The skill reads two small config files so nothing is hardcoded. Default location
`~/.config/morning-brief/`; override with `$MORNING_BRIEF_CONFIG`.

```bash
mkdir -p ~/.config/morning-brief
cp "$SKILL_DIR/config/repos.example.txt"   ~/.config/morning-brief/repos.txt
cp "$SKILL_DIR/config/sources.example.txt" ~/.config/morning-brief/sources.txt
# then edit both — one entry per line, "# comments" ignored
```

- `repos.txt` — absolute paths to the repos to summarise, one per line.
- `sources.txt` — `Label | https://feed-url` per line. RSS/Atom URLs are fetched
  and parsed directly; a plain web page URL is handled in step 3 via WebFetch.

If no config exists, the skill runs against the shipped examples and tells the
user to personalise them. See `references/config.md`.

## Workflow

1. **Run the brief:**
   ```bash
   bash "$SKILL_DIR/scripts/brief.sh"                 # last 24h, both sections
   bash "$SKILL_DIR/scripts/brief.sh --since 48h      # wider internal window
   bash "$SKILL_DIR/scripts/brief.sh --internal       # skip news
   bash "$SKILL_DIR/scripts/brief.sh --news           # news only
   ```

2. **Internal section** (from the script): per repo — commits in the window
   (author + one-line subject), current branch, uncommitted-file count, and open
   PRs via `gh` if authed. It also flags any **running relay** (a `.loop/` with a
   live log) so you know unattended work is in flight.

3. **External section**: the script fetches every RSS/Atom source and lists items
   from the window, newest first, grouped by source. For any source that is a
   plain web page (not a feed), fetch it with **WebFetch** and extract the
   headlines yourself — the script marks those lines `NEEDS-WEBFETCH:`.

4. **Summarise, don't dump.** Turn the raw lists into a tight brief:
   - *Internal:* what actually moved ("3 commits on the scraper's CZ court
     bootstrap; PR #12 waiting on you"), not a commit-by-commit replay.
   - *External:* the 5–10 items that matter for this builder's domain, one line
     each with the source, dropping duplicates and filler.

5. **Offer Telegram delivery** (only if `telegram-notify` is configured). Ask
   before sending; on yes, pipe the finished brief through its sender:
   ```bash
   printf '%s' "$BRIEF" | bash "$SKILL_DIR/../telegram-notify/scripts/telegram-notify.sh" --stdin --title "Morning brief"
   ```
   (Exact flags per that skill; if it isn't set up, skip silently.)

## Report format

```
☀️  Morning brief — <date>, last <window>

INTERNAL
  <repo>: <n> commits — <highlight>. branch <x>, <k> uncommitted.
  PRs waiting: #<n> <title> …
  ⚠ relay running: <slug> (<repo>)         # only if one is live

EXTERNAL  (your sources)
  • <headline> — <source>
  • …

Nothing urgent / <one-line call to attention>.
```

Keep the whole thing to one screen. If a section is empty, say so in a line —
"quiet overnight, no commits" is a valid, useful result.

## References

- `references/config.md` — the two config files, feed formats, Telegram wiring,
  and how the window/filters work.
