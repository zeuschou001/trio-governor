#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_line() {
  local file="$1" pattern="$2" label="$3"
  grep -q "$pattern" "$file" || { printf 'FAIL %s\n' "$label" >&2; cat "$file" >&2; exit 1; }
}

complete_quick_session() {
  local host="$1"
  "$REPO/trio" runtime transition "$host" start-guard-yes quick-writing-plans >/dev/null
  "$REPO/trio" runtime transition "$host" stage-finished quick-writing-plans >/dev/null
  "$REPO/trio" runtime transition "$host" confirm-yes quick-writing-plans >/dev/null
  "$REPO/trio" runtime transition "$host" stage-finished quick-executing-plans >/dev/null
  "$REPO/trio" runtime transition "$host" confirm-yes quick-executing-plans >/dev/null
  "$REPO/trio" runtime transition "$host" stage-finished quick-verification-before-completion >/dev/null
  "$REPO/trio" runtime transition "$host" confirm-yes quick-verification-before-completion >/dev/null
}

h=$(mktemp -d)
(cd "$h" && git init -q .)

boot_out=$(mktemp)
"$REPO/trio" runtime bootstrap --mode dev "$h" >"$boot_out"
assert_line "$boot_out" '^MODE=dev$' 'bootstrap mode'
assert_line "$boot_out" '^STATUS=running$' 'bootstrap status'
assert_line "$boot_out" '^CURRENT_PHASE=office-hours$' 'bootstrap phase'

stdout=$(mktemp)
stderr=$(mktemp)
"$REPO/trio" runtime status "$h" >"$stdout" 2>"$stderr"
assert_line "$stdout" '^MODE=dev$' 'status mode'
assert_line "$stdout" '^STATUS=running$' 'status running'
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'status current phase'
assert_line "$stdout" '^COMPLETED_PHASES=\[\]$' 'status completed phases'
assert_line "$stdout" '^ADAPTER_MODE=full$' 'status adapter mode'
assert_line "$stdout" '^CEO_REVIEW_FORCED=0$' 'status ceo review forced'
assert_line "$stdout" '^PROVIDER_SNAPSHOT=superpowers=unknown,gstack=unknown,gsd2=unknown,trellis=unknown$' 'status provider snapshot'
assert_line "$stdout" '^PROVIDER_SELECTION=discovery=gstack,product-review=gstack,architecture-review=gstack,planning=superpowers,execution=superpowers,verification=superpowers,qa=gstack,finish=superpowers$' 'status provider selection'
assert_line "$stdout" '^RESUME_AVAILABLE=1$' 'status resume available'
[ ! -s "$stderr" ] || { printf 'FAIL status stderr not empty\n' >&2; cat "$stderr" >&2; exit 1; }

"$REPO/trio" runtime record-deps "$h" 5.0.7 'superpowers=5.0.7,gstack=present,gsd2=absent,trellis=absent' 'discovery=gstack,planning=superpowers,qa=gstack' >"$stdout"
assert_line "$stdout" '^SUPERPOWERS_VERSION=5.0.7$' 'record-deps output'
grep -q '^superpowers_version: 5.0.7$' "$h/.trio/STATE.md" || { printf 'FAIL record-deps state write\n' >&2; exit 1; }
grep -q '^provider_snapshot: superpowers=5.0.7,gstack=present,gsd2=absent,trellis=absent$' "$h/.trio/STATE.md" || { printf 'FAIL record-deps provider snapshot write\n' >&2; exit 1; }
grep -q '^provider_selection: discovery=gstack,planning=superpowers,qa=gstack$' "$h/.trio/STATE.md" || { printf 'FAIL record-deps provider selection write\n' >&2; exit 1; }

h2=$(mktemp -d)
(cd "$h2" && git init -q .)
"$REPO/trio" runtime bootstrap --mode quick "$h2" >"$stdout"
assert_line "$stdout" '^MODE=quick$' 'quick bootstrap mode'
assert_line "$stdout" '^STATUS=awaiting-start-confirmation$' 'quick bootstrap status'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'quick bootstrap phase'
"$REPO/trio" runtime status "$h2" >"$stdout"
assert_line "$stdout" '^STATUS=awaiting-start-confirmation$' 'quick status guard pending'
assert_line "$stdout" '^RESUME_AVAILABLE=1$' 'quick status resume available'
complete_quick_session "$h2"
"$REPO/trio" runtime bootstrap --mode quick "$h2" >"$stdout"
assert_line "$stdout" '^MODE=quick$' 'quick bootstrap after completion mode'
assert_line "$stdout" '^STATUS=running$' 'quick bootstrap after completion status'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'quick bootstrap after completion phase'
grep -q '^quick_streak: 1$' "$h2/.trio/STATE.md" || { printf 'FAIL quick bootstrap should preserve quick streak\n' >&2; exit 1; }

tmp="$h/.trio/STATE.tmp"
sed 's/^quick_streak: .*/quick_streak: 9/' "$h/.trio/STATE.md" >"$tmp"
mv "$tmp" "$h/.trio/STATE.md"
"$REPO/trio" runtime bootstrap --mode dev "$h" >/dev/null
grep -q '^quick_streak: 0$' "$h/.trio/STATE.md" || { printf 'FAIL dev bootstrap should reset quick streak\n' >&2; exit 1; }

sed 's/^completed_phases: .*/completed_phases: [quick-writing-plans]/' "$h/.trio/STATE.md" >"$tmp"
mv "$tmp" "$h/.trio/STATE.md"
set +e
"$REPO/trio" runtime status "$h" >"$stdout" 2>"$stderr"
ec=$?
set -e
[ "$ec" = "1" ] || { printf 'FAIL malformed state should exit 1\n' >&2; exit 1; }
assert_line "$stderr" 'completed_phases' 'malformed state stderr'

set +e
"$REPO/trio" runtime not-a-verb >"$stdout" 2>"$stderr"
ec=$?
set -e
[ "$ec" = "2" ] || { printf 'FAIL unknown verb exit=%s\n' "$ec" >&2; exit 1; }
[ ! -s "$stdout" ] || { printf 'FAIL unknown verb polluted stdout\n' >&2; cat "$stdout" >&2; exit 1; }
assert_line "$stderr" '用法:' 'unknown verb usage'

printf 'runtime-status tests: OK\n'
