---
description: Show where every Gravity run stands and the installed plugin version
argument-hint: "[run-id]"
---

Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> status`, adding `--run $ARGUMENTS` if a run id was given. `<dir>` is the
current repository.

Show the output as it is. Point out any open wait, halt or pause, a worktree that has gone missing, and the said-done
against gates-rejected counts. Change nothing. Do not resume a run from here.
