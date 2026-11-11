# From scratch: building a todo app

A concrete, end-to-end run through the commands — from an empty repo to a merged
feature. This example uses the **local markdown tracker** so no GitHub/GitLab
account is needed. With GitHub or GitLab the flow is identical; only the
references change from file paths to issue numbers.

This is the full path: `/setup` → `/grill` → `/to-spec` → `/to-tickets` →
`/implement` → review. See [README.md](README.md) for the smaller entry points
when you do not need the whole chain.

## The shape of the run

```
once per repo:  /setup  → commit
per feature:    /grill → /to-spec → /to-tickets → /implement → review → merge
when context is long: /handoff
```

## 0. Scaffold the repo

The workflow needs a git repo with at least one commit, because `/implement`
creates worktrees from it.

```bash
npm create vite@latest todo-app -- --template react-ts
cd todo-app
npm install
npm install -D vitest jsdom @testing-library/react @testing-library/jest-dom
# configure vitest + a test script in package.json
git init
git add -A
git commit -m "chore: scaffold vite react ts app"
opencode
```

Make sure the commands you intend to record actually work:

```bash
npm run lint
npx tsc --noEmit
npm test
```

`/setup` records these, and every implementer and merger runs them before
reporting done.

## 1. One-time repo setup

```
/setup
```

It interviews you, one section at a time:

- **Tracker:** no remote → choose **local markdown** (`.scratch/`).
- **Triage labels:** accept the defaults (`ready-for-agent`, etc.).
- **Domain docs:** single-context (`GLOSSARY.md` + `docs/adr/`).
- **Verification:** confirm install, lint, typecheck, test, and "never run" —
  e.g. `npm install`, `npm run lint`, `npx tsc --noEmit`, `npm test`, and never
  `npm run dev` (watch mode).

It writes `docs/agents/*.md` and an `## Agent workflow` block in `AGENTS.md`.
If `AGENTS.md` already exists, only that block is added or updated; the rest of
the file is left alone. If `CLAUDE.md` exists, that file is edited instead.

Commit the setup so worktrees and implementers can see it:

```bash
git add AGENTS.md docs/agents
git commit -m "chore: configure agent workflow"
```

## 2. Grill the idea

Just run the command — it switches the session to `mp-grill` automatically.

```
/grill I want to build a local-first todo app. Single user, no backend. Tasks have a title, optional notes, priority (low/medium/high), an optional due date, and a done toggle. I need filters by status and priority, plus search. Ship as a static site.
```

It asks the frontier in rounds. A condensed first round might look like:

> **Q1 — Persistence:** localStorage vs IndexedDB vs backend?
> ➡️ localStorage; the dataset is small and synchronous.
>
> **Q2 — Stack:** React + TypeScript + Vite, state in `useReducer` + context,
> no extra state library?
> ➡️ yes.
>
> **Q3 — Due dates:** date-only calendar dates, or timestamps with timezone?
> ➡️ date-only.
>
> **Q4 — Ordering:** manual drag-and-drop, or automatic sort by
> priority/due date?
> ➡️ manual order; filters don't reorder.
>
> **Q5 — Recurring tasks:** out of scope for v1?
> ➡️ yes, out of scope.

You answer, add "also dark mode", and it runs another round on dark mode
(system preference + persisted toggle, CSS variables). As decisions settle it
writes:

- `GLOSSARY.md` — Task, Priority, Due date, View, Filter, etc.
- `docs/adr/0001-localstorage-persistence.md`
- `docs/adr/0002-date-only-due-dates.md`

Commit the decisions:

```bash
git add GLOSSARY.md docs/adr
git commit -m "docs: record todo app domain decisions"
```

## 3. Turn the conversation into a spec

```
/to-spec
```

No interview — it synthesizes what is already in the conversation. It asks you
to confirm the **testing seams**, e.g.:

- pure reducer/selector tests for the task store
- one React Testing Library integration test for add + list + toggle
- no new seam for drag-and-drop; test the reorder function directly

It then publishes `.scratch/todo-app/spec.md` with problem statement, user
stories, implementation decisions, testing decisions, and out-of-scope.

Commit the spec:

```bash
git add .scratch/todo-app/spec.md
git commit -m "docs: add todo app spec"
```

## 4. Break the spec into tickets

```
/to-tickets .scratch/todo-app/spec.md
```

It proposes a graph and quizzes you before publishing anything. A good
breakdown might be:

| #  | Ticket                                                       | Blocked by              |
|----|--------------------------------------------------------------|-------------------------|
| 01 | Task model + reducer + localStorage persistence + unit tests | —                       |
| 02 | App shell + add-task form + task list                        | 01                      |
| 03 | Toggle done + delete task                                    | 02                      |
| 04 | Edit title and notes                                         | 02                      |
| 05 | Priority and due date fields                                 | 02                      |
| 06 | Filter by status and priority                                | 03, 05                  |
| 07 | Search                                                       | 02                      |
| 08 | Drag-and-drop reorder                                        | 02                      |
| 09 | Dark mode                                                    | 02                      |
| 10 | Empty states + responsive polish                             | 02                      |
| 11 | E2E smoke test + production build check                      | 06, 07, 08, 09, 10      |

It asks: is the granularity right? are the blocking edges correct? should
anything be merged or split? You approve the breakdown.

It writes one file per ticket under `.scratch/todo-app/issues/`, numbered in
dependency order, each with `Blocked by:` and `Status: ready-for-agent`.

Commit the tickets and confirm a clean tree:

```bash
git add .scratch/todo-app
git commit -m "docs: add todo app tickets"
git status --porcelain   # must be empty before /implement
```

This graph is deliberate: after 01 and 02 land, **seven tickets are unblocked
at once** — that is the parallelism `/implement` exploits.

## 5. Implement

```
/implement .scratch/todo-app/spec.md
```

Then **leave the repo alone**. It will:

1. Read the spec and build the task graph.
2. Create `todo-mvp/integration` from `main`.
3. Create worktrees under `~/.opencode-work/todo-app/todo-mvp/wt/`.
4. Run 01, merge, run 02, merge — then launch 03, 04, 05, 07, 08, 09, 10 in
   parallel.
5. As each finishes, merge it serially; launch 06 when 03 and 05 land; finish
   with 11.
6. Run `mp-review-standards` and `mp-review-spec` on the integration branch.
7. Fix findings in one more worktree.
8. Mark each ticket `Status: done`, clean up worktrees, and report the branch.

Do not edit files, run git commands, or merge anything while it runs. Answer
questions if asked; otherwise wait for completion. The orchestrator never
pushes.

## 6. Review and land

Inspect it yourself:

```bash
git log --oneline main..todo-mvp/integration
git diff main...todo-mvp/integration
npm test
npm run build
```

If you made manual fixes and want another independent pass:

```bash
git switch todo-mvp/integration
/code-review main
```

Otherwise skip it — `/implement` already ran both review axes.

Then merge and push yourself, because the agents never push:

```bash
git switch main
git merge --no-ff todo-mvp/integration
# git push origin main   # if you have a remote
```

Switch back to the `build` agent for ordinary work. The next feature starts a
fresh session with `/grill`; `/setup` is not needed again.

## The entire sequence

```
/setup
# commit docs/agents + AGENTS.md

/grill I want a local-first todo app...
# answer rounds; commit GLOSSARY.md + docs/adr

/to-spec
# confirm testing seams; commit .scratch/todo-app/spec.md

/to-tickets .scratch/todo-app/spec.md
# approve graph; commit .scratch/todo-app/issues

/implement .scratch/todo-app/spec.md
# wait

# review diff, test, merge, push
```

## Rules that make or break the run

- **Commit everything before `/implement`.** It requires a clean checkout, and
  worktrees branch from committed state.
- **Spend your time on the ticket graph.** Its shape decides whether you get one
  implementer or seven in parallel.
- **Maximize the frontier.** Independent vertical slices run concurrently; a
  linear chain serializes the whole run.
- **One feature per session.** Use `/handoff` when the context gets long.
- **One `/implement` per repo at a time.** Merges are deliberately serialized.
- **Accurate `verification.md`.** Wrong commands produce "done" tickets that
  are not actually done.
- **Human gates stay human:** spec seams, ticket breakdown, final push/merge.
