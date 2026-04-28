#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_line() {
  local file="$1" pattern="$2" label="$3"
  grep -q "$pattern" "$file" || { printf 'FAIL %s\n' "$label" >&2; cat "$file" >&2; exit 1; }
}

prep_home() {
  local home="$1"
  mkdir -p "$home/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills"
  for s in writing-plans executing-plans test-driven-development verification-before-completion finishing-a-development-branch; do
    mkdir -p "$home/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/$s"
    echo "x" > "$home/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/$s/SKILL.md"
  done
  for s in office-hours plan-ceo-review plan-eng-review qa; do
    mkdir -p "$home/.claude/skills/$s"
    printf -- '---\nname: %s\n---\n' "$s" > "$home/.claude/skills/$s/SKILL.md"
  done
}

h=$(mktemp -d)
prep_home "$h"
stdout=$(mktemp)

host=$(mktemp -d)
(cd "$host" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev "$host" >/dev/null
HOME="$h" "$REPO/trio" session confirm "$host" " yes " >"$stdout"
assert_line "$stdout" '^CONFIRM_RESULT=not-awaiting-confirmation$' 'not awaiting result'
assert_line "$stdout" '^STATUS=running$' 'not awaiting status'

host2=$(mktemp -d)
(cd "$host2" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev "$host2" >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host2" stage-finished office-hours >/dev/null
HOME="$h" "$REPO/trio" session confirm "$host2" " YES " >"$stdout"
assert_line "$stdout" '^CONFIRM_RESULT=accepted$' 'dev confirm accepted'
assert_line "$stdout" '^NORMALIZED_INPUT=yes$' 'dev normalized input'
assert_line "$stdout" '^APPLIED_ACTION=confirm-yes-skip-optional-next$' 'dev applied action'
assert_line "$stdout" '^CURRENT_PHASE=plan-eng-review$' 'dev next phase'
assert_line "$stdout" '^STATUS=running$' 'dev post status'

host3=$(mktemp -d)
(cd "$host3" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev "$host3" >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host3" stage-finished office-hours >/dev/null
HOME="$h" "$REPO/trio" session confirm "$host3" " maybe " >"$stdout"
assert_line "$stdout" '^CONFIRM_RESULT=invalid$' 'invalid result'
assert_line "$stdout" '^NORMALIZED_INPUT=maybe$' 'invalid normalized input'
assert_line "$stdout" '^ALLOWED_INPUTS=y,yes,n,no$' 'invalid allowed inputs'
HOME="$h" "$REPO/trio" session phase "$host3" >"$stdout"
assert_line "$stdout" '^STATUS=awaiting-confirmation$' 'invalid preserves awaiting status'
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'invalid preserves phase'

host4=$(mktemp -d)
(cd "$host4" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev --with-ceo "$host4" >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host4" stage-finished office-hours >/dev/null
HOME="$h" "$REPO/trio" session confirm "$host4" "y" >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host4" stage-finished plan-ceo-review >/dev/null
HOME="$h" "$REPO/trio" session confirm "$host4" " skip " >"$stdout"
assert_line "$stdout" '^CONFIRM_RESULT=accepted$' 'skip accepted'
assert_line "$stdout" '^APPLIED_ACTION=confirm-skip$' 'skip applied action'
assert_line "$stdout" '^ALLOWED_INPUTS=y,yes,n,no,s,skip$' 'skip allowed inputs'
assert_line "$stdout" '^CURRENT_PHASE=plan-eng-review$' 'skip next phase'

host5=$(mktemp -d)
(cd "$host5" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode quick "$host5" >/dev/null
HOME="$h" "$REPO/trio" session confirm "$host5" " yes " >"$stdout"
assert_line "$stdout" '^CONFIRM_RESULT=accepted$' 'quick guard accepted'
assert_line "$stdout" '^APPLIED_ACTION=start-guard-yes$' 'quick guard applied action'
assert_line "$stdout" '^STATUS=running$' 'quick guard post status'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'quick guard post phase'

host6=$(mktemp -d)
(cd "$host6" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode quick "$host6" >/dev/null
HOME="$h" "$REPO/trio" session confirm "$host6" "n" >"$stdout"
assert_line "$stdout" '^CONFIRM_RESULT=accepted$' 'quick guard decline accepted'
assert_line "$stdout" '^APPLIED_ACTION=abort$' 'quick guard decline action'
assert_line "$stdout" '^STATUS=aborted$' 'quick guard decline status'

host7=$(mktemp -d)
(cd "$host7" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode quick "$host7" >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host7" start-guard-yes quick-writing-plans >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host7" stage-finished quick-writing-plans >/dev/null
HOME="$h" "$REPO/trio" session confirm "$host7" "n" >"$stdout"
assert_line "$stdout" '^CONFIRM_RESULT=accepted$' 'quick no accepted'
assert_line "$stdout" '^APPLIED_ACTION=confirm-no$' 'quick no action'
assert_line "$stdout" '^STATUS=running$' 'quick no post status'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'quick no same phase'

printf 'session-confirm tests: OK\n'
