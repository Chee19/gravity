#!/bin/bash
# Usage: tests/run.sh <core|plan|gates|review|hooks|setup|land|link|structure|all>

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
GDATA=$(mktemp -d)
: >"$GDATA/setup-done"
GB="$ROOT/bin/gravity"
PASS=0
FAILS=0
TMPS="$GDATA"

G() { bash "$GB" -C "$R" "$@"; }

t() {
  local name=$1 want=$2 rc
  shift 2
  OUT=$("$@" 2>&1)
  rc=$?
  if [ "$rc" = "$want" ]; then
    PASS=$((PASS + 1))
  else
    FAILS=$((FAILS + 1))
    printf 'FAIL %s: wanted exit %s, got %s\n%s\n' "$name" "$want" "$rc" "$OUT"
  fi
}

check() {
  local name=$1
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAILS=$((FAILS + 1))
    printf 'FAIL %s\nlast output: %s\n' "$name" "$OUT"
  fi
}

has() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
hasnt() { ! has "$1"; }

mk() {
  local parent
  parent=$(cd "$(mktemp -d)" && pwd -P)
  TMPS="$TMPS $parent"
  # A space in the path, because real workspaces have them.
  R="$parent/my repo"
  mkdir "$R"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@example.invalid
  git -C "$R" config user.name t
  mkdir -p "$R/.gravity" "$R/tests" "$R/src" "$R/docs/specs" "$R/docs/plans"
  cat >"$R/.gravity/project.conf" <<'EOF'
[commands]
test = bash check.sh | suite
run = bash check.sh | external

[paths]
specs = docs/specs
plans = docs/plans

[risk]
deny = npm publish, supabase db push

[bar]
paths = ci/** jest.config.*
EOF
  cat >"$R/check.sh" <<'EOF'
for f in tests/*.sh; do bash "$f" || { echo "FAIL $f"; exit 1; }; done
EOF
  printf 'true\n' >"$R/tests/base.sh"
  printf 'base\n' >"$R/src/base.txt"
  git -C "$R" add -A
  git -C "$R" commit -q -m init
  G setup exclude >/dev/null
}

hook() { printf '%s' "$2" | CLAUDE_PLUGIN_DATA="$GDATA" bash "$GB" hook "$1"; }
say_prompt() { hook user-prompt "{\"session_id\":\"${2:-S}\",\"cwd\":\"$R\",\"prompt\":\"$1\"}"; }
approve() { say_prompt /gravity:approve >/dev/null; }

write_docs() {
  cat >"$R/docs/specs/d.md" <<'EOF'
# Design
- R1: writes hello
EOF
  cat >"$R/docs/plans/p.md" <<'EOF'
# Plan

## Goal

Say hello.

## Global constraints

- bash only

## Acceptance

- `cat out.txt` expects `hello` [R1]

## Task 1: write hello

Requirements: R1
Files: out.txt, tests/a.sh
Interfaces: out.txt holds hello
Depends: none
Proof: test `bash tests/a.sh`
Steps:
1. write it
EOF
}

standard_run() {
  mk
  write_docs
  G run start --session S --playbook "${1:-standard}" --slug x >/dev/null
  if [ "${1:-standard}" = small ]; then
    G wait --gate G1G2 --doc docs/plans/p.md >/dev/null
    approve
  else
    G wait --gate G1 --doc docs/specs/d.md >/dev/null
    approve
    G wait --gate G2 --doc docs/plans/p.md >/dev/null
    approve
  fi
  W=$(G isolate)
}

commit_all() {
  git -C "$W" add -A
  git -C "$W" commit -q -m "$1"
}

red_commit() {
  printf 'grep -q hello out.txt\n' >"$W/tests/a.sh"
  commit_all red
  G red 1 >/dev/null
}

green_commit() {
  printf 'hello\n' >"$W/out.txt"
  commit_all green
}

through_task() {
  G gate G3 >/dev/null
  G task start 1 >/dev/null
  red_commit
  green_commit
  G task report 1 DONE >/dev/null
}

file_review() {
  local name=$1
  printf 'Verdict: Ship\nSafety: test at tests/a.sh:1 | level=ran\n' | G put "$name" >/dev/null
  G review check "$name" >/dev/null
}

to_report() {
  through_task
  G gate G4 1 >/dev/null
  file_review reviews/task-1.g1.1.md
  G gate G4R 1 >/dev/null
  G task done 1 >/dev/null
  G gate G5 >/dev/null
  file_review reviews/branch.g1.1.md
  G gate G6 >/dev/null
}

good_report() {
  local shas s
  shas=$(git -C "$W" rev-list "$(git -C "$R" rev-parse main)..HEAD" | cut -c1-7 | tr '\n' ' ')
  printf '# R\n## Your calls\nnone\n## What changed\nhello R1\n## Requirements\nR1\n## Rulings\nnone\n## Noticed\nnone\n## Not verified\nnone\n## Look here\nout.txt\n## Roll back\nrevert %s\n' "$shas"
}

to_landable() {
  standard_run
  to_report
  good_report | G put --replace report.md >/dev/null
  G report --check >/dev/null
}

suite_core() {
  mk
  rm "$R/.gravity/project.conf"
  t "run start needs conf" 2 G run start --session S --playbook standard --slug x
  mk
  t "bad playbook refused" 2 G run start --session S --playbook tiny --slug x
  t "run start" 0 G run start --session S --playbook standard --slug x
  check "prints run id" has "-x"
  local id=$OUT
  check "ledger written" [ -f "$R/.git/gravity/runs/$id/ledger.log" ]
  check "conf pinned" [ -f "$R/.git/gravity/runs/$id/project.conf" ]
  t "status" 0 G status
  t "status --run" 0 G status --run "$id"
  check "status shows playbook" has "playbook: standard"
  check "status shows counts" has "said_done=0"
  t "next" 0 G next
  check "next names ask" has "disciplines/ask.md"
  t "put" 0 bash -c "printf 'a\n' | bash '$GB' -C '$R' put notes.md"
  t "put refuses overwrite" 1 bash -c "printf 'b\n' | bash '$GB' -C '$R' put notes.md"
  t "put refuses escape" 2 bash -c "printf 'b\n' | bash '$GB' -C '$R' put ../x.md"
  t "replace only report" 2 bash -c "printf 'b\n' | bash '$GB' -C '$R' put --replace notes.md"
  t "put replaces report" 0 bash -c "printf 'b\n' | bash '$GB' -C '$R' put report.md"
  t "put replaces report twice" 0 bash -c "printf 'c\n' | bash '$GB' -C '$R' put --replace report.md"
  t "put refuses a token" 1 bash -c "printf 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3In0.abc\n' | bash '$GB' -C '$R' put j.md"
  t "put refuses secret" 1 bash -c "printf 'AKIAABCDEFGHIJKLMNOP\n' | bash '$GB' -C '$R' put s.md"
  check "secret not printed" hasnt "AKIAABCD"
  check "refused secret not stored" [ ! -e "$R/.git/gravity/runs/$id/s.md" ]
  t "wait needs doc" 2 G wait --gate G1 --doc docs/specs/none.md
  write_docs
  t "wait" 0 G wait --gate G1 --doc docs/specs/d.md
  t "next waits" 0 G next
  check "next says wait" has "wait for the human"
  t "halt" 0 G halt broken
  t "next after halt still waits on open wait" 0 G next
  t "second run makes it ambiguous" 0 G run start --session T --playbook bug --slug y
  t "ambiguous run refused" 2 G next
  check "says pass run" has "several unfinished"
  t "--run picks one" 0 bash "$GB" -C "$R" --run "$id" next
  sed -i '' 's/format=1/format=9/' "$R/.git/gravity/runs/$id/ledger.log"
  t "format mismatch refused" 2 bash "$GB" -C "$R" --run "$id" next
  check "format message" has "ledger format 9"
  t "outside a repo" 2 bash "$GB" -C /tmp status
}

plan_with() {
  printf '%s\n' "$1" >"$R/docs/plans/bad.md"
  t "$2" "$3" G plan check docs/plans/bad.md --design docs/specs/d.md
}

TASK_OK='## Task 1: one
Requirements: R1
Files: a.txt
Depends: none
Proof: test `true`
Steps:
1. x'

suite_plan() {
  mk
  write_docs
  t "good plan" 0 G plan check docs/plans/p.md --design docs/specs/d.md
  check "pair table" has "tasks sharing files"
  plan_with "$TASK_OK
Add TBD here" "placeholder" 1
  plan_with '## Task 1: one
Files: a.txt
Depends: none
Proof: test `true`' "requirement with no task" 1
  plan_with '## Task 1: one
Requirements: R1
Files: a.txt
Depends: none' "no proof" 1
  plan_with '## Task 1: one
Requirements: R1
Files: a.txt
Proof: run `x`' "run proof with no expected output" 1
  plan_with '## Task 1: one
Requirements: R1
Files: a.txt
Depends: 9
Proof: build' "unknown dependency" 1
  plan_with '## Task 1: one
Requirements: R1
Files: a.txt
Depends: 2
Proof: build

## Task 2: two
Requirements: R1
Files: b.txt
Depends: 1
Proof: build' "dependency cycle" 1
  plan_with "$TASK_OK
\`\`\`
open" "unclosed fence" 1
  plan_with '## Task 1: this and that
Requirements: R1
Files: a,b,c,d,e
Depends: none
Proof: build' "warns only" 0
  check "warn on and" has "'and' in its title"
  check "warn on files" has "touches 5 files"

  standard_run
  t "task before G3" 1 G task start 1
  t "G3" 0 G gate G3
  t "task start" 0 G task start 1
  t "task start twice is safe" 0 G task start 1
  t "unknown task" 2 G task start 7
  t "brief" 0 G brief 1
  local b=$OUT
  check "brief has requirement" grep -q 'R1: writes hello' "$b"
  check "brief has constraints" grep -q 'bash only' "$b"
  t "second brief is new" 0 G brief 1 --note "use out.txt"
  check "new attempt" has "task-1.g1.2.md"
  check "note kept" grep -q 'use out.txt' "$OUT"
  printf 'true\n' >"$W/tests/a.sh"
  commit_all fakered
  t "red refuses a passing test" 1 G red 1
  printf 'x\n' >"$W/dirty.txt"
  t "red refuses dirty tree" 2 G red 1
  rm "$W/dirty.txt"
  printf 'false\n' >"$W/tests/a.sh"
  commit_all red
  t "red records" 0 G red 1
  t "round 1" 0 G fix round 1 --cause gate
  t "round 2 attacks premise" 0 G fix round 1 --cause gate
  check "premise prompt" has "assumption the failed fixes share"
  t "round 3" 0 G fix round 1 --cause gate
  t "round 4 stronger" 0 G fix round 1 --cause gate
  check "stronger model" has "stronger model"
  t "round 5 refused" 1 G fix round 1 --cause gate
  t "G5 wave" 0 G fix round G5 --cause gate
  t "second G5 wave refused" 1 G fix round G5 --cause gate
  t "unknown status" 2 G task report 1 MAYBE
  t "block" 0 G task block 1 stuck
  t "blocked cannot restart" 1 G task start 1
}

suite_gates() {
  standard_run
  git -C "$W" config user.email t@example.invalid
  printf 'x\n' >"$W/dirty.txt"
  t "dirty is couldn't run" 2 G gate G3
  rm "$W/dirty.txt"
  t "unknown gate" 2 G gate G9
  printf 'hello\n' >"$W/out.txt"
  commit_all premature
  t "acceptance already passing fails G3" 1 G gate G3
  check "says cannot tell" has "cannot tell"
  git -C "$W" reset -q --hard HEAD~1
  printf 'false\n' >"$W/tests/base.sh"
  commit_all brokenbase
  t "bad baseline fails G3" 1 G gate G3
  git -C "$W" reset -q --hard HEAD~1
  printf '# changed\n' >>"$R/docs/plans/p.md"
  t "changed plan fails G3" 1 G gate G3
  check "fingerprint message" has "changed since approval"
  sed -i '' '$d' "$R/docs/plans/p.md"
  t "G3 passes" 0 G gate G3

  G task start 1 >/dev/null
  printf 'hello\n' >"$W/out.txt"
  printf 'grep -q hello out.txt\n' >"$W/tests/a.sh"
  commit_all together
  t "no red fails G4" 1 G gate G4 1
  check "says red" has "no recorded red"
  git -C "$W" reset -q --hard HEAD~1
  red_commit
  t "red but not green fails G4" 1 G gate G4 1
  green_commit
  t "G4 passes" 0 G gate G4 1
  t "G4 review missing fails" 1 G gate G4R 1
  t "task done needs review" 1 G task done 1
  file_review reviews/task-1.g1.1.md
  t "G4R passes" 0 G gate G4R 1
  printf 'more\n' >>"$W/out.txt"
  commit_all later
  t "stale pass refuses done" 1 G task done 1
  check "says stale" has "stale"

  # A diff line whose content looks like a file header must not desync the parser.
  standard_run
  G gate G3 >/dev/null
  G task start 1 >/dev/null
  red_commit
  green_commit
  mkdir -p "$W/ci" "$W/deep/tests"
  printf 'x\n' >"$W/ci/a.yml"
  commit_all bar
  t "bar guard fails" 1 G gate G4 1
  check "names bar path" has "ci/a.yml"
  git -C "$W" reset -q --hard HEAD~1

  floor_case() {
    local name=$1 file=$2 body=$3 kind=$4
    mkdir -p "$W/$(dirname "$file")"
    printf '%b' "$body" >"$W/$file"
    commit_all floorcase
    t "$name" 1 G gate G4 1
    check "$name reports kind" has "floor guard: $kind"
    check "$name says floor-only" has "floor-only"
    git -C "$W" reset -q --hard HEAD~1
  }
  floor_case "outside files" src/other.txt 'x\n' outside-files
  floor_case "manifest" package.json '{}\n' manifest
  printf 'grep -q hello out.txt\n# expect(1)\n' >"$W/tests/a.sh"
  commit_all more
  G fix round 1 --cause gate >/dev/null
  t "still passes with assertion added" 0 G gate G4 1

  standard_run
  cat >>"$R/docs/plans/p.md" <<'EOF'
Allow: src/kept.txt expected by the plan
EOF
  sed -i '' 's/^Files: out.txt, tests\/a.sh/Files: out.txt, tests\/*, src\/*/' "$R/docs/plans/p.md"
  G wait --gate G2 --doc docs/plans/p.md >/dev/null
  G plan change "widen" >/dev/null
  G wait --gate G2 --doc docs/plans/p.md >/dev/null
  approve
  G gate G3 >/dev/null
  printf 'it("a", () => expect(1).toBe(1))\nexpect(2)\n' >"$W/tests/d.test.js"
  commit_all assertbase
  G task start 1 >/dev/null
  red_commit
  green_commit
  mkdir -p "$W/src"
  floor_hit() {
    local name=$1 file=$2 body=$3 kind=$4
    printf '%b' "$body" >"$W/$file"
    commit_all f
    t "$name" 1 G gate G4 1
    check "$name kind" has "floor guard: $kind $file:"
    check "$name hides source" hasnt "SECRETVALUE"
    git -C "$W" reset -q --hard HEAD~1
  }
  floor_hit "skip" tests/b.test.js 'it.skip("SECRETVALUE", f)\n' skip
  floor_hit "focus" tests/c.spec.js 'describe.only("a", f)\n' skip
  floor_hit "suppression" src/a.ts '// eslint-disable-next-line SECRETVALUE\nx\n' suppression
  floor_hit "stub" src/b.py 'raise NotImplementedError("SECRETVALUE")\n' stub
  floor_hit "empty catch" src/c.js 'try { f() } catch (e) {}\n' empty-catch
  git -C "$W" rm -q tests/d.test.js
  commit_all removetest
  t "deleted test" 1 G gate G4 1
  check "deleted test kind" has "floor guard: deleted-test tests/d.test.js"
  git -C "$W" reset -q --hard HEAD~1
  printf 'it("a", () => expect(1).toBe(2))\nexpect(2)\n' >"$W/tests/d.test.js"
  commit_all changeassert
  t "changed expected value" 1 G gate G4 1
  check "assert kind" has "floor guard: assert-removed tests/d.test.js"
  check "floor-only" has "floor-only"
  printf 'Verdict: Ship\nSafety: test | level=ran\nFLOOR-OK: assert-removed tests/d.test.js expected value is the change\n' | G put reviews/task-1.g2.1.md >/dev/null
  t "countersign clears" 0 G gate G4 1
  git -C "$W" reset -q --hard HEAD~1
  # +++ inside a hunk is content, not a header.
  printf '+++ b/ghost\n--- a/ghost\nnormal\n' >"$W/src/plus.txt"
  commit_all plus
  printf '++ b/nope\n' >>"$W/src/plus.txt"
  commit_all plus2
  OUT=$(G gate G4 1 2>&1)
  check "no ghost path" hasnt "ghost"

  mk
  cat >>"$R/.gravity/project.conf" <<'EOF'

[baseline]
known_failing = .gravity/known.txt
EOF
  printf 'tests/flaky\n' >"$R/.gravity/known.txt"
  printf 'echo "FAIL tests/flaky"; exit 1\n' >"$R/check.sh"
  git -C "$R" add -A
  git -C "$R" commit -q -m known
  write_docs
  G run start --session S --playbook standard --slug x >/dev/null
  G wait --gate G1 --doc docs/specs/d.md >/dev/null
  approve
  G wait --gate G2 --doc docs/plans/p.md >/dev/null
  approve
  W=$(G isolate)
  t "known failure tolerated" 0 G gate G3
  printf 'echo "FAIL tests/flaky"; echo "FAIL tests/new"; exit 1\n' >"$W/check.sh"
  commit_all newfail
  t "new failure not tolerated" 1 G gate G3
  printf 'echo crashed; exit 1\n' >"$W/check.sh"
  commit_all unrecognised
  t "unrecognised failure not tolerated" 1 G gate G3

  mk
  sed -i '' 's/^test = .*/test = no-such-binary-xyz | suite/' "$R/.gravity/project.conf"
  git -C "$R" add -A
  git -C "$R" commit -q -m broken
  write_docs
  G run start --session S --playbook standard --slug x >/dev/null
  G wait --gate G1 --doc docs/specs/d.md >/dev/null
  approve
  G wait --gate G2 --doc docs/plans/p.md >/dev/null
  approve
  W=$(G isolate)
  t "missing command is couldn't run" 2 G gate G3

  standard_run
  to_report_until_g5() {
    through_task
    G gate G4 1 >/dev/null
    file_review reviews/task-1.g1.1.md
    G gate G4R 1 >/dev/null
    G task done 1 >/dev/null
  }
  to_report_until_g5
  t "G5 passes" 0 G gate G5
  git -C "$W" rm -q out.txt
  commit_all break
  t "G5 fails when acceptance fails" 1 G gate G5
  G next >/dev/null
  t "next offers a wave" 0 G next
  check "wave offered" has "fix round G5"

  mk
  sed -i '' 's/^run = .*/run = none | library/' "$R/.gravity/project.conf"
  git -C "$R" add -A
  git -C "$R" commit -q -m norun
  write_docs
  G run start --session S --playbook small --slug x >/dev/null
  G wait --gate G1G2 --doc docs/plans/p.md >/dev/null
  approve
  W=$(G isolate)
  through_task
  t "small G4 has no floor" 0 G gate G4 1
  t "small done needs no review" 0 G task done 1
  t "no run command is not verified" 0 G gate G5
  check "notverified" has "G5 notverified"
  mkdir -p "$W/src"
  printf 'try { f() } catch (e) {}\n' >"$W/src/x.js"
  commit_all sneak
  file_review reviews/branch.g1.1.md
  G gate G5 >/dev/null
  t "small floor runs at G6" 1 G gate G6
  check "floor at G6" has "floor guard: outside-files src/x.js"

  mk
  G run start --session S --playbook bug --slug b >/dev/null
  W=$(G isolate)
  t "B1 needs evidence" 2 G gate B1
  t "B1 evidence must exist" 1 G gate B1 --evidence b1.md
  printf 'when x then y\n' | G put b1.md >/dev/null
  t "B1" 0 G gate B1 --evidence b1.md
  printf 'Files: out.txt, tests/a.sh, ci/x.yml\n' | G put diagnosis.md >/dev/null
  t "B2" 0 G gate B2 --evidence diagnosis.md
  t "B3 needs red" 1 G gate B3
  printf 'grep -q hello out.txt\n' >"$W/tests/a.sh"
  commit_all red
  t "red B3" 0 G red B3 --cmd "bash tests/a.sh"
  t "B3" 0 G gate B3
  t "B4 not green" 1 G gate B4
  printf 'hello\n' >"$W/out.txt"
  mkdir -p "$W/ci"
  printf 'y\n' >"$W/ci/x.yml"
  commit_all fix
  t "B4 bar diff needs approval" 1 G gate B4
  check "tells to wait" has "gravity wait --gate B4"
  G wait --gate B4 --doc patches/bar-diff.1.patch >/dev/null
  approve
  t "B4 with approved bar diff" 0 G gate B4
  printf 'z\n' >>"$W/ci/x.yml"
  commit_all morebar
  t "B4 refuses a bar diff that moved" 1 G gate B4
}

suite_review() {
  standard_run
  G gate G3 >/dev/null
  G task start 1 >/dev/null
  t "empty range refused" 1 G package 1
  red_commit
  green_commit
  t "package" 0 G package 1
  check "names review file" has "reviews/task-1.g1.1.md"
  t "non-descendant refused" 1 G package 1 --since "$(git -C "$R" commit-tree -m x "$(git -C "$R" rev-parse 'HEAD^{tree}')")"

  rev() {
    local n=$1 body=$2 want=$3
    printf '%b' "$body" | G put "reviews/task-1.g1.$n.md" >/dev/null
    t "review $n" "$want" G review check "reviews/task-1.g1.$n.md"
  }
  rev 1 'Safety: x\n' 1
  check "no verdict" has "no valid Verdict"
  rev 2 'Verdict: Ship\n' 1
  check "no safety" has "no Safety"
  rev 3 'Verdict: Minor\nSafety: x\nF1 | out.txt:9 | hello | boom | Minor | regression\n' 1
  check "anchor quote" has "quote is not at"
  rev 4 'Verdict: Minor\nSafety: x\nF1 | nope.txt:1 | hello | boom | Minor | regression\n' 1
  check "missing file" has "no such file"
  rev 5 'Verdict: Minor\nSafety: x\nF1 | check.sh:1 | for f | boom | Minor | regression\n' 1
  check "outside the diff" has "outside the diff"
  rev 6 'Verdict: Rework\nSafety: x\nF1 | check.sh:1 | for f | boom | Important | pre-existing\n' 1
  check "pre-existing no rework" has "pre-existing"
  rev 7 'Verdict: Ship\nSafety: x\nAbsence: patterns=hello scope=out.txt hits=0\n' 1
  check "absence mismatch" has "found 1"
  rev 8 'Verdict: Minor\nSafety: x\nF1 | out.txt:1 | hello | boom | Minor | regression\nAbsence: patterns=hello scope=out.txt hits=1\n' 0
  t "G4R open finding" 1 G gate G4R 1
  check "lists open" has "F1"
  t "finding disposition" 0 G finding --id F1 --task 1 --disposition defer --why later
  t "bad disposition" 2 G finding --id F1 --task 1 --disposition shrug --why later
  t "G4R after disposition" 0 G gate G4R 1
  rev 9 'Verdict: Rework\nSafety: x\nF2 | out.txt:1 | hello | boom | Important | regression\n' 0
  t "G4R Rework is open" 1 G gate G4R 1
  G finding --id F2 --task 1 --disposition fix --why real >/dev/null
  t "fix alone does not close it" 1 G gate G4R 1
  rev 10 'Verdict: Minor\nSafety: x\nF2 NOT\n' 0
  t "NOT stays open" 1 G gate G4R 1
  rev 11 'Verdict: Ship\nSafety: x\nF2 ADDRESSED\n' 0
  t "ADDRESSED closes it" 0 G gate G4R 1
  t "gaps in attempts are fine" 0 bash -c "printf 'Verdict: Ship\nSafety: x\n' | bash '$GB' -C '$R' put reviews/task-1.g1.20.md"
  G review check reviews/task-1.g1.20.md >/dev/null
  t "newest attempt wins across a gap" 0 G gate G4R 1
  rev 21 'Verdict: Cannot verify\nSafety: unproven\n' 0
  t "Cannot verify fails" 1 G gate G4R 1

  standard_run
  to_report
  t "report needs a file" 2 G report --check
  G report >/dev/null
  t "facts" 0 G report
  check "facts list commits" has "commits:"
  printf '# nothing\n' | G put report.md >/dev/null
  t "empty report fails" 1 G report --check
  check "names section" has "missing section"
  check "names requirement" has "R1"
  check "names commit" has "commit "
  G ruling --cost low --what "kept the name" --why "design says so" >/dev/null
  good_report | G put --replace report.md >/dev/null
  t "ruling must appear" 1 G report --check
  check "names ruling" has "kept the name"
  { good_report; printf 'kept the name\n'; } | G put --replace report.md >/dev/null
  t "report passes" 0 G report --check
  printf 'more\n' >>"$W/out.txt"
  commit_all later
  { good_report; printf 'kept the name\n'; } | G put --replace report.md >/dev/null
  t "stale tree fails report" 1 G report --check
  check "stale message" has "tree other than"

  standard_run
  G gate G3 >/dev/null
  G task start 1 >/dev/null
  printf 'half\n' >"$W/half.txt"
  t "recover saves dirty work" 0 G recover
  check "saved" has "saved uncommitted work"
  check "patch kept" [ -s "$(ls "$R"/.git/gravity/runs/*/patches/dirty.1.patch)" ]
  check "tree clean" [ -z "$(git -C "$W" status --porcelain)" ]
  t "recover again is safe" 0 G recover
  red_commit
  green_commit
  t "recover keeps passing work" 0 G recover
  check "recovered" has "recovered"
  check "head kept" [ -f "$W/out.txt" ]

  standard_run
  G gate G3 >/dev/null
  G task start 1 >/dev/null
  red_commit
  t "recover resets unproven work" 0 G recover
  check "reset" has "saved"
  check "red dropped" [ ! -f "$W/tests/a.sh" ]

  standard_run
  G gate G3 >/dev/null
  G task start 1 >/dev/null
  red_commit
  G fix round 1 --cause gate >/dev/null
  t "open fix round continues" 0 G recover
  check "continue at round" has "continue at fix round 1"
  check "work kept" [ -f "$W/tests/a.sh" ]
}

suite_hooks() {
  mk
  local ctx='{"session_id":"S","cwd":"'"$R"'","source":"startup"}'
  local real=$GDATA
  GDATA=$(mktemp -d)
  TMPS="$TMPS $GDATA"
  t "reminder before setup" 0 hook session-start "$ctx"
  check "tells the person" has '"systemMessage":"Gravity is installed but not set up'
  t "/gravity refused before setup" 0 say_prompt "/gravity add csv export"
  check "blocked" has '"decision":"block"'
  t "/gravity:gravity refused before setup" 0 say_prompt "/gravity:gravity add csv export"
  check "blocked too" has '"decision":"block"'
  t "ordinary prompt untouched before setup" 0 say_prompt "hello there"
  check "ordinary silent" [ -z "$OUT" ]
  t "setup done needs a scope" 2 bash "$GB" -C "$R" setup done
  t "user scope needs a folder" 2 bash "$GB" -C "$R" setup done --scope user
  t "local setup recorded" 0 bash "$GB" -C "$R" setup done --scope local
  t "local setup lifts the block in this repo" 0 say_prompt "/gravity add csv export"
  check "no longer blocked" hasnt '"decision":"block"'
  rm "$R/.git/gravity/setup-done"
  t "user setup recorded" 0 bash "$GB" -C /tmp setup done --scope user --data "$GDATA"
  t "user setup lifts the block" 0 say_prompt "/gravity add csv export"
  check "user setup not blocked" hasnt '"decision":"block"'
  GDATA=$real
  t "session start silent with no run" 0 hook session-start "$ctx"
  check "nothing injected" [ -z "$OUT" ]
  t "silent outside a repo" 0 hook session-start '{"session_id":"S","cwd":"/tmp","source":"startup"}'
  check "nothing outside a repo" [ -z "$OUT" ]
  t "/gravity gives the session id" 0 say_prompt "/gravity add csv export"
  check "valid shape" has '"hookEventName":"UserPromptSubmit"'
  check "carries session id" has "Gravity session id: S"
  t "/gravity:gravity too" 0 say_prompt "/gravity:gravity add csv export"
  check "namespaced carries id" has "Gravity session id: S"
  t "bare /gravity" 0 say_prompt "/gravity"
  check "bare carries id" has "Gravity session id: S"
  t "lookalike ignored" 0 say_prompt "/gravityish hello"
  check "lookalike silent" [ -z "$OUT" ]
  t "no run is silent" 0 hook pre-tool '{"session_id":"S","cwd":"'"$R"'","tool_name":"Bash","tool_input":{"command":"git push"}}'
  check "silent" [ -z "$OUT" ]
  t "garbage input is safe" 0 hook pre-tool 'not json'
  t "non-gravity prompt silent" 0 say_prompt "hello there"
  check "prompt silent" [ -z "$OUT" ]
  t "approve with no run" 0 say_prompt /gravity:approve
  check "says no run" has "owns no run"

  write_docs
  local id
  id=$(G run start --session S --playbook standard --slug x)
  t "owner gets the router back after compaction" 0 hook session-start '{"session_id":"S","cwd":"'"$R"'","source":"compact"}'
  check "router restored" has "Classify"
  check "root substituted" has "$ROOT"
  check "no raw plugin root" hasnt "CLAUDE_PLUGIN_ROOT"
  check "no raw arguments" hasnt "ARGUMENTS"
  t "owner resume is brief" 0 hook session-start '{"session_id":"S","cwd":"'"$R"'","source":"resume"}'
  check "no router on resume" hasnt "Classify"
  check "id on resume" has "Gravity session id: S"
  t "other session is not given the router" 0 hook session-start '{"session_id":"T","cwd":"'"$R"'","source":"compact"}'
  check "no router for others" hasnt "Classify"
  t "other session unguarded" 0 hook pre-tool '{"session_id":"T","cwd":"'"$R"'","tool_name":"Write","tool_input":{"file_path":"'"$R"'/src/a.ts"}}'
  check "unguarded" [ -z "$OUT" ]
  t "other session is told" 0 hook session-start '{"session_id":"T","cwd":"'"$R"'","source":"startup"}'
  check "resume or abandon" has "/gravity:resume"
  edit() { hook pre-tool '{"session_id":"S","cwd":"'"$R"'","tool_name":"Write","tool_input":{"file_path":"'"$1"'","content":"\"file_path\": \"/etc/x\""}}'; }
  t "code edit denied before plan" 0 edit "$R/src/a.ts"
  check "denied" has '"permissionDecision":"deny"'
  t "docs edit allowed" 0 edit "$R/docs/specs/d.md"
  check "allowed" [ -z "$OUT" ]
  t "scratch allowed" 0 edit "$R/.gravity/scratch/a.sh"
  check "scratch ok" [ -z "$OUT" ]
  t "dot dot denied" 0 edit "$R/docs/specs/nope/../../../src/a.ts"
  check "traversal denied" has '"permissionDecision":"deny"'
  sh() { hook pre-tool '{"session_id":"S","cwd":"'"$R"'","tool_name":"Bash","tool_input":{"command":"'"$1"'"}}'; }
  for c in "git push" "git -C /x push origin" "ls; git push -u o b" "gh pr merge 3" "npm publish" "supabase db push"; do
    t "denied: $c" 0 sh "$c"
    check "denied json: $c" has '"permissionDecision":"deny"'
  done
  for c in "git status" "git log --grep push" "npm test"; do
    t "allowed: $c" 0 sh "$c"
    check "allowed: $c" [ -z "$OUT" ]
  done

  t "nothing to approve" 0 say_prompt /gravity:approve
  check "no wait" has "nothing is awaiting"
  G wait --gate G1 --doc docs/specs/d.md >/dev/null
  printf 'changed\n' >>"$R/docs/specs/d.md"
  t "changed doc refused" 0 say_prompt /gravity:approve
  check "refused" has "changed since it was shown"
  G wait --gate G1 --doc docs/specs/d.md >/dev/null
  t "other session cannot approve" 0 say_prompt /gravity:approve T
  check "other refused" has "owns no run"
  t "approve records" 0 say_prompt /gravity:approve
  check "approved" has "G1 approved"
  check "ledger line" grep -q 'gate=G1' "$R/.git/gravity/runs/$id/ledger.log"
  printf '## Task 1: x\nRequirements: R9\nProof: nothing\n' >"$R/docs/plans/bad.md"
  G wait --gate G2 --doc docs/plans/bad.md >/dev/null
  t "plan check blocks approval" 0 say_prompt /gravity:approve
  check "plan refused" has "plan check failed"
  G wait --gate G2 --doc docs/plans/p.md >/dev/null
  t "stop before handoff allowed" 0 hook stop '{"session_id":"S","cwd":"'"$R"'"}'
  check "open wait" [ -z "$OUT" ]
  approve
  t "stop after handoff blocks" 0 hook stop '{"session_id":"S","cwd":"'"$R"'"}'
  check "blocked" has '"decision":"block"'
  G pause lunch >/dev/null
  t "stop while paused" 0 hook stop '{"session_id":"S","cwd":"'"$R"'"}'
  check "paused allows" [ -z "$OUT" ]
  t "resume takes ownership" 0 say_prompt "/gravity:resume $id" T
  check "owner moved" has "now owns run"
  check "resume loads the router" has "Classify"
  t "stop for new owner blocks" 0 hook stop '{"session_id":"T","cwd":"'"$R"'"}'
  check "new owner blocked" has '"decision":"block"'
  t "edit outside worktree denied" 0 hook pre-tool '{"session_id":"T","cwd":"'"$R"'","tool_name":"Edit","tool_input":{"file_path":"'"$R"'/src/a.ts"}}'
  check "build denies main" has '"permissionDecision":"deny"'
  t "edit in worktree allowed" 0 hook pre-tool '{"session_id":"T","cwd":"'"$R"'","tool_name":"Edit","tool_input":{"file_path":"'"$R"'/.gravity/worktrees/'$id'/src/a.ts"}}'
  check "worktree ok" [ -z "$OUT" ]
  t "unknown land mode" 0 say_prompt "/gravity:land sideways" T
  check "mode refused" has "unknown landing mode"
  t "abandon" 0 say_prompt "/gravity:abandon $id" T
  t "abandoned leaves nothing open" 0 G status
  check "no runs" has "no unfinished runs"

  local big
  big=$(awk 'BEGIN{for(i=0;i<20000;i++) printf "padding text %d ",i}')
  local start=$SECONDS
  t "large payload" 0 hook pre-tool '{"session_id":"S","cwd":"/tmp","tool_name":"Write","tool_input":{"content":"'"$big"'","file_path":"/tmp/x"}}'
  check "large payload is quick" [ $((SECONDS - start)) -lt 5 ]
  check "hooks manifest parses" bash -c "grep -q 'hook session-start' '$ROOT/hooks/hooks.json'"
}

suite_setup() {
  mk
  local tp lint
  tp=$(mktemp)
  lint=$(mktemp)
  TMPS="$TMPS $tp $lint"
  cat >"$tp" <<'EOF'
--- /dev/null
+++ b/tests/planted.sh
@@ -0,0 +1 @@
+false
EOF
  cat >"$lint" <<'EOF'
--- /dev/null
+++ b/lint-marker
@@ -0,0 +1 @@
+x
EOF
  printf '[ ! -e lint-marker ]\n' >"$R/lint.sh"
  sed -i '' 's/^run = .*/lint = bash lint.sh | project/' "$R/.gravity/project.conf"
  git -C "$R" add -A
  git -C "$R" commit -q -m lint
  t "prove passes" 0 G setup prove --test-plant "$tp" --lint-plant "$lint"
  check "throwaway removed" [ ! -d "$R/.gravity/worktrees" ]
  sed -i '' 's/^test = .*/test = true | suite/' "$R/.gravity/project.conf"
  t "a test that cannot fail is caught" 1 G setup prove --test-plant "$tp" --lint-plant "$lint"
  check "proves nothing" has "proves nothing"
  sed -i '' 's/^test = .*/test = bash check.sh | suite/; s/^lint = .*/lint = true | project/' "$R/.gravity/project.conf"
  t "a lint that cannot fail is caught" 1 G setup prove --test-plant "$tp" --lint-plant "$lint"
  t "bad patch" 1 G setup prove --test-plant "$lint" --lint-plant "$lint"
  t "no patch" 2 G setup prove --test-plant /nope --lint-plant "$lint"
  G setup exclude >/dev/null
  G setup exclude >/dev/null
  check "exclude once" [ "$(grep -c 'gravity/worktrees' "$R/.git/info/exclude")" = 1 ]
  t "setup ci" 0 G setup ci
  check "checker copied" [ -f "$R/.gravity/receipt-check" ]
  check "workflow uses base" grep -q 'BASE:.gravity/receipt-check' "$R/.github/workflows/gravity-verify.yml"
}

suite_land() {
  to_landable
  local id
  id=$(ls "$R/.git/gravity/runs")
  t "land needs the human" 1 G land
  check "says who" has "/gravity:land"
  say_prompt /gravity:land >/dev/null
  t "flag cannot change the mode" 2 G land --discard
  t "land" 0 G land
  check "landed" has "landed, uncommitted"
  check "code staged" [ -f "$R/out.txt" ]
  check "not committed" [ "$(git -C "$R" rev-list --count HEAD)" = 1 ]
  check "worktree gone" [ ! -d "$W" ]
  check "branch gone" bash -c "! git -C '$R' show-ref --verify -q refs/heads/gravity/$id"
  local rc=$R/.gravity/receipts/$id.receipt
  check "receipt exists" [ -f "$rc" ]
  check "receipt head" grep -q "^format=1 gravity=1.0.0 run=$id" "$rc"
  check "receipt approve" grep -q '^approve G2 doc=docs/plans/p.md' "$rc"
  check "receipt gates" grep -q '^gate G6 pass tree=' "$rc"
  check "receipt counts" grep -q '^counts said_done=1' "$rc"
  check "receipt file" grep -q '^file out.txt blob=' "$rc"
  t "cannot land twice" 2 G land
  check "no prose in receipt" bash -c "! grep -q 'hello' '$rc'"

  local base
  base=$(git -C "$R" rev-parse HEAD)
  git -C "$R" add -A
  git -C "$R" commit -q -m landed
  t "verify matches" 0 G verify --base "$base"
  check "says proven" has "was proven"
  t "unknown base" 2 G verify --base nope
  printf 'edited\n' >>"$R/out.txt"
  git -C "$R" commit -q -am edited
  t "edited after proof reported" 0 G verify --base "$base"
  check "reported" has "changed after proof: out.txt"
  t "strict fails it" 1 G verify --base "$base" --strict
  git -C "$R" reset -q --hard HEAD~1
  printf 'new\n' >"$R/uncovered.txt"
  git -C "$R" add -A
  git -C "$R" commit -q -m uncovered
  t "uncovered reported" 0 G verify --base "$base"
  check "not covered" has "not covered by a receipt: uncovered.txt"
  t "uncovered strict" 1 G verify --base "$base" --strict
  git -C "$R" reset -q --hard HEAD~1
  git -C "$R" rm -q out.txt
  git -C "$R" commit -q -m gone
  t "deleted proven file reported" 1 G verify --base "$base"
  check "deleted" has "changed after proof: out.txt"
  git -C "$R" reset -q --hard HEAD~1
  printf 'false\n' >"$R/tests/z.sh"
  git -C "$R" add -A
  git -C "$R" commit -q -m failing
  t "tests fail under base rules" 1 G verify --base "$base"
  check "says failed" has "test failed"
  git -C "$R" reset -q --hard HEAD~1
  git -C "$R" checkout -q -b feature "$base"
  printf 'plain\n' >"$R/plain.txt"
  git -C "$R" add -A
  git -C "$R" commit -q -m plain
  t "no receipt is neutral" 0 G verify --base "$base"
  check "neutral" has "Neutral"

  # A clean rebase moves commits but not blobs, so the receipt still holds.
  git -C "$R" checkout -q main
  git -C "$R" checkout -q -b rebased
  git -C "$R" checkout -q main
  printf 'side\n' >"$R/side.txt"
  git -C "$R" add -A
  git -C "$R" commit -q -m side
  git -C "$R" checkout -q rebased
  git -C "$R" rebase -q main
  t "rebase keeps proof" 0 G verify --base "$(git -C "$R" rev-parse main~1)"
  check "rebase message" hasnt "changed after proof"

  to_landable
  printf 'mine\n' >"$R/out.txt"
  say_prompt /gravity:land >/dev/null
  t "dirty overlap refuses" 1 G land
  check "names overlap" has "out.txt"
  rm "$R/out.txt"

  to_landable
  say_prompt "/gravity:land patch" >/dev/null
  t "patch landing" 0 G land
  check "patch path" has ".patch"
  check "receipt beside patch" bash -c "ls '$R'/.gravity/patches/*.receipt >/dev/null"
  check "checkout untouched" [ ! -f "$R/out.txt" ]

  to_landable
  id=$(ls "$R/.git/gravity/runs")
  say_prompt "/gravity:land pr" >/dev/null
  t "pr landing" 0 G land
  check "tells push" has "git push"
  check "receipt committed last" git -C "$R" cat-file -e "gravity/$id:.gravity/receipts/$id.receipt"

  to_landable
  id=$(ls "$R/.git/gravity/runs")
  say_prompt "/gravity:land keep" >/dev/null
  t "keep" 0 G land
  check "branch kept" git -C "$R" show-ref --verify -q "refs/heads/gravity/$id"
  t "kept run is finished" 0 G status
  check "not open" has "no unfinished runs"

  to_landable
  id=$(ls "$R/.git/gravity/runs")
  say_prompt "/gravity:land discard" >/dev/null
  t "discard" 0 G land
  check "branch removed" bash -c "! git -C '$R' show-ref --verify -q refs/heads/gravity/$id"

  standard_run
  through_task
  G gate G4 1 >/dev/null
  file_review reviews/task-1.g1.1.md
  G gate G4R 1 >/dev/null
  G task done 1 >/dev/null
  git -C "$W" rm -q out.txt
  commit_all break
  G gate G5 >/dev/null
  say_prompt /gravity:land >/dev/null
  t "report required" 1 G land
}

suite_link() {
  mk
  write_docs
  local up=$R upid
  upid=$(G run start --session S --playbook standard --slug up)
  G wait --gate G1 --doc docs/specs/d.md >/dev/null
  approve
  mk
  local down=$R
  t "linked run" 0 G run start --session T --playbook standard --slug down --link-repo "$up" --link-run "$upid"
  check "linked" has "linked to approved design"
  t "next skips G1" 0 G next
  check "goes to plan" has "plan, then get it approved"
  R=$up
  printf 'edit\n' >>"$R/docs/specs/d.md"
  R=$down
  t "changed upstream" 0 G run start --session U --playbook standard --slug down2 --link-repo "$up" --link-run "$upid"
  check "own G1 needed" has "needs its own G1"
  t "unknown upstream" 2 G run start --session U --playbook standard --slug d3 --link-repo "$up" --link-run nope
}

suite_structure() {
  local f n
  for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json skills/gravity/SKILL.md \
    playbooks/tiny.md playbooks/bug.md playbooks/small.md playbooks/standard.md \
    disciplines/ask.md disciplines/plan.md disciplines/build.md disciplines/prove.md disciplines/debug.md disciplines/review.md disciplines/report.md \
    agents/implementer.md agents/task-reviewer.md agents/branch-reviewer.md agents/security-reviewer.md agents/builder-check.md agents/report-reviewer.md \
    commands/setup.md commands/approve.md commands/status.md commands/resume.md commands/abandon.md commands/land.md \
    templates/design.md templates/plan.md templates/brief.md templates/report.md templates/project-conf.md \
    bin/gravity lib/receipt-check; do
    check "exists: $f" [ -f "$ROOT/$f" ]
  done
  check "only typed by a person" grep -q "^disable-model-invocation: true" "$ROOT/skills/gravity/SKILL.md"
  n=$(wc -l <"$ROOT/skills/gravity/SKILL.md" | tr -d ' ')
  check "router under 120 lines ($n)" [ "$n" -le 120 ]

  local v1 v2 v3
  v1=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/plugin.json")
  v2=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/marketplace.json")
  v3=$(sed -n 's/^GRAVITY_VERSION=//p' "$ROOT/lib/core.sh")
  check "versions match" [ "$v1" = "$v2" ] && check "core version matches" [ "$v1" = "$v3" ]

  local hits
  hits=$(grep -n -E '\b(Grep|Glob|TodoWrite|AskUserQuestion|MultiEdit)\b|`(Read|Bash|Edit|Write)`|\b(Bash|Read|Edit|Write) tool' "$ROOT"/disciplines/*.md | head -n 5)
  OUT=$hits
  check "no host tool names in disciplines" [ -z "$hits" ]
  hits=$(grep -rn -i -E '\blanes?\b' "$ROOT/skills" "$ROOT/playbooks" "$ROOT/disciplines" "$ROOT/agents" "$ROOT/commands" "$ROOT/templates" | head -n 5)
  OUT=$hits
  check "says playbook, not the old word" [ -z "$hits" ]
  hits=$(grep -rn -E 'superpowers|pstack|poteto|agent-skills|Ironclad|Flightplan|Keel' "$ROOT/skills" "$ROOT/playbooks" "$ROOT/disciplines" "$ROOT/agents" "$ROOT/commands" "$ROOT/templates" | head -n 5)
  OUT=$hits
  check "no source names in shipped prose" [ -z "$hits" ]
  hits=$(grep -rln 'Co-Authored-By\|Generated with' "$ROOT/lib" "$ROOT/bin" "$ROOT/skills" "$ROOT/playbooks" "$ROOT/disciplines" "$ROOT/agents" "$ROOT/commands" "$ROOT/templates")
  OUT=$hits
  check "no attribution lines" [ -z "$hits" ]

  # Every documented command must be one the dispatcher knows.
  local known=" run status setup plan next put doc wait isolate brief dispatch red gate package finding ruling halt pause report recover land receipt goal playbook task fix review hook verify version "
  hits=$(grep -rhoE '(^|[^a-z/:.-])gravity( --run [^ ]+)? [a-z]+' "$ROOT/skills" "$ROOT/playbooks" "$ROOT/disciplines" "$ROOT/agents" "$ROOT/commands" "$ROOT/templates" | awk '{print $NF}' | sort -u)
  local w bad_cmds=
  for w in $hits; do
    case "$known" in *" $w "*) ;; *) bad_cmds="$bad_cmds $w" ;; esac
  done
  OUT=$bad_cmds
  check "every documented command exists" [ -z "$bad_cmds" ]

  # Links between the shipped files must resolve.
  local link miss=
  for link in $(grep -rhoE '(disciplines|playbooks|templates|agents)/[a-z-]+\.md' "$ROOT/skills" "$ROOT/playbooks" "$ROOT/disciplines" "$ROOT/agents" "$ROOT/commands" | sort -u); do
    [ -f "$ROOT/$link" ] || miss="$miss $link"
  done
  OUT=$miss
  check "links resolve" [ -z "$miss" ]
}

run_suite() {
  case "$1" in
    core | plan | gates | review | hooks | setup | land | link | structure) "suite_$1" ;;
    *) echo "unknown suite: $1" >&2; exit 2 ;;
  esac
}

if [ "${1:-all}" = all ]; then
  for s in core plan gates review hooks setup land link structure; do
    run_suite "$s"
  done
else
  run_suite "$1"
fi

for d in $TMPS; do rm -rf "$d"; done
printf '%s passed, %s failed\n' "$PASS" "$FAILS"
[ "$FAILS" = 0 ]
