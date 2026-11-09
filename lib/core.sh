GRAVITY_VERSION=1.0.0
GRAVITY_FORMAT=1
TAB=$(printf '\t')
NL='
'

bad() { note "FAIL: $*"; failed=1; }
die() { printf 'gravity: %s\n' "$*" >&2; exit 2; }
fail() { printf 'gravity: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

init_repo() {
  git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $DIR"
  GIT_COMMON=$(cd "$DIR" && cd "$(git rev-parse --git-common-dir)" && pwd -P) || die "cannot find the git directory"
  RUNS_DIR=$GIT_COMMON/gravity/runs
  MAIN_ROOT=$(git -C "$DIR" worktree list --porcelain | sed -n '1s/^worktree //p')
  MAIN_ROOT=$(cd "$MAIN_ROOT" && pwd -P)
}

run_is_open() {
  ! awk -F'\t' '$2=="landed"||$2=="abandoned"||$2=="kept"{f=1} END{exit !f}' "$RUNS_DIR/$1/ledger.log"
}

open_runs() {
  [ -d "$RUNS_DIR" ] || return 0
  local d
  for d in "$RUNS_DIR"/*; do
    [ -f "$d/ledger.log" ] || continue
    run_is_open "${d##*/}" && echo "${d##*/}"
  done
}

use_run() {
  RUN_ID=$1
  RUN_DIR=$RUNS_DIR/$RUN_ID
  LEDGER=$RUN_DIR/ledger.log
  [ -f "$LEDGER" ] || die "no such run: $RUN_ID"
  local f
  f=$(led_field "$(led_first run.start)" format)
  [ "$f" = "$GRAVITY_FORMAT" ] || die "run $RUN_ID uses ledger format $f, this Gravity understands $GRAVITY_FORMAT. Finish it with the matching version"
}

resolve_run() {
  [ -n "$RUN_ID" ] && { use_run "$RUN_ID"; return; }
  local top runs count
  top=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
  case "$top" in
    */.gravity/worktrees/*) use_run "${top##*/}"; return ;;
  esac
  runs=$(open_runs)
  count=$(printf '%s' "$runs" | grep -c .)
  [ "$count" = 1 ] || {
    [ "$count" = 0 ] && die "no unfinished run"
    die "several unfinished runs, pass --run: $(printf '%s' "$runs" | tr '\n' ' ')"
  }
  use_run "$runs"
}

clean_field() {
  local v=$1
  v=${v//$TAB/ }
  v=${v//$NL/ }
  printf '%s' "$v"
}

led() {
  local line f
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ)$TAB$1"
  shift
  for f in "$@"; do
    line="$line$TAB$(clean_field "$f")"
  done
  printf '%s\n' "$line" >>"$LEDGER"
}

led_field() {
  printf '%s\n' "$1" | awk -F'\t' -v k="$2=" '{for(i=3;i<=NF;i++) if(index($i,k)==1){print substr($i,length(k)+1); exit}}'
}

led_e() { awk -F'\t' -v e="$1" '$2==e' "${2:-$LEDGER}"; }
led_first() { led_e "$1" | head -n 1; }
led_last() { led_e "$1" | tail -n 1; }

# Lines after the last goal change (scope goal) or the last goal or plan change (scope plan).
led_since() {
  awk -F'\t' -v s="$1" '
    {l[NR]=$0}
    $2=="goal.change"||(s=="plan"&&$2=="plan.change"){m=NR}
    END{for(i=m+1;i<=NR;i++) print l[i]}' "$LEDGER"
}

scope_of() {
  case "$1" in G1) echo goal ;; *) echo plan ;; esac
}

approve_line() {
  led_since "$(scope_of "$1")" | awk -F'\t' -v g="gate=$1" '$2=="approve"{for(i=3;i<=NF;i++) if($i==g) l=$0} END{if(l!="") print l}'
}

gate_last() {
  led_since plan | awk -F'\t' -v g="$1" '$2=="gate"&&$3==g{l=$0} END{if(l!="") print l}'
}

gate_result() { printf '%s\n' "$1" | awk -F'\t' '{print $4}'; }

run_playbook() {
  awk -F'\t' '$2=="run.start"||$2=="playbook.up"{for(i=3;i<=NF;i++) if(index($i,"playbook=")==1) p=substr($i,10)} END{print p}' "$LEDGER"
}

run_owner() {
  awk -F'\t' '$2=="run.start"||$2=="run.own"{for(i=3;i<=NF;i++) if(index($i,"session=")==1) p=substr($i,9)} END{print p}' "$1"
}

run_base() { led_field "$(led_first run.start)" base; }
run_risk() { led_field "$(led_first run.start)" risk; }

plan_generation() {
  awk -F'\t' 'BEGIN{g=1} $2=="goal.change"||$2=="plan.change"{g++} END{print g}' "$LEDGER"
}

conf_get() {
  awk -v sec="$2" -v key="$3" '
    /^[ \t]*[#;]/{next}
    /^\[/{s=$0; gsub(/[][]/,"",s); next}
    s==sec&&index($0,"="){
      k=substr($0,1,index($0,"=")-1); gsub(/[ \t]+$/,"",k)
      if(k==key){v=substr($0,index($0,"=")+1); sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v); print v; exit}
    }' "$1"
}

conf_cmd() {
  local v
  v=$(conf_get "$RUN_DIR/project.conf" commands "$1")
  case "$v" in
    *" | external" | *" | project" | *" | suite") v=${v% | *} ;;
  esac
  printf '%s' "$v"
}

conf_class() {
  local v
  v=$(conf_get "$RUN_DIR/project.conf" commands "$1")
  case "$v" in
    *" | external" | *" | project" | *" | suite") printf '%s' "${v##* | }" ;;
    *) printf 'suite' ;;
  esac
}

file_hash() { git hash-object --no-filters "$1"; }

resolve_doc() {
  case "$1" in
    /*) [ -f "$1" ] && { echo "$1"; return 0; } ;;
    *)
      [ -f "$RUN_DIR/$1" ] && { echo "$RUN_DIR/$1"; return 0; }
      [ -f "$MAIN_ROOT/$1" ] && { echo "$MAIN_ROOT/$1"; return 0; }
      ;;
  esac
  return 1
}

run_worktree() {
  local p
  p=$(led_field "$(led_last isolate)" path)
  [ -n "$p" ] || die "no worktree yet, run gravity isolate"
  [ -d "$p" ] || die "worktree is missing: $p"
  printf '%s' "$p"
}

# Sets WT in this shell, because die inside $(...) would only end the subshell.
need_wt() {
  WT=$(run_worktree) || exit 2
}

task_base() { led_field "$(task_field_from_line task.start "$1")" base; }

ledger_has() { grep -F -q -- "$1" "$LEDGER"; }

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

conf_skip() {
  case "$1" in "" | none | "none "*) return 0 ;; esac
  return 1
}

tree_clean() { [ -z "$(git -C "$1" status --porcelain)" ]; }
head_tree() { git -C "$1" rev-parse 'HEAD^{tree}'; }

# Sets RUN_RC and LAST_EV. Evidence files are never overwritten.
run_logged() {
  local name=$1 cmd=$2 where=${3:-$WT} ev n=1
  ev=evidence/$name.$n.log
  while [ -e "$RUN_DIR/$ev" ]; do
    n=$((n + 1))
    ev=evidence/$name.$n.log
  done
  (cd "$where" && bash -c "$cmd") </dev/null >"$RUN_DIR/$ev" 2>&1
  RUN_RC=$?
  LAST_EV=$ev
}

could_not_run() { [ "$RUN_RC" = 126 ] || [ "$RUN_RC" = 127 ]; }

# 0 ok, 1 fail. A non-zero exit passes only if every recognised failure is on the known list.
suite_verdict() {
  [ "$RUN_RC" = 0 ] && return 0
  local known=$RUN_DIR/known-failing.txt lines patterns residual
  [ -s "$known" ] || return 1
  patterns=$RUN_DIR/.known.$$
  grep -v -E '^[[:space:]]*(#|$)' "$known" >"$patterns"
  lines=$(grep -E '(^|[[:space:]])(FAIL|FAILED|ERROR|not ok|✕|×)([[:space:]:]|$)' "$RUN_DIR/$LAST_EV")
  if [ -z "$lines" ] || [ ! -s "$patterns" ]; then
    rm -f "$patterns"
    return 1
  fi
  residual=$(printf '%s\n' "$lines" | grep -v -F -f "$patterns")
  rm -f "$patterns"
  [ -z "$residual" ]
}

opt_value() {
  local want=$1
  shift
  while [ $# -gt 0 ]; do
    [ "$1" = "$want" ] && { printf '%s' "${2:-}"; return 0; }
    shift
  done
  return 1
}

has_flag() {
  local want=$1
  shift
  while [ $# -gt 0 ]; do
    [ "$1" = "$want" ] && return 0
    shift
  done
  return 1
}
