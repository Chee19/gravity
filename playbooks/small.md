# Playbook: Small

One area, a few tasks. One document holds the design and the task list, approved once at the combined gate `G1G2`. You
build it yourself in a worktree.

`gravity`, `disciplines/` and `templates/` mean what the router defined. At every task boundary and before every fix
round, run `gravity next` and open the file it names.

## Act 1

1. **Ask, short form.** Open `disciplines/ask.md`. Mirror the request, sort the unknowns, and ask only what passes the
   question test.
2. **One document.** Open `disciplines/plan.md`. Combine `templates/design.md` and `templates/plan.md` in one file under
   the configured plans path, starting at the first answer. Requirements are lines starting `R1:`. Run `gravity doc <path>`
   on the first save, and `gravity plan check <path>` when the tasks are written. Fix every failure.
3. **G1G2.** `gravity wait --gate G1G2 --doc <path>`, show the document with the warnings and pair table, and stop. Only a
   typed `/gravity:approve` passes it.

More than 3 tasks or a risk path: step up to Standard. See the router.

## Handoff

Questions end here. Decide, and record what you decided with `gravity ruling --cost <c> --what <w> --why <y> [--file <f>]`.

## Act 2

4. **Isolate.** `gravity isolate`. Work in the worktree it prints. `gravity gate G3`. Exit 1 means the baseline is wrong or an
   `Acceptance` check already matches: `gravity halt`. Exit 2: run it once more, then `gravity halt`.
5. **Each task, in plan order.** Open `disciplines/build.md`.
   - `gravity task start <n>`.
   - For a `test` proof, commit the failing test, then `gravity red <n>`. If the test passes, stop and work out why.
   - Make the smallest change that meets the task. Touch only its `Files`. Commit.
   - `gravity gate G4 <n>`. Exit 1 is a fix round: `gravity next`, then `gravity fix round <n> --cause gate`. Exit 2: run it
     once more, then `gravity halt`.
   - `gravity task done <n>`. Or `gravity task block <n> <reason>`, which skips dependent tasks.
   - Small has no per-task reviewer, so the floor guard runs once at G6.
6. **G5.** Open `disciplines/prove.md`. `gravity gate G5`. If it fails, one wave: `gravity fix round G5 --cause gate`, fix,
   commit, run it again. Still failing: stop at the report with G5 as the Key signal. `/gravity:land` will refuse it.
7. **G6.** Open `disciplines/review.md`. `gravity package branch`. `gravity dispatch branch --role branch-reviewer --model opus`,
   then dispatch the `branch-reviewer` agent in the foreground, naming only the document, the package, the gate evidence and a
   name under `reviews/`. `gravity review check <file>`, then record
   each finding with `gravity finding`. Then `gravity gate G6`. One fix wave at most: `gravity fix round G6 --cause review`, a
   scoped re-review, `gravity gate G5`, then a new `gravity gate G6`.

## Report and land

8. **Report.** Open `disciplines/report.md`. Run `gravity report`, write the prose from `templates/report.md`, save it with
   `gravity put --replace report.md`, then `gravity report --check` until it passes.
9. **G7.** `gravity wait --gate G7 --doc report.md`, show the report, and stop. Only a typed `/gravity:land` lands it.
