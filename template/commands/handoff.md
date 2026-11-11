---
description: Compact this conversation into a handoff document for a fresh session
model: __MODEL_HANDOFF__
subagent: false
---

Write a handoff document summarising this conversation so a fresh agent can continue the work.

Save it to the temporary directory of this OS (`$TMPDIR`, else `/tmp`) — **not** the current
workspace.

Rules:

- **Do not duplicate content already captured in other artifacts** — specs, plans, ADRs, issues,
  commits, diffs. Reference them by path or URL instead. The next agent can read them; what it
  cannot recover is the reasoning that happened in this conversation.
- Include a **"Suggested commands"** section naming which of `/grill`, `/to-spec`,
  `/to-tickets`, `/implement`, `/code-review` the next session should run, and in what order.
- Capture the things that would otherwise be lost: decisions made and *why*, approaches already
  tried and rejected, open questions, and anything the user corrected you on.
- Record the current state plainly: branch, what is committed, what is still in the working
  tree, what is passing and what is failing.
- **Redact sensitive information** — API keys, passwords, tokens, personally identifiable
  information.

When you are done, print the path to the file.

If anything is written below, treat it as a description of what the next session will focus on
and tailor the document to that.

$ARGUMENTS
