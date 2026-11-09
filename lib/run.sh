cmd_run_start() {
  local session playbook slug risk id n conf
  session=$(opt_value --session "$@") || die "run start needs --session"
  playbook=$(opt_value --playbook "$@") || die "run start needs --playbook"
  slug=$(opt_value --slug "$@") || die "run start needs --slug"
  risk=$(opt_value --risk "$@") || risk=none
  case "$playbook" in bug | small | standard) ;; *) die "a run needs playbook bug, small or standard" ;; esac
  case "$slug" in *[!a-z0-9-]* | "") die "slug must be lowercase letters, digits and hyphens" ;; esac
  conf=$MAIN_ROOT/.gravity/project.conf
  [ -f "$conf" ] || die "this repo has no .gravity/project.conf, run /gravity:setup"

  local link_repo link_run
  link_repo=$(opt_value --link-repo "$@")
  link_run=$(opt_value --link-run "$@")

  id=$(date +%Y-%m-%d)-$slug
  n=2
  while [ -e "$RUNS_DIR/$id" ]; do
    id=$(date +%Y-%m-%d)-$slug-$n
    n=$((n + 1))
  done
  RUN_DIR=$RUNS_DIR/$id
  LEDGER=$RUN_DIR/ledger.log
  mkdir -p "$RUN_DIR/briefs" "$RUN_DIR/reports" "$RUN_DIR/reviews" "$RUN_DIR/evidence" "$RUN_DIR/patches" || die "cannot create the run directory"
  cp "$conf" "$RUN_DIR/project.conf"
  local known
  known=$(conf_get "$RUN_DIR/project.conf" baseline known_failing)
  [ -n "$known" ] && [ -f "$MAIN_ROOT/$known" ] && cp "$MAIN_ROOT/$known" "$RUN_DIR/known-failing.txt"
  led run.start "playbook=$playbook" "risk=$risk" "repo=${MAIN_ROOT##*/}" "base=$(git -C "$MAIN_ROOT" rev-parse HEAD)" "gravity=$GRAVITY_VERSION" "format=$GRAVITY_FORMAT" "session=$session"
  RUN_ID=$id
  [ -n "$link_repo" ] && link_upstream "$link_repo" "$link_run"
  echo "$id"
}

# A downstream G1 stands only while the upstream design is still what was approved.
link_upstream() {
  local repo=$1 upstream=$2 common ledger line doc hash cur abs
  [ -n "$upstream" ] || die "--link-repo needs --link-run"
  common=$(cd "$repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P) || die "cannot read upstream repo: $repo"
  ledger=$common/gravity/runs/$upstream/ledger.log
  [ -f "$ledger" ] || die "no upstream run: $upstream"
  line=$(awk -F'\t' '$2=="approve"{for(i=3;i<=NF;i++) if($i=="gate=G1"||$i=="gate=G1G2") l=$0} END{print l}' "$ledger")
  [ -n "$line" ] || fail "upstream run has no approved design"
  doc=$(led_field "$line" doc)
  hash=$(led_field "$line" hash)
  abs=$(cd "$repo" && pwd -P)/$doc
  [ -f "$abs" ] || fail "upstream design is missing: $abs"
  cur=$(file_hash "$abs")
  if [ "$cur" = "$hash" ]; then
    led link "doc=$abs" "run=$upstream" "hash=$hash"
    note "linked to approved design: $abs"
  else
    note "upstream design changed since approval, this run needs its own G1"
  fi
}

cmd_put() {
  local replace= name tmp target
  if [ "${1:-}" = --replace ]; then
    replace=1
    shift
  fi
  name=${1:-}
  [ -n "$name" ] || die "usage: gravity put [--replace] <name>"
  case "$name" in
    /* | ../* | */../* | *.. | "") die "path escapes the run: $name" ;;
  esac
  [ -z "$replace" ] || [ "$name" = report.md ] || die "only report.md may be replaced"
  target=$RUN_DIR/$name
  [ -e "$target" ] && [ -z "$replace" ] && fail "already exists, attempts are write-once: $name"
  mkdir -p "$(dirname "$target")" || die "cannot create parent of $name"
  tmp=$RUN_DIR/.put.$$
  cat >"$tmp" || die "cannot read stdin"
  if grep -q -E 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{36}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}' "$tmp"; then
    rm -f "$tmp"
    fail "refused: text looks like it contains a secret: $name"
  fi
  mv "$tmp" "$target" || die "cannot store $name"
  echo "$name"
}

cmd_doc() {
  [ -n "${1:-}" ] || die "usage: gravity doc <path>"
  led doc.draft "path=$1"
}

cmd_wait() {
  local gate doc abs hash
  gate=$(opt_value --gate "$@") || die "wait needs --gate"
  doc=$(opt_value --doc "$@") || die "wait needs --doc"
  abs=$(resolve_doc "$doc") || die "no such document: $doc"
  hash=$(file_hash "$abs")
  led wait "gate=$gate" "doc=$doc" "hash=$hash"
  note "waiting on $gate for $doc. Show the human this document and stop."
}

open_wait() {
  awk -F'\t' '$2=="wait"{w=$0} $2=="approve"||$2=="wait.closed"{w=""} END{if(w!="") print w}' "$LEDGER"
}

stopped_state() {
  awk -F'\t' '$2=="halt"||$2=="pause"{s=$2 "\t" $3} $2=="resume"{s=""} END{print s}' "$LEDGER"
}

cmd_halt() {
  [ -n "${1:-}" ] || die "usage: gravity halt <reason>"
  led halt "reason=$*"
  note "halted. Tell the human why and stop."
}

cmd_pause() {
  [ -n "${1:-}" ] || die "usage: gravity pause <note>"
  led pause "note=$*"
  note "paused. /gravity:resume continues it."
}

cmd_change() {
  local kind=$1 reason
  shift
  reason="$*"
  [ -n "$reason" ] || die "usage: gravity $kind change <reason>"
  led "$kind.change" "reason=$reason" "generation=$(($(plan_generation) + 1))"
  note "$kind change recorded. The docs paths are open again until the next plan approval."
}

cmd_playbook_up() {
  local to=${1:-} reason from
  reason=$(opt_value --reason "$@") || die "playbook up needs --reason"
  from=$(run_playbook)
  case "$from:$to" in
    small:standard | bug:standard | bug:small) ;;
    *) die "cannot step up from $from to $to" ;;
  esac
  led playbook.up "playbook=$to" "from=$from" "reason=$reason"
  note "stepped up from $from to $to: $reason"
}

cmd_ruling() {
  local cost what why file
  cost=$(opt_value --cost "$@") || die "ruling needs --cost"
  what=$(opt_value --what "$@") || die "ruling needs --what"
  why=$(opt_value --why "$@") || die "ruling needs --why"
  file=$(opt_value --file "$@")
  led ruling "cost=$cost" "what=$what" "why=$why" ${file:+"file=$file"}
}

cmd_finding() {
  local id task d why
  id=$(opt_value --id "$@") || die "finding needs --id"
  task=$(opt_value --task "$@") || die "finding needs --task"
  d=$(opt_value --disposition "$@") || die "finding needs --disposition"
  why=$(opt_value --why "$@") || die "finding needs --why"
  case "$d" in fix | disprove | defer | rule) ;; *) die "disposition must be fix, disprove, defer or rule" ;; esac
  led finding "id=$id" "task=$task" "disposition=$d" "why=$why"
}

said_done_counts() {
  awk -F'\t' '
    function kv(k, i){for(i=3;i<=NF;i++) if(index($i,k"=")==1) return substr($i,length(k)+2); return ""}
    $2=="task.report"{if(kv("status")~/^DONE/){said++; p[kv("n")]=1}}
    $2=="gate"&&$3~/^G4R?\./{n=$3; sub(/^G4R?\./,"",n); if(p[n]&&$4=="fail"){rej++; delete p[n]}}
    $2=="fix.round"{fix++}
    $2=="floor.hit"{floor++}
    END{printf "said_done=%d gates_rejected=%d fix_rounds=%d floor_hits=%d\n",said,rej,fix,floor}' "$LEDGER"
}

print_one_status() {
  use_run "$1"
  note "run: $RUN_ID"
  note "playbook: $(run_playbook)  risk: $(run_risk)  owner: $(run_owner "$LEDGER")"
  note "pinned gravity: $(led_field "$(led_first run.start)" gravity)  installed: $GRAVITY_VERSION"
  local w s
  w=$(open_wait)
  [ -n "$w" ] && note "waiting on human: $(led_field "$w" gate) for $(led_field "$w" doc)"
  s=$(stopped_state)
  [ -n "$s" ] && note "stopped: $(printf '%s' "$s" | tr '\t' ' ')"
  compute_next
  note "step: $NEXT_STEP"
  note "tasks: done=$(led_since plan | awk -F'\t' '$2=="task.done"' | grep -c .) blocked=$(led_since plan | awk -F'\t' '$2=="task.blocked"' | grep -c .) skipped=$(led_since plan | awk -F'\t' '$2=="task.skipped"' | grep -c .)"
  note "$(said_done_counts)"
}

cmd_status() {
  local want
  want=$(opt_value --run "$@") && RUN_ID=$want
  if [ -n "$RUN_ID" ]; then
    print_one_status "$RUN_ID"
    return
  fi
  local runs r first=1
  runs=$(open_runs)
  if [ -z "$runs" ]; then
    note "no unfinished runs (gravity $GRAVITY_VERSION)"
    return
  fi
  for r in $runs; do
    [ -n "$first" ] || note ""
    first=
    print_one_status "$r"
  done
}

task_is() { led_since plan | awk -F'\t' -v e="task.$2" -v n="n=$1" '$2==e{for(i=3;i<=NF;i++) if($i==n) f=1} END{exit !f}'; }

next_runnable_task() {
  local plan n
  plan=$(active_plan) || return 1
  for n in $(plan_tasks "$plan"); do
    task_is "$n" done && continue
    task_is "$n" blocked && continue
    task_is "$n" skipped && continue
    echo "$n"
    return 0
  done
  return 1
}

# Sets NEXT_STEP and NEXT_READ from the ledger alone, so a compacted session can always find its place.
compute_next() {
  local pb w d=$GRAVITY_ROOT/disciplines
  pb=$(run_playbook)
  NEXT_READ=
  NEXT_CAPS=
  w=$(open_wait)
  if [ -n "$w" ]; then
    NEXT_STEP="wait for the human: $(led_field "$w" gate) on $(led_field "$w" doc)"
    return
  fi
  if [ -n "$(stopped_state)" ]; then
    NEXT_STEP="stopped until /gravity:resume"
    return
  fi
  if led_e landed | grep -q .; then
    NEXT_STEP="landed, nothing left"
    return
  fi

  if [ "$pb" = bug ]; then
    compute_next_bug "$d"
    return
  fi

  local design_gate=G1 plan_gate=G2
  if [ "$pb" = small ]; then
    design_gate=G1G2
    plan_gate=G1G2
  fi
  if [ -z "$(approve_line "$plan_gate")" ]; then
    if [ -z "$(approve_line "$design_gate")" ] && [ -z "$(led_since goal | awk -F'\t' '$2=="link"')" ]; then
      NEXT_STEP="ask, then get the design approved ($design_gate)"
      NEXT_READ=$d/ask.md
    else
      NEXT_STEP="plan, then get it approved ($plan_gate)"
      NEXT_READ=$d/plan.md
    fi
    return
  fi
  compute_next_build "$d" "$pb"
}

compute_next_build() {
  local d=$1 pb=$2 g n last
  if ! led_e isolate | grep -q .; then
    NEXT_STEP="create the worktree: gravity isolate, then gravity gate G3"
    NEXT_READ=$d/build.md
    return
  fi
  g=$(gate_last G3)
  if [ "$(gate_result "$g")" != pass ]; then
    NEXT_STEP="gravity gate G3"
    NEXT_READ=$d/build.md
    return
  fi
  if n=$(next_runnable_task); then
    if task_is "$n" start; then
      NEXT_STEP="continue task $n"
    else
      NEXT_STEP="start task $n: gravity task start $n, then gravity brief $n"
    fi
    NEXT_READ=$d/build.md
    NEXT_CAPS="fix rounds left on task $n: $(fix_left "$n")"
    return
  fi
  compute_next_tail "$d"
}

compute_next_tail() {
  local d=$1 g5 g6
  local r
  g5=$(gate_last G5)
  r=$(gate_result "$g5")
  if [ "$r" = fail ] && gate_is_current "$g5"; then
    if [ "$(fix_left G5)" -gt 0 ]; then
      NEXT_STEP="G5 failed: gravity fix round G5 --cause gate, then gravity gate G5"
      NEXT_READ=$d/prove.md
      NEXT_CAPS="fix waves left on G5: $(fix_left G5)"
      return
    fi
    next_report_or_land "$d"
    return
  fi
  if ! { [ "$r" = pass ] || [ "$r" = notverified ]; } || ! gate_is_current "$g5"; then
    NEXT_STEP="gravity gate G5"
    NEXT_READ=$d/prove.md
    return
  fi
  review_or_report "$d"
}

next_report_or_land() {
  if ! led_since plan | awk -F'\t' '$2=="report.check"&&$3=="pass"{f=1} END{exit !f}'; then
    NEXT_STEP="write the report: gravity report, gravity put --replace report.md, gravity report --check"
    NEXT_READ=$1/report.md
    return
  fi
  NEXT_STEP="wait for the human to read the report and type /gravity:land"
}

compute_next_bug() {
  local d=$1 b
  if ! led_e isolate | grep -q .; then
    NEXT_STEP="create the worktree: gravity isolate"
    NEXT_READ=$d/debug.md
    return
  fi
  for b in B1 B2 B3 B4 B5; do
    if [ "$(gate_result "$(gate_last "$b")")" != pass ]; then
      NEXT_STEP="gate $b: see the bug playbook"
      NEXT_READ=$d/debug.md
      return
    fi
  done
  review_or_report "$d"
}

review_or_report() {
  local g6
  g6=$(gate_last G6)
  if [ "$(gate_result "$g6")" = pass ] && gate_is_current "$g6"; then
    next_report_or_land "$1"
    return
  fi
  if [ "$(gate_result "$g6")" = fail ] && gate_is_current "$g6" && [ "$(fix_left G6)" = 0 ]; then
    next_report_or_land "$1"
    return
  fi
  NEXT_STEP="whole-branch review: gravity package branch, dispatch the reviewer, gravity gate G6"
  NEXT_READ=$1/review.md
  NEXT_CAPS="fix waves left on G6: $(fix_left G6)"
}

cmd_next() {
  compute_next
  note "step: $NEXT_STEP"
  [ -n "$NEXT_READ" ] && note "read: $NEXT_READ"
  [ -n "$NEXT_CAPS" ] && note "caps: $NEXT_CAPS"
  return 0
}
