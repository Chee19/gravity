Goal: tell an informed reviewer what was done and why, so they can decide from this report alone.

The report is the product of the run. It covers what was done and why, not every line. Every decision made for the
person has to reach them here. A ruling that isn't in the report was a decision made in secret.

## Build it

1. Run `gravity report`. It assembles the facts from the ledger: requirements, rulings, findings, countersigns,
   blocked tasks, commits and gates. You write only the prose around them.
2. Write the report in the shape below and store it with `gravity put --replace report.md`.
3. Run `gravity report --check`. Fix what it names and repeat.

## The shape

Keep these sections, in this order:

    Your calls
    Key signal
    What changed
    Requirements
    Rulings
    Noticed
    Not verified
    Look here
    Roll back
    Claims

**Your calls** is what waits on the person, and it is never cut. A call is something only they can take: a choice,
an approval, an irreversible action, access you lack. Work you can still do yourself is not a call. Never make up a call
to fill the section. Each one must be decidable from this report alone:

    <the call>. My pick: <pick>
    Effect: <what it changes for users>
    Evidence: <what backs the pick>
    Risk: <even when low, such as "Low: only the colors change">

Write "unknown" for a fact the call needs that you don't have. Never shrink or merge items to save words. Every floor
guard countersign appears here. So does any judgment gate overruled, with its ruling.

**Key signal** is the single thing they must not miss. Omit it if there isn't one. A failing G5, or G5 `not verified`
because the conf says `run = none`, is the Key signal.

**What changed** uses plain words, against the goal, with one small diagram when it helps. Say what changed for the
person using it before how you did it. Leave out hashes, paths and counts unless the reader needs one to act.

**Requirements** has one row each:

    R1 | <evidence> | measured, inferred or guess | external, project or suite

Say plainly when a requirement's proof is suite-only. In the Bug playbook, `R1` is the restated sentence.

**Rulings** go costliest first: what, why, cost if wrong. List every one in the ledger, including those the breaker made.

**Noticed** is what was left alone on purpose, deferred minors, what reviewers declined to judge, and any follow-ups
parked during the build.

**Not verified** gives each gap a reason (`runtime`, `outside repo`, `no command`, `blocked`, `insufficient`) and what
would settle it. List any blocked task, what didn't happen because of it, and any gate that failed.

**Look here** says where to start and how to run it.

**Roll back** says what would tell them to, and the exact steps.

**Claims** backs every prose fact above:

    C1 | <the claim as written> | <file:line, command or ledger line> | measured, inferred or guess

Hunt absolute words like always, only and never. Weaken them or prove them. Never cite a file you did not read or a
result you did not see.

If repo instructions overrode a playbook, say so here. If the goal changed after the plan, say that too.

## What the check does and doesn't do

`gravity report --check` fails if a requirement, ruling, finding, countersign, blocked task or commit is unaccounted for,
or if the final suite, G5 or G6 records a tree other than the branch's current one. A `not verified` or failed gate
counts only if the report lists it. Agents compress, and this catches what they drop. If it reports a stale tree, run
the stale gate again rather than editing the report.

It proves completeness, not truth, and it can't see a ruling that was never logged.

## Report reviewer (Standard and risk paths)

Dispatch the `report-reviewer` agent in the foreground, naming the diff, the ledger and the report. It re-derives each
row of the claims list, hunts absolute words, and looks for decisions visible in the diff with no ruling, adding them.
Log each decision it adds with `gravity ruling`, correct the report, store it with `gravity put --replace report.md`,
and run `gravity report --check` again.

## Exit

**Done when** `gravity report --check` exits 0 and, where it applies, the report reviewer's corrections are in. Run
`gravity wait --gate G7 --doc report.md`, show the report, then stop. The person's `/gravity:land` records G7.
