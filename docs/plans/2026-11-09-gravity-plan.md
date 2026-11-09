# Gravity v1: Build plan

- Created: 2026-11-09
- Design: `docs/specs/2026-11-09-gravity-design.md`

## Goal

A working Claude Code plugin that implements the approved design, built in the design's §18 order.

## Global constraints

- Runtime is bash 3.2 and git, plus POSIX tools (`awk`, `sed`, `grep`). No Node, Python or `jq` at runtime.
- `gravity` is invoked as `bash <root>/bin/gravity -C <dir> <command>`.
- Exit codes: `0` pass, `1` fail, `2` couldn't run. Code 2 is never a pass.
- Only `gravity` writes the run directory. The ledger is append-only and tab-separated.
- Guards print kind and `path:line`, never the matched source text.
- Originals are never modified. Sources in `/tmp/gravity-src` and `~/Developer/_agents`, `~/.claude` are read only.
- Anything adapted from a source is credited in `THIRD_PARTY_NOTICES.md`.
- No AI attribution anywhere. Nothing is committed.

## Command contract

| Command | Does |
|---|---|
| `run start --session <id> --playbook <p> --slug <s> [--risk <r>] [--link-repo <path> --link-run <id>]` | Pin conf, write `run.start`, print the run id |
| `status [--run <id>]` | Replay the ledger. Shows version and said-done counts |
| `next` | Print current step, discipline file to read, caps left |
| `put [--replace] <name>` | Store stdin in the run dir. Refuses escapes, overwrites, secret-shaped text. Only `report.md` may be replaced |
| `doc <path>` | Record a draft document |
| `wait --gate <G> --doc <path>` | Record the fingerprint of what is shown |
| `plan check <path> [--design <path>]` | Fail on defects, warn, print pair table and counts |
| `plan change <reason>` / `goal change <reason>` | New plan generation, reopen docs paths |
| `playbook up <p> --reason <r>` | Step up within the same run |
| `isolate` | Create the worktree and branch, print its path |
| `task start <n>` / `task report <n> <status>` / `task done <n>` / `task block <n> <reason>` | Task lifecycle. Blocking skips dependents |
| `brief <n> [--note <text>]` | Write the next attempt's brief, print its path |
| `dispatch <n> --role <r> --model <m>` | Record a dispatch |
| `red <n>` | Run the proof on the current commit, expect failure, record the commit |
| `gate <G3\|G4 n\|G4R n\|G5\|G6\|B4>` | Run a gate at a clean tree and record the tree hash. Bug's B1, B2, B3, B5 are `gate B1 --evidence <name>` style records |
| `fix round <n\|G5\|G6> --cause <c>` | Record a round. Refuses past the cap |
| `package <n\|branch> [--since <sha>]` | Write the review diff, print its path. Refuses empty or non-descendant ranges |
| `review check <file>` | Verify verdict, anchors, quotes, absence claims |
| `finding --id <F> --task <n> --disposition <d> --why <w>` | Record a finding's outcome |
| `ruling --cost <c> --what <w> --why <y> [--file <f>]` | Record a ruling |
| `halt <reason>` / `pause <note>` | Stop safely |
| `report` / `report --check` | Print facts from the ledger, or verify `report.md` |
| `recover` | Apply the mid-build recovery rule, print what was done |
| `land [--patch\|--pr\|--keep\|--discard]` | Land. Needs the human's G7 line |
| `receipt` / `verify --base <ref> [--strict]` | Write the receipt, or check one |
| `setup prove --test-plant <patch> --lint-plant <patch>` / `setup exclude` / `setup ci` | Prove the conf, exclude scratch paths, install the CI check |
| `hook <session-start\|user-prompt\|pre-tool\|stop>` | Hook entry points, reading JSON on stdin |

Human lines (`approve`, `run.own`, G7) are written only by the prompt hook.

## Plan file format

```text
Design: docs/specs/x.md
## Acceptance
- `cmd` expects `text` [R1, R2]
## Task 1: title
Requirements: R1, R2
Files: src/a.ts, src/a.test.ts
Interfaces: ...
Depends: none
Proof: test `cmd`
Allow: src/a.test.ts edited expected value is the requested behavior change
Steps:
1. ...
```

`Proof:` may also be ``run `cmd` expects `text` `` or `build`. Requirements in the design are lines starting `R1:` or `- R1:`.

## Review file format

```text
Verdict: Ship
Safety: guard at auth.ts:40 | level=walked
F1 | src/a.ts:12 | quoted text | concrete failure | Important | regression
Declined: ...
Absence: patterns=fooBar scope=src hits=0
FLOOR-OK: skip src/a.test.ts reason
F1 ADDRESSED
```

## Tasks

### Stage 1: Spine

**Task 1. Core, ledger, status, next, put, wait.** `bin/gravity`, `lib/`. Proof: test `bash tests/run.sh core`.

**Task 2. Plan check, tasks, brief, red, fix rounds.** Proof: test `bash tests/run.sh plan`.

**Task 3. Gates, bar guard, floor guard.** Proof: test `bash tests/run.sh gates`. Depends on 1, 2.

**Task 4. Package, review check, report check, recovery.** Proof: test `bash tests/run.sh review`. Depends on 1 to 3.

### Stage 2: Hooks

**Task 5. Hook JSON reading, four hooks, `hooks.json`, plugin manifest.** Proof: test `bash tests/run.sh hooks`. Depends on 1.

### Stage 3: Setup

**Task 6. `setup prove`, `setup exclude`.** Proof: test `bash tests/run.sh setup`. Depends on 3.

### Stage 4: Router, Tiny and Bug, receipt

**Task 7. Router skill, Tiny and Bug playbooks, debug, prove and report disciplines, core agents and commands.** Proof: run `bash tests/run.sh structure` expects `0 failed`.

**Task 8. Land, receipt, `receipt-check`, CI workflow.** Proof: test `bash tests/run.sh land`. Depends on 3, 4.

### Stage 5 and 6: Small and Standard

**Task 9. Ask, plan, build and review disciplines, Small and Standard playbooks, all six agents, templates.** Proof: run `bash tests/run.sh structure` expects `0 failed`.

### Stage 7: Linked runs

**Task 10. `run start --link-repo <path> --link-run <id>`, `link` ledger line.** Proof: test `bash tests/run.sh link`. Depends on 1.

### Finish

**Task 11. Notices, README, marketplace manifest.** Proof: build.

**Task 12. Live check.** Install with `claude --plugin-dir` and run the §19 unknowns that a real session can answer. Proof: run, results recorded in this plan.

### Live check results (2026-11-09, CLI 2.1.318)

Run against a throwaway repo with no MCP servers and no user-level hooks.

| §19 unknown | Result | How it was shown |
|---|---|---|
| Hook context reaches the session | Yes | The session id appeared in the session's context. The router itself now loads on `/gravity` |
| `/gravity:approve` reaches the prompt hook | Yes | An `approve` ledger line was written |
| Session id across `claude --resume` | Stays the same | Compared before and after |
| Re-injection after `compact` | Yes | A marker changed after the session began and appeared only after `/compact` |
| Edit hook in the main session | Denies code, allows docs | Real writes with a control |
| Subagent hook payloads carry the owner session id | Yes, plus `agent_id` | Raw hook payload logged |
| Plugin `bin/` by absolute path from a subagent | Yes | `gravity version` ran in a subagent |
| `${CLAUDE_PLUGIN_ROOT}` in command bodies | Substituted | `/gravity:status` ran |
| `${CLAUDE_PLUGIN_ROOT}` in agent bodies | Substituted | A plugin agent quoted its own instructions |
| Reading `.git/gravity/` with the read tool | Works in the main session | Read the ledger. Not tried from a reviewer agent |
| Hooks under bypass-permissions | Not tested | Not run: it would launch an unsupervised nested session |
| Plugin version picked up mid-run | Not tested | Needs two releases |
| User-level agent overriding a Gravity agent | Not tested | The check ran without user-level settings |
| `--scope local` turns a plugin off for one repo only | Yes | Tested in a throwaway config |
| Setup reminder shown at session start | Yes | Seen in the session event stream |
| `/gravity` refused before setup | Yes | The hook blocked the prompt |
| `${CLAUDE_PLUGIN_DATA}` in a command matches the hook's | Yes | Compared the two paths |
| Router absent unless `/gravity` is typed | Yes | Asked in a session that did not type it |
| `skillOverrides` off hides a project skill | Yes | Listed before and after |

Team rollout waits for pressure tests (§16), which need a built plugin and real runs. Leave uncommitted; run lint.

Committing is handled by the user.
