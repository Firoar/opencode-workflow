# Flow 2: a small, well-understood tweak

Use this when the change is **one to three independent slices** and the requirements are already
clear. You do not need a spec or `/grill`; tickets are enough.

## Scenario

Two small, independent tweaks to the todo app:

1. Show the number of remaining tasks in the header.
2. Add a **Clear completed** button.

Neither depends on the other, and there is no design debate.

## 0. Start clean

```bash
cd ~/code/todo-app
git switch main
git pull
git status --porcelain   # must be empty
opencode
```

## 1. Describe the tweak

```text
Two small changes:

1. Show the number of remaining (not done) tasks in the header, e.g. "3 tasks left".
2. Add a "Clear completed" button that removes all done tasks. Disable it when
   there are no completed tasks.

No other behaviour changes.
```

## 2. Break it into tickets

```
/to-tickets
```

It works from the conversation because no spec path is given. It proposes a numbered breakdown
and asks:

- Is the granularity right?
- Are the blocking edges correct?
- Should anything be merged or split?

A reasonable result:

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Remaining-task count in the header | — |
| 02 | Clear completed button, disabled when empty | — |

Both can run in parallel. It writes one file per ticket under
`.scratch/todo-tweaks/issues/`, each with `Blocked by:` and
`Status: ready-for-agent`.

Commit them and confirm a clean tree:

```bash
git add .scratch/todo-tweaks
git commit -m "docs: add todo tweaks tickets"
git status --porcelain
```

## 3. Implement

### Option A — direct build (recommended for one or two tickets)

Create a branch first so the review diff is clean:

```bash
git switch -c tweak/todo-tweaks
```

Use the normal `build` agent for both changes, run the verification commands, then commit:

```bash
npm test
npm run lint
npx tsc --noEmit
git add -A
git commit -m "feat: add remaining count and clear completed"
```

This is faster than spinning up worktrees for two small edits.

### Option B — `/implement` (worktree orchestration)

If you want the parallel machinery anyway:

```
/implement .scratch/todo-tweaks/issues/
```

It reads the ticket files, builds the graph, creates an integration branch
(`todo-tweaks/integration`), runs both tickets in separate worktrees, merges them serially, and
runs the review axes. Because there is no separate spec, point the Spec review at the ticket
bodies as its acceptance surface.

If your installed version asks for a spec instead of accepting the ticket set, either point it at
the ticket directory or fall back to Option A. For two tiny slices, Option A is usually the better
trade.

## 4. Review and land

For Option A:

```bash
git log --oneline main..tweak/todo-tweaks
/code-review main
```

Then merge and push:

```bash
git switch main
git merge --no-ff tweak/todo-tweaks
# git push origin main
```

For Option B, review `todo-tweaks/integration` first:

```bash
git switch todo-tweaks/integration
git log --oneline main..HEAD
git diff main...HEAD
/code-review main
```

Then merge that branch.

## When to promote this flow

Move up to [multi-step](03-multi-step.md) if:

- The change spans more than three tickets or several layers.
- You need acceptance criteria that a ticket body cannot carry.
- You are unsure how the pieces fit together.

Move up to [ambiguous](04-ambiguous.md) if a real design question appears. Move down to
[obvious fix](01-obvious-fix.md) if it turns out to be a one-line change.
