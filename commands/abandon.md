---
description: Drop an unfinished Gravity run
argument-hint: "[run-id]"
disable-model-invocation: true
---

The prompt hook has already acted on this message, and its result is in this turn's context. Recording the abandon is the
hook's job and never yours. If the hook refused, or no result is visible, say so and stop.

Otherwise run `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> status`, with `<dir>` as the current repository, and report in
plain words what the run left behind: its worktree, its branch, any uncommitted docs. Delete nothing yourself.
