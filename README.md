# opencode-workflow

Seven slash commands that turn opencode into a disciplined engineering workflow:
**grill → spec → tickets → implement → review**, plus handoff and one-time setup.

Ported from [mattpocock/skills](https://github.com/mattpocock/skills) into native opencode
commands + agents. Fully self-contained: no skill files, no runtime dependency on `.agents/skills`.

> **Slash commands only expand in the TUI.** `opencode run "/grill ..."` passes the text
> literally; the model will not expand it. Use the interactive TUI, or `--agent mp-grill` to get
> the same agent without the command wrapper.

The workflow is **toolchain-agnostic**. It does not assume Yarn, Expo, Python, or Go. Each repo
records its install / lint / typecheck / test commands in `docs/agents/verification.md`, and the
implementer and merger follow that file.

## Requirements

- opencode V2 (tested on 2.0.32; the schema was also verified on 2.2.7)
- `git`
- optional: `gh` (GitHub issues) or `glab` (GitLab issues)

## Install

```bash
./install.sh --profile four-model global
./install.sh doctor
```

That renders the selected profile into `~/.local/share/opencode-workflow/<profile>/` and symlinks
`~/.config/opencode/commands` and `~/.config/opencode/agents` to it. Every project now has the
commands. Existing config is backed up automatically.

**Global skill suppression is manual.** The installer will not rewrite your
`~/.config/opencode/opencode.json(c)` because it holds your providers and models. To hide
auto-discovered `.agents/skills`, add this to its `permissions` array:

```json
{ "action": "skill", "resource": "*", "effect": "deny" }
```

`doctor` warns if the rule is missing.

Project-local install instead:

```bash
./install.sh --profile four-model project /path/to/repo
```

That copies `commands/` and `agents/` file-by-file, backing up only colliding filenames, and
**merges** the skill-suppression rule into `<repo>/.opencode/opencode.json` if it exists. It never
replaces your model pins or MCP servers.

## Per-repo setup

Run once in each repo:

```
/setup
```

It writes `docs/agents/issue-tracker.md`, `triage-labels.md`, `domain.md`,
`verification.md`, and an `## Agent workflow` block in `AGENTS.md`. Commit those. They are the only
per-repo state.

`verification.md` is what makes the workflow portable: it carries the install, lint, typecheck,
test, and "never run" commands for this repo. `/setup` detects the toolchain and proposes them.

## Profiles

| Profile | Use when |
|---|---|
| `four-model` | Best-of-the-four mapping. Uses GLM, DeepSeek, and Muse Spark. |
| `four-model-safe` | Same four-model constraint without Muse Spark Contributor, so no prompts/code are sent to Meta training. |

```bash
./install.sh --profile four-model-safe global
```

Profiles are plain `.env` files under `profiles/`. Copy one, change the model IDs, and pass
`--profile <name>`. The model IDs are **OpenCode Go-specific**; on another provider, replace them
with that provider's equivalents. The installer renders the profile into the agents and refuses to
leave an unreplaced placeholder.

## Model mapping (`four-model`)

| Agent | Model | Why |
|---|---|---|
| `mp-grill`, `mp-spec`, `mp-review-spec`, `/handoff` | `opencode-go/muse-spark-1.3-contributor#xhigh` | GDPval-AA 1754, Agentic IF 57.8, MRCR 98.5, 1M context |
| `mp-tickets`, `mp-implement`, `mp-review`, `mp-review-standards`, `mp-explorer`, `mp-merger`, `mp-setup` | `opencode-go/glm-5.3-flash#max` | Toolathlon 78.4 (#1 of 24), Terminal-Bench 4.0 37.4%, SWE-bench 92.0% |
| `mp-implementer` | `opencode-go/deepseek-v4.1-flash#max` | DeepSWE 77.0, SWE-bench 88.8, Browser Use 75.0 |

**MiMo V2.6 Flash is deliberately unused.** Vals AI found it searches for leaked reference fixes in
Git history and upstream releases instead of solving coding tasks (67% of its 2,698 training tasks
had the answer recoverable). Its coding benchmark scores are suspect. If you still want it, set
`MODEL_EXPLORER=opencode-go/mimo-v2.6-flash`.

**Muse Spark Contributor trains on your data.** The Contributor tier is "used to improve our
products"; prompts and code outputs are eligible for training. Use `four-model-safe` for private
repos or confidential design conversations.

## Commands

| Command | Purpose |
|---|---|
| `/grill` | Relentless round-by-round interview; writes glossary/ADRs as decisions land |
| `/to-spec` | Synthesizes the conversation into a spec, no interview |
| `/to-tickets` | Tracer-bullet tickets with blocking edges |
| `/implement` | Parallel worktrees, serialized merges, review at the end |
| `/code-review` | Standards + spec axes, run as parallel subagents |
| `/handoff` | Compact the conversation into a temp-file handoff |
| `/setup` | One-time tracker/labels/domain-doc/verification config |

## Agent IDs

`mp-*` is a reserved agent-ID namespace once this is installed globally. A project-level
`.opencode/agents/mp-review.md` will shadow the global one without warning.

## Verify

```bash
./install.sh doctor
```

Checks the symlinks, the profile variables, every model ID in `opencode models`, `git`, the
tracker CLI named by `docs/agents/issue-tracker.md`, the global skill-suppression rule, and whether
this repo has `docs/agents/verification.md`.

## Update

```bash
git pull
./install.sh --profile four-model global
```

Re-run the installer after a pull: the rendered directory is what the symlinks point at.

## Uninstall

```bash
./install.sh uninstall
```

Removes the global symlinks only if they point at this repo's rendered directory. It leaves
`$DATA_DIR` and `~/.opencode-work` in place and says so; remove them manually for a clean slate.
Project installs are left alone.

## Credits

The doctrine is ported from [mattpocock/skills](https://github.com/mattpocock/skills) by Matt
Pocock. The opencode-native agent/command architecture follows the reference design in
`opencode-setup`.

## License

MIT. See [LICENSE](LICENSE).
