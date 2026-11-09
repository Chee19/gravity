active_plan() {
  local pb gate line doc
  pb=$(run_playbook)
  gate=G2
  [ "$pb" = small ] && gate=G1G2
  line=$(approve_line "$gate")
  [ -n "$line" ] || return 1
  doc=$(led_field "$line" doc)
  resolve_doc "$doc"
}

active_design() {
  local line doc
  line=$(approve_line G1)
  [ -n "$line" ] || line=$(approve_line G1G2)
  if [ -n "$line" ]; then
    doc=$(led_field "$line" doc)
    resolve_doc "$doc"
    return
  fi
  line=$(led_since goal | awk -F'\t' '$2=="link"{l=$0} END{print l}')
  [ -n "$line" ] || return 1
  led_field "$line" doc
}

plan_tasks() {
  awk '
    /^```/{fence=!fence}
    !fence&&/^##+ Task [0-9]+/{t=$0; sub(/^##+ Task /,"",t); sub(/[^0-9].*/,"",t); print t}' "$1"
}

plan_block() {
  awk -v n="$2" '
    /^```/{fence=!fence}
    !fence&&/^##+ /{
      if($0~/^##+ Task [0-9]+/){t=$0; sub(/^##+ Task /,"",t); sub(/[^0-9].*/,"",t); f=(t==n)}
      else if(f){f=0}
    }
    f{print}' "$1"
}

plan_section() {
  awk -v want="$2" '
    /^```/{fence=!fence}
    !fence&&/^##+ /{h=$0; sub(/^##+ /,"",h); f=(h==want); next}
    f{print}' "$1"
}

block_field() {
  printf '%s\n' "$1" | awk -v k="$2:" 'index($0,k)==1{v=substr($0,length(k)+1); sub(/^[ \t]+/,"",v); print v}'
}

task_title() {
  printf '%s\n' "$1" | head -n 1 | sed -E 's/^##+ Task [0-9]+[:.]?[[:space:]]*//'
}

proof_kind() { printf '%s' "${1%%[ \`]*}"; }

between_ticks() {
  local s=${1#*\`}
  printf '%s' "${s%%\`*}"
}

proof_cmd() { between_ticks "$1"; }

proof_expects() {
  case "$1" in
    *' expects `'*) between_ticks "${1#* expects }" ;;
  esac
}

csv_items() { printf '%s\n' "$1" | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v '^$'; }

req_ids_in_design() { grep -oE '^[-* ]*\**R[0-9]+[:.]' "$1" 2>/dev/null | grep -oE 'R[0-9]+'; }

# Unit separator, because read collapses adjacent tabs and expects may be empty.
acceptance_lines() {
  plan_section "$1" Acceptance | grep -E '^- `' | while IFS= read -r l; do
    local c e r
    c=$(between_ticks "$l")
    e=$(proof_expects "$l")
    r=
    case "$l" in *'['*']') r=${l##*[}; r=${r%]} ;; esac
    printf '%s\037%s\037%s\n' "$c" "$e" "$r"
  done
}

deps_have_cycle() {
  awk '
    {n=$1; seen[n]=1; if($2!=""){dep[n,$2]=1; indeg[n]++; to[$2]=to[$2]" "n}}
    END{
      for(n in seen) if(indeg[n]==0) q[++tail]=n
      while(head<tail){x=q[++head]; done++; m=split(to[x],a," "); for(i=1;i<=m;i++){if(--indeg[a[i]]==0) q[++tail]=a[i]}}
      for(n in seen) total++
      exit (done==total)?1:0
    }'
}

cmd_plan_check() {
  local plan=${1:-} design failed=0
  [ -n "$plan" ] || die "usage: gravity plan check <path> [--design <path>]"
  shift
  [ -f "$plan" ] || plan=$MAIN_ROOT/$plan
  [ -f "$plan" ] || die "no such plan: $plan"
  design=$(opt_value --design "$@")
  if [ -n "$design" ]; then
    [ -f "$design" ] || design=$MAIN_ROOT/$design
    [ -f "$design" ] || die "no such design: $design"
  fi

  local fences
  fences=$(grep -c '^```' "$plan")
  [ $((fences % 2)) = 0 ] || bad "unclosed code fence"

  local placeholders
  placeholders=$(awk '/^```/{f=!f; next} !f' "$plan" | grep -n -i -E '\bTBD\b|\bTODO\b|\bFIXME\b|handle edge cases|add error handling|as appropriate|implement later|fill in|<placeholder>' | head -n 5)
  [ -z "$placeholders" ] || bad "placeholder text: $(printf '%s' "$placeholders" | cut -c1-60 | tr '\n' ';')"

  local tasks n block proof kind deps d edges= all_reqs=
  tasks=$(plan_tasks "$plan")
  [ -n "$tasks" ] || bad "no tasks"
  for n in $tasks; do
    block=$(plan_block "$plan" "$n")
    proof=$(block_field "$block" Proof | head -n 1)
    if [ -z "$proof" ]; then
      bad "task $n has no Proof"
    else
      kind=$(proof_kind "$proof")
      case "$kind" in
        test) [ -n "$(proof_cmd "$proof")" ] || bad "task $n: test proof has no command" ;;
        run)
          [ -n "$(proof_cmd "$proof")" ] || bad "task $n: run proof has no command"
          [ -n "$(proof_expects "$proof")" ] || bad "task $n: run proof has no expected output"
          ;;
        build) ;;
        *) bad "task $n: unknown proof kind: $kind" ;;
      esac
    fi
    [ -n "$(block_field "$block" Files)" ] || bad "task $n has no Files"
    all_reqs="$all_reqs $(block_field "$block" Requirements | tr ',' ' ')"
    deps=$(block_field "$block" Depends)
    edges="$edges$n$NL"
    case "$deps" in
      "" | none | None) ;;
      *)
        for d in $(printf '%s' "$deps" | tr ',' ' '); do
          case " $(printf '%s' "$tasks" | tr '\n' ' ') " in
            *" $d "*) edges="$edges$n $d$NL" ;;
            *) bad "task $n depends on unknown task $d" ;;
          esac
        done
        ;;
    esac
  done
  if [ -n "$tasks" ] && printf '%s' "$edges" | deps_have_cycle; then
    bad "dependency cycle"
  fi

  local src=${design:-$plan} r
  for r in $(req_ids_in_design "$src"); do
    case " $all_reqs " in
      *" $r "*) ;;
      *) bad "requirement $r has no task" ;;
    esac
  done

  if [ -f "$MAIN_ROOT/.gravity/project.conf" ]; then
    local run_cmd
    run_cmd=$(conf_get "$MAIN_ROOT/.gravity/project.conf" commands run)
    case "$run_cmd" in
      none*)
        if plan_section "$plan" Acceptance | grep -q -E 'localhost|127\.0\.0\.1|https?://'; then
          bad "Acceptance needs a live surface but the conf says run = none"
        fi
        ;;
    esac
  fi

  plan_warnings "$plan" "$design" "$tasks"
  [ "$failed" = 0 ] || exit 1
  note "plan check passed"
}

plan_warnings() {
  local plan=$1 design=$2 tasks=$3 total code n block files title count
  total=$(wc -l <"$plan" | tr -d ' ')
  code=$(awk '/^```/{f=!f; next} f{c++} END{print c+0}' "$plan")
  [ "$total" -gt 0 ] && [ $((code * 2)) -gt "$total" ] && note "WARN: the plan is mostly code"
  if [ -n "$design" ]; then
    local dl
    dl=$(wc -l <"$design" | tr -d ' ')
    [ $((dl * 3)) -lt "$total" ] && note "WARN: the plan is much longer than the design"
  fi
  local pairs= i j fa fj shared
  for n in $tasks; do
    block=$(plan_block "$plan" "$n")
    files=$(block_field "$block" Files)
    count=$(csv_items "$files" | grep -c .)
    [ "$count" -ge 5 ] && note "WARN: task $n touches $count files"
    title=$(task_title "$block")
    case "$title" in *" and "*) note "WARN: task $n has 'and' in its title" ;; esac
  done
  for i in $tasks; do
    fa=$(csv_items "$(block_field "$(plan_block "$plan" "$i")" Files)")
    for j in $tasks; do
      [ "$j" -gt "$i" ] || continue
      fj=$(csv_items "$(block_field "$(plan_block "$plan" "$j")" Files)")
      shared=$(printf '%s\n' "$fa" | grep -F -x -f /dev/stdin <(printf '%s\n' "$fj") | tr '\n' ' ')
      [ -n "$shared" ] && pairs="$pairs$i,$j: $shared$NL"
    done
  done
  note "tasks sharing files:"
  if [ -n "$pairs" ]; then printf '%s' "$pairs"; else note "none"; fi
  note "counts: tasks=$(printf '%s\n' "$tasks" | grep -c .) acceptance=$(plan_section "$plan" Acceptance | grep -c -E '^- `')"
}

cmd_isolate() {
  local wt branch base existing
  existing=$(led_field "$(led_last isolate)" path)
  if [ -n "$existing" ] && [ -d "$existing" ]; then
    echo "$existing"
    return
  fi
  wt=$MAIN_ROOT/.gravity/worktrees/$RUN_ID
  branch=gravity/$RUN_ID
  base=$(run_base)
  led isolate.start "path=$wt"
  mkdir -p "$MAIN_ROOT/.gravity/worktrees"
  if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$MAIN_ROOT" worktree add -q "$wt" "$branch" || die "cannot create the worktree"
  else
    git -C "$MAIN_ROOT" worktree add -q -b "$branch" "$wt" "$base" || die "cannot create the worktree"
  fi
  led isolate "path=$(cd "$wt" && pwd -P)" "branch=$branch" "base=$base"
  (cd "$wt" && pwd -P)
}

need_plan() {
  PLAN=$(active_plan) || fail "no approved plan"
}

task_block_or_die() {
  need_plan
  BLOCK=$(plan_block "$PLAN" "$1")
  [ -n "$BLOCK" ] || die "no task $1 in the plan"
}

task_field_from_line() { led_since plan | awk -F'\t' -v e="$1" -v n="n=$2" '$2==e{for(i=3;i<=NF;i++) if($i==n) l=$0} END{if(l!="") print l}'; }

cmd_task_start() {
  local n=${1:-} deps d proof kind base
  [ -n "$n" ] || die "usage: gravity task start <n>"
  task_block_or_die "$n"
  [ "$(gate_result "$(gate_last G3)")" = pass ] || fail "G3 has not passed"
  task_is "$n" done && fail "task $n is already done"
  task_is "$n" blocked && fail "task $n is blocked"
  task_is "$n" skipped && fail "task $n was skipped"
  deps=$(block_field "$BLOCK" Depends)
  case "$deps" in
    "" | none | None) ;;
    *)
      for d in $(printf '%s' "$deps" | tr ',' ' '); do
        task_is "$d" done || fail "task $n depends on task $d, which is not done"
      done
      ;;
  esac
  need_wt
  tree_clean "$WT" || die "the worktree is dirty"
  base=$(git -C "$WT" rev-parse HEAD)
  if task_is "$n" start; then
    note "task $n already started"
    return 0
  fi
  proof=$(block_field "$BLOCK" Proof | head -n 1)
  kind=$(proof_kind "$proof")
  if [ "$kind" = run ]; then
    run_logged "task-$n-base" "$(proof_cmd "$proof")"
    if grep -q -F -- "$(proof_expects "$proof")" "$RUN_DIR/$LAST_EV"; then
      fail "task $n's run proof already matches on the base, so it cannot tell: fix the plan with gravity halt"
    fi
  fi
  led task.start "n=$n" "base=$base"
  note "task $n started at $base"
}

cmd_task_report() {
  local n=${1:-} status=${2:-} head
  [ -n "$status" ] || die "usage: gravity task report <n> <status>"
  case "$status" in DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED | RECOVERED) ;; *) die "unknown status: $status" ;; esac
  need_wt
  head=$(git -C "$WT" rev-parse HEAD)
  led task.report "n=$n" "status=$status" "head=$head"
}

cmd_task_done() {
  local n=${1:-} g gr tree
  [ -n "$n" ] || die "usage: gravity task done <n>"
  need_plan
  need_wt
  tree=$(head_tree "$WT")
  g=$(gate_last "G4.$n")
  [ "$(gate_result "$g")" = pass ] || fail "G4 proof has not passed for task $n"
  [ "$(led_field "$g" tree)" = "$tree" ] || fail "G4 proof for task $n is stale, the code changed"
  if [ "$(run_playbook)" = standard ]; then
    gr=$(gate_last "G4R.$n")
    [ "$(gate_result "$gr")" = pass ] || fail "G4 review has not passed for task $n"
    [ "$(led_field "$gr" tree)" = "$tree" ] || fail "G4 review for task $n is stale, the code changed"
  fi
  led task.done "n=$n" "head=$(git -C "$WT" rev-parse HEAD)"
  note "task $n done"
}

dependents_of() {
  local target=$1 plan=$2 t deps d
  for t in $(plan_tasks "$plan"); do
    deps=$(block_field "$(plan_block "$plan" "$t")" Depends)
    for d in $(printf '%s' "$deps" | tr ',' ' '); do
      [ "$d" = "$target" ] && echo "$t"
    done
  done
}

skip_dependents() {
  local n=$1 cause=$2 t
  for t in $(dependents_of "$n" "$PLAN"); do
    task_is "$t" skipped && continue
    task_is "$t" done && continue
    led task.skipped "n=$t" "because=$cause"
    skip_dependents "$t" "$cause"
  done
}

cmd_task_block() {
  local n=${1:-}
  shift
  [ -n "$*" ] || die "usage: gravity task block <n> <reason>"
  need_plan
  led task.blocked "n=$n" "reason=$*"
  skip_dependents "$n" "task $n blocked"
  note "task $n blocked. Dependents skipped, independent tasks continue."
}

fix_cap() {
  case "$1" in G5 | G6) echo 1 ;; *) echo 4 ;; esac
}

fix_used() {
  led_since plan | awk -F'\t' -v n="n=$1" '$2=="fix.round"{for(i=3;i<=NF;i++) if($i==n) c++} END{print c+0}'
}

fix_left() { echo $(($(fix_cap "$1") - $(fix_used "$1"))); }

cmd_fix_round() {
  local n=${1:-} cause used cap round
  cause=$(opt_value --cause "$@") || die "fix round needs --cause"
  cap=$(fix_cap "$n")
  used=$(fix_used "$n")
  [ "$used" -lt "$cap" ] || fail "cap reached: $n has used all $cap fix rounds. Go to the breaker"
  round=$((used + 1))
  need_wt
  led fix.round "n=$n" "round=$round" "cause=$cause" "head=$(git -C "$WT" rev-parse HEAD)"
  note "round $round of $cap"
  [ "$round" = 2 ] && [ "$cap" = 4 ] && note "before fixing: write the assumption the failed fixes share, and one observation that would differ if it is false"
  [ "$round" = 4 ] && note "use the stronger model for this round"
  return 0
}

cmd_dispatch() {
  local n=${1:-} role model attempt
  role=$(opt_value --role "$@") || die "dispatch needs --role"
  model=$(opt_value --model "$@") || die "dispatch needs --model"
  attempt=$(led_since plan | awk -F'\t' -v n="n=$n" -v r="role=$role" '$2=="dispatch"{a=0;b=0;for(i=3;i<=NF;i++){if($i==n)a=1;if($i==r)b=1} if(a&&b)c++} END{print c+1}')
  led dispatch "n=$n" "attempt=$attempt" "role=$role" "model=$model"
}

# Lowest attempt first. Gaps are normal, because a review takes its brief's attempt number.
attempts() {
  local f
  for f in "$RUN_DIR/$2/$1.g$(plan_generation)".*.md; do
    [ -e "$f" ] && echo "$f"
  done | awk -F. '{print $(NF-1) "\t" $0}' | sort -n | cut -f2-
}

next_attempt_name() {
  local last n=0
  last=$(attempts "$1" "$2" | tail -n 1)
  if [ -n "$last" ]; then
    n=${last%.md}
    n=${n##*.}
  fi
  printf '%s.g%s.%s.md' "$1" "$(plan_generation)" "$((n + 1))"
}

latest_attempt() {
  local last
  last=$(attempts "$1" "$2" | tail -n 1)
  [ -n "$last" ] || return 1
  printf '%s' "$last"
}

cmd_brief() {
  local n=${1:-} note_text name out design goal reqs r deps d rulings prev_report prev_review
  [ -n "$n" ] || die "usage: gravity brief <n> [--note <text>]"
  task_block_or_die "$n"
  note_text=$(opt_value --note "$@")
  fences=$(printf '%s\n' "$BLOCK" | grep -c '^```')
  [ $((fences % 2)) = 0 ] || fail "task $n has an unclosed code fence"
  name=$(next_attempt_name "task-$n" briefs)
  out=$RUN_DIR/briefs/$name
  design=$(active_design)
  goal=$(plan_section "$PLAN" Goal)
  {
    echo "# Brief: task $n"
    echo
    echo "## Goal"
    echo
    echo "$goal"
    echo
    echo "## Task"
    echo
    echo "$BLOCK"
    echo
    reqs=$(block_field "$BLOCK" Requirements | tr ',' ' ')
    if [ -n "$reqs" ] && [ -n "$design" ] && [ -f "$design" ]; then
      echo "## Requirements"
      echo
      for r in $reqs; do
        grep -E "^[-* ]*\**$r[:.]" "$design"
      done
      echo
    fi
    echo "## Global constraints"
    echo
    plan_section "$PLAN" "Global constraints"
    echo
    deps=$(block_field "$BLOCK" Depends)
    case "$deps" in
      "" | none | None) ;;
      *)
        echo "## Interfaces from earlier tasks"
        echo
        for d in $(printf '%s' "$deps" | tr ',' ' '); do
          echo "Task $d: $(block_field "$(plan_block "$PLAN" "$d")" Interfaces)"
        done
        echo
        ;;
    esac
    rulings=$(led_e ruling | awk -F'\t' '{w="";y="";for(i=3;i<=NF;i++){if(index($i,"what=")==1)w=substr($i,6);if(index($i,"why=")==1)y=substr($i,5)} print "- " w ": " y}')
    if [ -n "$rulings" ]; then
      echo "## Rulings so far"
      echo
      echo "$rulings"
      echo
    fi
    if [ -n "$note_text" ]; then
      echo "## Ambiguity resolved by the orchestrator"
      echo
      echo "$note_text"
      echo
    fi
    prev_report=$(latest_attempt "task-$n" reports)
    if [ -n "$prev_report" ]; then
      echo "## Prior report"
      echo
      echo "Read: $prev_report"
      echo
    fi
    prev_review=$(latest_attempt "task-$n" reviews)
    if [ -n "$prev_review" ]; then
      echo "## Findings to fix, verbatim"
      echo
      grep -E '^F[0-9]+ ' "$prev_review"
      echo
    fi
    echo "## Report"
    echo
    echo 'Commit your work. End with one status: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT or BLOCKED, then NOTICED: anything outside this task you saw and left alone.'
  } >"$out"
  [ -s "$out" ] || fail "brief came out empty"
  echo "$out"
}

red_line() { task_field_from_line red "$1"; }

cmd_red() {
  local n=${1:-} cmd commit
  [ -n "$n" ] || die "usage: gravity red <n|B3> [--cmd <command>]"
  need_wt
  tree_clean "$WT" || die "commit the failing test first, the worktree is dirty"
  if [ "$n" = B3 ]; then
    cmd=$(opt_value --cmd "$@") || die "red B3 needs --cmd"
  else
    task_block_or_die "$n"
    local proof
    proof=$(block_field "$BLOCK" Proof | head -n 1)
    [ "$(proof_kind "$proof")" = test ] || die "task $n's proof is not a test"
    cmd=$(proof_cmd "$proof")
  fi
  run_logged "red-$n" "$cmd"
  if could_not_run; then
    die "the proof command could not run: $cmd"
  fi
  if [ "$RUN_RC" = 0 ]; then
    fail "the test passes, so it does not capture the behavior"
  fi
  commit=$(git -C "$WT" rev-parse HEAD)
  led red "n=$n" "commit=$commit" "evidence=$LAST_EV" "cmd=$cmd"
  note "red recorded at $commit"
}
