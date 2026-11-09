json_str() {
  local re='"'"$1"'"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)"' v
  [[ $INPUT =~ $re ]] || return 0
  v=${BASH_REMATCH[1]}
  v=${v//\\n/$NL}
  v=${v//\\t/$TAB}
  v=${v//\\\"/\"}
  v=${v//\\\//\/}
  v=${v//\\\\/\\}
  printf '%s' "$v"
}

json_escape() {
  local v=$1
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
  v=${v//$NL/\\n}
  v=${v//$TAB/\\t}
  v=${v//$'\r'/}
  printf '%s' "$v"
}

emit_context() {
  [ -n "$2" ] || return 0
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$(json_escape "$2")"
}

emit_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_escape "$1")"
}

hook_repo() {
  git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  init_repo
}

# Sets RUN_ID, RUN_DIR and LEDGER for the run this session owns.
hook_owned_run() {
  local r found=
  [ -n "$SESSION" ] || return 1
  for r in $(open_runs); do
    [ "$(run_owner "$RUNS_DIR/$r/ledger.log")" = "$SESSION" ] && found=$r
  done
  [ -n "$found" ] || return 1
  use_run "$found"
}

router_text() {
  local v
  v=$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{f=0;next} !f' "$GRAVITY_ROOT/skills/gravity/SKILL.md")
  v=${v//\$\{CLAUDE_PLUGIN_ROOT\}/$GRAVITY_ROOT}
  printf '%s' "${v//\$ARGUMENTS/(already stated in this conversation)}"
}

runs_summary() {
  local r owner line
  for r in $(open_runs); do
    (
      use_run "$r" 2>/dev/null || exit 0
      compute_next 2>/dev/null
      owner=$(run_owner "$LEDGER")
      if [ "$owner" = "$SESSION" ]; then
        printf 'This session owns run %s. Current step: %s\n' "$r" "$NEXT_STEP"
      else
        printf 'Run %s is unfinished (%s). Ask the person: /gravity:resume %s or /gravity:abandon %s. Do not resume on your own.\n' "$r" "$NEXT_STEP" "$r" "$r"
      fi
    )
  done
}

setup_is_done() {
  [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -f "$CLAUDE_PLUGIN_DATA/setup-done" ] && return 0
  hook_repo && [ -f "$GIT_COMMON/gravity/setup-done" ]
}

# After the wizard this is silent unless a run exists, so sessions that never typed /gravity see nothing.
hook_session_start() {
  local source out= sum
  if ! setup_is_done; then
    printf '{"systemMessage":"%s"}\n' "Gravity is installed but not set up. Run /gravity:setup to finish."
    return 0
  fi
  source=$(json_str source)
  hook_repo || return 0
  if hook_owned_run; then
    if [ "$source" != resume ]; then
      out=$(router_text)
      out="$out$NL$NL"
    fi
    out="${out}Gravity session id: $SESSION$NL"
  fi
  sum=$(runs_summary)
  [ -z "$sum" ] || out="$out$sum"
  emit_context SessionStart "$out"
}

hook_approve() {
  local w gate doc hash abs extra= pcheck design
  w=$(open_wait)
  if [ -z "$w" ]; then
    emit_context UserPromptSubmit "Gravity: nothing is awaiting approval on run $RUN_ID."
    return
  fi
  gate=$(led_field "$w" gate)
  doc=$(led_field "$w" doc)
  hash=$(led_field "$w" hash)
  abs=$(resolve_doc "$doc")
  if [ -z "$abs" ] || [ "$(file_hash "$abs")" != "$hash" ]; then
    emit_context UserPromptSubmit "Gravity: not approved. $doc changed since it was shown. Show it again with gravity wait."
    return
  fi
  if [ "$gate" = G2 ] || [ "$gate" = G1G2 ]; then
    design=$(active_design)
    if ! pcheck=$(cmd_plan_check "$abs" ${design:+--design "$design"} 2>&1); then
      emit_context UserPromptSubmit "Gravity: not approved. The plan check failed:$NL$pcheck"
      return
    fi
    [ -z "$design" ] || extra="design=$(file_hash "$design")"
  fi
  led approve "gate=$gate" "doc=$doc" "hash=$hash" "by=command" ${extra:+"$extra"}
  emit_context UserPromptSubmit "Gravity: $gate approved for $doc. Continue: run gravity next."
}

hook_target_run() {
  local id=$1 runs count
  if [ -n "$id" ]; then
    [ -f "$RUNS_DIR/$id/ledger.log" ] || return 1
    use_run "$id"
    return
  fi
  hook_owned_run && return 0
  runs=$(open_runs)
  count=$(printf '%s' "$runs" | grep -c .)
  [ "$count" = 1 ] || return 1
  use_run "$runs"
}

hook_resume() {
  if ! hook_target_run "$1"; then
    emit_context UserPromptSubmit "Gravity: name the run to resume. Unfinished: $(open_runs | tr '\n' ' ')"
    return
  fi
  led run.own "session=$SESSION"
  led resume
  emit_context UserPromptSubmit "$(router_text)$NL${NL}Gravity session id: $SESSION$NL${NL}Gravity: this session now owns run $RUN_ID. Run gravity --run $RUN_ID recover, then gravity next. The ledger outranks anything remembered."
}

hook_land() {
  local mode=${1:-uncommitted}
  if ! hook_owned_run; then
    emit_context UserPromptSubmit "Gravity: this session owns no run to land. /gravity:resume first."
    return
  fi
  case "$mode" in
    uncommitted | patch | pr | keep | discard) ;;
    *)
      emit_context UserPromptSubmit "Gravity: unknown landing mode: $mode. Use patch, pr, keep or discard."
      return
      ;;
  esac
  case "$mode" in
    uncommitted | patch | pr)
      if ! led_since plan | awk -F'\t' '$2=="report.check"{r=$3} END{exit r!="pass"}'; then
        emit_context UserPromptSubmit "Gravity: not recorded. The report has not passed gravity report --check."
        return
      fi
      ;;
  esac
  led approve "gate=G7" "mode=$mode" "by=command"
  emit_context UserPromptSubmit "Gravity: G7 recorded, mode $mode. Run gravity land."
}

hook_abandon() {
  if ! hook_target_run "$1"; then
    emit_context UserPromptSubmit "Gravity: name the run to abandon. Unfinished: $(open_runs | tr '\n' ' ')"
    return
  fi
  led abandoned "by=command"
  emit_context UserPromptSubmit "Gravity: run $RUN_ID abandoned. Its branch gravity/$RUN_ID and worktree are left for you to inspect."
}

hook_user_prompt() {
  local prompt word arg
  prompt=$(json_str prompt)
  word=${prompt%%[[:space:]]*}
  arg=$(trim "${prompt#"$word"}")
  arg=${arg%%[[:space:]]*}
  case "$word" in
    /gravity | /gravity:gravity)
      if ! setup_is_done; then
        printf '{"decision":"block","reason":"%s"}\n' "Gravity needs its setup wizard first. Run /gravity:setup."
        return
      fi
      emit_context UserPromptSubmit "Gravity session id: $SESSION"
      return
      ;;
    /gravity:approve | /gravity:resume | /gravity:land | /gravity:abandon) ;;
    *) return 0 ;;
  esac
  hook_repo || return 0
  case "$word" in
    /gravity:resume)
      hook_resume "$arg"
      return
      ;;
    /gravity:abandon)
      hook_abandon "$arg"
      return
      ;;
    /gravity:land)
      hook_land "$arg"
      return
      ;;
  esac
  if ! hook_owned_run; then
    emit_context UserPromptSubmit "Gravity: this session owns no run. /gravity:resume first."
    return
  fi
  hook_approve
}

abs_real() {
  local p=$1 tail=
  case "$p" in /*) ;; *) p=$DIR/$p ;; esac
  while [ ! -d "$p" ] && [ "$p" != / ]; do
    tail=/${p##*/}$tail
    p=${p%/*}
    [ -n "$p" ] || p=/
  done
  printf '%s%s' "$(cd "$p" && pwd -P)" "$tail"
}

is_handed_off() {
  case "$(run_playbook)" in
    bug) [ "$(gate_result "$(gate_last B2)")" = pass ] ;;
    small) [ -n "$(approve_line G1G2)" ] ;;
    *) [ -n "$(approve_line G2)" ] ;;
  esac
}

hook_pre_edit() {
  local real wt specs plans pb
  real=$(abs_real "$(json_str file_path)")
  case "$real" in
    */../* | */..)
      emit_deny "Gravity: resolve the path before editing it."
      return
      ;;
  esac
  pb=$(run_playbook)
  wt=$MAIN_ROOT/.gravity/worktrees/$RUN_ID
  if [ "$pb" = bug ] || { [ "$pb" = small ] && [ -n "$(approve_line G1G2)" ]; } || { [ "$pb" = standard ] && [ -n "$(approve_line G2)" ]; }; then
    case "$real" in
      "$wt"/*) return 0 ;;
    esac
    emit_deny "Gravity: during the build, edits go in the run's worktree: $wt"
    return
  fi
  specs=$(conf_get "$RUN_DIR/project.conf" paths specs)
  plans=$(conf_get "$RUN_DIR/project.conf" paths plans)
  case "$real" in
    "$MAIN_ROOT/${specs:-docs/specs}"/* | "$MAIN_ROOT/${plans:-docs/plans}"/* | "$MAIN_ROOT/.gravity/scratch"/*) return 0 ;;
  esac
  emit_deny "Gravity: no code edits before the plan is approved. Only the docs paths and .gravity/scratch are open."
}

hook_pre_bash() {
  local c deny pat re='(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)'
  c=$(json_str command)
  if [[ $c =~ $re ]]; then
    emit_deny "Gravity: pushing is yours to do, after the run lands."
    return
  fi
  case "$c" in
    *"gh pr merge"*)
      emit_deny "Gravity: merging is yours to do."
      return
      ;;
  esac
  deny=$(conf_get "$RUN_DIR/project.conf" risk deny)
  while IFS= read -r pat; do
    pat=$(trim "$pat")
    [ -n "$pat" ] || continue
    case "$c" in
      *"$pat"*)
        emit_deny "Gravity: this project denies that command during a run."
        return
        ;;
    esac
  done <<EOF
$(printf '%s\n' "$deny" | tr ',' '\n')
EOF
}

hook_pre_tool() {
  hook_repo || return 0
  hook_owned_run || return 0
  case "$(json_str tool_name)" in
    Bash) hook_pre_bash ;;
    Edit | Write | MultiEdit | NotebookEdit) hook_pre_edit ;;
  esac
}

hook_stop() {
  local line
  hook_repo || return 0
  hook_owned_run || return 0
  [ -z "$(open_wait)" ] || return 0
  [ -z "$(stopped_state)" ] || return 0
  is_handed_off || return 0
  line=$(led_since plan | awk -F'\t' '$2=="report.check"&&$3=="pass"{f=1} END{print f+0}')
  [ "$line" = 0 ] || return 0
  printf '{"decision":"block","reason":"%s"}\n' "$(json_escape "Gravity run $RUN_ID is mid-build. Run gravity next and keep going, or gravity halt with a reason.")"
}

hook_dispatch() {
  case "$1" in
    session-start) hook_session_start ;;
    user-prompt) hook_user_prompt ;;
    pre-tool) hook_pre_tool ;;
    stop) hook_stop ;;
  esac
}

# A hook that exits 2 blocks the action, so a Gravity bug must never reach that exit code.
cmd_hook() {
  local kind=${1:-} out
  INPUT=$(cat)
  SESSION=$(json_str session_id)
  local cwd
  cwd=$(json_str cwd)
  [ -z "$cwd" ] || DIR=$cwd
  out=$(hook_dispatch "$kind") || true
  [ -z "$out" ] || printf '%s\n' "$out"
  return 0
}
