# <Title>: Plan

Design: <docs/specs/x.md>
Goal: <One sentence>

## Global constraints

- <Exact values every task must use>

## Acceptance

Commands with expected output that prove the goal, each citing the requirements it proves. One citing none always runs.

- `<cmd>` expects `<text>` [R1, R2]

## Review Focus

Up to five inputs the design implies but no test covers. Pin each with a test in the task that owns the code.

- <Input or condition, and what a reasonable person expects>

## Task 1: <title>
Requirements: R1, R2
Files: <src/a.ts, src/a.test.ts>
Interfaces: <what it consumes and produces, with exact names and types. Each endpoint lists its status codes, including errors>
Depends: none
Proof: test `<cmd>`
Allow: <optional. src/a.test.ts edited expected value is the requested behavior change>
Steps:
1. <One action with a checkable result>

## Task 2: <title>
Requirements: R3
Files: <paths>
Interfaces: <exact names and types>
Depends: 1
Proof: run `<cmd>` expects `<text>`
Steps:
1. <One action with a checkable result>
