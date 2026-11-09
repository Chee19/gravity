Goal: let a capable builder make the hundred unmentioned decisions the way this person would have.

Small uses the short form: the same steps, each document section a line or two, no builder check.

## 1. Look first

Go through what they pointed at and the code it connects to. Keep reading until you can explain how the relevant
parts work today and what this change would touch. Never ask what the project or their context already answers, or
reopen what they have already decided.

## 2. Mirror the request

Your first message is 2 to 4 sentences, in your own words, in this shape:

```text
You want <what, for whom, why as far as they said>. <What you found that bears on it: a constraint, a conflict, a
cheaper path.> My best guess at what you're after: <one sentence>. Confidence: <n>%, <what is still missing if under 70>.
```

If nothing is left open and there is one sensible way, this first message is the short design: add the approach, a
line on why the others don't fit, and the design in a few lines. Write it to the design document and go to Exit.

## 3. Sort each unknown

A fact you could observe (behavior, timing, layout, output, performance) gets a look or a throwaway sketch in
`.gravity/scratch/`, where the rules invert: no tests, thrown away after. The design records what the sketch settled.
A preference or product call no experiment can settle goes to the question test.

## 4. The question test

Ask only when both are true:

- The answer would change what gets built.
- Neither the request, the project nor an experiment can answer it.

Process steps are always your call: writing things up, where files go, looking further, how to show something. Do
them and say so. For anything else that fails the test, state your call and your reason as a proposal they can correct.

## 5. How to ask

```text
Why I'm asking: <what the answer changes about what gets built>
<one focused question, in their terms>
My guess: <your answer and the reasoning that produced it>
```

- Ask about the why first, and ask it open: their own words, nothing to pick from. Your guess follows the question.
- Ask "what happens when X", built on their last answer or something you found. Never "any edge cases?".
- Never ask for an opinion you would override.
- One at a time when the next question depends on this answer. Batch only independent questions, at most 4. That is
  a ceiling, not a target.
- "Whatever you think" is delegation. Re-ask it as a choice between two options, with your pick.
- An answer that sounds like best practice ("scalable", "the standard way") hasn't told you what they want. Ask: "If
  you didn't have to justify this to anyone, what would you actually want?"
- Go one layer deeper each round: shape, boundaries, data, mechanics, risks. For each pick that matters, state what
  and why over what else.

## 6. Play back each part

As soon as you understand one part, describe it back, then return to questions about the next.

```text
Yours: <only what they said>
Proposed by me: <what I filled in>, because <reason>
How: you decided <...>. I decided <...>.
What's wrong or missing?
```

## 7. Scope check

When one request bundles capabilities that can each be tested alone (their own consumers or data, acceptance criteria
that cluster and could ship separately), get a small module map and build order approved before any design: one row
per module with its responsibility and what it depends on. Each module becomes its own run. This run covers the first.

## 8. Lay out the approaches

Once you understand what they want, in a message of its own. Come up with real alternatives and drop the weak ones,
including any that work against why they want it. Keep 2 or 3, grounded in what the project actually does:

```text
A. <what>. Why over the others: <...>. Trades off: <...>.
B. <what>. Why over the others: <...>. Trades off: <...>.
I recommend <A>, because <reason>. Which way do you want to go?
```

If they've handed you the how, say you'll go with your pick. If there is genuinely one sensible way, say so and why
the others don't fit.

## 9. Write the document as you go

From the first answer, write to `<specs>/YYYY-MM-DD-<topic>.md` and run `gravity doc <path>` once. Termination then
loses nothing. Approval state lives in the ledger, so approving never edits the document. Fill these slots:

```text
Intent and why
Goals
Non-goals
Constraints
Requirements
R1: <one testable behavior>
Approaches and the chosen one
Decided parts of the how (who decided each)
Left to the builder
What any sketch settled
```

Requirement lines start with `R1:` or `- R1:`. Tasks cite them and the report proves them.

## 10. Builder check (Standard only)

Dispatch the `builder-check` agent with the document's path and nothing else. Sort what it asks: **answered** by the
conversation or project goes in the document, **minor** you settle and mark as your call, and **yours** (only the person
can answer, and it changes what gets built) you bring in one message, most important first. Hand over the document with
a short list of the calls you made.

## Moving between playbooks

If the work outgrows its size, run `gravity playbook up <playbook> --reason <reason>` and say so out loud. If asking
reveals the wrong kind of work, return to the router. If several rounds in you still can't predict the answers, say that
something foundational is missing and ask to step back.

## Exit

**Done when** you can predict the person's reaction to the next three questions you would ask.

**Not done while** a core question keeps being deferred, whether to do it at all is still open, or two different
shapes are both alive.

Standard: run `gravity wait --gate G1 --doc <path>`, then stop. Their `/gravity:approve` records G1. Any edit after
the wait invalidates it, so run the wait again and show the change. Small: go to the plan discipline in the same
document. G1G2 is recorded when the plan is finished.
