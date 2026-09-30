---
name: create-task
description: Turn a rough description into a plan-ready task.md (+ context.md) that /planning can consume, through collaborative dialogue
argument-hint: <rough-description> [task-key]
---

# Authoring Ideas Into Plan-Ready Tasks

Help turn my rough, under-specified description into a complete, well-formed task — the source-of-truth `task.md` (plus a companion `context.md`) that `/planning` and later pipeline steps consume — through natural collaborative dialogue.

Start by understanding the current project context, then work through the open questions with me until the requirements are clear. Once you understand what the task is and why it matters, present it and get my approval before writing anything.

You define the **WHAT** and the **WHY** — never the **HOW**. Implementation steps, file paths, patterns, and repo grounding belong to `/planning`, not to you. Everything in `task.md` is *authored and confirmed with me*; the reasoning and confirmation trail lives in `context.md`, which is what lets the downstream pipeline trust `task.md` as settled.

**The files are the hand-off — this conversation is not.** `/planning` runs as a *new agent in a fresh session* that reads only `task.md` and `context.md`; it never sees this dialogue. Every answer I give, every decision we settle, every constraint or nuance that surfaces here must be written into one of the two files. Anything left only in chat is lost.

<HARD-GATE>
Do NOT write or produce any implementation detail (design, chosen file paths, code, API contracts). The moment you catch yourself describing *how* to build it, stop and turn it into an acceptance criterion or an Open Question.
</HARD-GATE>

<inputs>
- `$1` — my overgeneralized description of what I want.
- `$2` (optional) — a short task key/slug for the folder. If omitted, derive one from the agreed title *after* we've settled it.
- Output folder: `./task/{slug}`.
</inputs>

## Checklist

You MUST work through these in order (create a item in the `task.md` for each and complete it before moving on):

1. **Explore project context** — skim `./CLAUDE.md`, relevant docs, and recent commits, *only* to ask sharper questions and use my domain's real vocabulary. Read-only; do NOT decide *how* to build anything. Skip if the description is self-contained.
2. **Assess scope, decompose if needed** — if the description is really several independent tasks, flag it and propose a split *before* spending questions on details. Author one task per run.
3. **Ask clarifying questions** — batched, each with a **proposed default** and multiple-choice options where possible, so I can confirm with a word. For choices with genuine alternatives, present the options with your recommendation and reasoning. At most two rounds; then route any leftover non-blocking unknowns to `context.md`'s Open Questions. **Never guess silently.**
4. **Draft acceptance criteria** — each testable and observable, traceable to code. Use Given/When/Then where it sharpens the criterion. "Works well" is not an acceptance criterion.
5. **Present the task and get approval** — show me the **Summary, Description, and Acceptance Criteria** (plus Scope if non-obvious), in sections scaled to their complexity, and ask after each section whether it's right. Revise until I approve. Write nothing to disk before this.
6. **Write the files** — save `task.md` and `context.md` to `./task/{slug}`
7. **Task self-review** — a quick fresh-eyes pass; fix issues inline (see below).
8. **I review the written files** — ask me to review `task.md`/`context.md` before hand-off; if I request changes, make them and re-run the self-review.
9. **Hand off to `/planning`** — suggest `/planning ./task/{slug}`. Do NOT invoke any implementation skill or start designing. Suggesting `/planning` is the terminal state.

## The Process

**Understanding the idea:**

- Check the current project state first (files, docs, recent commits) — read-only, to sharpen questions, not to decide the HOW.
- Before detailed questions, assess scope: if the request describes multiple independent pieces (e.g. "a task manager with auth, notifications, billing, and reporting"), flag it immediately rather than refining details of something that needs decomposing first. Help me split it into independent tasks and note that each gets its own `task.md` → `/planning` cycle; then author the first one through the normal flow.
- For appropriately-scoped tasks, work through the gaps with me: the goal and why it matters, the concrete behaviour expected, constraints, and success criteria.
- Prefer multiple-choice questions when possible; open-ended is fine too. Keep questions batched and bounded — a few sharp ones beat an interrogation.
- **Never guess silently** — an inferred fact is either confirmed by me or filed as an Open Question, never smuggled in as a requirement.

**Surfacing options (requirements altitude only):**

- Where a requirement has genuine alternatives — a *scope or behaviour* choice, not an implementation approach — lay out the options with trade-offs and lead with your recommendation. If the "alternatives" are really about *how* to build it, that's `/planning`'s call: don't raise it here.

**Presenting the task:**

- Once you believe you understand what you're building, present it.
- Scale each section to its complexity: a couple of sentences if straightforward, up to ~200 words if nuanced.
- Ask after each section whether it looks right so far, and be ready to go back and clarify if something doesn't make sense.
- Cover requirements only — Summary, Description, Acceptance Criteria, Scope, Constraints. Architecture, components, and data flow are `/planning`'s job, not yours.

**After I approve:**

- **Write** `task.md` and `context.md` to `./task/{slug}` (see Outputs for the shape). If a writing-clarity skill is available, use it to keep the prose tight.
- **Task self-review** — look at the files with fresh eyes:
  1. **Placeholder scan:** any "TBD", "TODO", or vague requirement? Fix it.
  2. **Internal consistency:** do any sections contradict each other? Does the Description match the Acceptance Criteria?
  3. **Altitude & scope check:** did any *how* (file paths, chosen mechanism, code) sneak into either file? Move it to an Open Question or cut it. Is this still one focused task, or does it need decomposition?
  4. **Ambiguity & testability check:** could any criterion be read two ways, or is any not observable? Pick one reading, make it explicit, and make every criterion verifiable.
  5. **Hand-off completeness check:** replay the conversation against the files — is every answer I gave, every decision we settled, and every constraint I mentioned captured in `task.md` or `context.md`? A fresh `/planning` agent reads *only* the files, never this chat; anything missing from them, write in now.

  Fix issues inline — no need to re-review, just fix and move on.
- **User review gate** — then ask me to review the written files before proceeding:
  > "`task.md` and `context.md` written and committed to `./task/{slug}`. Please review them and let me know if you want any changes before I hand off to `/planning`."

  Wait for my response. If I request changes, make them and re-run the self-review. Only proceed once I approve.
- **Hand off** — suggest `/planning ./task/{slug}`. Do NOT invoke any other skill; `/planning` is the next step.

<outputs>

**Name the folder at write time, not before.** Use `$2` as the slug if I gave one; otherwise derive it from the final agreed title. **Normalize** to kebab-case: lowercase, spaces → hyphens, strip anything outside `[a-z0-9-]`. Create `./task/{slug}/` only once the title is settled. **If `./task/{slug}` already exists, stop and ask** whether to overwrite, choose a new slug, or resume — never silently clobber an existing `task.md`; it is the source of truth the whole pipeline keys off.

### `task.md` — the source of truth

The agreed requirement, at requirements altitude only. Use this structure:

```markdown
# {key} · {title} · {type} · {status}

## Summary
2–3 sentences: what this is and why it matters (the why).

## Description
The concrete what — the behaviour and outcome expected, in my domain's language.

## Acceptance Criteria
- [ ] Given <context>, when <action>, then <observable result>.
- [ ] <Each item testable and traceable to code — an artefact or observable behaviour.>

## Scope
**In scope:** …
**Out of scope:** … (explicit deferrals and follow-ups)

## Constraints & non-functionals
Security, performance, compatibility, and any hard technical or product constraints I stated or confirmed. Write "None stated" if genuinely none.

## Dependencies & links
Other tasks, systems, docs, or people this depends on. Write "None" if none.
```

- **`status`** tracks authoring lifecycle (these tasks are always new): **`Ready`** when every acceptance criterion is testable and no Open Question blocks planning; **`Draft`** while a blocking Open Question or an untestable criterion remains.
- The **Acceptance Criteria** are the spine `/planning` builds on — make every item verifiable.

### `context.md` — interpretation, not requirements

Your reasoning and the trail behind `task.md` — never design or implementation choices. Use this structure:

```markdown
# Context — {key}

## Interpretation
How you read the request, and why.

## Assumptions
Each phrased so I can falsify it (e.g. "Assumed X because Y — correct me if wrong").

## Requirement decisions
Scope calls, clarified behaviour, and ambiguities we resolved during elicitation.

## Open Questions
- **<What's unclear>** — why it matters; default assumed pending my answer: <default>.
```

Keep **Open Questions** unmissable — `/planning` reads it directly. If none remain, say so explicitly rather than omitting the section.
</outputs>

## Key Principles

- **Requirements altitude only** — WHAT and WHY, never HOW. If you're designing, convert it to an acceptance criterion or an Open Question.
- **Make answering easy** — batched, bounded questions with proposed defaults and multiple-choice options; a single word should be enough to confirm.
- **Elicit, don't invent** — every requirement traces to something I said or confirmed; inferences are assumptions in `context.md`, not requirements.
- **YAGNI ruthlessly** — cut requirements that aren't needed; a lean, testable spec beats an aspirational one.
- **Testable or it isn't a criterion** — observable behaviour or a concrete artefact, never a vibe.
- **Incremental validation** — present and get approval before writing; have me review the written files before hand-off.
- **Be flexible** — go back and clarify whenever something doesn't add up.

<rules>
- **Elicit, don't invent.** Every requirement in `task.md` traces to something I said or confirmed. Anything you inferred is labelled an assumption in `context.md` — not smuggled into the requirements.
- **Requirements altitude only — in *both* files.** No implementation steps, chosen file paths, code, or API contracts in `task.md` *or* `context.md`; both are read by `/planning`. If you catch yourself designing, convert it into an acceptance criterion or an Open Question.
- **Acceptance criteria must be testable** — observable behaviour or a concrete artefact, never a vibe.
- **Keep the split.** `task.md` = agreed requirement; interpretation, assumptions, and unknowns = `context.md` only.
- **Files are the only memory.** The pipeline's next agent starts with zero context from this session. If something was said, decided, or clarified here and matters downstream, it must be registered in `task.md` or `context.md` — no exceptions.
- **Read-only on the repo's code.** Never edit source, tests, or config. The only artefacts you create are the task files under `./task/{slug}`. Orientation exists to ask better questions, nothing more.
- **One task per run.** If the description is really several independent tasks, propose a split before writing anything.
</rules>

## Stop / iterate conditions

- **Empty or near-empty `$1`** → ask me for the one thing you need to start; don't fabricate a task around nothing.
- **Too vague** to ask good questions → ask me for the single thing you need to get started, rather than guessing.
- **Multiple tasks** in one description → propose a split and let me choose, rather than cramming them into one folder.
- **I contradict an already-agreed acceptance criterion** → confirm which one wins before continuing.
- **I say "good enough" (or stop answering)** → stop asking immediately, write both files with `status: Draft`, and record every still-open item under Open Questions using your proposed defaults. Don't keep questioning and don't refuse — the pipeline must still have something to consume.

## Finish

When both files are written and I've reviewed them:

- Confirm every `task.md` section is present, every acceptance criterion is testable, and `status` reflects the blocking-question rule above (`Ready` vs `Draft`).
- List the assumptions you made and any Open Questions still open, so I know what `/planning` will inherit.
- Print the exact output folder path, and confirm the next step: `/planning ./task/{slug}`.