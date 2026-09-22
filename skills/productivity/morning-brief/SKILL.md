---
name: morning-brief
description: "Produce a one-screen founder morning brief: INTERNAL (git activity, open PRs, relay ledgers across the user's repos), BUSINESS (opt-in: inbox needing a reply, Stripe revenue events, PostHog signups, production errors, due and overdue tasks, read through whatever tools are connected), EXTERNAL (news from sources in a config file), ending in a Top 3 for today; optionally delivered to Telegram. Use when the user says 'morning brief', 'daily digest', 'founder brief', 'catch me up', 'what happened overnight', 'what needs me today', 'get the news', or wants a start-of-day summary without browsing."
allowed-tools: Read, Bash, Grep, WebFetch, AskUserQuestion
---

# /morning-brief — start the day in one screen, not ten tabs

A solo builder loses the first half hour of the day reconstructing state: what
moved in the repos overnight, which PRs are waiting, who is waiting on a reply,
whether anyone paid or cancelled, whether prod is erroring, and what happened in
the world worth knowing. This skill collapses that into one read. Three sections:
**internal** (your own work, from git and GitHub), **business** (opt-in: inbox,
revenue, product, prod health, tasks — from the tools you have connected) and
**external** (news from sources *you* list, so it's your feed, not a generic
one). It ends with the three things that need you today. Optionally it lands in
Telegram so the brief is waiting on your phone.

Read-only. It observes repos, reads connected accounts and fetches public feeds;
it changes nothing — the one exception is step 7, and only on an explicit yes.

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
- `business.txt` — *optional*; its presence turns the BUSINESS section on.
  `section | provider | options` per line (see `config/business.example.txt`).
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
   bash "$SKILL_DIR/scripts/brief.sh --business       # business only
   ```

2. **Internal section** (from the script): per repo — commits in the window
   (author + one-line subject), current branch, uncommitted-file count, and open
   PRs via `gh` if authed. It also flags any **running relay** (a `.loop/` with a
   live log) so you know unattended work is in flight.

3. **External section**: the script fetches every RSS/Atom source and lists items
   from the window, newest first, grouped by source. For any source that is a
   plain web page (not a feed), fetch it with **WebFetch** and extract the
   headlines yourself — the script marks those lines `NEEDS-WEBFETCH:`.

4. **Business section** (only if `business.txt` exists). The script prints one
   `AGENT-FILL: <section> via <provider>` line per enabled source and reads a
   `tasks | file` list itself. Fill each AGENT-FILL line with the matching
   connected tool, for the same window:
   - **inbox** (Microsoft 365 / Gmail MCP): unread threads from real people that
     ask for a reply — sender, subject, age. Top 5. Never paste bodies; skip
     newsletters, receipts and notifications.
   - **revenue** (Stripe MCP, else an authed `stripe` CLI): new subscriptions,
     cancellations and failed payments in the window, with counts and amounts.
     Read-only calls only.
   - **product** (PostHog MCP): signups and active users vs the previous window.
   - **prod** (the `vercel-triage` skill if installed): deduped production
     errors, 5xx first. Skip if the skill is missing.
   - **tasks** (Notion MCP / task board): overdue, due today, in progress.
   A provider whose tool is not connected, or asks for authentication, gets one
   line — "revenue: not connected" — and nothing else. Never estimate a number
   you could not read, and never start an interactive login from the brief.

5. **Summarise, don't dump.** Turn the raw lists into a tight brief:
   - *Internal:* what actually moved ("3 commits on the scraper's CZ court
     bootstrap; PR #12 waiting on you"), not a commit-by-commit replay.
   - *External:* the 5–10 items that matter for this builder's domain, one line
     each with the source, dropping duplicates and filler.

   - *Business:* the numbers and names that need a decision; "no cancellations,
     2 signups" is enough when nothing moved.

6. **Top 3 today.** Close with the three items that most need the user today,
   drawn from all sections — a waiting reply, a failed payment, a PR to review,
   an overdue task. One line each, with where to act.

7. **Offer to file action items** (optional, only if a task tool is connected).
   If the brief surfaced new action items not already on the board, ask with
   `AskUserQuestion` (multiSelect, one option per item, plus "none"). Create only
   the ones picked. This is the only write the skill ever makes.

8. **Offer Telegram delivery** (only if `telegram-notify` is configured). Ask
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

BUSINESS
  Inbox: <n> waiting — <sender>: <subject> (<age>) …
  Revenue: +<n> subs (<amount>), <n> cancelled, <n> failed payments
  Product: <n> signups (<±> vs yesterday), <n> active
  Prod: <n> distinct errors — <top one>          # or "clean"
  Tasks: <n> overdue, <n> due today — <top one>
  <provider>: not connected                        # for each missing tool

EXTERNAL  (your sources)
  • <headline> — <source>
  • …

TOP 3 TODAY
  1. <action> — <where>
  2. …
  3. …
```

Keep the whole thing to one screen. If a section is empty, say so in a line —
"quiet overnight, no commits" is a valid, useful result.

## References

- `references/config.md` — the two config files, feed formats, Telegram wiring,
  and how the window/filters work.
