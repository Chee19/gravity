Goal: turn each approved task into committed, proven code, with limits counted by `gravity` and every decision logged.

In Standard the orchestrating session never writes code. It issues a brief for each task, dispatches, reads the result,
and writes the ledger. In Small the session builds each task itself, in the worktree, by the same steps without
dispatch or per-task review.

After handoff you do not ask, you rule. Log each decision with `gravity ruling --cost <c> --what <w> --why <y>`.
Authority settles conflicts: approval, then design, then plan, then brief, then diff.

## Start

1. Run `gravity isolate` and work from the path it prints.
2. Run `gravity gate G3`. A pass shows the baseline green and each `Acceptance` check not matching yet.

## Each task

One writer at a time. Dispatch implementers and reviewers in the foreground.

1. Run `gravity next` and read the file it names. Do this at every task boundary and before every fix round.
2. Run `gravity task start <n>`. If a `run` proof already matches, the check can't tell, so `gravity halt`.
3. Run `gravity brief <n>`. It prints the brief's path. Use `--note <text>` only for an ambiguity you resolved. If it
   refuses, the plan is defective, so `gravity halt`.
4. Run `gravity dispatch <n> --role implementer --model sonnet`, then dispatch. The dispatch names the brief path, the
   report location and the fixed report format, and nothing else. Artifacts move as files, never pasted into prompts.
5. Run `gravity task report <n> <status>` with the status it returned.
6. Check that the diff shows the change. An agent saying it finished is not evidence.
7. Run `gravity gate G4 <n>`. Standard then follows the review discipline and runs `gravity gate G4R <n>`.
8. Run `gravity task done <n>`.

## What an implementer does

The implementer sees only its brief. Attempts are write-once and named for plan generation and attempt, such as
`reports/task-3.g1.2.md`, stored with `gravity put`.

- **`test` proof:** commit the failing test, then run `gravity red <n>`. It runs the proof, expects failure and
  records the commit. Red is observed, not reported. If the test passes, report `BLOCKED`.
- Implement exactly what the task says, then commit. At least one commit per task, in the worktree only. Commit before
  any gate, because a dirty tree is exit 2.
- Touch only what the task needs. Don't clean up adjacent code or add what "seems useful". Report what you saw under
  `NOTICED` and leave it alone.
- Never dispatch agents. Review is already scheduled.

| Status | Means | Orchestrator does |
|---|---|---|
| `DONE` | Finished | Continue to step 6 |
| `DONE_WITH_CONCERNS` | Finished, with doubts | Doubts about correctness or scope are settled before the gate. Observations are noted |
| `NEEDS_CONTEXT` | Missing information | Rule on it, then issue a new brief with the note |
| `BLOCKED` | Cannot complete | Change something: context, model, a smaller scope, or a ruling on the plan. Never the same retry |
| Missing or unreadable | Failed attempt | The reason goes to the next one |

Saying "this is too hard" is always acceptable. Bad work is worse than no work.

## Why it failed decides what happens next

| Cause | Response | Uses a fix round |
|---|---|---|
| Lost connection or tool error | Same brief, then a fallback model once | No |
| Context limit | Smaller scope, or split the task | No |
| Test fails once in code the task touched | One retry. An identical second failure is real | After the retry |
| Test fails in code the task didn't touch | Run it on the base. Failing there too is recorded as pre-existing | No |
| Gate or review failure | Fix loop | Yes |

`gravity gate` exit 1 enters the fix loop. Exit 2 means run it once more, then `gravity halt`.

## Fix loop

Run `gravity next`, then `gravity fix round <n> --cause <c>`. It refuses a fifth. Every round is a **fresh implementer**
with one consolidated brief from `gravity brief <n>`: the original brief, every later ruling, the prior report and the
findings verbatim, in the same worktree.

| Round | Implementer |
|---|---|
| 1 | Fresh |
| 2 | Fresh, attacking the premise |
| 3 | Fresh |
| 4 | Fresh, with `--model opus` at dispatch |

**Attack the premise.** Before fixing, the round 2 implementer writes the one sentence every failed fix assumed, and
one observation that would come out differently if it is false, and makes that observation. If it contradicts the
premise, the cause is elsewhere. Pass this with `--note`.

After every round the proof, full suite and guards run again through `gravity gate G4 <n>`. Re-review is scoped, as the
review discipline describes. New issues found in a scoped review go to the ledger, not the loop.

## The breaker

At the cap, stop dispatching and sort what's open. Adjudicate only at the cap.

| Open item | Outcome | Record |
|---|---|---|
| Contestable finding | Ruling, shown in the report | `gravity finding --id <F> --task <n> --disposition rule --why <w>` |
| Real but deferrable | Deferred, shown in the report | `gravity finding --id <F> --task <n> --disposition defer --why <w>` |
| Load-bearing, or any hard gate still failing | Task blocked | `gravity task block <n> <reason>` |

Blocking skips every task that depends on it, directly or transitively. All independent tasks finish, and the report
lists what didn't happen and why. A load-bearing finding still `NOT` after round 4 means the design is suspect: block
that task and say so in the report.

## What stops a running plan

Run `gravity halt <reason>` for:

- something irreversible, something security-sensitive, or a side effect outside the worktree
- a plan so broken every path is a guess
- no runnable tasks left
- signals the design is wrong for everything: the same workaround in unrelated code, type escape hatches to get
  through, or two same-shaped deviations from the plan across tasks

A plan defect found after handoff is a halt. After `/gravity:resume`, run `gravity plan change <reason>`. The fixed plan
needs G2 approval.

## Messages after handoff

Sort every message from the person:

- **Would the approved design's text have to change? No:** a clarification. Write a ruling and continue.
- **Yes:** a goal change. You may never rule on it. Stop at the task boundary, or stop the in-flight task and save its
  patch, and run `gravity goal change <reason>`. Triage each finished task as keep, revert or modify, update the design,
  show the diff, and wait for approval. Then re-plan from surviving commits in the same worktree.
- **Unrelated question or new task:** answer the question without touching the run, or park the task as a follow-up
  in the report. It is not the next build step.
- **"Pause":** finish or abandon the current step at a safe boundary, then run `gravity pause <note>`.

## Excuses recorded in real runs

| Excuse | Reality |
|---|---|
| "One more round will converge" | Past the cap, rounds don't converge. The failure is structural |
| "I'll fix it myself, dispatching is overhead" | Orchestrator fixes skip review and pollute its context |
| "The fix was small, skip the re-review" | Unreviewed fixes are how regressions land |
| "This finding is obviously wrong, I'll drop it" | Silent discards are forbidden. Every finding gets a line in the ledger |
| "Ledger bookkeeping is overhead" | Orchestrators without one have re-dispatched entire completed task sequences |

## Exit

**Done when** every task is recorded as `gravity task done <n>` or `gravity task block <n> <reason>`. Run `gravity next`
and read the file it names. Next comes `gravity gate G5` in the prove discipline.
