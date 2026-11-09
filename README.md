# Gravity

**Ask first. Prove every step. Report what happened.**

Gravity is a Claude Code plugin that takes a request from intent to reviewed, landable code. Progress is decided by something
outside the agent: a tool it doesn't write records every approval and every pass against the exact content it applied to.

Gravity doesn't make the agent smarter. It gives you a receipt for what actually happened.

```text
 request
    ▼
 ROUTER      kind x size x risk picks a playbook, stated out loud, overridable
    ▼
 YOU'RE IN THE ROOM    ask, you approve the design; plan, you approve the plan
 ════════════════ handoff: questions end, rulings begin ════════════════
 AGENT ALONE           isolate, build task by task with fresh review, verify, whole-branch review
 ════════════════ report: built from the ledger, checked against the code ═══
 YOU'RE BACK           you read the report and land it, and a receipt is written
    ▼
 CI                    the receipt must match the code being merged, tests rerun under the base rules
```

## Install

```text
claude plugin marketplace add <owner>/gravity
claude plugin install gravity@gravity
```

Then start a new session and run the setup wizard. `/gravity` won't start until you have:

```text
/gravity:setup
```

A private repo needs git credentials on each machine. Updates are not automatic: run `claude plugin update gravity@gravity`
and check the version with `/gravity:status`.

An opus orchestrating session is recommended, and a plugin can't set that for you.

Runtime needs only bash and git.

## Set up a repo

Two workflows active at once fight over the same work, so the wizard first asks which one stays on and turns the others off.
It then prepares the repo you're in, and you run it once more in each other repo. It writes `.gravity/project.conf`, then proves it by running each command clean and
confirming `test` and `lint` really fail on planted violations. A test command that can't fail is caught here. Commit the conf.

It also proposes allow rules so builds don't stall on permission prompts, and offers the CI receipt check. Both ask first.

## Use it

Type `/gravity` and your request. Gravity runs only when you do, and ordinary messages stay plain Claude. The router picks a playbook and says so.

| Playbook | When | You approve | Build |
|---|---|---|---|
| Tiny | One clear edit | Nothing | Direct, then the check. No run |
| Bug | Something is wrong | Only if risky, then landing | Worktree, failing test first |
| Small | One area, a few tasks | One combined doc, then landing | In session |
| Standard | Several areas, or risky | Design, plan, then landing | Fresh agent per task |

| Command | Does |
|---|---|
| `/gravity <request>` | Start Gravity on a request |
| `/gravity:setup` | The wizard: choose the one active workflow, then create and prove the project conf |
| `/gravity:approve` | Approve the document you were just shown |
| `/gravity:status` | Where every run stands, and the plugin version |
| `/gravity:resume [run]` | Take over an unfinished run, clear a halt or pause |
| `/gravity:abandon [run]` | Drop an unfinished run |
| `/gravity:land [patch\|pr\|keep\|discard]` | Land the run and write its receipt. With no argument, leaves it uncommitted for you |

Gravity never commits to your branch or pushes. If a session dies, the next one tells you what was left and resumes only when
you say so.

## What it enforces, and what it doesn't

Enforced by `bin/gravity`, which agents call and don't edit: approvals bound to a document's hash, gates bound to a tree hash,
red-before-green, a pinned conf, the bar guard, the floor guard, fix-round caps and report completeness.

Limits, stated plainly:

- Hooks are guardrails, not security. An agent with shell access could write the ledger. Approvals aren't signed, so a forged approval line reads as valid.
- The edit hook doesn't see files written through the shell.
- In CI, a PR can edit the workflow file, so protect `.github/workflows/gravity-verify.yml` and `.gravity/receipt-check` with code owners or branch rules.
- `report --check` proves completeness, not truth.

## Develop

```text
bash tests/run.sh all
```

The design is in `docs/specs/2026-11-09-gravity-design.md`. Adapted material is credited in `THIRD_PARTY_NOTICES.md`.
