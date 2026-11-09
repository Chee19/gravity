Goal: make no claim about the code that fresh output from a check able to fail doesn't support.

If you haven't run the command that proves it, at the current tree, you cannot claim it.

## Before any claim

1. **Identify** the command that proves this claim.
2. **Run** the full command, fresh and complete.
3. **Read** the full output. Check the exit code and count failures.
4. **Compare.** If the output doesn't confirm the claim, state the actual status with the evidence. If it does, state
   the claim with the evidence.

Label what you say: measured, inferred or guess.

## The claim table

Used by every gate.

| Claim | Requires | Not enough |
|---|---|---|
| Tests pass | Fresh output showing zero failures, at the current tree | An earlier run |
| Bug fixed | The original symptom now passes | Code changed |
| Test is real | Seen failing for the right reason | It passes |
| Check can fail | Failed on a planted violation or on the base | It has never failed |
| Agent finished | The diff shows the change | The agent said so |
| Requirement met | A row in the requirement table with evidence | Tests are green |
| Survives a crash | The process was really killed | An injected exception |
| Nothing else uses it | The patterns, scope and hits, so the search can be re-run | "I searched" |

Stop if you catch yourself writing "should", "probably" or "seems to", or expressing satisfaction before the output is
in front of you.

## A pass is about specific code

Each gate line records the tree hash it ran on. Any later change to the tree makes that pass stale. After a fix wave,
run the checks again rather than carrying the old result forward.

`gravity gate` exits `0` for pass, `1` for fail and `2` for couldn't run. Code 2 is never a pass.

## Good tests

Before writing the test body, name the production change that would make this test fail.

| Your answer | Do |
|---|---|
| You cannot name one | Redesign around an observable behavior |
| "The source text changed" | Run the artifact and assert its effects |
| Only intentional decisions could fail it | It's a change detector. Test the behavior that depends on the decision |

- **Derive expected values without running the code under test.** Use literals and hand-checked fixtures.
- **Mirror assertions pass whatever the code does.** An expectation computed by the code or its helpers proves nothing.
- **Test the contract at your boundary:** the route you register, the query you emit, the payload you produce. Upstream
  mechanics are their maintainers' tests.
- **The mock earns no assertions.** If the mock is what you are checking, unmock it or delete the assertion.
- **Mock at the right level.** Learn every side effect of the real method first. Mock the slow or external operation
  and keep what the test depends on real.
- **Mirror real data completely.** Partial mocks pass while integration breaks.
- **A method only tests call** lives in test utilities, not production.

Before finishing, mutate the code in your head. At least one test should fail for each of these:

- a wrong constant or argument
- a wrong branch
- a missing state change or side effect
- an empty or default return
- missing validation for zero, empty, null, unauthorized or malformed input

A mutation nothing catches marks the behavior as unprotected, or the test as tautological.

Red needs the right failure. A test that fails on an import error or a typo has proved nothing about the behavior.

If the task's diff adds a test and you cannot name the break it catches, you didn't apply this.

## Not all proof is equal

Ask: could the agent make this pass by writing code that doesn't work?

| Class | Examples | Weight |
|---|---|---|
| `external` | A compiler, a real service | The agent can't argue with it |
| `project` | The repo's lint, types and build | A human owns the rules |
| `suite` | Tests the agent can edit | Useful, and the only circular one |

The report says plainly when a requirement's proof is suite-only.

## G5: the real thing runs on the real surface

Run `gravity gate G5` on the integrated branch. It runs the declared run command and every `Acceptance` check.
"Inconclusive" or the wrong surface is not a pass.

| Result | Do |
|---|---|
| Exit 0 | Go on to the review discipline |
| Exit 1 | One wave: `gravity fix round G5 --cause <c>`, `Files` being the union of every task's, then run the gate again |
| Still failing | The run stops at the report with G5 as the Key signal. `/gravity:land` refuses |
| Exit 2 | Run it once more, then `gravity halt` |
| The conf says `run = none` | G5 is `not verified` and becomes the report's Key signal |

An `Acceptance` check citing a requirement that depends on a blocked task is recorded as `not verified`, with the
reason blocked. Any other check the project has no command for is listed as not verified.

## The bar

Never move the bar to pass it. Commands come from the conf pinned at `run.start`. Any diff to `.gravity/**` or a `[bar]`
path fails G4 unless the task's approved `Allow` names it, or in the Bug playbook the person approves the diff. The floor
guard catches skipped or focused tests, deleted tests, a falling assertion count, changed expected values, new
suppressions, stubs, empty catch blocks, paths outside `Files`, and unplanned dependency changes. A hit fails unless
`Allow` covers it or a fresh reviewer countersigns. The agent that made the change can't clear it.

## Excuses recorded in the sources

| Excuse | Reality |
|---|---|
| "Should work now" | Run the verification |
| "I'm confident" | Confidence is not evidence |
| "Linter passed" | A linter doesn't compile the code |
| "Agent said success" | Check the diff |
| "Partial check is enough" | Partial proves nothing |

## Exit

**Done when** every claim you are about to make has fresh output behind it, and G5 is recorded by `gravity gate G5` as a
pass or stands as `not verified` with its reason. Then run `gravity next` and read the file it names.
