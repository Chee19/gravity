proven_tree() {
  led_field "$(gate_last G6)" tree
}

receipt_body() {
  local tree=$1 g line pb
  pb=$(run_playbook)
  printf 'format=%s gravity=%s run=%s playbook=%s base=%s\n' "$GRAVITY_FORMAT" "$(led_field "$(led_first run.start)" gravity)" "$RUN_ID" "$pb" "$(run_base)"
  for g in G1 G2 G1G2 B2 B4; do
    line=$(approve_line "$g")
    [ -n "$line" ] && printf 'approve %s doc=%s hash=%s\n' "$g" "$(led_field "$line" doc)" "$(led_field "$line" hash)"
  done
  for g in $(final_gates "$pb"); do
    line=$(gate_last "$g")
    [ -n "$line" ] && printf 'gate %s %s tree=%s\n' "$g" "$(gate_result "$line")" "$(led_field "$line" tree)"
  done
  led_since plan | awk -F'\t' '$2=="acceptance.nv"{r="";q="";for(i=3;i<=NF;i++){if(index($i,"req=")==1)q=substr($i,5);if(index($i,"reason=")==1)r=substr($i,8)} print "notverified " q " reason=" r}'
  printf 'counts %s\n' "$(said_done_counts)"
  git -C "$MAIN_ROOT" -c core.quotepath=off diff-tree -r --no-renames "$(run_base)" "$tree" | awk -F'\t' '{split($1,a," "); if(a[5]=="D") print "delete " $2; else print "file " $2 " blob=" a[4]}'
}

# Rebuilt from the ledger every time, so writing it again after a crash is safe.
write_receipt() {
  local tree dest
  tree=$(proven_tree)
  [ -n "$tree" ] || fail "no proven tree: G6 has not run"
  dest=$1
  mkdir -p "$(dirname "$dest")" || die "cannot create the receipts folder"
  receipt_body "$tree" >"$dest" || die "cannot write the receipt"
  echo "$dest"
}

cmd_receipt() {
  write_receipt "$MAIN_ROOT/.gravity/receipts/$RUN_ID.receipt"
}

dirty_overlap() {
  local wt=$1 base=$2 touched own
  touched=$(changed_paths "$wt" "$base")
  own=$(led_e approve | awk -F'\t' '{for(i=3;i<=NF;i++) if(index($i,"doc=")==1) print substr($i,5)}')
  git -C "$MAIN_ROOT" -c core.quotepath=off status --porcelain --no-renames | cut -c4- | sed 's/^"//; s/"$//' | while IFS= read -r p; do
    printf '%s\n' "$own" | grep -q -F -x -- "$p" && continue
    printf '%s\n' "$touched" | grep -q -F -x -- "$p" && echo "$p"
  done
}

remove_worktree() {
  local wt=$1 keep_branch=$2
  [ -d "$wt" ] && git -C "$MAIN_ROOT" worktree remove --force "$wt"
  git -C "$MAIN_ROOT" worktree prune
  [ -n "$keep_branch" ] || git -C "$MAIN_ROOT" branch -q -D "gravity/$RUN_ID" 2>/dev/null
  rmdir "$MAIN_ROOT/.gravity/worktrees" 2>/dev/null
  if [ -z "$(open_runs)" ]; then
    rm -rf "$MAIN_ROOT/.gravity/scratch"
  fi
  return 0
}

land_ready() {
  local line
  line=$(led_last report.check)
  [ "$(printf '%s' "$line" | awk -F'\t' '{print $3}')" = pass ] || fail "the report has not passed gravity report --check"
  [ "$(led_field "$line" tree)" = "$(head_tree "$WT")" ] || fail "the code changed after the report was checked"
  [ "$(gate_result "$(gate_last G5)")" != fail ] || fail "G5 failed. /gravity:land keep or /gravity:land discard"
}

cmd_land() {
  local g7 mode flag base over dest tree
  g7=$(approve_line G7)
  [ -n "$g7" ] || fail "landing needs the human to type /gravity:land"
  mode=$(led_field "$g7" mode)
  flag=${1:-}
  if [ -n "$flag" ] && [ "$flag" != "--$mode" ]; then
    die "the human chose $mode, not ${flag#--}"
  fi
  need_wt
  base=$(run_base)
  case "$mode" in
    keep)
      remove_worktree "$WT" keep
      led kept "branch=gravity/$RUN_ID"
      note "kept branch gravity/$RUN_ID"
      return 0
      ;;
    discard)
      remove_worktree "$WT" ""
      led abandoned "mode=discard" "by=command"
      note "discarded"
      return 0
      ;;
    uncommitted | patch | pr) ;;
    *) die "unknown landing mode: $mode" ;;
  esac
  tree_clean "$WT" || die "the worktree is dirty, commit first"
  land_ready
  case "$mode" in
    patch)
      mkdir -p "$MAIN_ROOT/.gravity/patches"
      dest=$MAIN_ROOT/.gravity/patches/$RUN_ID
      git -C "$WT" diff --binary "$base" HEAD >"$dest.patch" || die "cannot write the patch"
      write_receipt "$dest.receipt" >/dev/null
      led landed "sha=none" "mode=patch"
      remove_worktree "$WT" ""
      note "patch: $dest.patch"
      note "receipt: $dest.receipt"
      ;;
    pr)
      write_receipt "$WT/.gravity/receipts/$RUN_ID.receipt" >/dev/null
      git -C "$WT" add ".gravity/receipts/$RUN_ID.receipt"
      git -C "$WT" diff --cached --quiet || git -C "$WT" commit -q -m "Add Gravity receipt for $RUN_ID" || die "cannot commit the receipt"
      led landed "sha=$(git -C "$WT" rev-parse HEAD)" "mode=pr"
      remove_worktree "$WT" keep
      note "branch ready: gravity/$RUN_ID"
      note "push it yourself: git push -u origin gravity/$RUN_ID"
      ;;
    uncommitted)
      if ! led_e land.merged | grep -q .; then
        over=$(dirty_overlap "$WT" "$base")
        if [ -n "$over" ]; then
          note "your checkout has uncommitted changes in: $(printf '%s' "$over" | tr '\n' ' ')"
          fail "resolve those or type /gravity:land patch"
        fi
        led land.start "mode=uncommitted"
        if ! git -C "$MAIN_ROOT" merge --squash -q "gravity/$RUN_ID" >/dev/null 2>&1; then
          fail "the squash merge conflicted. Resolve it in your checkout, no commit, then run gravity land again"
        fi
        led land.merged "branch=gravity/$RUN_ID"
      fi
      tree=$(proven_tree)
      git -C "$MAIN_ROOT" status --short
      if [ "$(git -C "$MAIN_ROOT" write-tree)" != "$tree" ]; then
        note "note: the merged code differs from what was proven in:"
        git -C "$MAIN_ROOT" diff --cached --name-only "$tree" | sed 's/^/  /'
      fi
      dest=$(write_receipt "$MAIN_ROOT/.gravity/receipts/$RUN_ID.receipt")
      led landed "sha=none" "mode=uncommitted"
      remove_worktree "$WT" ""
      note "landed, uncommitted. Receipt: $dest"
      ;;
  esac
}
