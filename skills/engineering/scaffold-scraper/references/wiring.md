# Wiring a scaffolded scraper into the monorepo

`scaffold.sh` stamps the package and prints these edits. This is the reference
for doing them and for the framework contract the skeleton fills.

## The three wiring points

### 1. root `package.json` — four scripts

```json
"<country>:<alias>:test":      "tsx <country>/<vertical>/src/cli.ts test",
"<country>:<alias>:sample":    "tsx <country>/<vertical>/src/cli.ts sample",
"<country>:<alias>:bootstrap": "tsx <country>/<vertical>/src/cli.ts bootstrap",
"<country>:<alias>:update":    "tsx <country>/<vertical>/src/cli.ts update"
```

The `alias` is the short source tag (`law`, `court`, `nsud`, `uvo`, …), not the
full vertical slug — it keeps the script names short and matches the cron key.

### 2. `scripts/cron.sh` — a case arm

```bash
<country>-<alias>) CMD=(pnpm <country>:<alias>:update --since "${SINCE}") ;;
```

The Railway cron service sets `CORPUS=<country>-<alias>` and this arm runs the
right update window. `--since` is derived from the schedule; overlapping windows
are cheap because documents are keyed deterministically (a re-run overwrites the
identical R2 object rather than duplicating it).

### 3. `pnpm-workspace.yaml` — new country only

```yaml
- "<country>/*"
```

Add this **only when the country is new**. An existing country's `*` glob already
covers a new vertical, so the scaffold checks and tells you which case you're in.

## The framework contract the skeleton fills

- **`createCli({ name, description, storage, commands })`** from `@clausis/shared`.
  Commands: `test()`, `sample(count, flags)`, `bootstrap(yearFrom, yearTo, signal,
  flags)`, `update(since, signal, flags)`, and optional `index(signal, flags)`.
  `storage: { isConfigured: isR2Configured }` makes bootstrap refuse to run with
  R2 unconfigured (a scrape that writes only to local scratch is a silent loss).
- **`ScrapedDocument`** (`@clausis/shared`) is the base doc: `_id`, `_source`,
  `_type`, `_country`, `_fetchedAt`, `_contentHash` (+ optional `_language` for
  multilingual EU corpora). The skeleton's doc interface extends it.
- **`R2KeyGenerator<T>`** — `getKey(doc)` and `getPrefix(year?)`. Keys are the
  corpus's deterministic identity; get them right before bootstrapping.
- **`runPipeline({ documents, r2Keys, dataDir, r2Put, storeOriginal, extract,
  signal })`** drives bootstrap/update: consume the async generator, store
  originals, optionally AI-extract, write JSON to R2 + local, honour the abort
  signal.
- **`runIndexCommand({ dataDir, keys, flags, signal })`** from `@clausis/tpuf` is
  the `index` command — embeds stored docs and upserts into Turbopuffer.

## What the scaffold deliberately does NOT do

The site-specific fetch/list/parse logic in `scraper.ts` and the language-
specific legal-area union in `extraction-schema.ts` are bespoke. The skeleton
marks each `// TODO(scaffold)` and keeps the exported names the CLI is wired to
(`testConnection`, `fetchDocument`, `listDocuments`, `fetchAll`, `fetchUpdates`,
the doc type). Copy the nearest existing vertical of the same document type and
port its logic into those functions — do not rename them.

## The gate

```bash
pnpm install                                              # link the new package
pnpm --filter @clausis/<country>-<vertical> exec tsc --noEmit
pnpm <country>:<alias>:test                               # connection smoke test
```

A green `tsc` proves the wiring; the stamped skeleton is written to compile
against the framework as-is (verified: a freshly stamped package typechecks
clean before any bespoke code is added).
