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
"$REPO/trio" runtime project-write "$h" "trio-dev" "internal-tool" "bridge export smoke" >/dev/null
"$REPO/trio" runtime decision-append "$h" eng-review "Bridge boundary" "只导出快照" "保持 runtime 状态 ownership" "外部工具只消费上下文" >/dev/null
"$REPO/trio" runtime knowledge-append "$h" "bridge" "export" "外部工具只能读 trio 快照" >/dev/null
printf '# Export roadmap\n- bridge snapshot\n' | "$REPO/trio" runtime roadmap-rewrite "$h" -- >/dev/null

stdout=$(mktemp)
stderr=$(mktemp)
"$REPO/trio" bridge status trellis "$h" >"$stdout" 2>"$stderr"
assert_line "$stdout" '^PROVIDER_ID=trellis$' 'status provider id'
assert_line "$stdout" '^PROVIDER_KIND=memory-bridge$' 'status provider kind'
assert_line "$stdout" '^PROVIDER_STATE_POLICY=export-only$' 'status provider state policy'
assert_line "$stdout" '^PROVIDER_STATUS=absent$' 'status provider availability'
assert_line "$stdout" '^PROVIDER_INSTALL_HINT=安装 trellis CLI 后再启用 bridge$' 'status install hint'
assert_line "$stdout" '^BRIDGE_COMMAND_HINT=manual-handoff$' 'status command hint'
assert_line "$stdout" '^EXPORT_COUNT=0$' 'status export count'
assert_line "$stdout" '^LATEST_EXPORT=-$' 'status latest export'
assert_line "$stdout" '^LATEST_HANDOFF=-$' 'status latest handoff'
assert_line "$stdout" '^STATE_OWNER=trio-runtime$' 'status state owner'
assert_line "$stdout" '^STATE_MUTATION=forbidden$' 'status state mutation'
[ ! -s "$stderr" ] || { printf 'FAIL status stderr not empty\n' >&2; cat "$stderr" >&2; exit 1; }

state_before=$(mktemp)
cp "$h/.trio/STATE.md" "$state_before"
"$REPO/trio" bridge export trellis "$h" >"$stdout" 2>"$stderr"
assert_line "$stdout" '^PROVIDER_ID=trellis$' 'export provider id'
assert_line "$stdout" '^PROVIDER_KIND=memory-bridge$' 'export provider kind'
assert_line "$stdout" '^PROVIDER_STATE_POLICY=export-only$' 'export provider state policy'
assert_line "$stdout" '^PROVIDER_INSTALL_HINT=安装 trellis CLI 后再启用 bridge$' 'export install hint'
assert_line "$stdout" '^BRIDGE_COMMAND_HINT=manual-handoff$' 'export command hint'
assert_line "$stdout" '^EXPORTED_FILES=PROJECT.md,DECISIONS.md,KNOWLEDGE.md,ROADMAP.md,STATE.md$' 'exported files'
assert_line "$stdout" '^HANDOFF_PATH=-$' 'export handoff path'
assert_line "$stdout" '^STATE_OWNER=trio-runtime$' 'export state owner'
assert_line "$stdout" '^STATE_MUTATION=forbidden$' 'export state mutation'
[ ! -s "$stderr" ] || { printf 'FAIL export stderr not empty\n' >&2; cat "$stderr" >&2; exit 1; }

export_dir=$(sed -n 's/^EXPORT_DIR=//p' "$stdout" | head -n 1)
manifest=$(sed -n 's/^MANIFEST_PATH=//p' "$stdout" | head -n 1)
[ -d "$export_dir" ] || { printf 'FAIL export dir missing\n' >&2; exit 1; }
[ -f "$manifest" ] || { printf 'FAIL manifest missing\n' >&2; exit 1; }
cmp -s "$state_before" "$h/.trio/STATE.md" || { printf 'FAIL bridge export should not modify STATE.md\n' >&2; exit 1; }
for file in PROJECT.md DECISIONS.md KNOWLEDGE.md ROADMAP.md STATE.md; do
  cmp -s "$h/.trio/$file" "$export_dir/$file" || { printf 'FAIL exported copy mismatch: %s\n' "$file" >&2; exit 1; }
done
. "$manifest"
[ "${PROVIDER_ID:-}" = 'trellis' ] || { printf 'FAIL manifest provider id\n' >&2; exit 1; }
[ "${EXPORTED_FILES:-}" = 'PROJECT.md,DECISIONS.md,KNOWLEDGE.md,ROADMAP.md,STATE.md' ] || { printf 'FAIL manifest exported files\n' >&2; exit 1; }
[ "${STATE_OWNER:-}" = 'trio-runtime' ] || { printf 'FAIL manifest state owner\n' >&2; exit 1; }
[ "${STATE_MUTATION:-}" = 'forbidden' ] || { printf 'FAIL manifest state mutation\n' >&2; exit 1; }

"$REPO/trio" bridge status trellis "$h" >"$stdout"
assert_line "$stdout" '^EXPORT_COUNT=1$' 'status export count after export'
latest_export=$(sed -n 's/^LATEST_EXPORT=//p' "$stdout" | head -n 1)
[ "$latest_export" = "$export_dir" ] || { printf 'FAIL latest export path mismatch\n' >&2; exit 1; }

"$REPO/trio" bridge handoff trellis "$h" >"$stdout" 2>"$stderr"
assert_line "$stdout" '^PROVIDER_ID=trellis$' 'handoff provider id'
assert_line "$stdout" '^PROVIDER_KIND=memory-bridge$' 'handoff provider kind'
assert_line "$stdout" '^PROVIDER_INSTALL_HINT=安装 trellis CLI 后再启用 bridge$' 'handoff install hint'
assert_line "$stdout" '^BRIDGE_COMMAND_HINT=manual-handoff$' 'handoff command hint'
assert_line "$stdout" '^EXPORTED_FILES=PROJECT.md,DECISIONS.md,KNOWLEDGE.md,ROADMAP.md,STATE.md$' 'handoff exported files'
[ ! -s "$stderr" ] || { printf 'FAIL handoff stderr not empty\n' >&2; cat "$stderr" >&2; exit 1; }
handoff_export_dir=$(sed -n 's/^EXPORT_DIR=//p' "$stdout" | head -n 1)
handoff_path=$(sed -n 's/^HANDOFF_PATH=//p' "$stdout" | head -n 1)
outputs_dir=$(sed -n 's/^OUTPUTS_DIR=//p' "$stdout" | head -n 1)
[ -d "$handoff_export_dir" ] || { printf 'FAIL handoff export dir missing\n' >&2; exit 1; }
[ -f "$handoff_path" ] || { printf 'FAIL handoff file missing\n' >&2; exit 1; }
[ -d "$outputs_dir" ] || { printf 'FAIL outputs dir missing\n' >&2; exit 1; }
grep -q '^# trio Bridge Handoff: trellis$' "$handoff_path" || { printf 'FAIL handoff title\n' >&2; exit 1; }
grep -q 'Trellis Handoff' "$handoff_path" || { printf 'FAIL handoff provider section\n' >&2; exit 1; }
grep -q 'STATE.md 归 trio-runtime 独占' "$handoff_path" || { printf 'FAIL handoff ownership warning\n' >&2; exit 1; }

"$REPO/trio" bridge status trellis "$h" >"$stdout"
assert_line "$stdout" '^EXPORT_COUNT=2$' 'status export count after handoff'
latest_handoff=$(sed -n 's/^LATEST_HANDOFF=//p' "$stdout" | head -n 1)
latest_outputs=$(sed -n 's/^LATEST_OUTPUTS_DIR=//p' "$stdout" | head -n 1)
[ "$latest_handoff" = "$handoff_path" ] || { printf 'FAIL latest handoff path mismatch\n' >&2; exit 1; }
[ "$latest_outputs" = "$outputs_dir" ] || { printf 'FAIL latest outputs dir mismatch\n' >&2; exit 1; }

printf '# Spec Summary\nconstraint snapshot\n' >"$outputs_dir/spec-summary.md"
printf '# Task Graph\n- rewrite roadmap\n' >"$outputs_dir/task-graph.md"
printf '# Memory Notes\n- keep this insight\n' >"$outputs_dir/memory-notes.md"
printf '# Extra Note\n- manual review\n' >"$outputs_dir/extra-note.md"
state_before_review=$(mktemp)
cp "$h/.trio/STATE.md" "$state_before_review"
"$REPO/trio" bridge review trellis "$h" >"$stdout" 2>"$stderr"
assert_line "$stdout" '^OUTPUT_FILES=extra-note.md,memory-notes.md,spec-summary.md,task-graph.md$' 'review output files'
assert_line "$stdout" '^UNMAPPED_OUTPUT_FILES=extra-note.md$' 'review unmapped files'
assert_line "$stdout" '^SUGGESTION_COUNT=4$' 'review suggestion count'
assert_line "$stdout" '^MANUAL_REVIEW_REQUIRED=1$' 'review manual review required'
assert_line "$stdout" '^SUGGESTION_1_KIND=decision-candidate$' 'review suggestion 1 kind'
assert_line "$stdout" '^SUGGESTION_1_RUNTIME_VERB=decision-append$' 'review suggestion 1 verb'
assert_line "$stdout" '^SUGGESTION_2_KIND=roadmap-rewrite-candidate$' 'review suggestion 2 kind'
assert_line "$stdout" '^SUGGESTION_2_RUNTIME_VERB=roadmap-rewrite$' 'review suggestion 2 verb'
assert_line "$stdout" '^SUGGESTION_3_KIND=knowledge-candidate$' 'review suggestion 3 kind'
assert_line "$stdout" '^SUGGESTION_3_RUNTIME_VERB=knowledge-append$' 'review suggestion 3 verb'
assert_line "$stdout" '^SUGGESTION_4_KIND=manual-review$' 'review suggestion 4 kind'
assert_line "$stdout" '^SUGGESTION_4_RUNTIME_VERB=-$' 'review suggestion 4 verb'
assert_line "$stdout" '^SUGGESTION_4_APPLY_HINT=-$' 'review suggestion 4 apply hint'
[ ! -s "$stderr" ] || { printf 'FAIL review stderr not empty\n' >&2; cat "$stderr" >&2; exit 1; }
cmp -s "$state_before_review" "$h/.trio/STATE.md" || { printf 'FAIL bridge review should not modify STATE.md\n' >&2; exit 1; }

"$REPO/trio" bridge draft trellis "$h" >"$stdout" 2>"$stderr"
assert_line "$stdout" '^SUGGESTION_COUNT=4$' 'draft suggestion count'
assert_line "$stdout" '^DRAFT_ACTIONABLE_COUNT=3$' 'draft actionable count'
assert_line "$stdout" '^DRAFT_MANUAL_ONLY_COUNT=1$' 'draft manual only count'
assert_line "$stdout" '^DRAFT_READY_TO_RUN=0$' 'draft ready flag'
[ ! -s "$stderr" ] || { printf 'FAIL draft stderr not empty\n' >&2; cat "$stderr" >&2; exit 1; }
draft_shell=$(sed -n 's/^DRAFT_SHELL_PATH=//p' "$stdout" | head -n 1)
draft_markdown=$(sed -n 's/^DRAFT_MARKDOWN_PATH=//p' "$stdout" | head -n 1)
[ -f "$draft_shell" ] || { printf 'FAIL draft shell missing\n' >&2; exit 1; }
[ -f "$draft_markdown" ] || { printf 'FAIL draft markdown missing\n' >&2; exit 1; }
grep -q '^# Manual draft generated by ./trio bridge draft for provider: trellis$' "$draft_shell" || { printf 'FAIL draft shell header\n' >&2; exit 1; }
grep -q '# ./trio runtime decision-append ' "$draft_shell" || { printf 'FAIL draft shell decision command\n' >&2; exit 1; }
grep -q '# ./trio runtime roadmap-rewrite ' "$draft_shell" || { printf 'FAIL draft shell roadmap command\n' >&2; exit 1; }
grep -q '# ./trio runtime knowledge-append ' "$draft_shell" || { printf 'FAIL draft shell knowledge command\n' >&2; exit 1; }
grep -q '# no direct runtime command draft; manual triage required' "$draft_shell" || { printf 'FAIL draft shell manual only note\n' >&2; exit 1; }
grep -q '^# trio Bridge Import Draft: trellis$' "$draft_markdown" || { printf 'FAIL draft markdown title\n' >&2; exit 1; }
grep -q 'Draft command: ./trio runtime decision-append ' "$draft_markdown" || { printf 'FAIL draft markdown decision command\n' >&2; exit 1; }
cmp -s "$state_before_review" "$h/.trio/STATE.md" || { printf 'FAIL bridge draft should not modify STATE.md\n' >&2; exit 1; }

"$REPO/trio" bridge status trellis "$h" >"$stdout"
assert_line "$stdout" '^LATEST_DRAFT_SHELL=.*IMPORT-DRAFT\.sh$' 'status latest draft shell'
assert_line "$stdout" '^LATEST_DRAFT_MARKDOWN=.*IMPORT-DRAFT\.md$' 'status latest draft markdown'

"$REPO/trio" bridge scaffold trellis "$h" >"$stdout" 2>"$stderr"
assert_line "$stdout" '^SUGGESTION_COUNT=4$' 'scaffold suggestion count'
assert_line "$stdout" '^SCAFFOLD_ACTIONABLE_COUNT=3$' 'scaffold actionable count'
assert_line "$stdout" '^SCAFFOLD_MANUAL_ONLY_COUNT=1$' 'scaffold manual only count'
assert_line "$stdout" '^SCAFFOLD_READY_TO_RUN=0$' 'scaffold ready flag'
[ ! -s "$stderr" ] || { printf 'FAIL scaffold stderr not empty\n' >&2; cat "$stderr" >&2; exit 1; }
scaffold_dir=$(sed -n 's/^SCAFFOLD_DIR=//p' "$stdout" | head -n 1)
scaffold_summary=$(sed -n 's/^SCAFFOLD_SUMMARY_PATH=//p' "$stdout" | head -n 1)
[ -d "$scaffold_dir" ] || { printf 'FAIL scaffold dir missing\n' >&2; exit 1; }
[ -f "$scaffold_summary" ] || { printf 'FAIL scaffold summary missing\n' >&2; exit 1; }
[ -f "$scaffold_dir/suggestion-1-decision.env" ] || { printf 'FAIL scaffold decision env missing\n' >&2; exit 1; }
[ -f "$scaffold_dir/suggestion-2-roadmap.env" ] || { printf 'FAIL scaffold roadmap env missing\n' >&2; exit 1; }
[ -f "$scaffold_dir/suggestion-3-knowledge.env" ] || { printf 'FAIL scaffold knowledge env missing\n' >&2; exit 1; }
[ -f "$scaffold_dir/suggestion-4-manual.md" ] || { printf 'FAIL scaffold manual note missing\n' >&2; exit 1; }
grep -q '^TYPE=eng-review$' "$scaffold_dir/suggestion-1-decision.env" || { printf 'FAIL scaffold decision default type\n' >&2; exit 1; }
grep -q '^WHAT=TODO_FILL_WHAT$' "$scaffold_dir/suggestion-1-decision.env" || { printf 'FAIL scaffold decision what placeholder\n' >&2; exit 1; }
grep -q '^ROADMAP_INPUT_FILE=' "$scaffold_dir/suggestion-2-roadmap.env" || { printf 'FAIL scaffold roadmap input file\n' >&2; exit 1; }
grep -q '^CONTEXT=TODO_FILL_CONTEXT$' "$scaffold_dir/suggestion-3-knowledge.env" || { printf 'FAIL scaffold knowledge context placeholder\n' >&2; exit 1; }
grep -q '^# Manual Scaffold: Suggestion 4$' "$scaffold_dir/suggestion-4-manual.md" || { printf 'FAIL scaffold manual note title\n' >&2; exit 1; }
grep -q '^# trio Bridge Import Scaffold: trellis$' "$scaffold_summary" || { printf 'FAIL scaffold summary title\n' >&2; exit 1; }
cmp -s "$state_before_review" "$h/.trio/STATE.md" || { printf 'FAIL bridge scaffold should not modify STATE.md\n' >&2; exit 1; }

"$REPO/trio" bridge status trellis "$h" >"$stdout"
assert_line "$stdout" '^LATEST_SCAFFOLD_DIR=.*import-scaffold$' 'status latest scaffold dir'
assert_line "$stdout" '^LATEST_SCAFFOLD_SUMMARY=.*IMPORT-SCAFFOLD\.md$' 'status latest scaffold summary'

h2=$(mktemp -d)
(cd "$h2" && git init -q .)
"$REPO/trio" runtime bootstrap --mode quick "$h2" >/dev/null
"$REPO/trio" bridge export gsd2 "$h2" >"$stdout"
assert_line "$stdout" '^PROVIDER_ID=gsd2$' 'quick export provider id'
assert_line "$stdout" '^PROVIDER_KIND=workflow-bridge$' 'quick export provider kind'
assert_line "$stdout" '^EXPORTED_FILES=KNOWLEDGE.md,STATE.md$' 'quick exported files'
quick_export_dir=$(sed -n 's/^EXPORT_DIR=//p' "$stdout" | head -n 1)
[ -f "$quick_export_dir/KNOWLEDGE.md" ] || { printf 'FAIL quick export knowledge missing\n' >&2; exit 1; }
[ -f "$quick_export_dir/STATE.md" ] || { printf 'FAIL quick export state missing\n' >&2; exit 1; }
[ ! -e "$quick_export_dir/PROJECT.md" ] || { printf 'FAIL quick export should not create PROJECT.md\n' >&2; exit 1; }

"$REPO/trio" bridge handoff gsd2 "$h2" >"$stdout"
assert_line "$stdout" '^PROVIDER_ID=gsd2$' 'quick handoff provider id'
assert_line "$stdout" '^PROVIDER_KIND=workflow-bridge$' 'quick handoff provider kind'
assert_line "$stdout" '^EXPORTED_FILES=KNOWLEDGE.md,STATE.md$' 'quick handoff exported files'
quick_handoff_path=$(sed -n 's/^HANDOFF_PATH=//p' "$stdout" | head -n 1)
[ -d "$(sed -n 's/^OUTPUTS_DIR=//p' "$stdout" | head -n 1)" ] || { printf 'FAIL quick outputs dir missing\n' >&2; exit 1; }
[ -f "$quick_handoff_path" ] || { printf 'FAIL quick handoff file missing\n' >&2; exit 1; }
grep -q 'GSD 2 Handoff' "$quick_handoff_path" || { printf 'FAIL quick handoff provider section\n' >&2; exit 1; }
quick_outputs_dir=$(sed -n 's/^OUTPUTS_DIR=//p' "$stdout" | head -n 1)
printf '# Followups\n- capture insight\n' >"$quick_outputs_dir/followups.md"
"$REPO/trio" bridge review gsd2 "$h2" >"$stdout"
assert_line "$stdout" '^OUTPUT_FILES=followups.md$' 'quick review output files'
assert_line "$stdout" '^SUGGESTION_COUNT=1$' 'quick review suggestion count'
assert_line "$stdout" '^SUGGESTION_1_KIND=knowledge-candidate$' 'quick review suggestion kind'
assert_line "$stdout" '^SUGGESTION_1_RUNTIME_VERB=knowledge-append$' 'quick review suggestion verb'
"$REPO/trio" bridge draft gsd2 "$h2" >"$stdout"
assert_line "$stdout" '^DRAFT_ACTIONABLE_COUNT=1$' 'quick draft actionable count'
assert_line "$stdout" '^DRAFT_MANUAL_ONLY_COUNT=0$' 'quick draft manual only count'
"$REPO/trio" bridge scaffold gsd2 "$h2" >"$stdout"
assert_line "$stdout" '^SCAFFOLD_ACTIONABLE_COUNT=1$' 'quick scaffold actionable count'
assert_line "$stdout" '^SCAFFOLD_MANUAL_ONLY_COUNT=0$' 'quick scaffold manual count'

set +e
"$REPO/trio" bridge export superpowers "$h" >"$stdout" 2>"$stderr"
ec=$?
set -e
[ "$ec" = "1" ] || { printf 'FAIL non-bridge provider exit=%s\n' "$ec" >&2; exit 1; }
assert_line "$stderr" '不是 bridge' 'non-bridge rejected'

set +e
"$REPO/trio" bridge not-a-verb >"$stdout" 2>"$stderr"
ec=$?
set -e
[ "$ec" = "2" ] || { printf 'FAIL unknown bridge verb exit=%s\n' "$ec" >&2; exit 1; }
assert_line "$stderr" '用法:' 'unknown bridge usage'

printf 'bridge-export tests: OK\n'
