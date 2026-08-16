---
name: shred-plan
description: Tear a written plan apart to find gaps before implementing it. Use when the user has a plan — a docs/*-plan.md file or a plan just produced in the conversation — and wants it stress-tested, red-teamed, or "shredded". Verifies every codebase claim with evidence, hunts unverified assumptions, hidden dependencies, missing failure modes, scope leaks, and unverifiable done-criteria, then reports findings ranked by severity.
---

# /shred-plan — a plan that survives shredding is worth building

Plans fail in the gaps between sentences: the claim about the codebase that was
true three months ago, the dependency on work nobody scheduled, the failure
mode nobody priced in. A generated plan is a draft, not a decision. This skill
is the adversarial pass between "here's the plan" and "let's build it".

The stance is **shred, don't review**. A review tries to approve; shredding
tries to break. A plan that comes back with zero findings means you didn't
shred hard enough — go again with sharper lenses. No cheerleading, no "looks
good overall".

## Invocation

`/shred-plan <path-to-plan>` — or no argument, in which case shred the plan in
the current conversation, or the most recently modified `docs/*plan*.md` in the
repo. If neither exists, say so and stop; never shred a plan you have to
imagine.

## When to use this

- Right after a plan is generated, before any implementation starts.
- Before turning a plan into tickets, a spec, or a relay mission — garbage in,
  garbage out.
- When resuming an old plan doc: the codebase has moved since it was written,
  and half its "facts" may now be wrong.

## When NOT to use this

- The idea isn't a plan yet — it's a sketch. That's a grilling session
  (`grill-me`), not a shredding; there is nothing concrete enough to break.
- The plan is already being implemented and the code is the question. That is
  code review, not plan review.
- Trivial plans. Shredding a three-line plan costs more than the plan.

## Workflow

### 1. Load project truth first

Before reading the plan, load the documents that define what *correct* means
here: `CLAUDE.md` / `AGENTS.md` (git rules, monorepo layout, naming
namespaces), `CONTEXT.md` (domain language) if present, `.claude/relay.md`
(gates) if present. Every finding in step 4 is checked against these, and the
plan's compliance with them is itself a finding category. A plan that ignores
the repo's own rules is a gap, not a style choice.

### 2. Decompose the plan into claims

Read the plan and extract, as a flat list:

- **Codebase claims** — "backend is ready at `/api/mobile/connectors`",
  "web gates mutations behind an approval card", "uses `@jogai/shared`". Each
  is verifiable, and each is false often enough to be worth checking.
- **Assumptions** — anything the plan states about the world that it does not
  verify: environment state, data shape, a dependency being "done", user
  behaviour.
- **Sequencing and gates** — what blocks what, what must be true before a step
  starts, what "done" means per step.
- **Scope edges** — what is declared out of scope, and whether the workstreams
  quietly reach past it.

### 3. Verify claims with evidence, in parallel

Fan out `Explore` subagents — one per workstream or claim cluster, not one per
claim — to check every codebase claim against the actual repo. Each returns
`confirmed` / `contradicted` / `not found` with `path:line` evidence. Do this
in parallel subagents for two reasons: it is faster, and it keeps the pile of
grep output out of the context that has to stay adversarial.

Never ask the user for a fact you can look up. Facts are your job; decisions
are theirs. A claim that cannot be verified is not assumed true — it is
reported as a gap.

### 4. Run the gap lenses

With verified claims in hand, walk these lenses. Each one is a pass over the
whole plan:

- **Rotten facts** — contradicted or unverifiable codebase claims. The plan's
  foundation, checked first because everything else sits on it.
- **Hidden dependencies** — work the plan needs but does not schedule: another
  phase that must ship first, a credential nobody has, a migration with no
  owner. If a step is "hard-blocked" on something, that something must appear
  in the plan with a state and a date, or it is a gap.
- **Missing failure modes** — what happens halfway through? Old builds still
  in the wild, partial data, the rollback path, the deploy that fails at step
  3 of 7. A plan with no rollback story for anything irreversible has a hole.
- **Scope leaks** — workstreams that reach past the declared out-of-scope
  list, or no out-of-scope list at all. An unbounded plan is a gap by itself.
- **Unverifiable done** — a step whose completion cannot be checked with a
  command, a test, or a visible behavior cannot be finished, only abandoned.
  Every workstream needs a proof.
- **Rule violations** — the plan contradicts project truth from step 1: wrong
  branch model, wrong package namespace, touches a forbidden surface, no
  branch from main.
- **Parallel-work hazards** — if the repo is worked by multiple sessions or a
  shared checkout, does the plan survive another agent landing changes
  mid-flight?
- **Silently answered questions** — decisions the plan made that belong to the
  user. A good plan surfaces its open questions ("is the migration this
  depends on actually shipped?") instead of guessing. List every place it
  guessed.

### 5. Report

Lead with the verdict, then findings grouped by severity. Every finding cites
its evidence — `path:line`, the plan section it contradicts, or the question
it dodges. No evidence, no finding.

```
## Shred verdict: <SOUND / FIXABLE — N blockers / SHREDDED — rebuild around X>

### Blockers — fix before any code
1. **<finding>** — <evidence>. <what to change in the plan>

### Gaps — fix or explicitly accept
...

### Questions that are yours, not the plan's
...

### Nits
...
```

Then offer exactly one follow-up: patch the plan doc in place with the
findings, or leave the report here. Do not patch unasked.

## Rules that hold on any plan

Findings are ranked by severity, never by how interesting they are. A
contradicted codebase fact outranks a clever architectural observation. The
report's job is to change the plan, not to display how thoroughly it was read.
And the plan author — often yourself, an hour ago — gets no mercy and no
credit: shred the text in front of you, not the one you remember writing.
