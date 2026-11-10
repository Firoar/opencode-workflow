---
description: Two-axis review (standards + spec) of the diff since a fixed point
agent: mp-review
subagent: false
---

Current branch: !`git branch --show-current 2>/dev/null || echo "(not a git repository)"`

Recent commits:
!`git log --oneline -15 2>/dev/null || echo "(no commit history)"`

Review the changes since the fixed point given below, on both axes.

If no fixed point is named, ask me for one before spawning anything.

$ARGUMENTS
