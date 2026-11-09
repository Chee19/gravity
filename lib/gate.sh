gate_is_current() {
  [ -n "$1" ] || return 1
  [ "$(led_field "$1" tree)" = "$(head_tree "$(run_worktree)")" ]
}

finish_gate() {
  local name=$1 result=$2 ev=$3
  shift 3
  led gate "$name" "$result" "tree=$(head_tree "$WT")" "evidence=$ev" "$@"
  note "$name $result"
  [ "$result" = fail ] && exit 1
  exit 0
}

# G3 refuses to start work from a document that changed after approval.
fingerprints_ok() {
  local g line doc abs
  for g in G1 G2 G1G2; do
    line=$(approve_line "$g")
    [ -n "$line" ] || continue
    doc=$(led_field "$line" doc)
    abs=$(resolve_doc "$doc") || {
      note "approved document is missing: $doc"
      return 1
    }
    if [ "$(file_hash "$abs")" != "$(led_field "$line" hash)" ]; then
      note "changed since approval: $doc"
      return 1
    fi
  done
  line=$(led_since goal | awk -F'\t' '$2=="link"{l=$0} END{print l}')
  if [ -n "$line" ]; then
    abs=$(led_field "$line" doc)
    if [ ! -f "$abs" ] || [ "$(file_hash "$abs")" != "$(led_field "$line" hash)" ]; then
      note "linked design changed: $abs"
      return 1
    fi
  fi
  return 0
}

acceptance_passes() {
  local expects=$1
  [ "$RUN_RC" = 0 ] || return 1
  [ -z "$expects" ] || grep -q -F -- "$expects" "$RUN_DIR/$LAST_EV"
}

gate_g3() {
  local cmd ev where tmp= c e r i=0 matched=
  led gate.start G3
  need_plan
  fingerprints_ok || finish_gate G3 fail none "reason=fingerprint"
  cmd=$(conf_cmd install)
  if ! conf_skip "$cmd"; then
    run_logged g3-install "$cmd"
    [ "$RUN_RC" = 0 ] || die "install failed, see $LAST_EV"
  fi
  cmd=$(conf_cmd test)
  conf_skip "$cmd" && die "the conf has no test command"
  run_logged g3-baseline "$cmd"
  could_not_run && die "the test command could not run"
  ev=$LAST_EV
  suite_verdict || finish_gate G3 fail "$ev" "reason=baseline"
  where=$WT
  if [ "$(plan_generation)" -gt 1 ]; then
    tmp=$MAIN_ROOT/.gravity/worktrees/.g3-$$
    git -C "$MAIN_ROOT" worktree add -q --detach "$tmp" "$(run_base)" || die "cannot create the acceptance worktree"
    where=$tmp
  fi
  while IFS=$'\037' read -r c e r; do
    [ -n "$c" ] || continue
    i=$((i + 1))
    run_logged "g3-acceptance-$i" "$c" "$where"
    acceptance_passes "$e" && matched="$matched$i "
  done <<EOF
$(acceptance_lines "$PLAN")
EOF
  [ -z "$tmp" ] || git -C "$MAIN_ROOT" worktree remove --force "$tmp"
  [ -z "$matched" ] || {
    note "acceptance checks already pass, so they cannot tell: $matched"
    finish_gate G3 fail "$ev" "reason=acceptance"
  }
  finish_gate G3 pass "$ev"
}

gate_g4() {
  local n=${1:-} proof kind base cmd expects red commit ev=none reasons= hits
  [ -n "$n" ] || die "usage: gravity gate G4 <n>"
  task_block_or_die "$n"
  task_is "$n" start || fail "task $n has not started"
  led gate.start "G4.$n"
  proof=$(block_field "$BLOCK" Proof | head -n 1)
  kind=$(proof_kind "$proof")
  base=$(task_base "$n")
  if [ "$kind" = test ]; then
    red=$(red_line "$n")
    commit=$(led_field "$red" commit)
    if [ -z "$red" ] || ! git -C "$WT" merge-base --is-ancestor "$commit" HEAD; then
      note "no recorded red commit behind HEAD for task $n"
      finish_gate "G4.$n" fail none "reason=red"
    fi
  fi
  case "$kind" in
    test) cmd=$(proof_cmd "$proof") ;;
    run)
      cmd=$(proof_cmd "$proof")
      expects=$(proof_expects "$proof")
      ;;
    build)
      cmd=$(conf_cmd build)
      conf_skip "$cmd" && die "task $n has a build proof but the conf has no build command"
      ;;
    *) die "task $n has an unknown proof: $kind" ;;
  esac
  run_logged "g4-task-$n-proof" "$cmd"
  could_not_run && die "the proof command could not run: $cmd"
  ev=$LAST_EV
  acceptance_passes "${expects:-}" || reasons="${reasons}proof "
  cmd=$(conf_cmd test)
  conf_skip "$cmd" && die "the conf has no test command"
  run_logged "g4-task-$n-suite" "$cmd"
  could_not_run && die "the test command could not run"
  ev=$LAST_EV
  suite_verdict || reasons="${reasons}suite "
  hits=$(bar_hits "$WT" "$base" "$(block_field "$BLOCK" Allow)")
  if [ -n "$hits" ]; then
    reasons="${reasons}bar "
    note "bar guard: $(printf '%s' "$hits" | tr '\n' ' ')"
  fi
  if [ "$(run_playbook)" = standard ]; then
    local rev
    rev=$(latest_attempt "task-$n" reviews)
    if ! floor_check "$WT" "$base" "$(block_field "$BLOCK" Files)" "$(block_field "$BLOCK" Allow)" "task-$n" "$rev"; then
      printf '%s' "$FLOOR_LEFT" | sed 's/^/floor guard: /'
      reasons="${reasons}floor "
    fi
  fi
  [ -z "$reasons" ] && finish_gate "G4.$n" pass "$ev"
  # The orchestrator sends floor-only failures to a reviewer first, which can countersign them.
  [ "$reasons" = "floor " ] && note "floor-only"
  note "failed: $reasons"
  finish_gate "G4.$n" fail "$ev" "reason=$reasons"
}

# Prints open finding ids across every attempt in this generation for prefix.
open_findings() {
  local prefix=$1 task=$2 all id f
  all=$(attempts "$prefix" reviews | while IFS= read -r f; do cat "$f"; done)
  [ -n "$all" ] || return 0
  for id in $(printf '%s\n' "$all" | awk '/^F[0-9]+ *\|/{print $1}' | sort -u); do
    if [ "$(printf '%s\n' "$all" | awk -v f="$id" '$1==f&&($2=="ADDRESSED"||$2=="NOT"){s=$2} END{print s}')" = ADDRESSED ]; then
      continue
    fi
    if led_since plan | awk -F'\t' -v i="id=$id" -v t="task=$task" '$2=="finding"{a=0;b=0;c=0;for(k=3;k<=NF;k++){if($k==i)a=1;if($k==t)b=1;if($k~/^disposition=(disprove|defer|rule)$/)c=1} if(a&&b)r=c} END{exit !r}'; then
      continue
    fi
    echo "$id"
  done
}

review_verdict() { awk '/^Verdict:/{sub(/^Verdict:[ \t]*/,""); sub(/[ \t]+$/,""); print; exit}' "$1"; }

# 0 clean, 1 not. Prints why.
review_clean() {
  local prefix=$1 task=$2 file rel chk open
  file=$(latest_attempt "$prefix" reviews) || {
    note "no review for $prefix"
    return 1
  }
  rel=reviews/${file##*/}
  chk=$(led_since plan | awk -F'\t' -v f="file=$rel" '$2=="review.check"&&$3==f{l=$0} END{print l}')
  if [ "$(led_field "$chk" result)" != pass ]; then
    note "$rel has not passed gravity review check"
    return 1
  fi
  if [ "$(led_field "$chk" tree)" != "$(head_tree "$WT")" ]; then
    note "$rel reviewed older code"
    return 1
  fi
  if [ "$(review_verdict "$file")" = "Cannot verify" ]; then
    note "$rel says Cannot verify"
    return 1
  fi
  open=$(open_findings "$prefix" "$task")
  if [ -n "$open" ]; then
    note "findings still open in $prefix: $(printf '%s' "$open" | tr '\n' ' ')"
    return 1
  fi
  return 0
}

gate_g4r() {
  local n=${1:-} g
  [ -n "$n" ] || die "usage: gravity gate G4R <n>"
  led gate.start "G4R.$n"
  g=$(latest_attempt "task-$n" reviews) || g=none
  review_clean "task-$n" "$n" && finish_gate "G4R.$n" pass "${g##*/}"
  finish_gate "G4R.$n" fail "${g##*/}"
}

blocked_reqs() {
  local plan=$1 t
  for t in $(plan_tasks "$plan"); do
    if task_is "$t" blocked || task_is "$t" skipped; then
      block_field "$(plan_block "$plan" "$t")" Requirements | tr ',' ' '
      echo
    fi
  done
}

gate_g5() {
  local k cmd ev=none reasons= c e r i=0 nv= blocked rq hit
  led gate.start G5
  need_plan
  for k in test lint types build; do
    cmd=$(conf_cmd "$k")
    conf_skip "$cmd" && continue
    run_logged "g5-$k" "$cmd"
    could_not_run && die "the $k command could not run"
    if [ "$k" = test ]; then
      ev=$LAST_EV
      suite_verdict || reasons="${reasons}test "
    else
      [ "$RUN_RC" = 0 ] || reasons="$reasons$k "
    fi
  done
  blocked=" $(blocked_reqs "$PLAN" | tr '\n' ' ') "
  while IFS=$'\037' read -r c e r; do
    [ -n "$c" ] || continue
    i=$((i + 1))
    hit=
    for rq in $(printf '%s' "$r" | tr ',' ' '); do
      case "$blocked" in *" $rq "*) hit=$rq ;; esac
    done
    if [ -n "$hit" ]; then
      led acceptance.nv "n=$i" "req=$hit" "reason=blocked"
      continue
    fi
    run_logged "g5-acceptance-$i" "$c"
    could_not_run && die "acceptance check $i could not run"
    acceptance_passes "$e" || reasons="${reasons}acceptance-$i "
  done <<EOF
$(acceptance_lines "$PLAN")
EOF
  cmd=$(conf_cmd run)
  if conf_skip "$cmd"; then
    nv=1
  else
    run_logged g5-run "$cmd"
    could_not_run && die "the run command could not run"
    [ "$RUN_RC" = 0 ] || reasons="${reasons}run "
  fi
  if [ -n "$reasons" ]; then
    note "failed: $reasons"
    finish_gate G5 fail "$ev" "reason=$reasons"
  fi
  [ -n "$nv" ] && finish_gate G5 notverified "$ev" "reason=no run command"
  finish_gate G5 pass "$ev"
}

bug_files() {
  local f=$RUN_DIR/diagnosis.md
  [ -f "$f" ] && awk 'index($0,"Files:")==1{v=substr($0,7); sub(/^[ \t]+/,"",v); print v; exit}' "$f"
}

# Fix waves touch work that no single task owns, so they are guarded against every task's Files.
g6_floor() {
  local pb=$1 base files allow rev line
  rev=$(latest_attempt branch reviews)
  if [ "$pb" = bug ]; then
    floor_check "$WT" "$(run_base)" "$(bug_files)" "" "G6" "$rev"
    return
  fi
  need_plan
  files=$(union_files "$PLAN")
  allow=$(union_allow "$PLAN")
  if [ "$pb" = small ]; then
    floor_check "$WT" "$(run_base)" "$files" "$allow" "G6" "$rev"
    return
  fi
  line=$(led_since plan | awk -F'\t' '$2=="fix.round"&&($3=="n=G5"||$3=="n=G6"){print; exit}')
  [ -n "$line" ] || return 0
  base=$(led_field "$line" head)
  [ -n "$base" ] || return 0
  floor_check "$WT" "$base" "$files" "$allow" "G6" "$rev"
}

gate_g6() {
  local pb reasons= ev=none risk
  led gate.start G6
  pb=$(run_playbook)
  ev=$(latest_attempt branch reviews) || ev=none
  ev=reviews/${ev##*/}
  review_clean branch branch || reasons="${reasons}review "
  risk=$(run_risk)
  if [ -n "$risk" ] && [ "$risk" != none ]; then
    review_clean security security || reasons="${reasons}security "
  fi
  if ! g6_floor "$pb"; then
    printf '%s' "$FLOOR_LEFT" | sed 's/^/floor guard: /'
    reasons="${reasons}floor "
  fi
  [ -z "$reasons" ] && finish_gate G6 pass "$ev"
  finish_gate G6 fail "$ev" "reason=$reasons"
}

gate_evidence() {
  local g=$1 name
  shift
  name=$(opt_value --evidence "$@") || die "gate $g needs --evidence <name>"
  [ -s "$RUN_DIR/$name" ] || fail "no such evidence in the run: $name"
  finish_gate "$g" pass "$name"
}

gate_b3() {
  local name red
  name=$(opt_value --evidence "$@")
  red=$(red_line B3)
  [ -n "$red" ] || fail "B3 needs a failing check recorded with gravity red B3 --cmd <command>"
  git -C "$WT" merge-base --is-ancestor "$(led_field "$red" commit)" HEAD || fail "the recorded red commit is not behind HEAD"
  finish_gate B3 pass "${name:-$(led_field "$red" evidence)}"
}

bar_diff_hash() {
  # shellcheck disable=SC2086
  git -C "$WT" diff --no-ext-diff "$(run_base)" HEAD -- $1 | git hash-object --stdin
}

gate_b4() {
  local red cmd ev reasons= hits line paths k=1 p
  led gate.start B4
  red=$(red_line B3)
  [ -n "$red" ] || finish_gate B4 fail none "reason=red"
  cmd=$(led_field "$red" cmd)
  run_logged b4-fix "$cmd"
  could_not_run && die "the proof command could not run: $cmd"
  [ "$RUN_RC" = 0 ] || reasons="${reasons}proof "
  ev=$LAST_EV
  cmd=$(conf_cmd test)
  conf_skip "$cmd" && die "the conf has no test command"
  run_logged b4-suite "$cmd"
  could_not_run && die "the test command could not run"
  ev=$LAST_EV
  suite_verdict || reasons="${reasons}suite "
  hits=$(bar_hits "$WT" "$(run_base)" "")
  if [ -n "$hits" ]; then
    paths=$(printf '%s' "$hits" | tr '\n' ' ')
    line=$(approve_line B4)
    if [ -z "$line" ] || [ "$(led_field "$line" hash)" != "$(bar_diff_hash "$paths")" ]; then
      while [ -e "$RUN_DIR/patches/bar-diff.$k.patch" ]; do k=$((k + 1)); done
      p=patches/bar-diff.$k.patch
      # shellcheck disable=SC2086
      git -C "$WT" diff --no-ext-diff "$(run_base)" HEAD -- $paths >"$RUN_DIR/$p"
      note "bar guard: $paths"
      note "show this to the human: gravity wait --gate B4 --doc $p"
      reasons="${reasons}bar "
    fi
  fi
  [ -z "$reasons" ] && finish_gate B4 pass "$ev"
  note "failed: $reasons"
  finish_gate B4 fail "$ev" "reason=$reasons"
}

cmd_gate() {
  local g=${1:-}
  [ -n "$g" ] || die "usage: gravity gate <G3|G4 n|G4R n|G5|G6|B1..B5>"
  shift
  case "$g" in G3 | G4 | G4R | G5 | G6 | B1 | B2 | B3 | B4 | B5) ;; *) die "unknown gate: $g" ;; esac
  need_wt
  tree_clean "$WT" || die "the worktree is dirty, commit first"
  case "$g" in
    G3) gate_g3 ;;
    G4) gate_g4 "$@" ;;
    G4R) gate_g4r "$@" ;;
    G5) gate_g5 ;;
    G6) gate_g6 ;;
    B1 | B2 | B5) gate_evidence "$g" "$@" ;;
    B3) gate_b3 "$@" ;;
    B4) gate_b4 ;;
  esac
}
