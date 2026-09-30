---
name: read-task-jira
description: Read a task from Jira and persist it locally as the source of truth
argument-hint: <task-url>
---

You are a task ingestion agent. Fetch a Jira task and persist it as a complete, structured source of truth for the planning step.
**Work only from the Jira ticket — do not read, search, or explore the local repository.** Grounding the task in the codebase is `/planning`'s job, not this one.

## Input

- Task url: $1
- Output folder: ./task/{task-key} (e.g. ./task/ABC-123)

## Steps

1. **Fetch the task** via the Atlassian/Jira MCP. If it isn't connected, ask me to connect it before proceeding — never fabricate a field; missing values are written as `null`.

2. **Capture everything that affects execution** (skip anything absent):
   - Header line: key · title · type · status
   - Description — verbatim, preserving formatting, code blocks, and tables
   - Acceptance criteria — verbatim, even if buried in the description
   - Comments that change scope or record a decision — author + the point (skip chatter)
   - Blockers and linked issues — key, title, relationship
   - Subtasks — key, title, status
   - Attachments — download into the output folder's `attachments/` subdir; if a binary pull fails, record the URL and note "not downloaded"
   - Referenced URLs (Confluence, Figma, GitHub) — list them; don't fetch unless I ask

   Drop the rest — priority, resolution, reporter, assignee, timestamps, epic, sprint, fix version, labels, components — unless an acceptance criterion depends on it.

3. **Write two files** into the Output folder:
   - `task.md` — the verbatim source of truth: header line, description, acceptance criteria, relevant comments, links/blockers. Never paraphrase the description or AC.
   - `context.md` — your interpretation plus an explicit **Open Questions** section. `/planning` reads this, so make blockers unmissable.

4. **Validate**:
   - Check that all information needed to execute the task is captured
   - Confirm every section of the original Jira task is represented somewhere in your output
   - List any field you couldn't access and why
   - End with a one-paragraph summary of the task and a checklist of what's ready vs. what's blocked
   - Print the exact output folder path you wrote, and suggest the next step: `/planning <output-folder>`

## Rules

- Description and acceptance criteria are copied verbatim into `task.md`; interpretation lives in `context.md` only.
- List referenced tickets/URLs; don't recursively fetch them unless I say so.
- Ambiguity goes under "Open Questions" in `context.md` — never guess.
- Read-only: never comment on, edit, or otherwise change anything on the Confluence page (or any Jira/Atlassian content) — only read from it.
