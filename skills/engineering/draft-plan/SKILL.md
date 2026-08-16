---
name: draft-plan
description: Turn an investigation or conversation into a written plan doc with diagnosis, explicit scope, workstreams with verifiable proofs, sequencing gates, and open questions. Use when the user wants a plan written down before building — then chain into shred-plan to stress-test it.
---

# /draft-plan — write the plan down before you build it

A plan that lives only in a conversation dies with the context window. This
skill turns what has been figured out — in this session, in an investigation,
in a grilling — into a plan doc in the repo, in a shape that can be
stress-tested, ticketed, or handed to another agent.

The doc structure below is not arbitrary: it is exactly the list of things
`shred-plan` checks. A plan written in this shape is born with fewer gaps.

## Invocation

`/draft-plan` — synthesize the current conversation into a plan.
`/draft-plan <topic>` — investigate first, then write the plan.

## When to use this

- The what and why are settled (a grilling happened, or the user knows), and
  the next step is a written plan.
- Work big enough that "just start coding" would lose the thread: multiple
  workstreams, a migration, a cutover, anything with a gate.
- Work another session or agent will pick up — the doc is the handoff.

## When NOT to use this

- The idea isn't settled yet. Drafting a plan around unresolved decisions
  bakes the guesses in. Grill first, draft after.
- One well-understood change. Just make it.
- The plan already exists and needs checking. That is `/shred-plan`.

## Workflow

### 1. Learn what is true, not what is assumed

Before writing anything, verify the codebase facts the plan will rest on.
Fan out `Explore` subagents over the areas the plan touches: the surfaces to
change, the current behavior, the dependencies. A plan that starts from rotten
facts is worse than no plan — it confers false confidence. Every factual claim
in the Diagnosis section should be something you checked, with a `path:line`
you could cite.

Also load the project's truth: `CLAUDE.md` / `AGENTS.md` (git rules, layout,
conventions), `CONTEXT.md` if present. The plan must comply with them, and
should speak the project's domain language.

### 2. Write the doc

Infer the docs location from the repo (`docs/` is the convention; ask only if
genuinely ambiguous) and write `docs/<slug>-plan.md`:

```markdown
# <Title>

**Date:** <today>
**Branch context:** <current branch / relevant state>

## 1. Diagnosis — what is actually true today

The current state, with evidence. What works, what's missing, what's broken.
Not what anyone assumed — what you verified in step 1.

## 2. Scope decisions

**In scope:** what this plan builds or fixes.
**Out of scope:** what it explicitly does not, including the tempting adjacent
work. An unbounded plan is a gap.

## 3. Workstreams

One section per workstream. Each names the surfaces it touches and ends with
a **proof of done**: a command that passes, a test that goes green, or a
visible behavior. A step whose completion can't be checked can't be finished,
only abandoned.

## 4. Sequencing & gates

What blocks what. Anything the plan depends on but does not itself schedule —
another piece of work, a credential, a migration — is named here with its
current state, or it is a hidden dependency.

## 5. Failure modes & rollback

What happens if this stops halfway: partial data, old versions still live,
the irreversible step and its rollback path. If nothing here is irreversible,
say so explicitly.

## 6. Open questions

Decisions that belong to the user, listed plainly. Never silently answer one
inside a workstream — if you caught yourself guessing, it belongs here.
```

Keep it tight. A plan doc is read under pressure, mid-implementation; every
section earns its place or gets cut.

### 3. Hand back

Report the path and the two or three things most likely to be wrong with it —
the parts you are least sure of. Then offer the natural next step:

> Shred it? `/shred-plan docs/<slug>-plan.md`

Do not commit the doc unless asked.

## Rules that hold in any repo

Facts are verified before they are written down. Scope has two lists, never
one. Every workstream has a proof. Dependencies the plan needs but doesn't
schedule get named. Open questions get asked, not answered. The plan complies
with the repo's own rules — wrong branch model or wrong conventions in a plan
is a defect in the plan, not a style choice.
