#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_line() {
  local file="$1" pattern="$2" label="$3"
  grep -q "$pattern" "$file" || { printf 'FAIL %s\n' "$label" >&2; cat "$file" >&2; exit 1; }
}

complete_quick_session() {
  local home="$1" host="$2"
  HOME="$home" "$REPO/trio" session confirm "$host" "yes" >/dev/null 2>&1 || true
  HOME="$home" "$REPO/trio" runtime transition "$host" stage-finished quick-writing-plans >/dev/null
  HOME="$home" "$REPO/trio" session confirm "$host" "yes" >/dev/null
  HOME="$home" "$REPO/trio" runtime transition "$host" stage-finished quick-executing-plans >/dev/null
  HOME="$home" "$REPO/trio" session confirm "$host" "yes" >/dev/null
  HOME="$home" "$REPO/trio" runtime transition "$host" stage-finished quick-verification-before-completion >/dev/null
  HOME="$home" "$REPO/trio" session confirm "$host" "yes" >/dev/null
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
host=$(mktemp -d)
(cd "$host" && git init -q .)
stdout=$(mktemp)

HOME="$h" "$REPO/trio" session start --mode dev "$host" >"$stdout"
assert_line "$stdout" '^REQUESTED_MODE=dev$' 'fresh requested mode'
assert_line "$stdout" '^REQUESTED_ADAPTER_MODE=full$' 'fresh requested adapter mode'
assert_line "$stdout" '^REQUESTED_CEO_REVIEW_FORCED=0$' 'fresh requested ceo review forced'
assert_line "$stdout" '^ACTIVE_MODE=dev$' 'fresh active mode'
assert_line "$stdout" '^ADAPTER_MODE=full$' 'fresh active adapter mode'
assert_line "$stdout" '^CEO_REVIEW_FORCED=0$' 'fresh active ceo review forced'
assert_line "$stdout" '^START_ACTION=run-phase$' 'fresh start action'
assert_line "$stdout" '^PROFILE_MISMATCH=0$' 'fresh profile mismatch'
assert_line "$stdout" '^RUN_PHASE=office-hours$' 'fresh run phase'
assert_line "$stdout" '^GSTACK_ENABLED=1$' 'fresh gstack enabled'
assert_line "$stdout" '^DETECTED_SUPERPOWERS_VERSION=5.0.7$' 'fresh detected superpowers'

HOME="$h" "$REPO/trio" session start --mode dev "$host" >"$stdout"
assert_line "$stdout" '^START_ACTION=resume-decision$' 'same-mode resume action'
assert_line "$stdout" '^RESUME_MODE=dev$' 'same-mode resume mode'
assert_line "$stdout" '^RESTART_MODE=dev$' 'same-mode restart mode'
assert_line "$stdout" '^RESTART_ADAPTER_MODE=full$' 'same-mode restart adapter mode'
assert_line "$stdout" '^RESTART_CEO_REVIEW_FORCED=0$' 'same-mode restart ceo review forced'
assert_line "$stdout" '^PROFILE_MISMATCH=0$' 'same-mode profile mismatch'

HOME="$h" "$REPO/trio" session start --mode dev --minimal "$host" >"$stdout"
assert_line "$stdout" '^START_ACTION=resume-decision$' 'same-mode minimal resume action'
assert_line "$stdout" '^PROFILE_MISMATCH=1$' 'same-mode minimal profile mismatch'
assert_line "$stdout" '^RESTART_ADAPTER_MODE=minimal$' 'same-mode minimal restart adapter mode'

host2=$(mktemp -d)
(cd "$host2" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode quick "$host2" >"$stdout"
assert_line "$stdout" '^REQUESTED_MODE=quick$' 'quick requested mode'
assert_line "$stdout" '^REQUESTED_ADAPTER_MODE=minimal$' 'quick requested adapter mode'
assert_line "$stdout" '^ACTIVE_MODE=quick$' 'quick active mode'
assert_line "$stdout" '^STATUS=awaiting-start-confirmation$' 'quick active status'
assert_line "$stdout" '^GSTACK_ENABLED=0$' 'quick gstack disabled'
assert_line "$stdout" '^ADAPTER_MODE=minimal$' 'quick minimal adapter mode'
assert_line "$stdout" '^START_ACTION=run-phase$' 'quick run phase'

HOME="$h" "$REPO/trio" session start --mode quick "$host2" >"$stdout"
assert_line "$stdout" '^START_ACTION=run-phase$' 'quick pending guard rerun action'
assert_line "$stdout" '^STATUS=awaiting-start-confirmation$' 'quick pending guard rerun status'

HOME="$h" "$REPO/trio" session start --mode dev "$host2" >"$stdout"
assert_line "$stdout" '^START_ACTION=resume-decision$' 'cross-mode resume action'
assert_line "$stdout" '^ACTIVE_MODE=quick$' 'cross-mode active mode preserved'
assert_line "$stdout" '^RESUME_STATUS=awaiting-start-confirmation$' 'cross-mode resume status preserved'
assert_line "$stdout" '^RESUME_MODE=quick$' 'cross-mode resume mode'
assert_line "$stdout" '^RESTART_MODE=dev$' 'cross-mode restart mode'
assert_line "$stdout" '^RESTART_ADAPTER_MODE=full$' 'cross-mode restart adapter mode'
assert_line "$stdout" '^PROFILE_MISMATCH=1$' 'cross-mode profile mismatch'

host3=$(mktemp -d)
(cd "$host3" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev --with-ceo "$host3" >"$stdout"
assert_line "$stdout" '^REQUESTED_CEO_REVIEW_FORCED=1$' 'with-ceo requested'
assert_line "$stdout" '^CEO_REVIEW_FORCED=1$' 'with-ceo active forced'
assert_line "$stdout" '^PROFILE_MISMATCH=0$' 'with-ceo profile mismatch'

host4=$(mktemp -d)
(cd "$host4" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode quick "$host4" >/dev/null
complete_quick_session "$h" "$host4"
HOME="$h" "$REPO/trio" session start --mode quick "$host4" >"$stdout"
assert_line "$stdout" '^ACTIVE_MODE=quick$' 'repeat quick active mode'
assert_line "$stdout" '^STATUS=running$' 'repeat quick should skip guard'
assert_line "$stdout" '^CURRENT_PHASE=quick-writing-plans$' 'repeat quick restart phase'
assert_line "$stdout" '^START_ACTION=run-phase$' 'repeat quick run phase'

stderr=$(mktemp)
set +e
HOME="$h" "$REPO/trio" session start --mode dev --with-ceo --minimal "$host3" >"$stdout" 2>"$stderr"
ec=$?
set -e
[ "$ec" = "2" ] || { printf 'FAIL mutual exclusion exit\n' >&2; exit 1; }
assert_line "$stderr" '互斥' 'mutual exclusion message'

printf 'session-start tests: OK\n'
