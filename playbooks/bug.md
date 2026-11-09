# Playbook: Bug

Something is wrong. The bug procedure replaces ASK and PLAN. Human gates: B2 only if risky, plus G7. One diagnosis
record. Worktree from the start, red first.

`gravity`, `disciplines/` and `templates/` mean what the router defined. Run `gravity next` at each gate and open the
file it names. Every gate records the tree it ran on, so commit before running one.

## Find it

1. **Isolate.** `gravity isolate`. Work in the worktree it prints. Reproduction scripts go in the worktree's
   `.gravity/scratch/`.
2. **B1, restate and reproduce.** Open `disciplines/debug.md`. State the one sentence before reading anyone's theory of the
   cause, then reproduce it on the original surface, or request diagnostics. Save it with `gravity put b1.md`, then
   `gravity gate B1 --evidence b1.md`. The restated sentence is `R1` in the report.
3. **B2, root cause.** Map, locate, list candidates and score them under the rubric in `disciplines/debug.md`. Save the
   diagnosis in the format it gives with `gravity put diagnosis.md`. Its `Files` line is the floor guard's list at G6. Run
   `gravity gate B2 --evidence diagnosis.md`.
4. **Nothing Confirmed means no fix.** Save the at most 4 cheap checks as `diagnostics.<k>.md` with `gravity put`, then
   `gravity wait --gate B2 --doc diagnostics.<k>.md` and stop. Hand back as well when three candidates are ruled out with no
   new leads, the fix needs restructuring, every fix breaks something else, or the evidence contradicts itself.
5. **Show the cause.** State the cause and blast radius in plain words. If risk is Low and the fix is reversible,
   continue without waiting. Otherwise `gravity wait --gate B2 --doc diagnosis.md` and stop for `/gravity:approve`.

## Fix it

6. **B3, red.** Write a failing test that captures the bug and commit it. Run `gravity red B3 --cmd <test command>`,
   which runs it and expects it to fail. Save the failing output with `gravity put b3.md`, then
   `gravity gate B3 --evidence b3.md`. If no test can reach the bug, use the closest executable check, record why with
   `gravity ruling`, and report it.
7. **B4, green.** Make the smallest fix the evidence justifies. Remove anything added for a refuted hypothesis. Commit,
   then `gravity gate B4`. Exit 1 starts a round: `gravity next`, then `gravity fix round B4 --cause gate`, which refuses
   past the cap. Exit 2: run it once more, then `gravity halt`.
8. **Bar guard hit at B4.** A change to a bar path has no plan to allow it. Save the bar-path diff with `gravity put
   <name>.patch`, run `gravity wait --gate B4 --doc <name>.patch`, and stop. After approval the guard passes only while the
   bar-path diff in the tree equals that patch.
9. **B5, on the original surface.** Open `disciplines/prove.md`. Show the original symptom is gone where it was seen,
   save the output with `gravity put b5.md`, then `gravity gate B5 --evidence b5.md`. Inconclusive or wrong-surface is not a
   pass.

## Review, report, land

10. **G6.** Open `disciplines/review.md`. `gravity package branch`. `gravity dispatch branch --role branch-reviewer --model opus`,
    and dispatch the `branch-reviewer` agent, and the `security-reviewer` agent when the risk question matched, each in the
    foreground, naming only the diagnosis, the package, the gate evidence and a name under `reviews/`. For each review, `gravity review check <file>`, then record each finding with
    `gravity finding`. Then `gravity gate G6`. The floor guard runs here, once, against the diagnosis paths. One fix wave at
    most: `gravity fix round G6 --cause review`, a scoped re-review, `gravity gate B4`, the symptom shown gone again with
    `gravity gate B5 --evidence <name>`, then a new `gravity gate G6`.
11. **Report.** Open `disciplines/report.md`. Run `gravity report`, write the prose from `templates/report.md`, save it with
    `gravity put --replace report.md`, then `gravity report --check` until it passes. On a risk match, dispatch the
    `report-reviewer` agent, add what it finds, and check again.
12. **G7.** `gravity wait --gate G7 --doc report.md`, show the report, and stop. Only a typed `/gravity:land` lands it.
