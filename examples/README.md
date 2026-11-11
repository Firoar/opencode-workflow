# Workflow examples

Four change-size flows, plus the full from-scratch run. Pick by **change size and ambiguity**, not
by ceremony.

| Flow | Use when | Start with |
|---|---|---|
| [From scratch](00-from-scratch.md) | New repo or feature with open design questions | `/setup` → `/grill` → `/to-spec` → `/to-tickets` → `/implement` |
| [Obvious fix](01-obvious-fix.md) | Typo, copy change, or a crash with one clear cause | Normal `build` agent → `/code-review` |
| [Small tweak](02-small-tweak.md) | One to three independent slices, requirements already clear | `/to-tickets` → implement |
| [Multi-step change](03-multi-step.md) | Several tickets or layers, requirements clear | `/to-spec` → `/to-tickets` → `/implement` |
| [Ambiguous feature](04-ambiguous.md) | Real design questions, multiple approaches | `/grill` → `/to-spec` → `/to-tickets` → `/implement` |

The examples use the **local markdown tracker** (`.scratch/`). With GitHub or GitLab, the flow is
the same; swap paths for issue numbers.

## Shared rules

- Run `/setup` once per repo, then commit `docs/agents/` and the `## Agent workflow` block in
  `AGENTS.md`.
- Keep one feature or change per session. Use `/handoff` when the context gets long.
- Commit the spec, tickets, glossary, and ADRs before `/implement`. It requires a clean checkout.
- Agents never push. Review the integration branch or diff, then push and merge yourself.
- `/code-review <base>` reviews **committed** changes only: `git diff <base>...HEAD`.
- For a tiny change, skip the workflow. Ceremony is not a quality signal.

## Moving between flows

- A "small fix" that spreads across modules or needs a design decision should be promoted to a
  small tweak, multi-step change, or ambiguous feature.
- An "ambiguous feature" that collapses to one obvious slice should be demoted. Do not grill a
  decision you have already made.
- If a design question appears while writing requirements, stop and `/grill` **that question**,
  then return to the flow. `/grill` is for uncertainty, not a required first step.
