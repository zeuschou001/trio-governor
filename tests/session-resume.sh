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
HOME="$h" "$REPO/trio" session resume --mode dev "$host" " continue " >"$stdout"
assert_line "$stdout" '^RESUME_RESULT=not-awaiting-decision$' 'fresh not awaiting decision'
assert_line "$stdout" '^NORMALIZED_INPUT=continue$' 'fresh normalized input'
assert_line "$stdout" '^START_ACTION=run-phase$' 'fresh start action'
assert_line "$stdout" '^RUN_PHASE=office-hours$' 'fresh run phase'

host2=$(mktemp -d)
(cd "$host2" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev "$host2" >/dev/null
HOME="$h" "$REPO/trio" session resume --mode dev "$host2" " CONTINUE " >"$stdout"
assert_line "$stdout" '^RESUME_RESULT=accepted$' 'continue accepted'
assert_line "$stdout" '^NORMALIZED_INPUT=continue$' 'continue normalized input'
assert_line "$stdout" '^APPLIED_ACTION=continue$' 'continue action'
assert_line "$stdout" '^STATUS=running$' 'continue status'
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'continue phase'

host3=$(mktemp -d)
(cd "$host3" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode quick "$host3" >/dev/null
HOME="$h" "$REPO/trio" session resume --mode dev "$host3" " maybe " >"$stdout"
assert_line "$stdout" '^RESUME_RESULT=invalid$' 'invalid result'
assert_line "$stdout" '^NORMALIZED_INPUT=maybe$' 'invalid normalized input'
assert_line "$stdout" '^ALLOWED_INPUTS=c,continue,r,restart,a,abort$' 'invalid allowed inputs'
assert_line "$stdout" '^START_ACTION=resume-decision$' 'invalid start action'
assert_line "$stdout" '^PROFILE_MISMATCH=1$' 'invalid profile mismatch'
HOME="$h" "$REPO/trio" session phase "$host3" >"$stdout"
assert_line "$stdout" '^MODE=quick$' 'invalid preserves mode'
assert_line "$stdout" '^STATUS=awaiting-start-confirmation$' 'invalid preserves status'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'invalid preserves phase'

HOME="$h" "$REPO/trio" session resume --mode dev "$host3" "-nope" >"$stdout"
assert_line "$stdout" '^RESUME_RESULT=invalid$' 'dash-prefixed invalid result'
assert_line "$stdout" '^NORMALIZED_INPUT=-nope$' 'dash-prefixed invalid normalized input'
assert_line "$stdout" '^ALLOWED_INPUTS=c,continue,r,restart,a,abort$' 'dash-prefixed invalid allowed inputs'

HOME="$h" "$REPO/trio" session resume --mode dev "$host3" " r " >"$stdout"
assert_line "$stdout" '^RESUME_RESULT=accepted$' 'restart accepted'
assert_line "$stdout" '^NORMALIZED_INPUT=r$' 'restart normalized input'
assert_line "$stdout" '^APPLIED_ACTION=restart$' 'restart action'
assert_line "$stdout" '^MODE=dev$' 'restart mode'
assert_line "$stdout" '^STATUS=running$' 'restart status'
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'restart phase'
assert_line "$stdout" '^ADAPTER_MODE=full$' 'restart adapter mode'

host4=$(mktemp -d)
(cd "$host4" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev --with-ceo "$host4" >/dev/null
HOME="$h" "$REPO/trio" session resume --mode dev --with-ceo "$host4" " abort " >"$stdout"
assert_line "$stdout" '^RESUME_RESULT=accepted$' 'abort accepted'
assert_line "$stdout" '^NORMALIZED_INPUT=abort$' 'abort normalized input'
assert_line "$stdout" '^APPLIED_ACTION=abort$' 'abort action'
assert_line "$stdout" '^STATUS=aborted$' 'abort status'
assert_line "$stdout" '^PHASE_EXECUTOR=-$' 'abort phase executor'
HOME="$h" "$REPO/trio" runtime status "$host4" >"$stdout"
assert_line "$stdout" '^STATUS=aborted$' 'abort persisted'
if grep -q '^RESUME_AVAILABLE=' "$stdout"; then
  printf 'FAIL aborted session should not be resumable after session resume abort\n' >&2
  cat "$stdout" >&2
  exit 1
fi

host5=$(mktemp -d)
(cd "$host5" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode quick "$host5" >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host5" start-guard-yes quick-writing-plans >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host5" stage-finished quick-writing-plans >/dev/null
HOME="$h" "$REPO/trio" session resume --mode dev "$host5" "continue" >"$stdout"
assert_line "$stdout" '^RESUME_RESULT=accepted$' 'awaiting continue accepted'
assert_line "$stdout" '^APPLIED_ACTION=continue$' 'awaiting continue action'
assert_line "$stdout" '^MODE=quick$' 'awaiting continue preserves mode'
assert_line "$stdout" '^STATUS=awaiting-confirmation$' 'awaiting continue preserves status'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'awaiting continue preserves phase'
assert_line "$stdout" '^ADAPTER_MODE=minimal$' 'awaiting continue preserves adapter mode'

printf 'session-resume tests: OK\n'
