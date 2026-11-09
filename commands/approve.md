---
description: Approve the document you were just shown
disable-model-invocation: true
---

The prompt hook has already acted on this message, and its result is in this turn's context. Recording an approval is the
hook's job and never yours. Below, `<dir>` is the run's worktree if one exists, otherwise the repository.

Read the result and do exactly one of these:

- **Recorded.** Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> next`, open the file it names, and continue the playbook.
- **Changed since shown.** Say so and show what changed. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> wait --gate <gate> --doc <path>` again, show the document, and stop.
- **`plan check` failed.** Fix what it reported, run `wait` again the same way, show the document, and stop.
- **Nothing awaiting approval, or no result visible.** Say so and stop. Do not continue as if approved.
