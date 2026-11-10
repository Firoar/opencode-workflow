---
description: Implement a spec's ticket graph across parallel worktrees, then review
agent: mp-implement
subagent: false
---

Current branch: !`git branch --show-current 2>/dev/null || echo "(not a git repository)"`

Recent commits:
!`git log --oneline -10 2>/dev/null || echo "(no commit history)"`

Implement the spec below. Read its tickets, build the task graph, and work the frontier:
one fresh implementer per unblocked ticket, each in its own worktree, merging as they land.

If no spec is named, ask me which one before doing anything else.

$ARGUMENTS
