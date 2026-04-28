#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_line() {
  local file="$1" pattern="$2" label="$3"
  grep -q "$pattern" "$file" || { printf 'FAIL %s\n' "$label" >&2; cat "$file" >&2; exit 1; }
}

h=$(mktemp -d)
(cd "$h" && git init -q .)
"$REPO/trio" runtime bootstrap --mode dev "$h" >/dev/null

stdout=$(mktemp)
stderr=$(mktemp)
set +e
"$REPO/trio" runtime gate-check "$h" eng-review >"$stdout" 2>"$stderr"
ec=$?
set -e
[ "$ec" != "0" ] || { printf 'FAIL gate-check should fail before eng-review\n' >&2; exit 1; }
assert_line "$stderr" '架构评审未通过' 'gate fail message'

"$REPO/trio" runtime decision-append "$h" eng-review "引入 runtime" "下沉状态" "减少 prompt owner" "影响所有阶段" >/dev/null
"$REPO/trio" runtime gate-check "$h" eng-review >"$stdout"
assert_line "$stdout" '^GATE=eng-review$' 'eng-review gate key'
assert_line "$stdout" '^PASSED=1$' 'eng-review gate pass'

"$REPO/trio" runtime gate-check "$h" state-sync >"$stdout"
assert_line "$stdout" '^GATE=state-sync$' 'state-sync gate key'
assert_line "$stdout" '^PASSED=1$' 'state-sync gate pass'

printf 'runtime-gates tests: OK\n'
