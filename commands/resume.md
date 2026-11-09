---
description: Take over an unfinished Gravity run, and clear its halt or pause
argument-hint: "[run-id]"
disable-model-invocation: true
---

The prompt hook has already acted on this message, and its result is in this turn's context. Taking ownership is the hook's
job and never yours. If the hook refused, or no result is visible, say so and stop. Otherwise, with `<dir>` as the run's
worktree if one exists, otherwise the repository:

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> status`. Ledger state outranks anything this conversation remembers.
2. If a task has started and not finished, run `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> recover` and read what it printed.
3. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> next`, open the file it names, and continue the playbook.

| Stopped during | Then |
|---|---|
| Before G1 | The draft is on disk. Play it back and ask what changed |
| G1 to G2 | The fingerprint is checked. On a mismatch, re-approve |
| Mid fix loop | Continue at the recorded round. The cap still counts |
| Report | Regenerate from the ledger |
| A halt for a plan defect | `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> plan change <reason>`, then fix the plan for G2 approval |
