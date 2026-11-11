# Flow 4: an ambiguous feature

Use this when there are **real design questions**: several plausible models, unclear scope, or
decisions that would be expensive to reverse. Start with `/grill`, not `/to-spec`.

## Scenario

Add recurring tasks to the todo app:

```text
I want recurring tasks: daily, weekly, monthly. Completing one should schedule
the next. I also want to be able to skip an occurrence.
```

That sounds clear until you ask what “monthly” means at month-end, whether editing changes one
occurrence or the series, and what happens to missed occurrences. Those are the branches
`/grill` resolves.

## 0. Start clean

```bash
cd ~/code/todo-app
git switch main
git pull
git status --porcelain   # must be empty
opencode
```

## 1. Grill the change

```
/grill I want recurring tasks: daily, weekly, monthly. Completing one should schedule the next. I also want to skip an occurrence.
```

It asks the frontier in rounds. A condensed first round:

> **Q1 — Recurrence rules:** preset daily/weekly/monthly plus “every N days/weeks”, or a full
> RRULE implementation?
> ➡️ Presets plus every-N; no RRULE in v1.
>
> **Q2 — Date arithmetic:** local calendar dates, or UTC timestamps?
> ➡️ Local calendar dates, consistent with ADR-0002.
>
> **Q3 — Completion:** completing an occurrence materializes the next one. Do missed occurrences
> auto-create retroactively?
> ➡️ No. Completion schedules the next future date; missed dates show as overdue.
>
> **Q4 — Editing:** does editing change this occurrence or the whole series?
> ➡️ Series only in v1, plus an explicit “skip this occurrence” action.
>
> **Q5 — End condition:** never, until a date, or after N occurrences?
> ➡️ Until a date.
>
> **Q6 — Out of scope:** notifications/reminders, complex RRULE, shared lists?
> ➡️ Yes, all out of scope.

You answer, then add: “What if the next occurrence already exists because I reopened a completed
task?” That reshapes the tree, so it asks another round:

> **Q7 — Duplicate prevention:** materialize the next occurrence idempotently by series ID and due
> date?
> ➡️ Yes.
>
> **Q8 — Reopen behaviour:** reopening a completed occurrence must not materialize a second next
> occurrence.
> ➡️ Yes; only the first completion materializes, and the series records it.
>
> **Q9 — Month-end and leap year:** “monthly” from Jan 31 should clamp to the last day of the
> target month, not overflow into March.
> ➡️ Yes.

As decisions settle, it writes:

- `GLOSSARY.md` — **Series**, **Occurrence**, **Recurrence rule**, **Skip**.
- `docs/adr/0003-recurring-tasks-are-series.md`
- `docs/adr/0004-date-only-recurrence-arithmetic.md`

Commit them:

```bash
git add GLOSSARY.md docs/adr
git commit -m "docs: record recurrence decisions"
```

Notice what the grill prevented: a UTC model, retroactive occurrences, per-occurrence editing, and
a full RRULE parser. Each would have changed the data model and UI.

## 2. Synthesize the spec

```
/to-spec
```

It asks you to confirm the testing seams. Good seams for this feature:

- pure `nextOccurrence(rule, fromDate)` calculator, including month-end and leap-year cases
- completion materialization: first completion creates the next occurrence, reopen does not
- a React Testing Library test for the recurrence picker and the task-row badge
- no new seam for the badge itself; test the rendered text

It publishes `.scratch/todo-recurrence/spec.md`.

Commit:

```bash
git add .scratch/todo-recurrence/spec.md
git commit -m "docs: add recurrence spec"
```

## 3. Break the spec into tickets

```
/to-tickets .scratch/todo-recurrence/spec.md
```

A good graph:

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Recurrence rule model + next-date calculator + boundary tests | — |
| 02 | Completion materialization + series identity + idempotency tests | 01 |
| 03 | Recurrence picker in the add/edit form | 01 |
| 04 | Recurrence badge on task rows | 03 |
| 05 | Skip occurrence action | 02, 03 |
| 06 | End condition (until date) + validation | 01 |
| 07 | Month-end and leap-year edge-case tests | 01 |
| 08 | E2E smoke test + production build check | 04, 05, 06, 07 |

Approve the granularity and blocking edges, then commit:

```bash
git add .scratch/todo-recurrence
git commit -m "docs: add recurrence tickets"
git status --porcelain   # must be empty
```

## 4. Implement

```
/implement .scratch/todo-recurrence/spec.md
```

It creates `todo-recurrence/integration`, runs 01, then fans out 02, 03, 06, and 07 in parallel
worktrees. As those land, 04 and 05 become unblocked, then 08. It merges serially, reviews both
axes, fixes findings, closes tickets, and cleans up worktrees.

Do not edit files or run git commands while it runs.

## 5. Review and land

```bash
git log --oneline main..todo-recurrence/integration
git diff main...todo-recurrence/integration
npm test
npm run build
```

Optional second review after manual fixes:

```bash
git switch todo-recurrence/integration
/code-review main
```

Then merge and push yourself:

```bash
git switch main
git merge --no-ff todo-recurrence/integration
# git push origin main
```

## Why start with `/grill`

Without it, the agent would have guessed at least one of these:

- UTC timestamps instead of local dates
- retroactive occurrences for missed dates
- editing a single occurrence instead of the series
- a full RRULE parser instead of presets
- month-end overflow into the next month

Those are not implementation details; they are product decisions. `/grill` turns them into
explicit answers, then records them in the glossary and ADRs so `/to-spec`, `/to-tickets`, and
`/implement` do not re-litigate them.

If the conversation gets long before `/to-spec`, run `/handoff` and continue in a fresh session.
