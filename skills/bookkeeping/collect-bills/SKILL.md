---
name: collect-bills
description: Sweep mailboxes for vendor invoices billed to the company, drop anything without the company tax number, diff against what is already archived, and download only the delta. Use when the user says collect the bills, gather receipts, get the invoices, or do the bookkeeping.
---

# /collect-bills — gather only the invoices the accountant can use

Periodic bookkeeping sweep. The goal is not "every receipt in the mailbox", it is
**every invoice made out to the company**. An invoice billed to someone's personal
email is not deductible, so collecting it pollutes the archive and inflates the
count you report.

Most of this skill's value is the traps table. Read it before starting, not after.

## When to use this

- Periodic bookkeeping: "collect the bills for August".
- Before handing records to an accountant.
- To audit which vendors are billing a person instead of the company.

## When NOT to use this

- Chasing one known invoice. Just search the mailbox.
- Vendor portal invoices (telcos, banks, utilities). Those live behind a login and
  never arrive as email. Report them as absent; that is the correct answer, not a
  failure.
- A mailbox you have not been asked to read.

## 0. Locate this skill on disk

```bash
for d in "${CLAUDE_PLUGIN_ROOT:-}" ~/.agents/skills/collect-bills ./.agents/skills/collect-bills \
         ~/.claude/skills/collect-bills ~/.codex/skills/collect-bills \
         ~/.gemini/skills/collect-bills ~/.cursor/skills/collect-bills ./.claude/skills/collect-bills; do
  [ -x "$d/scripts/filter-by-tin.sh" ] && SKILL_DIR="$d" && break
done
```

## 1. Read the host config

Company identity is never hardcoded here. Read `.collect-bills.json` from the
working directory; if it is absent, ask the user once and offer to write it.

```json
{
  "taxIdCore": "12345678",
  "companyNames": ["Acme Technologies Ltd.", "Acme Kft."],
  "archive": "https://drive.google.com/drive/folders/...",
  "stagingDir": "~/Desktop/Bills-<date>"
}
```

`taxIdCore` is the **shortest stable digit sequence** in the tax number, not the
formatted string. The same company appears as `HU TIN 12345678-1-41` on one
vendor's invoice and `HU VAT HU12345678` on another's; matching the full
formatted value silently drops the other format. Company names change through
rebrands and legal-form changes, so names are a fallback signal, never the key.

## 2. Preflight

1. **Allow multiple downloads for each mail host.** Browsers silently block
   repeated downloads from a site after the first one. The failure is invisible:
   clicks appear to succeed and no file lands. In Chrome:
   `chrome://settings/content/automaticDownloads`, then allow the mail host.
   This is a browser permission. **Ask the user to set it. Never change it yourself.**
2. **Confirm sign-in** on every mailbox and on the archive destination. A shared
   Drive link opened anonymously is read-only, so uploads fail even though the
   folder is visible. Never enter credentials; the user signs in.
3. **Inventory the destination first.** The filenames already archived are the
   diff baseline. Skip this and you re-download everything.

## 3. Sweep, diff, download

1. Search each mailbox by attachment filename first (`attachment:Receipt`), then
   broadly (`hasattachments:yes`), then by vendor name, then in the local
   language (`számla`, `facture`, `Rechnung`).
2. **Verify the result count is stable before trusting it.** See Traps.
3. Diff against the baseline. Report three numbers: found, already archived, to
   collect.
4. Download. Prefer the **email attachment**: it never expires. A hosted link in
   the body (Stripe's `Download receipt`) is fetchable with `curl -L` and no auth,
   but expires after roughly 30 days and then returns HTTP 410 with an HTML body.
5. Verify every file is genuinely a PDF. An error page saved as `.pdf` looks fine
   in a directory listing:
   ```bash
   head -c4 "$f" | grep -q '%PDF' || { echo "BAD: $f"; rm -f "$f"; }
   ```

## 4. Filter to company invoices

```bash
"$SKILL_DIR/scripts/filter-by-tin.sh" <dir> --tax-id <core>            # dry run
"$SKILL_DIR/scripts/filter-by-tin.sh" <dir> --tax-id <core> --apply    # move the rest aside
```

`--apply` moves non-company files into `<dir>/_no-tax-number/` rather than
deleting them, and prints which vendors are billing a person. That list is the
finding with money attached, not the file count.

## 5. Reconcile before reporting

Diff the staged folder against the expected list. Never report a count you have
not diffed; a copy that ran before downloads finished leaves a folder that is
short by N and still looks plausible.

## Traps

| Trap | Symptom | Handling |
|---|---|---|
| **Cold search index** | The same query reports 8 results, then 19, then 59 | Run it, wait, run again. Trust only a count that repeats. Never call a sweep complete off the first number. |
| **Browser blocks repeat downloads** | First file lands, the rest silently do not | Preflight permission. Check disk after the *first* download, not at the end. |
| **Synthetic clicks** | Scripted `element.click()` selects messages fine but downloads produce nothing | Selection by script is fine; downloads need a real gesture or the permission. Never trust a scripted "ok" without checking disk. |
| **Cross-origin `download` attribute** | `<a download>` ignored, no file, no tab | Use the attachment route instead. |
| **Expired hosted links** | HTTP 410, HTML saved as `.pdf` | Check status codes, fall back to attachments. |
| **Search terms AND together** | A valid term returns zero because an earlier term is still an active chip | Clear the search box between queries and confirm visually. |
| **Virtualised message lists** | Only ~10 rows in the DOM, `scrollTop` resets, synthetic wheel events do nothing | Scroll with real wheel events, harvest incrementally, dedupe by receipt number. |
| **Conversation grouping** | Many receipts collapse into a few rows | Turn conversation view off before enumerating. |
| **New Outlook for Mac** | AppleScript errors `-1728` on `every account` | No scripting access to server mail. Use the web client. |
| **One company, two tax formats** | A valid invoice classified as personal | Match the digit core, not the formatted string. |

## Report format

Lead with the counts, then exclusions, then what is genuinely unavailable.

```
Collected: N invoices -> <staging dir>
  Found: X   Already archived: Y   Collected: N

Excluded (no company tax number): M
  <vendor> (n) ... billing profile is a personal address, fix it

Not available in mail:
  <vendor>: portal only, no invoice emailed
```
