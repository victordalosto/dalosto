---
name: hand-off
description: Make the current plan self-contained for a new agent with fresh context
argument-hint: [plan-file-or-task-folder]
---

Prepare the current plan for handoff to a new agent with fresh context.

The new agent will not have access to this conversation. Review the entire current chat and update the plan with every execution-relevant detail that exists only here, including:

- Decisions and their rationale
- Clarifications, assumptions, constraints, and user preferences
- Open questions and blockers
- Work already completed, the current state, and the exact next step
- Relevant file paths, symbols, commands, results, conventions, and discovered pitfalls
- Anything else the next agent would otherwise need to rediscover or ask about

If `$1` is provided, use it as the plan file or task folder. Otherwise, use the plan currently being discussed. If the target plan cannot be identified unambiguously, ask me for its path before editing.

Preserve the plan's existing structure and content. Merge the handoff details into the relevant sections, avoiding duplication. Do not implement the next step. Do not leave important context only in your final response, and do not add irrelevant conversation or secrets to the plan.

After updating it, re-read the plan as if you had no memory of this chat. Make sure a new agent can continue from the exact current state using only the plan and the repository.

Finish by stating which plan was updated and briefly summarizing the handoff information added.
