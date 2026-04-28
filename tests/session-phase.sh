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
stdout=$(mktemp)

host=$(mktemp -d)
(cd "$host" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev "$host" >/dev/null
HOME="$h" "$REPO/trio" session phase "$host" >"$stdout"
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'dev phase current phase'
assert_line "$stdout" '^CURRENT_PHASE_INDEX=1$' 'dev phase index'
assert_line "$stdout" '^TOTAL_PHASES=8$' 'dev phase total'
assert_line "$stdout" '^PHASE_EXECUTOR=adapter$' 'dev phase executor'
assert_line "$stdout" '^PHASE_CAPABILITY=discovery$' 'dev phase capability'
assert_line "$stdout" '^PROVIDER_ID=gstack$' 'dev provider id'
assert_line "$stdout" '^PROVIDER_KIND=skill-provider$' 'dev provider kind'
assert_line "$stdout" '^PROVIDER_INVOKE_MODE=skill$' 'dev provider invoke mode'
assert_line "$stdout" '^PROVIDER_ENTRYPOINTS=office-hours$' 'dev provider entrypoints'
assert_line "$stdout" '^PROVIDER_WRITER_BOUNDARY=project-write$' 'dev provider writer boundary'
assert_line "$stdout" '^ADAPTER_PROVIDER=gstack$' 'dev phase provider'
assert_line "$stdout" '^ADAPTER_SKILLS=office-hours$' 'dev phase skills'
assert_line "$stdout" '^PHASE_WRITERS=project-write$' 'dev phase writers'
assert_line "$stdout" '^PHASE_INPUT_FILES=STATE.md$' 'dev phase input files'
assert_line "$stdout" '^YES_ACTION=confirm-yes-skip-optional-next$' 'dev phase yes action'
assert_line "$stdout" '^NEXT_PHASE_ON_YES=plan-eng-review$' 'dev phase next on yes'
assert_line "$stdout" '^NEXT_PHASE_INPUT_FILES_ON_YES=PROJECT.md,DECISIONS.md,STATE.md$' 'dev phase next input files on yes'
assert_line "$stdout" '^DETECT_MINIMAL=0$' 'dev phase detect minimal'

host2=$(mktemp -d)
(cd "$host2" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev --with-ceo "$host2" >/dev/null
HOME="$h" "$REPO/trio" session phase "$host2" >"$stdout"
assert_line "$stdout" '^TOTAL_PHASES=9$' 'with-ceo total'
assert_line "$stdout" '^CEO_REVIEW_FORCED=1$' 'with-ceo forced'
assert_line "$stdout" '^CEO_REVIEW_REQUIRED=1$' 'with-ceo required'
assert_line "$stdout" '^YES_ACTION=confirm-yes$' 'with-ceo yes action'
assert_line "$stdout" '^NEXT_PHASE_ON_YES=plan-ceo-review$' 'with-ceo next on yes'
assert_line "$stdout" '^NEXT_PHASE_INPUT_FILES_ON_YES=PROJECT.md,STATE.md$' 'with-ceo next input files on yes'

host3=$(mktemp -d)
(cd "$host3" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev --minimal "$host3" >/dev/null
HOME="$h" "$REPO/trio" session phase "$host3" >"$stdout"
assert_line "$stdout" '^ADAPTER_MODE=minimal$' 'minimal adapter mode'
assert_line "$stdout" '^PHASE_EXECUTOR=dialogue$' 'minimal phase executor'
assert_line "$stdout" '^PHASE_CAPABILITY=discovery$' 'minimal phase capability'
assert_line "$stdout" '^PROVIDER_ID=-$' 'minimal provider id'
assert_line "$stdout" '^PROVIDER_ENTRYPOINTS=-$' 'minimal provider entrypoints'
assert_line "$stdout" '^PROVIDER_WRITER_BOUNDARY=project-write$' 'minimal provider writer boundary'
assert_line "$stdout" '^ADAPTER_PROVIDER=-$' 'minimal phase provider'
assert_line "$stdout" '^ADAPTER_SKILLS=-$' 'minimal phase skills'
assert_line "$stdout" '^PHASE_INPUT_FILES=STATE.md$' 'minimal phase input files'
assert_line "$stdout" '^DETECT_MINIMAL=1$' 'minimal phase detect minimal'

host4=$(mktemp -d)
(cd "$host4" && git init -q .)
HOME="$h" "$REPO/trio" runtime bootstrap --mode dev "$host4" >/dev/null
HOME="$h" "$REPO/trio" runtime project-write "$host4" demo user-facing-feature desc >/dev/null
HOME="$h" "$REPO/trio" session phase "$host4" >"$stdout"
assert_line "$stdout" '^PROJECT_TYPE=user-facing-feature$' 'project type surfaced'
assert_line "$stdout" '^CEO_REVIEW_REQUIRED=1$' 'project type requires ceo review'
assert_line "$stdout" '^YES_ACTION=confirm-yes$' 'project type yes action'

host4b=$(mktemp -d)
(cd "$host4b" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev --with-ceo "$host4b" >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host4b" stage-finished office-hours >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host4b" confirm-yes office-hours >/dev/null
HOME="$h" "$REPO/trio" session phase "$host4b" >"$stdout"
assert_line "$stdout" '^CURRENT_PHASE=plan-ceo-review$' 'ceo review current phase'
assert_line "$stdout" '^SKIP_ACTION=confirm-skip$' 'ceo review skip action'
assert_line "$stdout" '^NEXT_PHASE_ON_SKIP=plan-eng-review$' 'ceo review next on skip'
assert_line "$stdout" '^NEXT_PHASE_INPUT_FILES_ON_SKIP=PROJECT.md,DECISIONS.md,STATE.md$' 'ceo review next input files on skip'

host5=$(mktemp -d)
(cd "$host5" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode dev "$host5" >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host5" stage-finished office-hours >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host5" confirm-yes-skip-optional-next office-hours >/dev/null
HOME="$h" "$REPO/trio" runtime decision-append "$host5" eng-review "架构评审" "状态下沉" "减小 prompt 漂移" "影响 phase 契约" >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host5" stage-finished plan-eng-review >/dev/null
HOME="$h" "$REPO/trio" runtime transition "$host5" confirm-yes plan-eng-review >/dev/null
HOME="$h" "$REPO/trio" session phase "$host5" >"$stdout"
assert_line "$stdout" '^CURRENT_PHASE=state-sync$' 'state-sync current phase'
assert_line "$stdout" '^CURRENT_PHASE_INDEX=3$' 'state-sync phase index'
assert_line "$stdout" '^TOTAL_PHASES=8$' 'state-sync total'
assert_line "$stdout" '^PHASE_EXECUTOR=runtime$' 'state-sync executor'
assert_line "$stdout" '^PHASE_CAPABILITY=state-sync$' 'state-sync capability'
assert_line "$stdout" '^PROVIDER_ID=-$' 'state-sync provider id'
assert_line "$stdout" '^PROVIDER_WRITER_BOUNDARY=record-deps$' 'state-sync provider writer boundary'
assert_line "$stdout" '^PHASE_GATE=state-sync$' 'state-sync gate'
assert_line "$stdout" '^PHASE_WRITERS=record-deps$' 'state-sync writer'
assert_line "$stdout" '^PHASE_INPUT_FILES=DECISIONS.md,STATE.md$' 'state-sync input files'
assert_line "$stdout" '^NEXT_PHASE_ON_YES=writing-plans$' 'state-sync next on yes'
assert_line "$stdout" '^NEXT_PHASE_INPUT_FILES_ON_YES=PROJECT.md,DECISIONS.md,KNOWLEDGE.md,STATE.md$' 'state-sync next input files on yes'

host6=$(mktemp -d)
(cd "$host6" && git init -q .)
HOME="$h" "$REPO/trio" session start --mode quick "$host6" >/dev/null
HOME="$h" "$REPO/trio" session phase "$host6" >"$stdout"
assert_line "$stdout" '^PHASE_EXECUTOR=guard$' 'quick guard executor'
assert_line "$stdout" '^START_GUARD_REQUIRED=1$' 'quick guard required'
assert_line "$stdout" '^START_GUARD_KIND=quick-risk$' 'quick guard kind'
assert_line "$stdout" '^PHASE_INPUT_FILES=STATE.md$' 'quick guard input files'
assert_line "$stdout" '^YES_ACTION=start-guard-yes$' 'quick guard yes action'
assert_line "$stdout" '^NO_ACTION=abort$' 'quick guard no action'
assert_line "$stdout" '^NEXT_PHASE_ON_YES=quick-writing-plans$' 'quick guard next on yes'
assert_line "$stdout" '^NEXT_PHASE_INPUT_FILES_ON_YES=KNOWLEDGE.md,STATE.md$' 'quick guard next input files on yes'
complete_quick_session "$h" "$host6"
HOME="$h" "$REPO/trio" runtime restart --mode quick "$host6" >/dev/null
complete_quick_session "$h" "$host6"
HOME="$h" "$REPO/trio" runtime restart --mode quick "$host6" >/dev/null
complete_quick_session "$h" "$host6"
HOME="$h" "$REPO/trio" runtime restart --mode quick "$host6" >/dev/null
complete_quick_session "$h" "$host6"
HOME="$h" "$REPO/trio" runtime restart --mode quick "$host6" >/dev/null
HOME="$h" "$REPO/trio" session phase "$host6" >"$stdout"
assert_line "$stdout" '^MODE=quick$' 'quick phase mode'
assert_line "$stdout" '^CURRENT_PHASE_INDEX=1$' 'quick phase index'
assert_line "$stdout" '^TOTAL_PHASES=3$' 'quick total'
assert_line "$stdout" '^PHASE_CAPABILITY=planning$' 'quick phase capability'
assert_line "$stdout" '^PROVIDER_ID=superpowers$' 'quick provider id'
assert_line "$stdout" '^PROVIDER_KIND=plugin-provider$' 'quick provider kind'
assert_line "$stdout" '^PROVIDER_INVOKE_MODE=plugin-skill$' 'quick provider invoke mode'
assert_line "$stdout" '^PROVIDER_ENTRYPOINTS=writing-plans$' 'quick provider entrypoints'
assert_line "$stdout" '^ADAPTER_PROVIDER=superpowers$' 'quick phase provider'
assert_line "$stdout" '^ADAPTER_SKILLS=writing-plans$' 'quick phase skills'
assert_line "$stdout" '^PHASE_INPUT_FILES=KNOWLEDGE.md,STATE.md$' 'quick phase input files'
assert_line "$stdout" '^START_GUARD_REQUIRED=0$' 'quick guard cleared after confirm'
assert_line "$stdout" '^QUICK_STREAK=4$' 'quick streak accumulated naturally'
assert_line "$stdout" '^DEV_REVIEW_SUGGESTED=1$' 'quick review suggestion'

printf 'session-phase tests: OK\n'
