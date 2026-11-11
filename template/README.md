# opencode workflow commands

Seven slash commands ported from [mattpocock/skills](https://github.com/mattpocock/skills) into
native opencode commands + agents. Each is **fully self-contained** — no skill files, no
cross-references. The originals are not needed at runtime.

This README ships with the installable payload. The workflow repo keeps the source in `template/`
and deliberately has no `.opencode/`, so opencode does not load the workflow into the workflow
repo itself. The installer copies the payload into target repos as `.opencode/`.

## The commands

| Command | What it does | Agent | Model role |
|---|---|---|---|
| `/grill` | Round-by-round interview that stress-tests a plan, writing `GLOSSARY.md` and ADRs as answers land | `mp-grill` | knowledge |
| `/to-spec` | Synthesizes the conversation into a spec and publishes it | `mp-spec` | knowledge |
| `/to-tickets` | Breaks a spec into tracer-bullet tickets with blocking edges | `mp-tickets` | terminal |
| `/implement` | Orchestrates the ticket graph across parallel worktrees, then reviews | `mp-implement` | terminal |
| `/code-review` | Two-axis review (standards + spec) as parallel subagents | `mp-review` | terminal |
| `/handoff` | Compacts the conversation into a handoff doc | *(none)* | knowledge |
| `/setup` | Configures a repo's issue tracker, domain docs, and verification commands | `mp-setup` | terminal |

Typical flow: `/setup` once per repo, then
`/grill` → `/to-spec` → `/to-tickets` → `/implement` → `/code-review`.

## How it's wired

**Doctrine lives in agents, not command bodies.** A command's `model:` applies to the prompt it
submits; `agent:` switches the session, and the agent's model persists across turns. Since every
command except `/handoff` is multi-turn, each one is a thin body that switches to a primary agent
whose *system prompt* carries the full inlined doctrine. `/handoff` is one-shot, so it pins
`model:` directly and stays in the current session.

**Six primary agents** (session-switching, carry doctrine) and **five worker subagents**:

```
mp-grill ──────────────► mp-explorer
mp-spec  ──────────────► mp-explorer
mp-tickets ────────────► mp-explorer
mp-review ─────────────► mp-review-standards, mp-review-spec
mp-implement ──────────► mp-explorer, mp-implementer, mp-merger,
                         mp-review-standards, mp-review-spec
```

Each primary denies all subagents, then allows only its own workers. Because opencode's catalog
filter drops deny-resolved agents, this both restricts the model *and* narrows the menu it sees —
`mp-review` is shown exactly two subagents, not eleven.

**Verification is per-repo, not per-agent.** `/setup` writes `docs/agents/verification.md` with the
install, lint, typecheck, test, and "never run" commands. `mp-implementer` and `mp-merger` read
that file instead of hardcoding a toolchain, so the same agents work in a Yarn repo, a Python
repo, or a Go repo.

## Platform constraints this design works around

- **`subagent_depth` defaults to 1** — subagents cannot spawn subagents. All fan-out originates in
  the primary session. This is why TDD doctrine is inlined into `mp-implementer` and why
  `/implement`'s whole orchestration loop lives in the orchestrator.
- **`hidden: true` removes an agent from the subagent catalog**, making it uncallable. No worker
  sets it.
- **Command frontmatter is `additionalProperties: false`** with exactly six fields. There is no
  `argument-hint`.
- **Agent frontmatter uses the V2 `permissions` array**, not the V1 `permission` object.
  `tools`, `temperature` and `prompt` are V1 and silently ignored.
- **`` !`shell` `` blocks run outside the permission flow.** Only argument-free read-only git
  commands are interpolated, and never `$ARGUMENTS`.
- **Worktrees live under `~/.opencode-work/<repo>/<slug>/`**, not `$TMPDIR`: `~` expands at
  config-load time for permission resources, and the repo name prevents collisions across
  projects.

## Safety properties

- `mp-implementer` and `mp-explorer` carry `deny edit *` → `allow edit ~/.opencode-work/*`, so a
  worker can only ever touch its own worktree, never the main checkout.
- `git push` is explicitly denied for `mp-implement`, `mp-implementer` and `mp-merger`. Pushing
  stays the user's call.
- All four review/explore agents are `deny edit *` — they read and report, nothing else.
- `git worktree`, `git switch -c` and `git merge` are allowed **only** for the three agents that
  orchestrate worktrees, so a five-ticket run doesn't generate fifteen approval prompts. Nothing
  else is loosened.

## Skill policy

`opencode.jsonc` contains a targeted deny block at the **end** of the `permissions` array:

```jsonc
{ "action": "skill", "resource": "grill-me", "effect": "deny" }
```

Only the upstream skills that duplicate these commands are denied: `grill-me`,
`grill-with-docs`, `grilling`, `to-spec`, `to-tickets`, `implement`, `implement-spec`,
`code-review`, `handoff`, and `setup-matt-pocock-skills`. Every other skill — `find-skills`,
`tdd`, `research`, your own — remains available.

The block is last because the last matching rule wins. The canonical list is
`template/opencode.jsonc` in the workflow repo; edit it there and re-run the installer. To
re-enable a skill, delete its deny line. Appending an allow after the block also overrides the
policy, but `doctor` warns and the next install re-appends the deny.

**Project installs** merge the targeted rules into `<repo>/.opencode/opencode.json` when it is
strict JSON. A `.jsonc` target is left untouched and the block is printed, so comments are
preserved. **Global installs** cannot safely rewrite `~/.config/opencode/opencode.json(c)` because
it holds your providers and models, so the installer prints the block and `doctor` reports what is
missing.

## Known limitations

- **Slash commands only expand in the TUI.** `opencode run "/grill ..."` passes the text
  literally; the model will not expand it. Use the interactive TUI, or `--agent mp-grill` to get
  the same agent without the command wrapper.
- **An `agent:` switch does not auto-revert.** After `/grill` the session stays on `mp-grill`.
  Each primary's prompt ends by reminding you to switch back to `build`.
- **Global installs need the targeted skill policy added manually.** See above.
- **Global or project-local.** The installer can symlink the commands and agents into
  `~/.config/opencode/` so every project gets them, or copy them into a repo's `.opencode/`.
  See the repo README.
