Goal: write down the decisions the implementer cannot make alone, so each step has exactly one reasonable reading.

The bar is unambiguous, not complete. Write for an engineer who has not seen this codebase or the design. They write
idiomatic code once they know the exact interface and the exact test. What they cannot know is what you decided: which
files, which names and signatures, which values, which proof.

Before tasks, map which files will be created or modified and what each is responsible for. In existing code, follow
established patterns. Prefer the simplest design that works. No abstraction without a second real use.

## The file

Standard writes `<plans>/YYYY-MM-DD-<topic>.md` and runs `gravity doc <path>`. Small adds these sections to its one
document, with `Design:` naming that same document. Use this shape exactly, since `gravity plan check` parses it:

````text
Design: docs/specs/x.md

## Goal
<one sentence>

## Global constraints
<one line each, exact values copied from the design>

## Review Focus
<up to five inputs the design implies but no test covers, most likely to bite first>
<input or condition>: <what a reasonable person would expect>. Pinned by Task <n>.

## Acceptance
- `cmd` expects `text` [R1, R2]
- `cmd` expects `text`

## Task 1: title
Requirements: R1, R2
Files: src/a.ts, src/a.test.ts
Interfaces: consumes <exact names and types>. Produces <exact names and types>.
Depends: none
Proof: test `cmd`
Allow: src/a.test.ts edited expected value is the requested behavior change
Steps:
1. ...
````

## Acceptance

Commands with expected output that prove the goal, each citing the requirements it proves. One citing none always
runs. When the conf says `run = none`, each command must be self-contained: it starts whatever it needs.

## Each field

- **`Requirements`** lists the R-numbers served.
- **`Files`** is the whole list. The floor guard fails on any path outside it.
- **`Interfaces`** are precise. A task's implementer sees only its own task, and this is how it learns its neighbors'
  names. `string` isn't enough when the truth is a UUID or an ISO 8601 date. Each endpoint lists its status codes,
  including errors.
- **`Depends`** is `none` or task numbers.
- **`Proof`** is one of:

| Proof | Written as | Use for |
|---|---|---|
| `test` | ``test `cmd` `` | The default. The failing test is committed first |
| `run` | ``run `cmd` expects `text` `` | Code that can't be unit tested. `gravity task start` runs it on the task's base and records it as not matching |
| `build` | `build` | Config or generated code only |

- **`Allow`** names a test or bar change the task is expected to make, and why. It is approved with the plan.

## What a step contains

A step is done when the implementer can write exactly one reasonable thing from it.

- **A test step:** the test's name and its assertions, with the design's exact values in them.
- **A code step:** the exact signature, the file, and the specific values the design pins. A body appears only for
  an algorithm the signature and tests do not determine.
- **A verification step:** the command and the output that means it passed.
- **A reference to another task:** that task's `Interfaces` says what to use. Don't repeat its code.

## Split and order

Fold setup, configuration and scaffolding into the task whose deliverable needs them. Split only where a reviewer
could reject one task and approve its neighbor. Prefer one complete path through the stack over one layer at a time.
Riskiest tasks go first, and dependencies decide the rest.

## Two failures to avoid

- **The transcript:** a plan that writes the program. Replace bodies with signatures, test names and assertions.
- **The empty promise:** a line that decides nothing, such as "handle edge cases", "add appropriate validation" or
  "write tests for the above". A type or function no task defines is the same failure.

## Self-review

Run this yourself and fix what it finds inline.

1. **Coverage.** For each requirement, point at a task. A requirement with no task gets one.
2. **Step scan.** A line that decides nothing is a gap. A body the signature and tests already determine is a transcript.
3. **Type consistency.** `clearLayers()` in Task 3 and `clearFullLayers()` in Task 7 is a bug.
4. **Review Focus.** Each line gets its test added to the task that owns the code. An empty section means you checked.
5. **Proportion.** If code blocks are most of the document, or it is several times longer than the design, cut it.
6. **Simplicity.** Name anything here that exists for a use nobody asked for, and remove it.

If a task cites a requirement and its `Proof` could pass with that requirement missing, the citation is decoration.
Change the proof.

## Check it

Run `gravity plan check <path> --design <design path>`.

- It **fails** on placeholder phrases, a requirement with no task, a task with no proof, a `run` proof with no
  expected output, non-self-contained `Acceptance` under `run = none`, an unknown dependency, a dependency cycle, or an
  unclosed code fence. Fix each and run it again.
- It **warns** when the plan is mostly code, is much longer than the design, a task touches about 5 files or more, or
  a title has "and". Fix what you agree with. The rest stays visible for the person at G2.
- It **prints a table** of every task pair sharing a file or interface. For each pair, compare what one produces with
  what the other consumes. Settle any conflict in the plan, against the design.

It proves shape only, never that the content is good.

## If the design changes

Editing an approved design voids its approval and any G2 built on it. Show the diff, get it approved again, and
re-plan. If the plan outgrows Small (more than 3 tasks or a risk path), run
`gravity playbook up standard --reason <reason>` and write the missing documents before continuing.

## Exit

**Done when** `gravity plan check` exits 0, the self-review is clean, and no unknown remains that would change the
build and only the person can answer.

Standard: run `gravity wait --gate G2 --doc <plan path>`, then stop. Small: run
`gravity wait --gate G1G2 --doc <document path>`, then stop. Their `/gravity:approve` records the gate. Questions end
there. After it, you rule.
