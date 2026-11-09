cmd_package() {
  local target=${1:-} since base prefix out k=1 name
  [ -n "$target" ] || die "usage: gravity package <n|branch|security> [--since <sha>]"
  need_wt
  since=$(opt_value --since "$@")
  case "$target" in
    branch | security)
      base=$(run_base)
      prefix=$target
      ;;
    *)
      base=$(task_base "$target")
      prefix=task-$target
      ;;
  esac
  [ -n "$base" ] || fail "no recorded base for $target"
  [ -z "$since" ] || base=$since
  git -C "$WT" merge-base --is-ancestor "$base" HEAD || fail "HEAD does not descend from $base"
  [ -n "$(git -C "$WT" rev-list "$base..HEAD")" ] || fail "nothing to review between $base and HEAD"
  while [ -e "$RUN_DIR/evidence/package-$prefix.$k.diff" ]; do k=$((k + 1)); done
  out=$RUN_DIR/evidence/package-$prefix.$k.diff
  git -C "$WT" diff -U20 --no-color --no-ext-diff "$base" HEAD >"$out" || die "cannot write the package"
  name=$(next_attempt_name "$prefix" reviews)
  echo "$out"
  echo "review file: reviews/$name"
}

# 0 when line ln of file is on the new side of the diff from base.
line_in_diff() {
  git -C "$WT" diff -U0 --no-color --no-ext-diff "$1" HEAD -- "$2" | awk -v want="$3" '
    /^@@ /{split($3,b,","); s=substr(b[1],2)+0; c=(length(b)>0&&b[2]!="")?b[2]+0:1; if(want>=s&&want<s+c) f=1}
    END{exit !f}'
}

cmd_review_check() {
  local arg=${1:-} file rel base failed=0 verdict line id anchor quote failure sev cls f ln regressions=0 content
  [ -n "$arg" ] || die "usage: gravity review check <file>"
  case "$arg" in
    /*) file=$arg ;;
    *) file=$RUN_DIR/$arg ;;
  esac
  [ -f "$file" ] || die "no such review: $arg"
  rel=reviews/${file##*/}
  need_wt
  case "${file##*/}" in
    task-*)
      f=${file##*/task-}
      base=$(task_base "${f%%.*}")
      ;;
    branch.* | security.*) base=$(run_base) ;;
    *) die "review file name must start with task-, branch. or security." ;;
  esac
  verdict=$(review_verdict "$file")
  case "$verdict" in
    Ship | Minor | Rework | "Cannot verify") ;;
    *) bad "no valid Verdict line" ;;
  esac
  grep -q '^Safety:' "$file" || bad "no Safety line"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS='|' read -r id anchor quote failure sev cls <<EOF
$line
EOF
    id=$(trim "$id")
    anchor=$(trim "$anchor")
    quote=$(trim "$quote")
    sev=$(trim "$sev")
    cls=$(trim "$cls")
    case "$sev" in Critical | Important | Minor) ;; *) bad "$id: severity must be Critical, Important or Minor" ;; esac
    case "$cls" in regression | pre-existing) ;; *) bad "$id: must be regression or pre-existing" ;; esac
    [ -n "$(trim "$failure")" ] || bad "$id: no concrete failure"
    f=${anchor%:*}
    ln=${anchor##*:}
    case "$ln" in "" | *[!0-9]*)
      bad "$id: anchor is not path:line"
      continue
      ;;
    esac
    if [ ! -f "$WT/$f" ]; then
      bad "$id: no such file: $f"
      continue
    fi
    content=$(sed -n "${ln}p" "$WT/$f")
    if [ -z "$quote" ]; then
      bad "$id: no quote"
    else
      case "$content" in *"$quote"*) ;; *) bad "$id: quote is not at $anchor" ;; esac
    fi
    if [ "$cls" = regression ]; then
      regressions=$((regressions + 1))
      line_in_diff "$base" "$f" "$ln" || bad "$id: called a regression but $anchor is outside the diff"
    fi
  done <<EOF
$(grep -E '^F[0-9]+ *\|' "$file")
EOF
  [ "$verdict" != Rework ] || [ "$regressions" -gt 0 ] || bad "a pre-existing defect cannot produce Rework"
  local re='^Absence: patterns=(.*) scope=([^ ]*) hits=([0-9]+)$' got
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [[ $line =~ $re ]]; then
      got=$(git -C "$WT" grep -n -E -e "${BASH_REMATCH[1]}" HEAD -- "${BASH_REMATCH[2]}" | grep -c .)
      [ "$got" = "${BASH_REMATCH[3]}" ] || bad "absence claim for ${BASH_REMATCH[1]} says ${BASH_REMATCH[3]} hits, found $got"
    else
      bad "unparsable Absence line"
    fi
  done <<EOF
$(grep '^Absence:' "$file")
EOF
  if [ "$failed" = 0 ]; then
    led review.check "file=$rel" "result=pass" "tree=$(head_tree "$WT")"
    note "review check passed: $verdict"
    return 0
  fi
  led review.check "file=$rel" "result=fail" "tree=$(head_tree "$WT")"
  exit 1
}

report_gates() {
  case "$1" in
    bug) echo "B1 B2 B3 B4 B5 G6" ;;
    *) echo "G3 G5 G6" ;;
  esac
}

final_gates() {
  case "$1" in
    bug) echo "B4 G6" ;;
    *) echo "G5 G6" ;;
  esac
}

run_requirements() {
  local d
  if [ "$(run_playbook)" = bug ]; then
    echo R1
    return
  fi
  d=$(active_design) || return 0
  [ -f "$d" ] && req_ids_in_design "$d" | sort -u
}

all_finding_ids() {
  local g d f
  g=$(plan_generation)
  for f in "$RUN_DIR"/reviews/*.g"$g".*.md; do
    [ -f "$f" ] && awk '/^F[0-9]+ *\|/{print $1}' "$f"
  done | sort -u
}

report_facts() {
  local pb g line t
  pb=$(run_playbook)
  note "run: $RUN_ID playbook: $pb risk: $(run_risk)"
  note "requirements: $(run_requirements | tr '\n' ' ')"
  note "gates:"
  for g in $(report_gates "$pb"); do
    line=$(gate_last "$g")
    if [ -n "$line" ]; then
      note "  $g $(gate_result "$line") tree=$(led_field "$line" tree) evidence=$(led_field "$line" evidence)"
    else
      note "  $g missing"
    fi
  done
  note "rulings:"
  led_e ruling | awk -F'\t' '{printf "  "; for(i=3;i<=NF;i++) printf "%s  ", $i; print ""}'
  note "findings:"
  led_since plan | awk -F'\t' '$2=="finding"{printf "  "; for(i=3;i<=NF;i++) printf "%s  ", $i; print ""}'
  note "open or undisposed ids in reviews: $(all_finding_ids | tr '\n' ' ')"
  note "countersigned floor hits:"
  led_e floor.ok | awk -F'\t' '{printf "  "; for(i=3;i<=NF;i++) printf "%s  ", $i; print ""}'
  note "blocked:"
  led_since plan | awk -F'\t' '$2=="task.blocked"||$2=="task.skipped"{printf "  %s ", $2; for(i=3;i<=NF;i++) printf "%s  ", $i; print ""}'
  note "not verified:"
  led_since plan | awk -F'\t' '$2=="acceptance.nv"{printf "  "; for(i=3;i<=NF;i++) printf "%s  ", $i; print ""}'
  note "goal and plan changes:"
  awk -F'\t' '$2=="goal.change"||$2=="plan.change"||$2=="playbook.up"{printf "  %s ", $2; for(i=3;i<=NF;i++) printf "%s  ", $i; print ""}' "$LEDGER"
  note "commits:"
  t=$(run_worktree 2>/dev/null) && git -C "$t" log --format='  %h %s' "$(run_base)..HEAD"
  note "$(said_done_counts)"
}

report_check() {
  local failed=0 report=$RUN_DIR/report.md pb s id line g t w final
  [ -f "$report" ] || die "no report.md in the run"
  need_wt
  pb=$(run_playbook)
  for s in "Your calls" "What changed" "Requirements" "Rulings" "Noticed" "Not verified" "Look here" "Roll back"; do
    grep -q -E "^#*[[:space:]]*$s" "$report" || bad "missing section: $s"
  done
  for id in $(run_requirements); do
    grep -q -w -- "$id" "$report" || bad "requirement $id is not accounted for"
  done
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    w=$(led_field "$line" what)
    grep -q -F -- "$w" "$report" || bad "ruling not in report: $w"
  done <<EOF
$(led_e ruling)
EOF
  for id in $(all_finding_ids); do
    grep -q -w -- "$id" "$report" || bad "finding $id is not accounted for"
  done
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    s=$(led_field "$line" path)
    grep -q -F -- "$s" "$report" || bad "countersigned floor hit not in report: $s"
  done <<EOF
$(led_e floor.ok)
EOF
  for t in $(led_since plan | awk -F'\t' '$2=="task.blocked"||$2=="task.skipped"{print substr($3,3)}'); do
    grep -q -i -E "task[ -]*$t([^0-9]|\$)" "$report" || bad "blocked or skipped task $t is not accounted for"
  done
  for s in $(git -C "$WT" rev-list "$(run_base)..HEAD"); do
    grep -q -- "$(printf '%s' "$s" | cut -c1-7)" "$report" || bad "commit $(printf '%s' "$s" | cut -c1-7) is not accounted for"
  done
  final=" $(final_gates "$pb") "
  for g in $(report_gates "$pb"); do
    line=$(gate_last "$g")
    if [ "$(gate_result "$line")" != pass ]; then
      grep -q -w -- "$g" "$report" || bad "$g did not pass and the report does not list it"
    fi
    case "$final" in
      *" $g "*)
        if [ -n "$line" ] && ! gate_is_current "$line"; then
          bad "$g records a tree other than the branch's current one"
        fi
        ;;
    esac
  done
  if [ "$failed" = 0 ]; then
    led report.check pass "tree=$(head_tree "$WT")"
    note "report check passed"
    return 0
  fi
  led report.check fail "tree=$(head_tree "$WT")"
  exit 1
}

cmd_report() {
  if [ "${1:-}" = --check ]; then
    report_check
    return
  fi
  report_facts
}

patch_name() {
  local stem=$1 k=1
  while [ -e "$RUN_DIR/patches/$stem.$k.patch" ]; do k=$((k + 1)); done
  printf 'patches/%s.%s.patch' "$stem" "$k"
}

task_in_progress() {
  local plan n
  plan=$(active_plan) || return 1
  for n in $(plan_tasks "$plan"); do
    task_is "$n" start || continue
    task_is "$n" done && continue
    task_is "$n" blocked && continue
    task_is "$n" skipped && continue
    echo "$n"
    return 0
  done
  return 1
}

open_fix_round() {
  led_since plan | awk -F'\t' -v n="n=$1" '
    $2=="fix.round"&&$3==n{o=$4}
    $2=="task.done"&&$3==n{o=""}
    $2=="gate"&&$4=="pass"&&($3=="G4."substr(n,3)){o=""}
    END{if(o!="") print substr(o,7)}'
}

# Every step is safe to repeat, because a crash can hit recovery too.
cmd_recover() {
  local n base p round proof kind cmd head red
  need_wt
  if ! tree_clean "$WT"; then
    p=$(patch_name dirty)
    git -C "$WT" add -A
    git -C "$WT" diff --cached --binary HEAD >"$RUN_DIR/$p"
    git -C "$WT" reset -q --hard HEAD
    git -C "$WT" clean -q -fd
    note "saved uncommitted work to $p"
  fi
  n=$(task_in_progress) || {
    note "no task in progress"
    return 0
  }
  task_block_or_die "$n"
  round=$(open_fix_round "$n")
  if [ -n "$round" ]; then
    note "task $n: continue at fix round $round with a fresh brief: gravity brief $n"
    return 0
  fi
  base=$(task_base "$n")
  head=$(git -C "$WT" rev-parse HEAD)
  if [ "$head" != "$base" ]; then
    proof=$(block_field "$BLOCK" Proof | head -n 1)
    kind=$(proof_kind "$proof")
    red=1
    [ "$kind" != test ] || [ -n "$(red_line "$n")" ] || red=
    if [ -n "$red" ] && [ "$kind" != build ]; then
      cmd=$(proof_cmd "$proof")
      run_logged "recover-task-$n" "$cmd"
      if acceptance_passes "$(proof_expects "$proof")"; then
        led task.report "n=$n" "status=RECOVERED" "head=$head"
        note "task $n: proof passes on HEAD, recovered. Continue at its gates and review"
        return 0
      fi
    fi
    p=$(patch_name "task-$n-abandoned")
    git -C "$WT" diff --binary "$base" HEAD >"$RUN_DIR/$p"
    git -C "$WT" reset -q --hard "$base"
    note "task $n: saved $base..HEAD to $p and reset"
  fi
  note "task $n: redo with a fresh implementer: gravity brief $n"
}
