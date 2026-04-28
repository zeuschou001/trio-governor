#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_line() {
  local file="$1" pattern="$2" label="$3"
  grep -q "$pattern" "$file" || { printf 'FAIL %s\n' "$label" >&2; cat "$file" >&2; exit 1; }
}

complete_quick_session() {
  local host="$1"
  "$REPO/trio" runtime transition "$host" start-guard-yes quick-writing-plans >/dev/null 2>&1 || true
  "$REPO/trio" runtime transition "$host" stage-finished quick-writing-plans >/dev/null
  "$REPO/trio" runtime transition "$host" confirm-yes quick-writing-plans >/dev/null
  "$REPO/trio" runtime transition "$host" stage-finished quick-executing-plans >/dev/null
  "$REPO/trio" runtime transition "$host" confirm-yes quick-executing-plans >/dev/null
  "$REPO/trio" runtime transition "$host" stage-finished quick-verification-before-completion >/dev/null
  "$REPO/trio" runtime transition "$host" confirm-yes quick-verification-before-completion >/dev/null
}

h=$(mktemp -d)
(cd "$h" && git init -q .)
"$REPO/trio" runtime bootstrap --mode dev "$h" >/dev/null

stdout=$(mktemp)
"$REPO/trio" runtime transition "$h" stage-finished office-hours >"$stdout"
assert_line "$stdout" '^STATUS=awaiting-confirmation$' 'stage-finished status'
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'stage-finished phase'

"$REPO/trio" runtime transition "$h" confirm-no office-hours >"$stdout"
assert_line "$stdout" '^STATUS=running$' 'confirm-no status'
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'confirm-no phase'

"$REPO/trio" runtime transition "$h" stage-finished office-hours >/dev/null
"$REPO/trio" runtime transition "$h" confirm-yes office-hours >"$stdout"
assert_line "$stdout" '^CURRENT_PHASE=plan-ceo-review$' 'confirm-yes next phase'
assert_line "$stdout" '^COMPLETED_PHASES=\[office-hours\]$' 'confirm-yes append history'

"$REPO/trio" runtime transition "$h" stage-finished plan-ceo-review >/dev/null
"$REPO/trio" runtime transition "$h" confirm-skip plan-ceo-review >"$stdout"
assert_line "$stdout" '^CURRENT_PHASE=plan-eng-review$' 'confirm-skip next phase'
assert_line "$stdout" '^COMPLETED_PHASES=\[office-hours\]$' 'confirm-skip no append'

set +e
"$REPO/trio" runtime transition "$h" confirm-skip plan-eng-review >/dev/null 2>&1
ec=$?
set -e
[ "$ec" != "0" ] || { printf 'FAIL invalid skip accepted\n' >&2; exit 1; }

h3=$(mktemp -d)
(cd "$h3" && git init -q .)
"$REPO/trio" runtime bootstrap --mode dev "$h3" >/dev/null
"$REPO/trio" runtime transition "$h3" stage-finished office-hours >/dev/null
"$REPO/trio" runtime transition "$h3" confirm-yes-skip-optional-next office-hours >"$stdout"
assert_line "$stdout" '^CURRENT_PHASE=plan-eng-review$' 'conditional ceo path next phase'
assert_line "$stdout" '^COMPLETED_PHASES=\[office-hours\]$' 'conditional ceo path append history'

set +e
"$REPO/trio" runtime transition "$h3" confirm-yes-skip-optional-next plan-eng-review >/dev/null 2>&1
ec=$?
set -e
[ "$ec" != "0" ] || { printf 'FAIL invalid optional-next accepted\n' >&2; exit 1; }

h2=$(mktemp -d)
(cd "$h2" && git init -q .)
"$REPO/trio" runtime bootstrap --mode quick "$h2" >/dev/null
"$REPO/trio" runtime transition "$h2" start-guard-yes quick-writing-plans >"$stdout"
assert_line "$stdout" '^STATUS=running$' 'quick guard confirm status'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'quick guard confirm phase'
"$REPO/trio" runtime transition "$h2" stage-finished quick-writing-plans >/dev/null
"$REPO/trio" runtime transition "$h2" confirm-yes quick-writing-plans >"$stdout"
assert_line "$stdout" '^MODE=quick$' 'quick transition mode'
assert_line "$stdout" '^CURRENT_PHASE=quick-executing-plans$' 'quick next phase'
assert_line "$stdout" '^COMPLETED_PHASES=\[quick-writing-plans\]$' 'quick append history'
grep -q '^quick_streak: 1$' "$h2/.trio/STATE.md" || { printf 'FAIL quick streak increment\n' >&2; exit 1; }

h4=$(mktemp -d)
(cd "$h4" && git init -q .)
"$REPO/trio" runtime bootstrap --mode quick "$h4" >/dev/null
"$REPO/trio" runtime transition "$h4" abort quick-writing-plans >"$stdout"
assert_line "$stdout" '^STATUS=aborted$' 'abort transition status'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'abort transition phase'

h5=$(mktemp -d)
(cd "$h5" && git init -q .)
"$REPO/trio" runtime bootstrap --mode quick "$h5" >/dev/null
complete_quick_session "$h5"
"$REPO/trio" runtime restart --mode quick "$h5" >"$stdout"
assert_line "$stdout" '^MODE=quick$' 'quick restart mode'
assert_line "$stdout" '^STATUS=running$' 'quick restart should skip guard after streak'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'quick restart resets phase'
grep -q '^quick_streak: 1$' "$h5/.trio/STATE.md" || { printf 'FAIL quick restart should preserve quick streak\n' >&2; exit 1; }
"$REPO/trio" runtime restart --mode dev "$h5" >/dev/null
grep -q '^quick_streak: 0$' "$h5/.trio/STATE.md" || { printf 'FAIL dev restart should reset quick streak\n' >&2; exit 1; }

printf 'runtime-transition tests: OK\n'
