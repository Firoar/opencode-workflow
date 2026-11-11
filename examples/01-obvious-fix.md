# Flow 1: an obvious fix

Use this when the change is a single, unambiguous fix: a typo, wrong copy, or a crash with one
clear cause. No spec, no tickets, no worktrees, no `/grill`.

## Scenario

Deleting the last remaining task throws:

```text
Cannot read properties of undefined (reading 'id')
```

Expected: the list becomes empty and shows the empty state. One cause, one fix.

## 0. Start clean

```bash
cd ~/code/todo-app
git switch main
git pull
git status --porcelain   # must be empty
opencode
```

`/setup` already ran in this repo, so there is nothing to configure.

## 1. Make a branch

A branch keeps the review diff clean and makes the change easy to discard.

```bash
git switch -c fix/empty-list-crash
```

## 2. Describe the fix

Use the normal `build` agent — no `/grill`, no `/to-spec`.

```text
Bug: deleting the last remaining task throws "Cannot read properties of undefined
(reading 'id')". Expected: the list becomes empty and shows the empty state.

Fix it and add a regression test that deletes the last task.
```

The agent should:

1. Reproduce the bug with a failing test.
2. Fix the cause, not the symptom.
3. Run the commands in `docs/agents/verification.md`.
4. Report the diff and the test result.

## 3. Verify locally

```bash
npm test
npm run lint
npx tsc --noEmit
```

Use whatever `docs/agents/verification.md` records for this repo.

## 4. Commit

```bash
git add -A
git commit -m "fix: handle deleting the last task"
```

`/code-review` reviews committed changes only, so commit before reviewing.

## 5. Review

Optional for a typo; useful for a bug fix:

```bash
/code-review main
```

It runs the Standards axis and, because there is no spec, the Spec axis replies:

```text
No spec available — Spec axis skipped.
```

## 6. Land

```bash
git switch main
git merge --no-ff fix/empty-list-crash
# git push origin main
```

## When to promote this flow

Stop and move up a flow if:

- The fix touches a schema, API, or several modules.
- The bug has more than one plausible cause and needs investigation.
- You need more than one ticket or want acceptance criteria.
- A design choice appears ("where should this state live?").

A quick promotion path is [small tweak](02-small-tweak.md) for one or two slices, or
[multi-step](03-multi-step.md) if the fix grows into a small feature.
