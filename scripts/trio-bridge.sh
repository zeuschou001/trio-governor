#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ABS=$(cd "$SCRIPT_DIR/.." && pwd)
VERSION_VALUE=$(cat "$REPO_ABS/VERSION")

command -v flock >/dev/null 2>&1 || export PATH="$REPO_ABS/scripts/bin:$PATH"

# shellcheck source=scripts/lib/phase-graph.sh
. "$SCRIPT_DIR/lib/phase-graph.sh"
# shellcheck source=scripts/lib/state-store.sh
. "$SCRIPT_DIR/lib/state-store.sh"
# shellcheck source=scripts/lib/providers.sh
. "$SCRIPT_DIR/lib/providers.sh"

usage() {
  printf '用法: %s {status|export|handoff|review|draft|scaffold} [参数...]\n' "${0##*/}" >&2
  printf '  status <provider> <宿主项目目录>\n' >&2
  printf '  export <provider> <宿主项目目录>\n' >&2
  printf '  handoff <provider> <宿主项目目录>\n' >&2
  printf '  review <provider> <宿主项目目录>\n' >&2
  printf '  draft <provider> <宿主项目目录>\n' >&2
  printf '  scaffold <provider> <宿主项目目录>\n' >&2
  printf '定位: ./trio 的内部 bridge 调试接口,不构成主要用户表面\n' >&2
}

resolve_host_dir() {
  HOST_DIR=$(cd "$1" && pwd)
  TRIO_DIR="$HOST_DIR/.trio"
}

bridge_lock_or_fail() {
  mkdir -p "$TRIO_DIR"
  exec 9>"$TRIO_DIR/.lock"
  if ! flock -xn 9; then
    printf '检测到同项目已有活动 trio 会话,请等待其结束\n' >&2
    return 3
  fi
}

bridge_join_csv() {
  local out='' sep='' item=''
  for item in "$@"; do
    [ -n "$item" ] || continue
    out="${out}${sep}${item}"
    sep=','
  done
  printf '%s\n' "${out:--}"
}

bridge_array_csv() {
  [ "$#" -gt 0 ] || { printf '%s\n' '-'; return 0; }
  bridge_join_csv "$@"
}

bridge_provider_ids() {
  local id='' kind=''
  for id in $(providers_registry_ids); do
    providers_load_provider "$id" || continue
    kind="$(provider_kind)"
    case "$kind" in
      workflow-bridge|memory-bridge) printf '%s\n' "$id" ;;
    esac
  done
  providers_unload
}

bridge_known_ids_csv() {
  local ids=() id=''
  while IFS= read -r id; do
    [ -n "$id" ] && ids+=("$id")
  done < <(bridge_provider_ids)
  bridge_join_csv "${ids[@]}"
}

bridge_require_provider() {
  local id="$1" kind='' policy=''
  if ! providers_load_provider "$id"; then
    printf '未知 bridge provider:%s\n' "$id" >&2
    printf '可用 bridge provider:%s\n' "$(bridge_known_ids_csv)" >&2
    return 1
  fi
  kind="$(provider_kind)"
  policy="$(provider_state_policy)"
  case "$kind" in
    workflow-bridge|memory-bridge) ;;
    *)
      printf 'provider %s 不是 bridge,不能通过 trio bridge 调用\n' "$id" >&2
      return 1
      ;;
  esac
  if [ "$policy" != 'export-only' ]; then
    printf 'provider %s 不符合 export-only bridge 边界\n' "$id" >&2
    return 1
  fi
}

bridge_capabilities_csv() {
  local raw='' item='' caps=()
  raw="$(provider_capabilities | tr '\n' ' ')"
  for item in $raw; do
    caps+=("$item")
  done
  bridge_join_csv "${caps[@]}"
}

bridge_detect_out() {
  provider_detect 0
}

bridge_provider_install_hint() {
  provider_install_hint
}

bridge_provider_command_hint() {
  if declare -F provider_bridge_command_hint >/dev/null 2>&1; then
    provider_bridge_command_hint
    return 0
  fi
  printf '%s\n' '-'
}

bridge_provider_review_catalog() {
  if declare -F provider_bridge_review_catalog >/dev/null 2>&1; then
    provider_bridge_review_catalog
    return 0
  fi
  return 1
}

bridge_export_root() {
  printf '%s/bridges/%s\n' "$TRIO_DIR" "$1"
}

bridge_next_export_dir() {
  local provider="$1" root='' stamp='' candidate='' i=1
  root="$(bridge_export_root "$provider")"
  mkdir -p "$root"
  stamp="$(archive_stamp)"
  candidate="$root/$stamp"
  while [ -e "$candidate" ]; do
    candidate="$root/$stamp-$i"
    i=$((i + 1))
  done
  printf '%s\n' "$candidate"
}

bridge_export_count() {
  local provider="$1" root='' path='' count=0
  root="$(bridge_export_root "$provider")"
  [ -d "$root" ] || { printf '0\n'; return 0; }
  for path in "$root"/*; do
    [ -d "$path" ] || continue
    count=$((count + 1))
  done
  printf '%s\n' "$count"
}

bridge_latest_export_dir() {
  local provider="$1" root='' path='' latest=''
  root="$(bridge_export_root "$provider")"
  [ -d "$root" ] || return 1
  for path in "$root"/*; do
    [ -d "$path" ] || continue
    if [ -z "$latest" ] || [ "${path##*/}" \> "${latest##*/}" ]; then
      latest="$path"
    fi
  done
  [ -n "$latest" ] || return 1
  printf '%s\n' "$latest"
}

bridge_collect_files() {
  local file=''
  for file in PROJECT.md DECISIONS.md KNOWLEDGE.md ROADMAP.md STATE.md; do
    [ -f "$TRIO_DIR/$file" ] && printf '%s\n' "$file"
  done
}

bridge_manifest_write() {
  local manifest="$1" export_dir="$2" provider="$3" exported_csv="$4"
  local detect_out='' capabilities='' provider_status='' provider_version=''
  detect_out="$(bridge_detect_out)"
  capabilities="$(bridge_capabilities_csv)"
  provider_status="$(providers_kv_get "$detect_out" PROVIDER_STATUS)"
  provider_version="$(providers_kv_get "$detect_out" PROVIDER_VERSION)"
  atomic_write "$manifest" <<EOF
TRIO_BRIDGE_VERSION=$(printf '%q' "$VERSION_VALUE")
EXPORT_TIMESTAMP=$(printf '%q' "$(ts_utc)")
PROVIDER_ID=$(printf '%q' "$provider")
PROVIDER_KIND=$(printf '%q' "$(provider_kind)")
PROVIDER_AVAILABILITY=$(printf '%q' "$(provider_availability)")
PROVIDER_INVOKE_MODE=$(printf '%q' "$(provider_invoke_mode)")
PROVIDER_CAPABILITIES=$(printf '%q' "$capabilities")
PROVIDER_STATE_POLICY=$(printf '%q' "$(provider_state_policy)")
PROVIDER_SELECTABLE=$(printf '%q' "$(provider_selectable)")
PROVIDER_STATUS=$(printf '%q' "$provider_status")
PROVIDER_VERSION=$(printf '%q' "$provider_version")
PROVIDER_INSTALL_HINT=$(printf '%q' "$(bridge_provider_install_hint)")
BRIDGE_COMMAND_HINT=$(printf '%q' "$(bridge_provider_command_hint)")
HOST_DIR=$(printf '%q' "$HOST_DIR")
TRIO_DIR=$(printf '%q' "$TRIO_DIR")
EXPORT_DIR=$(printf '%q' "$export_dir")
MODE=$(printf '%q' "$STATE_MODE")
STATUS=$(printf '%q' "$STATE_STATUS")
CURRENT_PHASE=$(printf '%q' "$STATE_CURRENT_PHASE")
STATE_LAST_UPDATED=$(printf '%q' "$STATE_LAST_UPDATED")
PROVIDER_SNAPSHOT=$(printf '%q' "$STATE_PROVIDER_SNAPSHOT")
PROVIDER_SELECTION=$(printf '%q' "$STATE_PROVIDER_SELECTION")
EXPORTED_FILES=$(printf '%q' "$exported_csv")
STATE_OWNER=trio-runtime
STATE_MUTATION=forbidden
EOF
}

bridge_create_export_artifacts() {
  local provider="$1" export_dir='' manifest='' exported_csv='' file=''
  local exported_files=()
  export_dir="$(bridge_next_export_dir "$provider")"
  mkdir -p "$export_dir"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    cp "$TRIO_DIR/$file" "$export_dir/$file"
    exported_files+=("$file")
  done < <(bridge_collect_files)
  exported_csv="$(bridge_join_csv "${exported_files[@]}")"
  manifest="$export_dir/manifest.env"
  bridge_manifest_write "$manifest" "$export_dir" "$provider" "$exported_csv"
  BRIDGE_EXPORT_DIR="$export_dir"
  BRIDGE_MANIFEST_PATH="$manifest"
  BRIDGE_EXPORTED_FILES="$exported_csv"
}

bridge_latest_handoff_path() {
  local provider="$1" latest_export=''
  latest_export="$(bridge_latest_export_dir "$provider" 2>/dev/null)" || return 1
  [ -f "$latest_export/HANDOFF.md" ] || return 1
  printf '%s/HANDOFF.md\n' "$latest_export"
}

bridge_latest_outputs_dir() {
  local provider="$1" latest_export=''
  latest_export="$(bridge_latest_export_dir "$provider" 2>/dev/null)" || return 1
  [ -d "$latest_export/outputs" ] || return 1
  printf '%s/outputs\n' "$latest_export"
}

bridge_latest_manifest_path() {
  local provider="$1" latest_export=''
  latest_export="$(bridge_latest_export_dir "$provider" 2>/dev/null)" || return 1
  [ -f "$latest_export/manifest.env" ] || return 1
  printf '%s/manifest.env\n' "$latest_export"
}

bridge_latest_draft_shell_path() {
  local provider="$1" latest_export=''
  latest_export="$(bridge_latest_export_dir "$provider" 2>/dev/null)" || return 1
  [ -f "$latest_export/IMPORT-DRAFT.sh" ] || return 1
  printf '%s/IMPORT-DRAFT.sh\n' "$latest_export"
}

bridge_latest_draft_markdown_path() {
  local provider="$1" latest_export=''
  latest_export="$(bridge_latest_export_dir "$provider" 2>/dev/null)" || return 1
  [ -f "$latest_export/IMPORT-DRAFT.md" ] || return 1
  printf '%s/IMPORT-DRAFT.md\n' "$latest_export"
}

bridge_latest_scaffold_dir() {
  local provider="$1" latest_export=''
  latest_export="$(bridge_latest_export_dir "$provider" 2>/dev/null)" || return 1
  [ -d "$latest_export/import-scaffold" ] || return 1
  printf '%s/import-scaffold\n' "$latest_export"
}

bridge_latest_scaffold_summary_path() {
  local provider="$1" latest_export=''
  latest_export="$(bridge_latest_export_dir "$provider" 2>/dev/null)" || return 1
  [ -f "$latest_export/import-scaffold/IMPORT-SCAFFOLD.md" ] || return 1
  printf '%s/import-scaffold/IMPORT-SCAFFOLD.md\n' "$latest_export"
}

bridge_file_title_hint() {
  local file="$1" title='' base=''
  title="$(sed -n 's/^#\{1,6\}[[:space:]]*//p' "$file" | head -n 1)"
  if [ -n "$title" ]; then
    printf '%s\n' "$title"
    return 0
  fi
  base="$(basename "$file")"
  base="${base%.*}"
  printf '%s\n' "$base"
}

bridge_apply_hint_for_verb() {
  local runtime_verb="$1" source="$2" title_hint="$3"
  case "$runtime_verb" in
    roadmap-rewrite)
      printf './trio runtime roadmap-rewrite %s %s\n' "$HOST_DIR" "$source"
      ;;
    knowledge-append)
      printf './trio runtime knowledge-append %s <%s-title> <%s-context> <%s-takeaway>\n' "$HOST_DIR" "$title_hint" "$title_hint" "$title_hint"
      ;;
    decision-append)
      printf './trio runtime decision-append %s <eng-review|ceo-review> <%s-title> <%s-what> <%s-why> <%s-impact>\n' "$HOST_DIR" "$title_hint" "$title_hint" "$title_hint" "$title_hint"
      ;;
    *)
      printf '%s\n' '-'
      ;;
  esac
}

bridge_write_handoff_file() {
  local handoff="$1" provider="$2" export_dir="$3" outputs_dir="$4" exported_csv="$5"
  local install_hint='' command_hint=''
  install_hint="$(bridge_provider_install_hint)"
  command_hint="$(bridge_provider_command_hint)"
  {
    cat <<EOF
# trio Bridge Handoff: $provider

这个目录由 ./trio bridge handoff 生成,用于把当前 .trio 会话上下文交给外部 bridge 工具消费。

## 边界

- STATE.md 归 trio-runtime 独占,禁止外部工具改写
- trio 保留 phase 推进权,外部工具不得自行推进会话
- 如需回流结果,应回到 trio runtime writer,而不是覆盖当前 export

## 当前上下文

- Host: $HOST_DIR
- Export: $export_dir
- Outputs: $outputs_dir
- Mode: $STATE_MODE
- Status: $STATE_STATUS
- Current phase: $STATE_CURRENT_PHASE
- Exported files: $exported_csv
- Provider status: $(providers_kv_get "$(bridge_detect_out)" PROVIDER_STATUS)
- Install hint: $install_hint
- Command hint: $command_hint

## 通用操作

1. 只读取当前 export 目录中的快照文件。
2. 把外部整理结果写到 outputs/ 目录。
3. 需要回流 trio 时,优先回写结构化摘要,不要直接复制外部状态机。

EOF
    if declare -F provider_bridge_handoff_markdown >/dev/null 2>&1; then
      provider_bridge_handoff_markdown "$export_dir" "$outputs_dir"
    else
      cat <<EOF
## Provider Guidance

- 当前 provider 未声明额外 handoff 模板。
- 请把外部结果写入 $(basename "$outputs_dir")/result.md,再由开发者决定是否回流 trio。
EOF
    fi
  } | atomic_write "$handoff"
}

bridge_review_emit_suggestion() {
  local index="$1" kind="$2" runtime_verb="$3" source="$4" title_hint="$5" reason="$6"
  printf 'SUGGESTION_%s_KIND=%s\n' "$index" "$kind"
  printf 'SUGGESTION_%s_RUNTIME_VERB=%s\n' "$index" "$runtime_verb"
  printf 'SUGGESTION_%s_SOURCE=%s\n' "$index" "$source"
  printf 'SUGGESTION_%s_TITLE_HINT=%s\n' "$index" "$title_hint"
  printf 'SUGGESTION_%s_REASON=%s\n' "$index" "$reason"
  printf 'SUGGESTION_%s_MANUAL_REVIEW=1\n' "$index"
  printf 'SUGGESTION_%s_APPLY_HINT=%s\n' "$index" "$(bridge_apply_hint_for_verb "$runtime_verb" "$source" "$title_hint")"
}

bridge_write_import_draft_markdown() {
  local file="$1" provider="$2" review_output="$3"
  local export_dir='' outputs_dir='' suggestion_count=0 index=1 kind='' runtime_verb='' source='' title_hint='' reason='' apply_hint=''
  export_dir="$(providers_kv_get "$review_output" EXPORT_DIR)"
  outputs_dir="$(providers_kv_get "$review_output" OUTPUTS_DIR)"
  suggestion_count="$(providers_kv_get "$review_output" SUGGESTION_COUNT)"
  {
    cat <<EOF
# trio Bridge Import Draft: $provider

这个草稿由 ./trio bridge draft 生成,仅用于人工确认后执行。

## 边界

- STATE.md 仍由 trio-runtime 独占
- 本文件不代表 trio 已接受这些回流建议
- 只有开发者显式挑选并执行 runtime writer 命令,结果才会进入 .trio

## 上下文

- Host: $HOST_DIR
- Export: $export_dir
- Outputs: $outputs_dir
- Suggestion count: $suggestion_count

## 建议草稿

EOF
    while [ "$index" -le "$suggestion_count" ]; do
      kind="$(providers_kv_get "$review_output" "SUGGESTION_${index}_KIND")"
      runtime_verb="$(providers_kv_get "$review_output" "SUGGESTION_${index}_RUNTIME_VERB")"
      source="$(providers_kv_get "$review_output" "SUGGESTION_${index}_SOURCE")"
      title_hint="$(providers_kv_get "$review_output" "SUGGESTION_${index}_TITLE_HINT")"
      reason="$(providers_kv_get "$review_output" "SUGGESTION_${index}_REASON")"
      apply_hint="$(providers_kv_get "$review_output" "SUGGESTION_${index}_APPLY_HINT")"
      cat <<EOF
### Suggestion $index

- Kind: $kind
- Runtime verb: $runtime_verb
- Source: $source
- Title hint: $title_hint
- Reason: $reason
- Manual review: 1
- Draft command: $apply_hint

EOF
      index=$((index + 1))
    done
  } | atomic_write "$file"
}

bridge_write_import_draft_shell() {
  local file="$1" provider="$2" review_output="$3"
  local suggestion_count=0 index=1 kind='' runtime_verb='' source='' title_hint='' reason='' apply_hint=''
  suggestion_count="$(providers_kv_get "$review_output" SUGGESTION_COUNT)"
  {
    cat <<EOF
#!/usr/bin/env bash
# Manual draft generated by ./trio bridge draft for provider: $provider
# Review placeholders and uncomment selected commands before applying.
# This file intentionally contains only commented commands.

# Host: $HOST_DIR
# Suggestion count: $suggestion_count

EOF
    while [ "$index" -le "$suggestion_count" ]; do
      kind="$(providers_kv_get "$review_output" "SUGGESTION_${index}_KIND")"
      runtime_verb="$(providers_kv_get "$review_output" "SUGGESTION_${index}_RUNTIME_VERB")"
      source="$(providers_kv_get "$review_output" "SUGGESTION_${index}_SOURCE")"
      title_hint="$(providers_kv_get "$review_output" "SUGGESTION_${index}_TITLE_HINT")"
      reason="$(providers_kv_get "$review_output" "SUGGESTION_${index}_REASON")"
      apply_hint="$(providers_kv_get "$review_output" "SUGGESTION_${index}_APPLY_HINT")"
      cat <<EOF
# Suggestion $index
# kind: $kind
# runtime_verb: $runtime_verb
# source: $source
# title_hint: $title_hint
# reason: $reason
EOF
      if [ "$apply_hint" = '-' ] || [ -z "$apply_hint" ]; then
        printf '# no direct runtime command draft; manual triage required\n\n'
      else
        printf '# %s\n\n' "$apply_hint"
      fi
      index=$((index + 1))
    done
  } | atomic_write "$file"
}

bridge_scaffold_slug_for_suggestion() {
  local runtime_verb="$1" kind="$2"
  case "$runtime_verb" in
    decision-append) printf 'decision\n' ;;
    knowledge-append) printf 'knowledge\n' ;;
    roadmap-rewrite) printf 'roadmap\n' ;;
    *) case "$kind" in
         manual-review) printf 'manual\n' ;;
         *) printf 'generic\n' ;;
       esac ;;
  esac
}

bridge_scaffold_env_write() {
  local file="$1" review_output="$2" index="$3" kind="$4" runtime_verb="$5" source="$6" title_hint="$7" reason="$8"
  local apply_hint='' slug=''
  apply_hint="$(providers_kv_get "$review_output" "SUGGESTION_${index}_APPLY_HINT")"
  slug="$(bridge_scaffold_slug_for_suggestion "$runtime_verb" "$kind")"
  case "$runtime_verb" in
    decision-append)
      atomic_write "$file" <<EOF
SUGGESTION_INDEX=$index
SUGGESTION_KIND=$(printf '%q' "$kind")
RUNTIME_VERB=$(printf '%q' "$runtime_verb")
SOURCE_FILE=$(printf '%q' "$source")
TITLE=$(printf '%q' "$title_hint")
TYPE=eng-review
WHAT=TODO_FILL_WHAT
WHY=TODO_FILL_WHY
IMPACT=TODO_FILL_IMPACT
REASON=$(printf '%q' "$reason")
APPLY_HINT=$(printf '%q' "$apply_hint")
EOF
      ;;
    knowledge-append)
      atomic_write "$file" <<EOF
SUGGESTION_INDEX=$index
SUGGESTION_KIND=$(printf '%q' "$kind")
RUNTIME_VERB=$(printf '%q' "$runtime_verb")
SOURCE_FILE=$(printf '%q' "$source")
TITLE=$(printf '%q' "$title_hint")
CONTEXT=TODO_FILL_CONTEXT
TAKEAWAY=TODO_FILL_TAKEAWAY
REASON=$(printf '%q' "$reason")
APPLY_HINT=$(printf '%q' "$apply_hint")
EOF
      ;;
    roadmap-rewrite)
      atomic_write "$file" <<EOF
SUGGESTION_INDEX=$index
SUGGESTION_KIND=$(printf '%q' "$kind")
RUNTIME_VERB=$(printf '%q' "$runtime_verb")
SOURCE_FILE=$(printf '%q' "$source")
TITLE=$(printf '%q' "$title_hint")
ROADMAP_INPUT_FILE=$(printf '%q' "$source")
REASON=$(printf '%q' "$reason")
APPLY_HINT=$(printf '%q' "$apply_hint")
EOF
      ;;
    *)
      atomic_write "$file" <<EOF
SUGGESTION_INDEX=$index
SUGGESTION_KIND=$(printf '%q' "$kind")
RUNTIME_VERB=-
SOURCE_FILE=$(printf '%q' "$source")
TITLE=$(printf '%q' "$title_hint")
NEXT_STEP=TODO_DECIDE_TARGET_WRITER
REASON=$(printf '%q' "$reason")
APPLY_HINT=-
EOF
      ;;
  esac
}

bridge_scaffold_manual_note_write() {
  local file="$1" index="$2" kind="$3" source="$4" title_hint="$5" reason="$6"
  atomic_write "$file" <<EOF
# Manual Scaffold: Suggestion $index

- Kind: $kind
- Source: $source
- Title hint: $title_hint
- Reason: $reason

## Next Step

- 选择它应回流到 DECISIONS / KNOWLEDGE / ROADMAP 中的哪一种 writer。
- 确认后再手动执行对应的 ./trio runtime 命令。
EOF
}

bridge_write_import_scaffold_markdown() {
  local file="$1" provider="$2" review_output="$3" scaffold_dir="$4"
  local suggestion_count=0 index=1 kind='' runtime_verb='' source='' title_hint='' reason='' target=''
  suggestion_count="$(providers_kv_get "$review_output" SUGGESTION_COUNT)"
  {
    cat <<EOF
# trio Bridge Import Scaffold: $provider

这个目录由 ./trio bridge scaffold 生成,用于把 review suggestion 收敛成可填写模板。

## 边界

- 所有模板都需要人工填写或确认
- 这些模板不会自动导入 trio
- STATE.md 仍由 trio-runtime 独占

## 目录

- Scaffold root: $scaffold_dir
- Suggestion count: $suggestion_count

## 模板索引

EOF
    while [ "$index" -le "$suggestion_count" ]; do
      kind="$(providers_kv_get "$review_output" "SUGGESTION_${index}_KIND")"
      runtime_verb="$(providers_kv_get "$review_output" "SUGGESTION_${index}_RUNTIME_VERB")"
      source="$(providers_kv_get "$review_output" "SUGGESTION_${index}_SOURCE")"
      title_hint="$(providers_kv_get "$review_output" "SUGGESTION_${index}_TITLE_HINT")"
      reason="$(providers_kv_get "$review_output" "SUGGESTION_${index}_REASON")"
      target="$(basename "$(providers_kv_get "$review_output" "SCAFFOLD_${index}_PATH")")"
      cat <<EOF
### Suggestion $index

- Runtime verb: $runtime_verb
- Kind: $kind
- Source: $source
- Title hint: $title_hint
- Reason: $reason
- Template: $target

EOF
      index=$((index + 1))
    done
  } | atomic_write "$file"
}

bridge_status() {
  [ "$#" -eq 2 ] || { printf '用法: %s status <provider> <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  local provider="$1" detect_out='' capabilities='' export_root='' export_count='' latest_export='-' latest_manifest='-' latest_handoff='-' latest_outputs='-' latest_draft_shell='-' latest_draft_markdown='-' latest_scaffold_dir='-' latest_scaffold_summary='-' provider_status='' provider_version=''
  bridge_require_provider "$provider" || return 1
  resolve_host_dir "$2"
  state_require_owned_dir "$TRIO_DIR" || return 1
  [ -f "$TRIO_DIR/STATE.md" ] || { printf 'STATE.md 缺失\n' >&2; return 1; }
  state_upgrade_if_needed "$TRIO_DIR/STATE.md"
  state_parse_file "$TRIO_DIR/STATE.md"

  detect_out="$(bridge_detect_out)"
  capabilities="$(bridge_capabilities_csv)"
  provider_status="$(providers_kv_get "$detect_out" PROVIDER_STATUS)"
  provider_version="$(providers_kv_get "$detect_out" PROVIDER_VERSION)"
  export_root="$(bridge_export_root "$provider")"
  export_count="$(bridge_export_count "$provider")"
  if latest_export="$(bridge_latest_export_dir "$provider" 2>/dev/null)"; then
    [ -f "$latest_export/manifest.env" ] && latest_manifest="$latest_export/manifest.env"
  else
    latest_export='-'
  fi
  latest_handoff="$(bridge_latest_handoff_path "$provider" 2>/dev/null || printf '%s' '-')"
  latest_outputs="$(bridge_latest_outputs_dir "$provider" 2>/dev/null || printf '%s' '-')"
  latest_draft_shell="$(bridge_latest_draft_shell_path "$provider" 2>/dev/null || printf '%s' '-')"
  latest_draft_markdown="$(bridge_latest_draft_markdown_path "$provider" 2>/dev/null || printf '%s' '-')"
  latest_scaffold_dir="$(bridge_latest_scaffold_dir "$provider" 2>/dev/null || printf '%s' '-')"
  latest_scaffold_summary="$(bridge_latest_scaffold_summary_path "$provider" 2>/dev/null || printf '%s' '-')"

  printf 'PROVIDER_ID=%s\n' "$provider"
  printf 'PROVIDER_KIND=%s\n' "$(provider_kind)"
  printf 'PROVIDER_AVAILABILITY=%s\n' "$(provider_availability)"
  printf 'PROVIDER_INVOKE_MODE=%s\n' "$(provider_invoke_mode)"
  printf 'PROVIDER_CAPABILITIES=%s\n' "$capabilities"
  printf 'PROVIDER_STATE_POLICY=%s\n' "$(provider_state_policy)"
  printf 'PROVIDER_SELECTABLE=%s\n' "$(provider_selectable)"
  printf 'PROVIDER_STATUS=%s\n' "$provider_status"
  printf 'PROVIDER_VERSION=%s\n' "$provider_version"
  printf 'PROVIDER_INSTALL_HINT=%s\n' "$(bridge_provider_install_hint)"
  printf 'BRIDGE_COMMAND_HINT=%s\n' "$(bridge_provider_command_hint)"
  printf 'HOST_DIR=%s\n' "$HOST_DIR"
  printf 'TRIO_DIR=%s\n' "$TRIO_DIR"
  printf 'MODE=%s\n' "$STATE_MODE"
  printf 'STATUS=%s\n' "$STATE_STATUS"
  printf 'CURRENT_PHASE=%s\n' "$STATE_CURRENT_PHASE"
  printf 'STATE_LAST_UPDATED=%s\n' "$STATE_LAST_UPDATED"
  printf 'EXPORT_ROOT=%s\n' "$export_root"
  printf 'EXPORT_COUNT=%s\n' "$export_count"
  printf 'LATEST_EXPORT=%s\n' "$latest_export"
  printf 'LATEST_MANIFEST=%s\n' "$latest_manifest"
  printf 'LATEST_HANDOFF=%s\n' "$latest_handoff"
  printf 'LATEST_OUTPUTS_DIR=%s\n' "$latest_outputs"
  printf 'LATEST_DRAFT_SHELL=%s\n' "$latest_draft_shell"
  printf 'LATEST_DRAFT_MARKDOWN=%s\n' "$latest_draft_markdown"
  printf 'LATEST_SCAFFOLD_DIR=%s\n' "$latest_scaffold_dir"
  printf 'LATEST_SCAFFOLD_SUMMARY=%s\n' "$latest_scaffold_summary"
  printf 'STATE_OWNER=trio-runtime\n'
  printf 'STATE_MUTATION=forbidden\n'
}

bridge_export() {
  [ "$#" -eq 2 ] || { printf '用法: %s export <provider> <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  local provider="$1"
  bridge_require_provider "$provider" || return 1
  resolve_host_dir "$2"
  state_require_owned_dir "$TRIO_DIR" || return 1
  [ -f "$TRIO_DIR/STATE.md" ] || { printf 'STATE.md 缺失\n' >&2; return 1; }
  bridge_lock_or_fail || return $?
  state_upgrade_if_needed "$TRIO_DIR/STATE.md"
  state_parse_file "$TRIO_DIR/STATE.md"

  bridge_create_export_artifacts "$provider"

  printf 'PROVIDER_ID=%s\n' "$provider"
  printf 'PROVIDER_KIND=%s\n' "$(provider_kind)"
  printf 'PROVIDER_INVOKE_MODE=%s\n' "$(provider_invoke_mode)"
  printf 'PROVIDER_CAPABILITIES=%s\n' "$(bridge_capabilities_csv)"
  printf 'PROVIDER_STATE_POLICY=%s\n' "$(provider_state_policy)"
  printf 'PROVIDER_INSTALL_HINT=%s\n' "$(bridge_provider_install_hint)"
  printf 'BRIDGE_COMMAND_HINT=%s\n' "$(bridge_provider_command_hint)"
  printf 'HOST_DIR=%s\n' "$HOST_DIR"
  printf 'TRIO_DIR=%s\n' "$TRIO_DIR"
  printf 'MODE=%s\n' "$STATE_MODE"
  printf 'STATUS=%s\n' "$STATE_STATUS"
  printf 'CURRENT_PHASE=%s\n' "$STATE_CURRENT_PHASE"
  printf 'EXPORT_DIR=%s\n' "$BRIDGE_EXPORT_DIR"
  printf 'MANIFEST_PATH=%s\n' "$BRIDGE_MANIFEST_PATH"
  printf 'EXPORTED_FILES=%s\n' "$BRIDGE_EXPORTED_FILES"
  printf 'HANDOFF_PATH=-\n'
  printf 'STATE_OWNER=trio-runtime\n'
  printf 'STATE_MUTATION=forbidden\n'
}

bridge_handoff() {
  [ "$#" -eq 2 ] || { printf '用法: %s handoff <provider> <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  local provider="$1" handoff='' outputs_dir=''
  bridge_require_provider "$provider" || return 1
  resolve_host_dir "$2"
  state_require_owned_dir "$TRIO_DIR" || return 1
  [ -f "$TRIO_DIR/STATE.md" ] || { printf 'STATE.md 缺失\n' >&2; return 1; }
  bridge_lock_or_fail || return $?
  state_upgrade_if_needed "$TRIO_DIR/STATE.md"
  state_parse_file "$TRIO_DIR/STATE.md"

  bridge_create_export_artifacts "$provider"
  outputs_dir="$BRIDGE_EXPORT_DIR/outputs"
  mkdir -p "$outputs_dir"
  handoff="$BRIDGE_EXPORT_DIR/HANDOFF.md"
  bridge_write_handoff_file "$handoff" "$provider" "$BRIDGE_EXPORT_DIR" "$outputs_dir" "$BRIDGE_EXPORTED_FILES"

  printf 'PROVIDER_ID=%s\n' "$provider"
  printf 'PROVIDER_KIND=%s\n' "$(provider_kind)"
  printf 'PROVIDER_INVOKE_MODE=%s\n' "$(provider_invoke_mode)"
  printf 'PROVIDER_CAPABILITIES=%s\n' "$(bridge_capabilities_csv)"
  printf 'PROVIDER_STATE_POLICY=%s\n' "$(provider_state_policy)"
  printf 'PROVIDER_INSTALL_HINT=%s\n' "$(bridge_provider_install_hint)"
  printf 'BRIDGE_COMMAND_HINT=%s\n' "$(bridge_provider_command_hint)"
  printf 'HOST_DIR=%s\n' "$HOST_DIR"
  printf 'TRIO_DIR=%s\n' "$TRIO_DIR"
  printf 'MODE=%s\n' "$STATE_MODE"
  printf 'STATUS=%s\n' "$STATE_STATUS"
  printf 'CURRENT_PHASE=%s\n' "$STATE_CURRENT_PHASE"
  printf 'EXPORT_DIR=%s\n' "$BRIDGE_EXPORT_DIR"
  printf 'MANIFEST_PATH=%s\n' "$BRIDGE_MANIFEST_PATH"
  printf 'HANDOFF_PATH=%s\n' "$handoff"
  printf 'OUTPUTS_DIR=%s\n' "$outputs_dir"
  printf 'EXPORTED_FILES=%s\n' "$BRIDGE_EXPORTED_FILES"
  printf 'STATE_OWNER=trio-runtime\n'
  printf 'STATE_MUTATION=forbidden\n'
}

bridge_review() {
  [ "$#" -eq 2 ] || { printf '用法: %s review <provider> <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  local provider="$1" latest_export='' manifest='' handoff='' outputs_dir='' output_files_csv='-' filename='' path='' title_hint='' index=0
  local known_files=() output_files=() extra_files=()
  bridge_require_provider "$provider" || return 1
  resolve_host_dir "$2"
  state_require_owned_dir "$TRIO_DIR" || return 1

  latest_export="$(bridge_latest_export_dir "$provider" 2>/dev/null)" || {
    printf '未检测到 bridge export,请先执行 trio bridge export 或 trio bridge handoff\n' >&2
    return 1
  }
  manifest="$(bridge_latest_manifest_path "$provider" 2>/dev/null)" || {
    printf 'bridge manifest 缺失,请重新执行 trio bridge export 或 trio bridge handoff\n' >&2
    return 1
  }
  outputs_dir="$(bridge_latest_outputs_dir "$provider" 2>/dev/null)" || {
    printf '未检测到 bridge handoff outputs,请先执行 trio bridge handoff\n' >&2
    return 1
  }
  handoff="$latest_export/HANDOFF.md"
  [ -f "$handoff" ] || {
    printf 'HANDOFF.md 缺失,请重新执行 trio bridge handoff\n' >&2
    return 1
  }

  # shellcheck source=/dev/null
  . "$manifest"

  for path in "$outputs_dir"/*; do
    [ -f "$path" ] || continue
    [ -s "$path" ] || continue
    output_files+=("$(basename "$path")")
  done
  output_files_csv="$(bridge_array_csv "${output_files[@]:-}")"

  printf 'PROVIDER_ID=%s\n' "$provider"
  printf 'PROVIDER_KIND=%s\n' "$(provider_kind)"
  printf 'PROVIDER_INVOKE_MODE=%s\n' "$(provider_invoke_mode)"
  printf 'PROVIDER_CAPABILITIES=%s\n' "$(bridge_capabilities_csv)"
  printf 'PROVIDER_STATE_POLICY=%s\n' "$(provider_state_policy)"
  printf 'PROVIDER_INSTALL_HINT=%s\n' "$(bridge_provider_install_hint)"
  printf 'BRIDGE_COMMAND_HINT=%s\n' "$(bridge_provider_command_hint)"
  printf 'HOST_DIR=%s\n' "$HOST_DIR"
  printf 'TRIO_DIR=%s\n' "$TRIO_DIR"
  printf 'MODE=%s\n' "${MODE:-unknown}"
  printf 'STATUS=%s\n' "${STATUS:-unknown}"
  printf 'CURRENT_PHASE=%s\n' "${CURRENT_PHASE:-unknown}"
  printf 'EXPORT_DIR=%s\n' "$latest_export"
  printf 'MANIFEST_PATH=%s\n' "$manifest"
  printf 'HANDOFF_PATH=%s\n' "$handoff"
  printf 'OUTPUTS_DIR=%s\n' "$outputs_dir"
  printf 'OUTPUT_FILES=%s\n' "$output_files_csv"

  if bridge_provider_review_catalog >/dev/null 2>&1; then
    while IFS='|' read -r filename _ _ _; do
      [ -n "$filename" ] && known_files+=("$filename")
    done < <(bridge_provider_review_catalog)

    while IFS='|' read -r filename kind runtime_verb reason; do
      [ -n "$filename" ] || continue
      path="$outputs_dir/$filename"
      [ -f "$path" ] || continue
      [ -s "$path" ] || continue
      title_hint="$(bridge_file_title_hint "$path")"
      index=$((index + 1))
      bridge_review_emit_suggestion "$index" "$kind" "$runtime_verb" "$path" "$title_hint" "$reason"
    done < <(bridge_provider_review_catalog)
  fi

  for path in "$outputs_dir"/*; do
    [ -f "$path" ] || continue
    [ -s "$path" ] || continue
    filename="$(basename "$path")"
    case " ${known_files[*]} " in
      *" $filename "*) continue ;;
    esac
    extra_files+=("$filename")
    title_hint="$(bridge_file_title_hint "$path")"
    index=$((index + 1))
    bridge_review_emit_suggestion "$index" 'manual-review' '-' "$path" "$title_hint" '未声明的 provider 输出,需要人工判断回流目标'
  done

  printf 'UNMAPPED_OUTPUT_FILES=%s\n' "$(bridge_array_csv "${extra_files[@]:-}")"
  printf 'SUGGESTION_COUNT=%s\n' "$index"
  if [ "$index" -gt 0 ]; then
    printf 'MANUAL_REVIEW_REQUIRED=1\n'
  else
    printf 'MANUAL_REVIEW_REQUIRED=0\n'
  fi
  printf 'STATE_OWNER=trio-runtime\n'
  printf 'STATE_MUTATION=forbidden\n'
}

bridge_draft() {
  [ "$#" -eq 2 ] || { printf '用法: %s draft <provider> <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  local provider="$1" review_output='' export_dir='' suggestion_count=0 draft_shell='' draft_markdown='' index=1 runtime_verb='' actionable_count=0 manual_only_count=0
  bridge_require_provider "$provider" || return 1
  resolve_host_dir "$2"
  state_require_owned_dir "$TRIO_DIR" || return 1

  review_output="$(bridge_review "$provider" "$HOST_DIR")"
  export_dir="$(providers_kv_get "$review_output" EXPORT_DIR)"
  suggestion_count="$(providers_kv_get "$review_output" SUGGESTION_COUNT)"
  draft_shell="$export_dir/IMPORT-DRAFT.sh"
  draft_markdown="$export_dir/IMPORT-DRAFT.md"

  while [ "$index" -le "$suggestion_count" ]; do
    runtime_verb="$(providers_kv_get "$review_output" "SUGGESTION_${index}_RUNTIME_VERB")"
    if [ "$runtime_verb" = '-' ] || [ -z "$runtime_verb" ]; then
      manual_only_count=$((manual_only_count + 1))
    else
      actionable_count=$((actionable_count + 1))
    fi
    index=$((index + 1))
  done

  bridge_write_import_draft_markdown "$draft_markdown" "$provider" "$review_output"
  bridge_write_import_draft_shell "$draft_shell" "$provider" "$review_output"

  printf '%s\n' "$review_output"
  printf 'DRAFT_SHELL_PATH=%s\n' "$draft_shell"
  printf 'DRAFT_MARKDOWN_PATH=%s\n' "$draft_markdown"
  printf 'DRAFT_ACTIONABLE_COUNT=%s\n' "$actionable_count"
  printf 'DRAFT_MANUAL_ONLY_COUNT=%s\n' "$manual_only_count"
  printf 'DRAFT_READY_TO_RUN=0\n'
}

bridge_scaffold() {
  [ "$#" -eq 2 ] || { printf '用法: %s scaffold <provider> <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  local provider="$1" review_output='' export_dir='' scaffold_dir='' scaffold_summary='' suggestion_count=0 index=1
  local kind='' runtime_verb='' source='' title_hint='' reason='' ext='' target='' actionable_count=0 manual_only_count=0
  bridge_require_provider "$provider" || return 1
  resolve_host_dir "$2"
  state_require_owned_dir "$TRIO_DIR" || return 1

  review_output="$(bridge_review "$provider" "$HOST_DIR")"
  export_dir="$(providers_kv_get "$review_output" EXPORT_DIR)"
  suggestion_count="$(providers_kv_get "$review_output" SUGGESTION_COUNT)"
  scaffold_dir="$export_dir/import-scaffold"
  mkdir -p "$scaffold_dir"

  while [ "$index" -le "$suggestion_count" ]; do
    kind="$(providers_kv_get "$review_output" "SUGGESTION_${index}_KIND")"
    runtime_verb="$(providers_kv_get "$review_output" "SUGGESTION_${index}_RUNTIME_VERB")"
    source="$(providers_kv_get "$review_output" "SUGGESTION_${index}_SOURCE")"
    title_hint="$(providers_kv_get "$review_output" "SUGGESTION_${index}_TITLE_HINT")"
    reason="$(providers_kv_get "$review_output" "SUGGESTION_${index}_REASON")"
    case "$runtime_verb" in
      decision-append|knowledge-append|roadmap-rewrite) ext='env'; actionable_count=$((actionable_count + 1)) ;;
      *) ext='md'; manual_only_count=$((manual_only_count + 1)) ;;
    esac
    target="$scaffold_dir/suggestion-$index-$(bridge_scaffold_slug_for_suggestion "$runtime_verb" "$kind").$ext"
    if [ "$ext" = 'env' ]; then
      bridge_scaffold_env_write "$target" "$review_output" "$index" "$kind" "$runtime_verb" "$source" "$title_hint" "$reason"
    else
      bridge_scaffold_manual_note_write "$target" "$index" "$kind" "$source" "$title_hint" "$reason"
    fi
    review_output="$review_output"$'\n'"SCAFFOLD_${index}_PATH=$target"
    index=$((index + 1))
  done

  scaffold_summary="$scaffold_dir/IMPORT-SCAFFOLD.md"
  bridge_write_import_scaffold_markdown "$scaffold_summary" "$provider" "$review_output" "$scaffold_dir"

  printf '%s\n' "$review_output"
  printf 'SCAFFOLD_DIR=%s\n' "$scaffold_dir"
  printf 'SCAFFOLD_SUMMARY_PATH=%s\n' "$scaffold_summary"
  printf 'SCAFFOLD_ACTIONABLE_COUNT=%s\n' "$actionable_count"
  printf 'SCAFFOLD_MANUAL_ONLY_COUNT=%s\n' "$manual_only_count"
  printf 'SCAFFOLD_READY_TO_RUN=0\n'
}

[ "$#" -gt 0 ] || { usage; exit 2; }
verb="$1"
shift
case "$verb" in
  status) bridge_status "$@" ;;
  export) bridge_export "$@" ;;
  handoff) bridge_handoff "$@" ;;
  review) bridge_review "$@" ;;
  draft) bridge_draft "$@" ;;
  scaffold) bridge_scaffold "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
