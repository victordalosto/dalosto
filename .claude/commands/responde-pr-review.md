---
name: responde-pr-review
description: Respond to review comments on one of my PRs — apply the changes worth making, push back on the rest, and draft a reply for each comment.
argument-hint: <PR URL or number>
---

## Respond to PR review

You are a agent that will help me respond to code-review feedback on this pull request: $ARGUMENTS

## The Response Pattern

```
WHEN receiving code review feedback:

1. READ: Complete feedback without reacting
2. UNDERSTAND: Restate requirement in own words (or ask)
3. VERIFY: Check against codebase reality
4. EVALUATE: Technically sound for THIS codebase?
5. RESPOND: Technical acknowledgment or reasoned pushback
6. IMPLEMENT (if necessary): One item at a time, test each. If any implementaiton was done, run all tests and lint/checkstyle in the end to ensure that everything is still working.
```

## Guiding principle

Keeping the code working and stable matters more than satisfying every comment. Prefer small, safe, targeted edits. Don't refactor broadly or make sweeping changes just to address a minor or stylistic note. If a suggestion would risk breaking functionality, add churn out of proportion to its value, or isn't clearly an improvement, it's fine to leave the code as-is and explain why in the reply.

## Transport: `curl` + the GitHub API (there is no `gh` here)

**`gh` is not installed on this machine. Do not use it.** Talk to GitHub with plain `curl` against the REST + GraphQL API, authenticated with the `TOKEN_GITHUB` environment variable (a PAT with full `repo` scope that reads/writes private repos). **Reach for the API first for everything** — it's far more reliable than driving the web UI, even for private repos. The browser is only a fallback. These `curl` recipes assume the **Bash tool** (Git Bash), not PowerShell — run them there.


**Authorship caveat — read freely, but dont post anything**.

**Browser fallback.** If a call returns 401/403/404 that isn't just a wrong path, or I'd rather replies appear under my own name, fall back to the `claude-in-chrome` MCP (I'm logged into GitHub there). Its tools are deferred — load them in one `ToolSearch` call first (`select:mcp__claude-in-chrome__list_connected_browsers,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__tabs_context_mcp`), then `list_connected_browsers`; if it's empty, ask me to open Chrome with the extension before continuing.

## Steps

1. **Resolve the target and set up.** `$ARGUMENTS` is either a full URL (`https://github.com/{owner}/{repo}/pull/{n}`) or a bare number.
   - From a URL, parse `owner`, `repo`, `n`. From a bare number, infer `owner`/`repo` from the repo I'm in (`git config --get remote.origin.url`).
   - Find the **local clone** by git remote, not folder name. **Several repos have more than one clone sharing a remote** (branch-specific working copies). If more than one folder matches: prefer the clone already on the PR head ref, else one with a clean working tree; if still ambiguous, list the matches and ask me — don't silently pick the first. If nothing matches, tell me and offer to clone `git@github.com:{owner}/{repo}.git`.
   - Assign shell vars — **every command below uses them**:
     ```bash
     owner=…; repo=…; n=…
     H="Authorization: Bearer $TOKEN_GITHUB"
     API="https://api.github.com/repos/$owner/$repo"
     ```

   > **The core deliverable is the drafted replies (the Output section) — reading, assessing, and drafting need NO local checkout, so always produce them. Making code changes is a best-effort second phase that must never block the replies.** Only step 4 (code edits) touches the working tree and may be skipped; every other step runs on every invocation.

2. **Load every piece of review feedback** (capture the file + line each refers to):
   ```bash
   curl -s -H "$H" "$API/pulls/$n"                       # title, state, head/base refs, head.repo.full_name, author
   curl -s -H "$H" "$API/pulls/$n/comments?per_page=100" # inline comments: path, line/original_line, diff_hunk, id, in_reply_to_id, user
   curl -s -H "$H" "$API/pulls/$n/reviews?per_page=100"  # summary reviews: APPROVED / CHANGES_REQUESTED / COMMENTED + body
   curl -s -H "$H" "$API/issues/$n/comments?per_page=100"# general (non-inline) conversation comments
   ```
   Then get **resolved / outdated status and thread ids** via GraphQL (REST doesn't expose them). Build the body in a file to dodge quoting pain, then POST it:
   ```bash
   cat > q.json <<EOF
   {"query":"query{repository(owner:\"$owner\",name:\"$repo\"){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved isOutdated path line comments(first:30){nodes{databaseId author{login} body}}}}}}}"}
   EOF
   curl -s -H "$H" -H "Content-Type: application/json" -X POST https://api.github.com/graphql --data @q.json
   ```
   Parse JSON with `python` (jq may be absent). **What counts as an item to answer:** every inline review **thread**, every summary **review that has a non-empty `body`** (a CHANGES_REQUESTED/COMMENTED writeup), and every general **conversation comment** — dedup where a summary just restates its own inline comments, and group a multi-comment inline thread as one item. Then:
   - **Answer every reviewer — human or bot alike.** Bot accounts (`user.type == "Bot"` or a login ending in `[bot]` — `coderabbitai[bot]`, `sonarcloud[bot]`, `github-actions[bot]`, `dependabot[bot]`, Copilot, …) now post real review feedback, so treat their comments exactly like a human's: read, assess, and draft a reply for each. **Never skip an item just because a bot authored it** — and likewise never skip a human reviewer, even if their comment is emoji-heavy, terse, or says "revisão automática" / looks tool-generated. (A bot's `` ```suggestion `` block is still the reviewer's exact replacement — apply it per step 3.)
   - **Skip already-resolved threads** for drafting *new* replies (they're handled), and don't treat my own earlier replies as items — but still mention which ones you skipped as resolved (a one-line note under the block) so nothing looks silently dropped.
   - **file:line display:** use `line`; when it's null (outdated/collapsed diff), fall back to `original_line`, then `path`.
   - **Paging:** these endpoints cap at 100. If any list returns a full 100 (or GraphQL reports `hasNextPage`), page through (`Link: rel="next"` / GraphQL `after: endCursor`) before concluding you've seen everything.

3. **Assess each item.** Decide whether it's worth acting on — correctness issues, bugs, security, and clear improvements usually are; nitpicks, style preferences, out-of-scope asks, or risky changes often aren't. Apply the guiding principle. If an item is marked **outdated**, check whether the current code already resolves it first. If a comment body contains a <code>```suggestion</code> block, that's the reviewer's exact replacement for the commented lines — plan to apply it verbatim rather than retyping (the API reply endpoints don't commit suggestions; apply it locally).

4. **For items you'll fix with code, prepare the local clone.** This is the *only* part that touches the working tree, and it must never block the reply drafting — if it can't be done cleanly, mark those items as *proposed* and move on to step 6.
   - If the clone is **already on the PR head ref** (common — I'm usually mid-work on that very branch; check `git -C <folder> rev-parse --abbrev-ref HEAD`), just work in place. **A dirty tree is fine here — it's my in-progress work; do not stop, stash, or discard it.**
   - Only if it's on a **different** branch do you switch, and only on a clean tree: if `git -C <folder> status --porcelain` prints anything, don't switch — tell me (offer to stash) or just skip the edits and still draft replies. Fork-safe fetch: `git -C <folder> fetch origin "pull/$n/head:pr-$n" && git -C <folder> switch pr-$n`.
   - Never run `git reset --hard`, `git checkout -- .`, `git clean`, or `git stash drop`.
   - Make the smallest change that correctly addresses the feedback, scoped to what was asked. Then **verify per the repo's stack** (match the folder to its build tool in `CLAUDE.md`); for a big multi-module repo like `integration` (Maven), build/test only the **touched module**:
     ```bash
     mvn -q -pl <module> -am test        # Maven — just the affected module
     ./gradlew :<module>:test            # Gradle
     npm run lint && npm run test:ci     # web-app (React)
     ```

5. **For items you won't fix:** note a short, respectful reason (keeps behavior stable, out of scope, would add risk, current approach is intentional, etc.). **But mine the item for a useful action first** — even a false-positive often points at something cheap and worth doing, most commonly a **test scenario**. If the reviewer's concern is unfounded but the case they raise isn't covered, adding a small test that documents and guards that behavior (and proves the point) is usually worth it — do it, and say so in the reply.

6. **Draft one reply per item and ALWAYS produce the Output below** — the drafted replies are the deliverable, even if you made zero code changes or couldn't touch the repo. Natural, human tone, like a considerate teammate. **Match the reviewer's language** — pt-BR when they wrote Portuguese, English when they wrote English. If, after filtering, nothing actually needs a reply, say so plainly and show what feedback exists (resolved / already-answered) — never return empty.

## Output

**The response is the line-by-line reply block — NOT a table.** Give me one numbered entry per item, one after another, in exactly this format:

```
<n> - <short description of the comment> - [<status>]
<what was done: the concrete action taken, or the reason if not>
```

- `<status>` is `[Fixed]`, `[False-positive]`, or a short verdict such as `[Won't fix — out of scope]` / `[Intentional]` / `[Won't fix — adds risk]`. If you rejected the concern but still added a test (or other cheap useful item) it raised, say so — e.g. `[False-positive — added test]`.
- One blank line between items; keep each entry to a line or two. Number them in the order the comments appear on the PR.
- Write the description/action prose in the **reviewer's language** (pt-BR when they wrote Portuguese); the status tag in brackets can stay English.
- This whole block is what gets posted to GitHub — don't wrap it in a table or add commentary inside it.

## Response Guidance
Only respond in technical and professional terms. Prefer brief and accurate responses over long and verbose ones.
Be direct and straightforward. Only states what is necessary and show that you heard the feedback.
Its not necessary to thank or apologise the reviewer. State the correction factually and move on.


## Example:

```
1 - Validation error message change - [Fixed]
Ajustei a mensagem em CnpjValidator para "CNPJ inválido" e cobri com teste.

2 - Possível NPE quando a lista vem vazia - [False-positive — added test]
O fluxo já trata lista vazia, então não muda a lógica; mesmo assim adicionei um teste cobrindo esse cenário para deixar o comportamento garantido.

3 - Broaden the regex to accept alphanumerics - [Won't fix — adds risk]
Mudaria o comportamento de validação para outros fluxos; mantido de propósito.
```

After the block, add a few plain lines (not a table) for me: **Files changed:** …, **Verification:** … (say plainly if anything failed), and a **Posting map** of item → `comment_id` (numeric `id` of each thread's **root** inline comment — what `/replies` needs). If any reviewer is **CHANGES_REQUESTED**, add one line noting merge is blocked.

## Posting

**Don't post to GitHub or push commits.** I'll handle committing and pushing the code. It should produce a **consolidated reply block** above. When I approve it:

- **Default:** hand me the block to paste myself (so it's authored by me, not the bot).


**Don't mutate the PR in any other way** — no resolving/unresolving threads, re-requesting review, editing/closing the PR, approving/dismissing reviews, labeling, or merging — unless I ask for that specific action. Two exceptions I may ask for:
- **Re-request review** after a CHANGES_REQUESTED reviewer, once I confirm the fixes are pushed: `curl -s -X POST -H "$H" "$API/pulls/$n/requested_reviewers" --data '{"reviewers":["<login>"]}'`.
- **Resolve a thread** after replying: GraphQL `resolveReviewThread(input:{threadId:"<id>"})`, where `<id>` is the **thread-level** node `id` from step 2 (the `PRRT_…`/`MDIz…` value — **not** a comment's numeric `id`/`databaseId`).
