globs_regex() {
  printf '%s\n' "$1" | tr -s ' \t' '\n' | sed -e '/^$/d' \
    -e 's#[.+^$(){}|\\]#\\&#g' -e 's#\*\*/#@@#g' -e 's#\*\*#@A#g' \
    -e 's#\*#[^/]*#g' -e 's#?#[^/]#g' -e 's#@@#(.*/)?#g' -e 's#@A#.*#g' \
    -e 's#^#^#' -e 's#$#$#' | paste -sd'|' -
}

matches_re() {
  [ -n "$2" ] && printf '%s\n' "$1" | grep -q -E "$2"
}

changed_paths() {
  git -C "$1" -c core.quotepath=off diff --name-only --no-renames "$2" HEAD
}

allow_regex() {
  globs_regex "$(printf '%s\n' "$1" | awk 'NF{print $1}')"
}

bar_regex() {
  globs_regex ".gravity/** $(conf_get "$RUN_DIR/project.conf" bar paths)"
}

bar_hits() {
  local wt=$1 base=$2 allow=$3 re are p
  re=$(bar_regex)
  are=$(allow_regex "$allow")
  changed_paths "$wt" "$base" | while IFS= read -r p; do
    matches_re "$p" "$re" || continue
    matches_re "$p" "$are" && continue
    echo "$p"
  done
}

floor_raw() {
  git -C "$1" -c core.quotepath=off diff -U0 --no-color --no-renames --no-ext-diff "$2" HEAD | awk '
    function is_test(p) { return p ~ /(^|\/)(__tests__|tests?)\// || p ~ /\.(test|spec)\./ || p ~ /_(test|spec)\./ || p ~ /(^|\/)test_[^\/]*\.py$/ }
    function is_assert(s) { return s ~ /expect\(|assert|\.should[.(]|t\.(Error|Fatal)|require\.[A-Z]/ }
    function strip(p) { sub(/\t.*$/, "", p); gsub(/"/, "", p); return p }
    function hit(k, l) { printf "%s\t%s\t%d\n", k, path, l }
    rem > 0 || add > 0 {
      c = substr($0, 1, 1); s = substr($0, 2)
      if (c == "-") {
        rem--
        if (is_test(path) && is_assert(s)) hit("assert-removed", oln)
        oln++
      } else if (c == "+") {
        add--
        if (is_test(path) && s ~ /(it|test|describe|context)\.(skip|only)\(|\.only\(|(^|[^a-zA-Z_.])(xit|fit|xtest|xdescribe|fdescribe)\(|@pytest\.mark\.(skip|xfail)|@unittest\.skip|t\.Skip\(|#\[ignore\]|@Disabled|@Ignore/) hit("skip", nln)
        if (s ~ /eslint-disable|@ts-ignore|@ts-expect-error|#[ ]*noqa|#[ ]*type:[ ]*ignore|\/\/[ ]*nolint|#\[allow\(|@SuppressWarnings|rubocop:disable|shellcheck disable|pylint:[ ]*disable/) hit("suppression", nln)
        if (!is_test(path) && s ~ /[Nn]ot [Ii]mplemented|NotImplementedError|unimplemented!\(|todo!\(/) hit("stub", nln)
        if (s ~ /catch[ \t]*(\([^)]*\))?[ \t]*\{[ \t]*\}|except[^:]*:[ \t]*pass[ \t]*$/) hit("empty-catch", nln)
        nln++
      }
      next
    }
    /^--- / { old = strip(substr($0, 5)); sub(/^a\//, "", old); next }
    /^\+\+\+ / {
      path = strip(substr($0, 5))
      if (path == "/dev/null") { path = old; if (is_test(path)) hit("deleted-test", 0); next }
      sub(/^b\//, "", path)
      next
    }
    /^@@ / {
      n = split($2, a, ","); oln = substr(a[1], 2) + 0; rem = (n > 1) ? a[2] + 0 : 1
      n = split($3, b, ","); nln = substr(b[1], 2) + 0; add = (n > 1) ? b[2] + 0 : 1
    }'
}

floor_outside() {
  local wt=$1 base=$2 re=$3 p kind
  changed_paths "$wt" "$base" | while IFS= read -r p; do
    matches_re "$p" "$re" && continue
    case "${p##*/}" in
      package.json | package-lock.json | pnpm-lock.yaml | yarn.lock | go.mod | go.sum | requirements*.txt | Cargo.toml | Cargo.lock | pyproject.toml | uv.lock | poetry.lock | Gemfile | Gemfile.lock | pom.xml)
        kind=manifest
        ;;
      *) kind=outside-files ;;
    esac
    printf '%s\t%s\t0\n' "$kind" "$p"
  done
}

# Sets FLOOR_LEFT to the hits nothing cleared. Prints kind and path:line only, never source text.
floor_check() {
  local wt=$1 base=$2 files=$3 allow=$4 label=$5 review=$6
  local files_re allow_re raw k p l key reason
  FLOOR_LEFT=
  files_re=$(globs_regex "$(csv_items "$files")")
  allow_re=$(allow_regex "$allow")
  raw=$(floor_raw "$wt" "$base"; floor_outside "$wt" "$base" "$files_re")
  [ -n "$raw" ] || return 0
  while IFS=$TAB read -r k p l; do
    key="scope=$label${TAB}kind=$k${TAB}path=$p${TAB}line=$l"
    ledger_has "$key" || led floor.hit "scope=$label" "kind=$k" "path=$p" "line=$l"
    matches_re "$p" "$allow_re" && continue
    reason=
    [ -n "$review" ] && reason=$(awk -v k="$k" -v p="$p" '$1=="FLOOR-OK:"&&$2==k&&$3==p&&NF>3{sub(/^[^ ]+ +[^ ]+ +[^ ]+ +/,""); print; exit}' "$review")
    if [ -n "$reason" ]; then
      ledger_has "floor.ok${TAB}scope=$label${TAB}kind=$k${TAB}path=$p" || led floor.ok "scope=$label" "kind=$k" "path=$p" "reason=$reason"
      continue
    fi
    FLOOR_LEFT="$FLOOR_LEFT$k $p:$l$NL"
  done <<EOF
$raw
EOF
  [ -z "$FLOOR_LEFT" ]
}

union_files() {
  local plan=$1 t out=
  for t in $(plan_tasks "$plan"); do
    out="$out,$(block_field "$(plan_block "$plan" "$t")" Files)"
  done
  printf '%s' "$out"
}

union_allow() {
  local plan=$1 t
  for t in $(plan_tasks "$plan"); do
    block_field "$(plan_block "$plan" "$t")" Allow
  done
}
