setup_exclude() {
  local f=$GIT_COMMON/info/exclude e
  mkdir -p "$GIT_COMMON/info"
  for e in .gravity/worktrees/ .gravity/scratch/ .gravity/patches/; do
    grep -q -x -F -- "$e" "$f" 2>/dev/null || printf '%s\n' "$e" >>"$f"
  done
  note "excluded Gravity's scratch paths through $f"
}

# Each check must be shown able to fail, because every later gate trusts what this proves.
setup_prove() {
  local test_plant lint_plant conf known k cmd failed=0 tmp
  test_plant=$(opt_value --test-plant "$@") || die "setup prove needs --test-plant"
  lint_plant=$(opt_value --lint-plant "$@") || die "setup prove needs --lint-plant"
  conf=$MAIN_ROOT/.gravity/project.conf
  [ -f "$conf" ] || die "no .gravity/project.conf yet"
  [ -f "$test_plant" ] || die "no such patch: $test_plant"
  [ -f "$lint_plant" ] || die "no such patch: $lint_plant"
  tmp=$(mktemp -d) || die "cannot create a temporary folder"
  RUN_DIR=$tmp
  mkdir -p "$RUN_DIR/evidence"
  cp "$conf" "$RUN_DIR/project.conf"
  known=$(conf_get "$conf" baseline known_failing)
  [ -n "$known" ] && [ -f "$MAIN_ROOT/$known" ] && cp "$MAIN_ROOT/$known" "$RUN_DIR/known-failing.txt"
  WT=$MAIN_ROOT/.gravity/worktrees/.setup-$$
  mkdir -p "$MAIN_ROOT/.gravity/worktrees"
  git -C "$MAIN_ROOT" worktree add -q --detach "$WT" HEAD || die "cannot create a throwaway worktree"
  for k in install test lint types build; do
    cmd=$(conf_cmd "$k")
    conf_skip "$cmd" && continue
    run_logged "setup-$k" "$cmd"
    if could_not_run; then
      bad "$k could not run: $cmd"
    elif [ "$k" = test ]; then
      suite_verdict || bad "test fails on a clean checkout, see known_failing"
    elif [ "$RUN_RC" != 0 ]; then
      bad "$k fails on a clean checkout"
    fi
  done
  setup_plant test "$test_plant"
  setup_plant lint "$lint_plant"
  git -C "$MAIN_ROOT" worktree remove --force "$WT"
  rmdir "$MAIN_ROOT/.gravity/worktrees" 2>/dev/null
  if [ "$failed" = 0 ]; then
    rm -rf "$tmp"
    note "setup proof passed: test and lint both fail on planted violations"
    return 0
  fi
  note "logs: $tmp/evidence"
  exit 1
}

setup_plant() {
  local k=$1 patch=$2 cmd
  cmd=$(conf_cmd "$k")
  if conf_skip "$cmd"; then
    note "$k: no command, not proven"
    return 0
  fi
  if ! git -C "$WT" apply "$patch"; then
    bad "$k plant does not apply"
    return 0
  fi
  git -C "$WT" add -A
  run_logged "setup-$k-plant" "$cmd"
  if [ "$k" = test ]; then
    suite_verdict && bad "test passed with a planted failure, so it proves nothing"
  else
    [ "$RUN_RC" != 0 ] || bad "lint passed with a planted violation, so it proves nothing"
  fi
  git -C "$WT" reset -q --hard HEAD
  git -C "$WT" clean -q -fd
}

setup_ci() {
  local wf=$MAIN_ROOT/.github/workflows/gravity-verify.yml
  mkdir -p "$MAIN_ROOT/.gravity" "$MAIN_ROOT/.github/workflows"
  cp "$GRAVITY_ROOT/lib/receipt-check" "$MAIN_ROOT/.gravity/receipt-check"
  cat >"$wf" <<'YAML'
name: gravity-verify
on: pull_request
permissions:
  contents: read
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Check the Gravity receipt using the base branch rules
        env:
          BASE: ${{ github.event.pull_request.base.sha }}
        run: |
          if git cat-file -e "$BASE:.gravity/receipt-check" 2>/dev/null; then
            git show "$BASE:.gravity/receipt-check" >"$RUNNER_TEMP/receipt-check"
            bash "$RUNNER_TEMP/receipt-check" --base "$BASE"
          else
            echo "The base branch has no receipt checker yet, skipping."
          fi
YAML
  note "wrote .gravity/receipt-check and .github/workflows/gravity-verify.yml. Protect them with code owners or branch rules, then commit them"
}

# Runs outside a repo too, because the wizard comes straight after install.
setup_done() {
  local scope data
  scope=$(opt_value --scope "$@") || die "setup done needs --scope"
  case "$scope" in
    user)
      data=$(opt_value --data "$@") || die "setup done --scope user needs --data"
      [ -n "$data" ] || die "setup done --scope user needs --data"
      mkdir -p "$data" && : >"$data/setup-done" || die "cannot record setup in $data"
      ;;
    local)
      init_repo
      mkdir -p "$GIT_COMMON/gravity" && : >"$GIT_COMMON/gravity/setup-done" || die "cannot record setup"
      ;;
    *) die "scope must be user or local" ;;
  esac
  note "setup recorded ($scope)"
}

cmd_setup() {
  local sub=${1:-}
  shift
  case "$sub" in
    prove) setup_prove "$@" ;;
    exclude) setup_exclude ;;
    ci) setup_ci ;;
    *) die "usage: gravity setup prove|exclude|ci" ;;
  esac
}
