---
name: model-router
description: Pick the cheapest model and effort that can do a task well, BEFORE doing it or spawning agents. Cheap probe (max 3 tool calls), five-axis score, a one-line route card (model + effort + delegate or not) for the main session, each subagent and each workflow agent. Use at the start of any non-trivial task, before spawning subagents, or when the user says 'which model', 'what effort', 'save tokens', 'don't burn tokens'.
---

# /model-router: right model, right effort, before the first token is spent

Most token burn comes from three mistakes: a strong model at high effort on a mechanical task, a fan-out of agents for work that needed three tool calls, and a weak model that fails so the work is done twice. This skill prevents all three with a short triage before the work.

## When NOT to use

- One-line answers, a single file lookup, a typo fix. Just do it; the triage costs more than the task.
- The user already named the model or effort. Their choice wins. Do not argue it.

## Tiers

The skill speaks in four tiers. Map them to whatever your agent offers:

| Tier | Claude Code | Other agents |
|---|---|---|
| **small** | `haiku` | the fast/mini model |
| **mid** | `sonnet` | the default model |
| **large** | `opus` | the strong default for real work |
| **frontier** | `fable` | the most capable (and costliest) model |

Effort: `low` · `medium` · `high` · `xhigh` · `max` (or the agent's reasoning-effort equivalent). `max` effort is the user's call only. Tier and effort are separate dials: a medium task on a large model at medium effort is often cheaper than a mid model at high effort that needs a retry.

## Step 0: read the host repo's overrides (optional)

If the repo has `.agents/model-router.md` (or a `## Model router` section in `AGENTS.md`/`CLAUDE.md`), read it. It lists paths that are always Risk 2, models the team never uses, and tasks with a fixed route. It overrides the defaults below.

## Step 1: probe (cheap, max 3 tool calls, never read whole files)

Collect only the signals the conversation has not already given you:

```bash
git diff --stat "$(git merge-base HEAD origin/HEAD 2>/dev/null || echo HEAD~1)" | tail -1   # size of a review target
git grep -l "<key symbol>" | wc -l                                                        # files the change touches
ls <target dir> | head                                                                    # does the area exist, how big
```

If you need more than 3 calls to size it, it is Scope 2. Stop probing.

## Step 2: score five axes (0, 1 or 2 each)

| Axis | 0 | 1 | 2 |
|---|---|---|---|
| **Scope** | 1 file, < 50 lines | 2 to 5 files, one package | > 5 files or several packages |
| **Ambiguity** | exact instruction | some choices, sensible defaults exist | open design, several valid readings |
| **Reasoning depth** | mechanical (rename, lookup, format, grep) | normal feature/fix with a known pattern | unknown root cause, concurrency, architecture, perf, security |
| **Risk** | docs, scratch, throwaway | app code behind a flag, tests catch it | migrations, auth, money, public API/contracts, prod data, anything legal or medical |
| **Verification** | one command proves it | tests + one manual check | hard to check (UX judgement, model quality, no tests) |

**Hard floors** (override the sum):
- Risk = 2: the step that DECIDES (writes the migration, the auth check, the money path) runs on **large/high** minimum. Gathering facts for it can stay cheap.
- Pure search, file location, log grep: **small/low**. Always.
- Reasoning depth = 2 and the first attempt failed: one tier up, never two (large fails -> frontier).

## Step 3: route

| Sum | Route | Delegate? |
|---|---|---|
| 0 to 2 | small / low | No. Do it inline. |
| 3 to 4 | mid / medium | Inline. One search subagent (small) only if the search spans many dirs. |
| 5 to 6 | large / medium | Split: cheap gather, strong decide (below). |
| 7 to 8 | large / high | Short plan first, each step names its check. Subagents only for independent parallel parts. |
| 9 to 10 | frontier / high, or large / xhigh | Plan, then have it critiqued before any code. |

## Step 4: apply the route

**Main session.** An agent usually cannot switch its own model. If the route is two or more tiers away from the current model (a large/xhigh session doing a Scope-0 rename), say it in one line and carry on:

> model-router: this is a small/low task. Cheaper: `/model haiku` + `/effort low`. Continuing on the current model.

One tier off: say nothing. Switching costs more than it saves.

**Subagents.** Pass the route's model on every spawn. This skill authorizes setting the subagent's effort: pass the route's effort. Search/explore agents: small/low.

**Multi-agent workflows.** Score each agent on its own: fact gatherers and mechanical checkers on small/mid, the synthesis or decision agent on large.

**Cheap gather, strong decide** (sum 5+):
1. A small/mid agent collects facts and returns a short list (file:line, quotes, numbers). No opinions.
2. The strong model decides and writes the code.

Give the cheap agent the question, never your hypothesis to "confirm": it will confirm it.

## Step 5: escalate, do not start high

- Start at the route. If the output fails its check (test red, wrong answer, missed the point), retry ONCE one tier up, with what failed in the prompt.
- Two failures on the same tier means the score was wrong. Re-score (usually Ambiguity or Reasoning depth was under-counted) and say so.
- Do not downgrade in the middle of a step that already proved hard.

## Output: the route card

Before starting, print one line:

```
model-router: S1 A0 D1 R2 V1 = 5 (risk floor) -> gather small/low, decide large/high, inline
```

For several agents, one line with one entry each:

```
model-router: find-routes small/low | audit-auth large/high | write-tests mid/medium
```

## Example `.agents/model-router.md`

```markdown
## Model router
- Always Risk 2: `db/migrations/**`, `src/auth/**`, `billing/**`, `api/public/**`
- Never use: <model the team has vetoed>
- Fixed routes: changelog entries small/low; release notes mid/medium
```

## Scope

This skill picks models for the coding agent doing the work. It does not choose the models your product calls at runtime; that is a product decision with its own evals.
