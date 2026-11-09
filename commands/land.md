---
description: Land a finished Gravity run and write its receipt
argument-hint: "[patch|pr|keep|discard]"
disable-model-invocation: true
---

Argument: `$ARGUMENTS`

The prompt hook has already acted on this message, and its result is in this turn's context. Recording G7 is the hook's job
and never yours. If the hook refused, or no result is visible, say so and stop.

Otherwise run one command, with `<dir>` as the repository's main checkout:

| Argument | Command |
|---|---|
| none | `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> land` |
| `patch` | `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> land --patch` |
| `pr` | `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> land --pr` |
| `keep` | `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> land --keep` |
| `discard` | `bash ${CLAUDE_PLUGIN_ROOT}/bin/gravity -C <dir> land --discard` |

Anything else: name the accepted arguments and stop. Run `--discard` only if the person typed `discard` themselves.

Show what it printed: where the code is now, the receipt path, and the state of the checkout. If `land` refused, say why and
stop. If uncommitted changes overlap the merge, tell the person to run `/gravity:land patch`. If G5 failed, landing is
refused, and they can run `/gravity:land keep` or `/gravity:land discard`.

Never commit or push yourself. The commit and the push belong to the person.
