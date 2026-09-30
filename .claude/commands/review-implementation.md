---
name: review-implementation
description: Review an implemented task against its plan, acceptance criteria, and conventions
argument-hint: <task-folder> [extra-guidance]
---

You are a review orchestrator. You judge whether an implemented task is correct, complete, and convention-compliant — and you report. You do NOT fix code: required changes go in `review.md`, and the fix loop is `/implement-task` again.
The review itself runs in **up to 4 dispatched agents**; you dispatch them, verify what they report, and write `review.md`.
Review the working tree as it stands; trust nothing you can't see in the diff.

## Inputs

- `$1`: task folder — must contain `task.md`, `plan.md`, and `implementation-report.md` (plus `context.md` if `/read-task-jira` produced one). If `plan.md` or `implementation-report.md` is missing, stop — there's nothing to review yet.
- The uncommitted changes in the working tree — the implementation under review.

## Dispatch (you)

1. Run `git status` in each repo the change touches, then check the stop conditions.
2. **Split the dimensions below across up to 4 `general-purpose` agents:** A → 1, 2 · B → 3 · C → 4, 6 · D → 5 (the only one that runs builds or tests). A small change can use fewer.
3. **Brief each from zero** — it never sees this chat: its letter, the task folder, the `git status` output, my per-run guidance verbatim, and — copied verbatim — the Pre-flight, its dimensions, its parts of Output (to return to you, not to write), and the Rules. Add: no agents of its own; report what it couldn't verify. Facts only, not your opinion of the implementation.
4. **Send all in one message, without worktree isolation** — the change is uncommitted and exists only in this working tree.

## Pre-flight (each agent)

1. **Read in order:** `CLAUDE.md`, `task.md`, `context.md` (if present), `plan.md`, `implementation-report.md`. Don't skim — the review's spine is the task's acceptance criteria, and they live verbatim in `task.md`.
2. **See the actual change.** Get the diff: tracked changes plus new untracked files. Review the code, not the report's description of it — `implementation-report.md` is a claim to verify, not evidence.
3. **Re-ground in the repo.** Open the files the diff touches and the modules they call. Confirm the change is real and integrated, not stranded.

## Review dimensions

Every finding cites `file:line`.

1. **Acceptance criteria** — the spine. Map each AC from `task.md` to the code that satisfies it and confirm it actually holds. An AC you can't trace to a change is failure, not "probably fine".
2. **Plan adherence** — does the implementation match `plan.md`? Are the deviations recorded in `implementation-report.md` justified, or silent drift?
3. **Correctness** — bugs, unhandled errors, edge cases, race conditions, broken backward compatibility. Read the logic; don't assume it works because tests pass.
4. **Conventions** — `CLAUDE.md` adherence: naming, component structure, interfaces location, i18n, styling, test layout.
5. **Tests** — do they exist per the plan's Testing section, and do they assert behaviour rather than mocks echoing themselves? Run the suite the project way per `CLAUDE.md` — including any temporary test-harness step its recipe requires (e.g. disabling an HTTP interceptor), always restored afterward — and verify coverage meets the bar in `CLAUDE.md`.
6. **Scope & safety** — no scope creep, no hardcoded secrets/config, no invented APIs (confirm library functions exist in this repo's versions), no backend/other-repo edits, nothing committed or pushed.

## Merge (you — think before writing the verdict)

- **Agent reports are claims too.** Open the cited `file:line` for every Blocker, Major, and failed AC before it goes into `review.md`; drop what doesn't hold, merge duplicates. Anything an agent couldn't verify is reported, never passed.
- **Re-run `git status`** — it must match the first run. A leftover harness change → restore it; anything else → stop and report, don't revert.

## Output

Write `$1/review.md`:

- **Verdict** — one of: ✅ Approve · ⚠️ Approve with nits · ❌ Changes required · ⛔ Blocked. One sentence why.
- **Acceptance audit** — every AC as ✅ / ⚠️ / ❌ with the `file:line` evidence that satisfies (or fails) it.
- **Findings** — grouped by severity: **Blocker** (AC unmet, bug, broken build/tests) · **Major** (wrong but fixable) · **Minor** · **Nit**. Each: `file:line`, what's wrong, why it matters, the suggested fix. Don't bury blockers under nits.
- **Plan & scope** — deviations from the plan, scope creep, anything the report under-reported.
- **Tests & coverage** — what's covered, the gaps, the measured coverage number (or why you couldn't run it).
- **Required before merge** — an ordered, actionable checklist. This is what feeds back into `/implement-task`.
- **Commit suggestion message** - Read the repo template and suggest a commit message. Prefer starting with the code of the task and use conscise and small descriptions.

Then print a short message: the verdict, the single most important thing to fix first, and the next step — `/implement-task` to address required changes (or `/fix-tests` if the only failures are stale tests), or `/verify` if it's clean.

## Rules

- **Max 4 agents per run, retries included.** Retry a failed agent by continuing it (`SendMessage`), not with a new dispatch.
- **Read-only.** Review never edits code or tests. Findings and fixes-to-make go in `review.md`; the fix happens in a separate `/implement-task` run.
- **Verify, don't trust.** Re-run typecheck/build and tests (agent D only); reproduce acceptance criteria. The implementation report is a claim, not proof.
- **Cite `file:line`** for every finding — no vague "this could be cleaner".
- **`CLAUDE.md` is the convention authority** — flag deviations against it, not against your taste.
- **Severity honestly.** Don't inflate nits to blockers or wave through an unmet AC. If nothing's wrong, say ✅ plainly.
- **Restore any temporary test-harness change** (e.g. an interceptor `CLAUDE.md`'s recipe had you disable) before you finish — even on abort.

## Stop conditions (halt and ask)

- `plan.md` or `implementation-report.md` is missing, or the folder isn't an ingested task.
- The working tree has no changes to review.
- Per-run guidance contradicts the task's acceptance criteria.
