---
name: scaffold-scraper
description: "Stamp a new country x vertical scraper in a clausis-scrapers-style monorepo: create the workspace package, framework-wired cli.ts, typed scraper.ts skeleton, extraction schema, R2 key generator, and test stubs, then wire root scripts, the Railway cron case, and the pnpm workspace. Use when the user says 'add a scraper', 'scaffold a country', 'new vertical', 'add <country> laws/courts', or is expanding the corpus to a new jurisdiction."
allowed-tools: Read, Bash, Grep, Glob, Edit, AskUserQuestion
---

# /scaffold-scraper — a new corpus without re-typing the wiring

Every country×vertical in this monorepo is the *same shape*: a workspace package
depending on `@clausis/{shared,storage,extraction,tpuf}`, a `cli.ts` wired to
`createCli` with four commands, a typed `scraper.ts`, an `extraction-schema.ts`,
an `r2-keys.ts`, and tests — plus three wiring points that are easy to forget
(root `package.json` scripts, the Railway cron `case`, the pnpm workspace). Doing
that by hand for a 6-country × ~10-vertical roadmap is copy-paste that drifts.

This skill stamps the skeleton from templates so it **compiles against the
framework on day one**, then walks the wiring. What it can't generate is the
site-specific fetch/parse logic in `scraper.ts` — that's genuinely bespoke, so
the skill points you at the nearest existing vertical to copy the patterns from.

## When to use this

- "Add a scraper", "scaffold <country> laws/courts", "new vertical", expanding to
  a new jurisdiction.

## When NOT to use this

- The bespoke scraping logic itself — this scaffolds structure, not the parser.
- A one-off script that doesn't belong in the corpus pipeline.
- A repo that isn't this monorepo shape (no `packages/`-workspace, no `createCli`).
  Confirm the shape (step 1) before stamping.

## Workflow

1. **Confirm the repo shape and pick a reference vertical.** From the scrapers
   repo root, verify the framework exists and find the closest existing vertical
   of the same document type to copy bespoke logic from later:
   ```bash
   test -f pnpm-workspace.yaml && grep -q createCli packages/shared/src/index.ts && echo "shape OK"
   ls */                     # existing countries
   ls slovakia/              # verticals under a country (laws, court-decisions, …)
   ```
   A **legislation** vertical's nearest reference is another `laws`; a
   **case_law** one, another `court-decisions`. Note that path — step 4 needs it.

2. **Gather the parameters** (ask the user only for what you can't infer):
   - country (e.g. `czechia`) and its ISO code (`cz`)
   - vertical slug (`laws`, `court-decisions`, `supreme-court`, …) and a short
     script alias (`law`, `court`, `nsud`, …) for the root `pnpm` scripts
   - document type: `legislation` or `case_law`
   - R2 key prefix (`cz/laws`) and the source id (`CZ/Sbirka`)
   - the source base URL (for the `cli.ts` description + a TODO in `scraper.ts`)

3. **Stamp the package:**
   ```bash
   bash "$SKILL_DIR/scripts/scaffold.sh" \
     --country czechia --code cz --vertical laws --alias law \
     --type legislation --prefix cz/laws --source "CZ/Sbirka" \
     --url "https://www.zakonyprolidi.cz" --repo "$(pwd)"
   ```
   It creates `<country>/<vertical>/` with `package.json` and `src/{cli,scraper,
   extraction-schema,r2-keys}.ts` + a `scraper.test.ts` stub, all token-
   substituted and typed against the framework. It refuses to overwrite an
   existing directory.

4. **Fill the bespoke logic** by copying the reference vertical from step 1. Open
   its `scraper.ts` and port the fetch/list/parse functions into the stubbed
   `scraper.ts` (the stub marks each `// TODO(scaffold)` site). Keep the exported
   names the skeleton already wired (`testConnection`, `fetchAll`, `fetchUpdates`,
   the document type). Do the same for `extraction-schema.ts` (the legal-area
   union is language-specific).

5. **Do the wiring** the scaffold printed (exact lines in `references/wiring.md`):
   - **root `package.json`**: four scripts `<country>:<alias>:{test,sample,
     bootstrap,update}`.
   - **`scripts/cron.sh`**: a `case` arm `<country>-<alias>) CMD=(pnpm
     <country>:<alias>:update --since "${SINCE}") ;;`.
   - **`pnpm-workspace.yaml`**: only if this is a **new country** (add
     `- "<country>/*"`); an existing country's glob already covers a new vertical.

6. **Install and prove it compiles** (the real gate):
   ```bash
   pnpm install                                   # link the new workspace pkg
   pnpm --filter @clausis/<country>-<vertical> exec tsc --noEmit   # or repo's typecheck
   pnpm <country>:<alias>:test                    # connection smoke test
   ```
   A green `tsc` on the skeleton means the framework wiring is correct; the
   `test` command exercises the connection stub you'll replace in step 4.

## Report format

- The package created and its path.
- The reference vertical to copy bespoke logic from.
- The exact wiring edits made (or still to make), file by file.
- The compile/test result — green skeleton, or the errors to fix.

## References

- `references/wiring.md` — the three wiring points with copy-paste lines, and the
  framework contract the skeleton fills (`createCli` commands, `ScrapedDocument`,
  `R2KeyGenerator`).
