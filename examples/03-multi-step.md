# Flow 3: a multi-step change with clear requirements

Use this when the change spans **several tickets or layers**, but the requirements are already
settled. You do not need `/grill`; you need a spec so the tickets have an acceptance surface.

## Scenario

Add tags to the existing todo app:

- Each task has zero or more user-defined tags.
- Tags are normalized: trim, lowercase, max 32 characters, no duplicates per task.
- The add/edit form gets a tag picker with inline creation.
- Task rows show tag chips.
- The filter bar filters by one tag at a time.
- Tag management supports rename and delete; deleting removes the tag from all tasks.
- Existing tasks load with `tags: []`.
- Tests cover the reducer/selectors, the storage migration, and add/edit/filter integration.

Out of scope: nested tags, tag colors, backend sync.

## 0. Start clean

```bash
cd ~/code/todo-app
git switch main
git pull
git status --porcelain   # must be empty
opencode
```

## 1. State the requirements

Put the brief above in the conversation. Because `/to-spec` does **not** interview you, this is
the input it will synthesize. If a requirement is still fuzzy, stop and `/grill` that specific
question first.

## 2. Synthesize the spec

```
/to-spec
```

It reads the conversation and the existing code, then asks you to confirm the **testing seams**.
For this change, a good answer is:

- pure reducer/selector tests for tag normalization and filtering
- a storage migration test: old tasks gain `tags: []`
- one React Testing Library integration test: add a task → add a tag → filter by it

It publishes `.scratch/todo-tags/spec.md` with the problem statement, user stories,
implementation decisions, testing decisions, and out-of-scope.

Commit it:

```bash
git add .scratch/todo-tags/spec.md
git commit -m "docs: add tags spec"
```

## 3. Break the spec into tickets

```
/to-tickets .scratch/todo-tags/spec.md
```

It proposes a graph and quizzes you before publishing. A good breakdown:

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Tag model, normalization, storage migration, unit tests | — |
| 02 | Tag editor in the add/edit form | 01 |
| 03 | Tag chips on task rows + inline tag creation | 02 |
| 04 | Filter bar: single-tag filtering | 03 |
| 05 | Tag management: rename and delete | 01 |
| 06 | Multi-tag filter with AND semantics | 04, 05 |
| 07 | Empty states and responsive styling for tags | 03 |
| 08 | E2E smoke test + production build check | 06, 07 |

It asks:

- Is the granularity right?
- Are the blocking edges correct?
- Should anything be merged or split?

Approve it. It writes one file per ticket under `.scratch/todo-tags/issues/`, numbered in
dependency order, each with `Blocked by:` and `Status: ready-for-agent`.

Commit the tickets and confirm a clean tree:

```bash
git add .scratch/todo-tags
git commit -m "docs: add tags tickets"
git status --porcelain   # must be empty
```

## 4. Implement

```
/implement .scratch/todo-tags/spec.md
```

Then leave the repo alone. It will:

1. Build the task graph from the spec and tickets.
2. Create `todo-tags/integration` from `main`.
3. Run 01; merge it.
4. Launch 02 and 05 in parallel worktrees.
5. Flow the frontier: 03, then 04 and 07, then 06, then 08.
6. Run `mp-review-standards` and `mp-review-spec` on the integration branch.
7. Fix findings in a fresh worktree and merge the fix.
8. Mark tickets `done`, clean up worktrees, and report the branch.

Do not edit files, run git commands, or merge while it is running.

## 5. Review and land

```bash
git log --oneline main..todo-tags/integration
git diff main...todo-tags/integration
npm test
npm run build
```

If you made manual fixes after the run and want another independent pass:

```bash
git switch todo-tags/integration
/code-review main
```

Otherwise skip it; `/implement` already ran both review axes.

Merge and push yourself:

```bash
git switch main
git merge --no-ff todo-tags/integration
# git push origin main
```

## Why not `/grill`

There is no open design question: storage, normalization, filtering semantics, and scope are
already stated. `/to-spec` can synthesize directly.

If a real decision appears while writing the brief — for example, “should multi-tag filtering be
AND or OR?” — stop and `/grill` **that question**. Then return here.
