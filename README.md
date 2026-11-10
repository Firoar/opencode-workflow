# opencode-workflow

Seven slash commands that turn opencode into a disciplined engineering workflow:
**grill → spec → tickets → implement → review**, plus handoff and one-time setup.

Ported from [mattpocock/skills](https://github.com/mattpocock/skills) into native opencode
commands + agents. Fully self-contained: no skill files, no runtime dependency on `.agents/skills`.

## Requirements

- opencode V2 (tested on 2.0.32)
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

Project-local install instead:

```bash
./install.sh --profile four-model project /path/to/repo
```

That copies `commands/`, `agents/`, and `opencode.json` into `<repo>/.opencode/`.

## Per-repo setup

Run once in each repo:

```
/setup
```

It writes `docs/agents/issue-tracker.md`, `triage-labels.md`, `domain.md`, and an
`## Agent workflow` block in `AGENTS.md`. Commit those. They are the only per-repo state.

## Profiles

| Profile | Use when |
|---|---|
| `four-model` | Best-of-the-four mapping. Uses GLM, DeepSeek, and Muse Spark. |
| `four-model-safe` | Same four-model constraint without Muse Spark Contributor, so no prompts/code are sent to Meta training. |

```bash
./install.sh --profile four-model-safe global
```

Profiles are plain `.env` files under `profiles/`. Copy one, change the model IDs, and pass
`--profile <name>`. The installer renders them into the agents and refuses to leave an unreplaced
placeholder.

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
| `/setup` | One-time tracker/labels/domain-doc config |

## Verify

```bash
./install.sh doctor
```

Checks the symlinks, the profile variables, and that every model ID exists in `opencode models`.
In a project, it also notes whether `/setup` has run.

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

Removes the global symlinks if they point at this repo's rendered directory. Project installs are
left alone.

## Credits

The doctrine is ported from [mattpocock/skills](https://github.com/mattpocock/skills) by Matt
Pocock. The opencode-native agent/command architecture follows the reference design in
`opencode-setup`.

## License

MIT. See [LICENSE](LICENSE).
