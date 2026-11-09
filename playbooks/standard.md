# Playbook: Standard

Several areas, or a risk match. Human gates G1, G2 and G7. A design and a plan. The session never writes code here:
it issues briefs, dispatches, reads results and writes the ledger.

`gravity`, `disciplines/` and `templates/` mean what the router defined. At every task boundary and before every fix
round, run `gravity next` and open the file it names.

## Act 1. In the room

1. **Ask.** Open `disciplines/ask.md`. Draft the design from `templates/design.md` under the configured specs path,
   starting at the first answer, and run `gravity doc <design>` on the first save.
2. **Builder check.** Dispatch the `builder-check` agent in the foreground, naming only the design and a review name.
   Ask the person each question sorted `yours`. Fold in `minor` ones as marked proposals.
3. **G1.** `gravity wait --gate G1 --doc <design>`, show the design, and stop. Only a typed `/gravity:approve` passes it.
4. **Plan.** Open `disciplines/plan.md`. Draft from `templates/plan.md` under the configured plans path, run
   `gravity doc <plan>`, then `gravity plan check <plan> --design <design>`. Fix every failure.
5. **G2.** `gravity wait --gate G2 --doc <plan>`, show the plan with the warnings and pair table, and stop.

## Handoff

Questions end here. Decide, and record it: `gravity ruling --cost <c> --what <w> --why <y> [--file <f>]`.

## Act 2. Unattended

6. **Isolate.** `gravity isolate`. `gravity gate G3`. Exit 1 means the baseline is wrong or an `Acceptance` check already
   matches: `gravity halt`. Exit 2: run it once more, then `gravity halt`.
7. **Each task, in plan order, one writer at a time.** Open `disciplines/build.md` at the first task, then whatever
   `gravity next` names.
   1. `gravity task start <n>`. A `run` proof that already matches halts for a plan fix.
   2. `gravity brief <n>`, which prints the brief path. `gravity dispatch <n> --role implementer --model sonnet`.
   3. Dispatch the `implementer` agent in the foreground. Name only the brief and the report name, which is the brief's name
      under `reports/`.
   4. Take the result. `gravity task report <n> <status>`. A missing or unreadable status is a failed attempt, and the
      reason goes to the next one. `NEEDS_CONTEXT` is answered in a new brief with `gravity brief <n> --note <text>`. `BLOCKED`
      goes through the cause table in `disciplines/build.md`.
   5. `gravity gate G4 <n>`. Exit 1 is the fix loop, unless the only hits are floor-guard hits: those can be cleared only by
      the reviewer's `FLOOR-OK`, so continue to review and name the evidence. Exit 2: run it once more, then `gravity halt`.
   6. `gravity package <n>`. `gravity dispatch <n> --role task-reviewer --model sonnet`. Dispatch the `task-reviewer` agent in
      the foreground, naming only the brief, the package, the gate evidence and the review name, which is the brief's name under `reviews/`. Never pass the implementer's
      report or reasoning, though evidence that contradicts it is fine.
   7. `gravity review check <review>`. A failed check is a failed review attempt: a fresh reviewer once, then treat it as
      `Cannot verify`, which you resolve and send to one scoped re-review.
   8. Give every finding one disposition with `gravity finding --id <F> --task <n> --disposition <fix|disprove|defer|rule> --why <w>`.
      Risk-path findings are never dismissed without disproof.
   9. `gravity gate G4 <n>` again if a countersign was needed, then `gravity gate G4R <n>`. Then `gravity task done <n>`, and go
      to the next task.

**Fix loop.** Up to 4 rounds, each a fresh implementer. Open `disciplines/build.md` for the cause table.

- Run `gravity next`, then `gravity fix round <n> --cause <c>`. It refuses a fifth.
- Run `gravity brief <n>` for one consolidated brief, and dispatch with `--model sonnet`.
- Round 2: add a note with `--note` to attack the premise. Round 4: dispatch with `--model opus`.
- After each round, `gravity gate G4 <n>` again. Then `gravity package <n> --since <head the last review saw>` and a scoped
  re-review: findings verbatim and the fix diff only. New issues found there go to `gravity finding`, not the loop.

**Breaker**, at the cap. A contestable finding becomes a `gravity ruling`. A real but deferrable one becomes a `defer`
disposition. A load-bearing finding, or any hard gate still failing, is `gravity task block <n> <reason>`. Dependents
are skipped and independent tasks still finish.

8. **G5.** Open `disciplines/prove.md`. `gravity gate G5`. If it fails, one wave: `gravity fix round G5 --cause gate`, one fresh
   implementer with `Files` as the union of every task's, and `gravity gate G5` again. Still failing: stop at the report with G5
   as the Key signal. `/gravity:land` will refuse it.
9. **G6.** Open `disciplines/review.md`. `gravity package branch`. `gravity dispatch branch --role branch-reviewer --model opus`,
   then dispatch the `branch-reviewer` agent in the foreground, and the `security-reviewer` agent as well on a risk match, naming
   only the design, the plan, the package, the evidence and a name under `reviews/` each. `gravity review check` each one, and give every finding a disposition. Then `gravity gate G6`.
   One fix wave at most: `gravity fix round G6 --cause review`, one fresh implementer, one scoped re-review, `gravity gate G5`, and a
   new `gravity gate G6` for the final tree. What's left goes through the breaker.

## Report

10. Open `disciplines/report.md`. Run `gravity report` for the facts, write the prose from `templates/report.md`, save it with
    `gravity put --replace report.md`, and run `gravity report --check` until it passes.
11. Dispatch the `report-reviewer` agent in the foreground, naming the package, the ledger, the report and a review name. Record
    every ruling it adds with `gravity ruling`, fix what it found in the report, and run `gravity report --check` again.

## Act 3. You're back

12. **G7.** `gravity wait --gate G7 --doc report.md`, show the report, and stop. Only a typed `/gravity:land` lands it.

## A feature that spans repos

One design, approved once in the upstream repo, including the shared data shapes as the contract. Each repo gets its own run,
plan, worktree and report. Upstream goes first.

Start each downstream run with `gravity run start --session <id> --playbook standard --slug <s> --link-repo <upstream path> --link-run <upstream run id>`.
That records a `link` line in place of G1, only if the upstream design still has its approved fingerprint. If it says the design
changed, this run needs its own G1. Each downstream `Acceptance` includes a call to the real upstream, checking URL, shape and auth.

If the contract must change during a downstream run, that is a goal change on the shared design. Only runs whose part of the
contract changed re-plan.
