#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ABS=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE_DIR="$REPO_ABS/templates/trio-state"
VERSION_VALUE=$(cat "$REPO_ABS/VERSION")

command -v flock >/dev/null 2>&1 || export PATH="$REPO_ABS/scripts/bin:$PATH"

# shellcheck source=scripts/lib/phase-graph.sh
. "$SCRIPT_DIR/lib/phase-graph.sh"
# shellcheck source=scripts/lib/state-store.sh
. "$SCRIPT_DIR/lib/state-store.sh"
# shellcheck source=scripts/lib/doc-store.sh
. "$SCRIPT_DIR/lib/doc-store.sh"

usage() {
  printf '用法: %s {bootstrap|status|restart|abort|transition|gate-check|record-deps|project-write|decision-append|knowledge-append|roadmap-rewrite} [参数...]\n' "${0##*/}" >&2
}

resolve_host_dir() {
  HOST_DIR=$(cd "$1" && pwd)
  TRIO_DIR="$HOST_DIR/.trio"
}

require_git_host() {
  [ -d "$HOST_DIR/.git" ] && return 0
  printf 'trio-dev 需要 git 仓库作为宿主,请先执行 git init\n' >&2
  return 4
}

session_lock_or_fail() {
  mkdir -p "$TRIO_DIR"
  exec 9>"$TRIO_DIR/.lock"
  if ! flock -xn 9; then
    printf '检测到同项目已有活动 trio 会话,请等待其结束\n' >&2
    return 3
  fi
}

print_status_summary() {
  printf 'MODE=%s\n' "$STATE_MODE"
  printf 'STATUS=%s\n' "$STATE_STATUS"
  printf 'CURRENT_PHASE=%s\n' "$STATE_CURRENT_PHASE"
  printf 'COMPLETED_PHASES=%s\n' "$STATE_COMPLETED_PHASES"
  printf 'ADAPTER_MODE=%s\n' "$STATE_ADAPTER_MODE"
  printf 'CEO_REVIEW_FORCED=%s\n' "$STATE_CEO_REVIEW_FORCED"
  printf 'PROVIDER_SNAPSHOT=%s\n' "$STATE_PROVIDER_SNAPSHOT"
  printf 'PROVIDER_SELECTION=%s\n' "$STATE_PROVIDER_SELECTION"
}

ensure_layout_for_mode() {
  local mode="$1" file
  if [ "$mode" = 'quick' ]; then
    for file in KNOWLEDGE.md; do
      [ -f "$TRIO_DIR/$file" ] || { doc_write_skeleton "$TRIO_DIR" "$file"; printf '%s\n' "$file"; }
    done
  else
    for file in PROJECT.md DECISIONS.md KNOWLEDGE.md ROADMAP.md; do
      [ -f "$TRIO_DIR/$file" ] || { doc_write_skeleton "$TRIO_DIR" "$file"; printf '%s\n' "$file"; }
    done
  fi
}

archive_state_file() {
  local archive
  archive="$(doc_archive_path "$TRIO_DIR" STATE)"
  cp "$TRIO_DIR/STATE.md" "$archive"
  printf '%s\n' "$archive"
}

reset_quick_streak_for_mode() {
  local target_mode="$1" current_mode="${2:-}" current_quick_streak="${3:-0}"
  if [ "$target_mode" = 'dev' ]; then
    printf '0\n'
    return 0
  fi
  if [ "$current_mode" = 'quick' ]; then
    printf '%s\n' "$current_quick_streak"
  else
    printf '0\n'
  fi
}

bootstrap_usage() {
  printf '用法: %s bootstrap --mode <dev|quick> [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2
}

runtime_bootstrap() {
  local mode='' adapter_mode='' ceo_review_forced='' host='' filled=() new_dir=0 file archive existing_mode existing_status reset_quick_streak=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode)
        [ "$#" -ge 2 ] || { bootstrap_usage; return 2; }
        mode="$2"
        shift 2
        ;;
      --adapter-mode)
        [ "$#" -ge 2 ] || { bootstrap_usage; return 2; }
        adapter_mode="$2"
        shift 2
        ;;
      --ceo-review-forced)
        [ "$#" -ge 2 ] || { bootstrap_usage; return 2; }
        ceo_review_forced="$2"
        shift 2
        ;;
      -*)
        bootstrap_usage
        return 2
        ;;
      *)
        [ -z "$host" ] || { bootstrap_usage; return 2; }
        host="$1"
        shift
        ;;
    esac
  done
  [ -n "$host" ] || { bootstrap_usage; return 2; }
  state_validate_mode "$mode" || { bootstrap_usage; return 2; }
  [ -n "$adapter_mode" ] || adapter_mode="$(state_default_adapter_mode_for_mode "$mode")"
  [ -n "$ceo_review_forced" ] || ceo_review_forced=0
  state_validate_adapter_mode "$adapter_mode" || { bootstrap_usage; return 2; }
  state_validate_ceo_review_forced "$ceo_review_forced" || { bootstrap_usage; return 2; }
  if [ "$mode" = 'quick' ] && [ "$adapter_mode" != 'minimal' ]; then
    printf '%s\n' 'quick 模式只允许 adapter_mode=minimal' >&2
    return 2
  fi
  if [ "$mode" = 'quick' ] && [ "$ceo_review_forced" != '0' ]; then
    printf '%s\n' 'quick 模式不允许 ceo_review_forced=1' >&2
    return 2
  fi
  resolve_host_dir "$host"
  require_git_host || return $?

  if [ -e "$TRIO_DIR" ] && [ ! -d "$TRIO_DIR" ]; then
    printf '检测到非本插件管理的 .trio/ 目录,请手动备份后移除\n' >&2
    return 1
  fi
  if [ -d "$TRIO_DIR" ]; then
    state_signature_valid "$TRIO_DIR/.trio-signature" || {
      printf '检测到非本插件管理的 .trio/ 目录,请手动备份后移除\n' >&2
      return 1
    }
  else
    mkdir -p "$TRIO_DIR"
    new_dir=1
  fi

  session_lock_or_fail || return $?

  if [ "$new_dir" -eq 1 ]; then
    doc_write_signature "$TRIO_DIR"
  fi

  if [ -f "$TRIO_DIR/STATE.md" ]; then
    state_upgrade_if_needed "$TRIO_DIR/STATE.md"
    state_parse_file "$TRIO_DIR/STATE.md"
    existing_mode="$STATE_MODE"
    existing_status="$STATE_STATUS"

    if [ "$existing_status" = 'completed' ] || [ "$existing_status" = 'aborted' ]; then
      while IFS= read -r file; do
        [ -n "$file" ] && filled+=("$file")
      done < <(ensure_layout_for_mode "$mode")
      archive="$(archive_state_file)"
      reset_quick_streak="$(reset_quick_streak_for_mode "$mode" "$STATE_MODE" "$STATE_QUICK_STREAK")"
      state_reset_file "$TRIO_DIR/STATE.md" "$mode" "$adapter_mode" "$ceo_review_forced" "$reset_quick_streak"
      printf '检测到已结束会话,已归档并重置为 %s 模式:%s\n' "$mode" "$archive" >&2
    else
      while IFS= read -r file; do
        [ -n "$file" ] && filled+=("$file")
      done < <(ensure_layout_for_mode "$existing_mode")
      if [ "$existing_mode" != "$mode" ]; then
        printf '检测到可恢复的 %s 会话,请先 continue 或执行 trio runtime restart --mode %s %s\n' "$existing_mode" "$mode" "$HOST_DIR" >&2
      fi
    fi
  else
    while IFS= read -r file; do
      [ -n "$file" ] && filled+=("$file")
    done < <(ensure_layout_for_mode "$mode")
    state_reset_file "$TRIO_DIR/STATE.md" "$mode" "$adapter_mode" "$ceo_review_forced"
    filled+=("STATE.md")
  fi

  state_parse_file "$TRIO_DIR/STATE.md"
  if [ "$mode" = 'dev' ] && [ "$STATE_QUICK_STREAK" != '0' ]; then
    state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" "$STATE_STATUS" "$STATE_CURRENT_PHASE" "$STATE_COMPLETED_PHASES" 0 "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
    state_parse_file "$TRIO_DIR/STATE.md"
  fi
  if [ "$new_dir" -eq 0 ] && [ "${#filled[@]}" -gt 0 ]; then
    local list=''
    printf -v list '%s, ' "${filled[@]}"
    printf '检测到上次初始化未完成,已自动补齐 %s\n' "${list%, }" >&2
  fi

  print_status_summary
}

runtime_status() {
  [ "$#" -eq 1 ] || { printf '用法: %s status <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$1"
  state_require_owned_dir "$TRIO_DIR" || return 1
  [ -f "$TRIO_DIR/STATE.md" ] || { printf 'STATE.md 缺失\n' >&2; return 1; }
  state_upgrade_if_needed "$TRIO_DIR/STATE.md"
  state_parse_file "$TRIO_DIR/STATE.md"

  printf 'MODE=%s\n' "$STATE_MODE"
  printf 'STATUS=%s\n' "$STATE_STATUS"
  printf 'CURRENT_PHASE=%s\n' "$STATE_CURRENT_PHASE"
  printf 'COMPLETED_PHASES=%s\n' "$STATE_COMPLETED_PHASES"
  printf 'LAST_UPDATED=%s\n' "$STATE_LAST_UPDATED"
  printf 'QUICK_STREAK=%s\n' "$STATE_QUICK_STREAK"
  printf 'SUPERPOWERS_VERSION=%s\n' "$STATE_SUPERPOWERS_VERSION"
  printf 'ADAPTER_MODE=%s\n' "$STATE_ADAPTER_MODE"
  printf 'CEO_REVIEW_FORCED=%s\n' "$STATE_CEO_REVIEW_FORCED"
  printf 'PROVIDER_SNAPSHOT=%s\n' "$STATE_PROVIDER_SNAPSHOT"
  printf 'PROVIDER_SELECTION=%s\n' "$STATE_PROVIDER_SELECTION"
  if [ "$STATE_STATUS" = 'running' ] || [ "$STATE_STATUS" = 'awaiting-start-confirmation' ] || [ "$STATE_STATUS" = 'awaiting-confirmation' ]; then
    if state_try_resume_available "$TRIO_DIR/.lock"; then
      printf 'RESUME_AVAILABLE=1\n'
    fi
  fi
}

runtime_restart() {
  local target_mode='' target_adapter_mode='' target_ceo_review_forced='' host='' reset_quick_streak=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode)
        [ "$#" -ge 2 ] || { printf '用法: %s restart [--mode <dev|quick>] [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
        target_mode="$2"
        shift 2
        ;;
      --adapter-mode)
        [ "$#" -ge 2 ] || { printf '用法: %s restart [--mode <dev|quick>] [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
        target_adapter_mode="$2"
        shift 2
        ;;
      --ceo-review-forced)
        [ "$#" -ge 2 ] || { printf '用法: %s restart [--mode <dev|quick>] [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
        target_ceo_review_forced="$2"
        shift 2
        ;;
      -*)
        printf '用法: %s restart [--mode <dev|quick>] [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2
        return 2
        ;;
      *)
        [ -z "$host" ] || { printf '用法: %s restart [--mode <dev|quick>] [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
        host="$1"
        shift
        ;;
    esac
  done
  [ -n "$host" ] || { printf '用法: %s restart [--mode <dev|quick>] [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  [ -z "$target_mode" ] || state_validate_mode "$target_mode" || { printf '用法: %s restart [--mode <dev|quick>] [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  [ -z "$target_adapter_mode" ] || state_validate_adapter_mode "$target_adapter_mode" || { printf '用法: %s restart [--mode <dev|quick>] [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  [ -z "$target_ceo_review_forced" ] || state_validate_ceo_review_forced "$target_ceo_review_forced" || { printf '用法: %s restart [--mode <dev|quick>] [--adapter-mode <full|minimal>] [--ceo-review-forced <0|1>] <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$host"
  state_require_owned_dir "$TRIO_DIR" || return 1
  [ -f "$TRIO_DIR/STATE.md" ] || { printf 'STATE.md 缺失\n' >&2; return 1; }
  session_lock_or_fail || return $?
  state_upgrade_if_needed "$TRIO_DIR/STATE.md"
  state_parse_file "$TRIO_DIR/STATE.md"
  [ -n "$target_mode" ] || target_mode="$STATE_MODE"
  if [ -z "$target_adapter_mode" ]; then
    if [ "$target_mode" = "$STATE_MODE" ]; then
      target_adapter_mode="$STATE_ADAPTER_MODE"
    else
      target_adapter_mode="$(state_default_adapter_mode_for_mode "$target_mode")"
    fi
  fi
  if [ -z "$target_ceo_review_forced" ]; then
    if [ "$target_mode" = "$STATE_MODE" ]; then
      target_ceo_review_forced="$STATE_CEO_REVIEW_FORCED"
    else
      target_ceo_review_forced=0
    fi
  fi
  if [ "$target_mode" = 'quick' ] && [ "$target_adapter_mode" != 'minimal' ]; then
    printf '%s\n' 'quick 模式只允许 adapter_mode=minimal' >&2
    return 2
  fi
  if [ "$target_mode" = 'quick' ] && [ "$target_ceo_review_forced" != '0' ]; then
    printf '%s\n' 'quick 模式不允许 ceo_review_forced=1' >&2
    return 2
  fi
  while IFS= read -r file; do
    :
  done < <(ensure_layout_for_mode "$target_mode")
  local archive
  archive="$(archive_state_file)"
  reset_quick_streak="$(reset_quick_streak_for_mode "$target_mode" "$STATE_MODE" "$STATE_QUICK_STREAK")"
  state_reset_file "$TRIO_DIR/STATE.md" "$target_mode" "$target_adapter_mode" "$target_ceo_review_forced" "$reset_quick_streak"
  state_parse_file "$TRIO_DIR/STATE.md"
  printf 'MODE=%s\n' "$STATE_MODE"
  printf 'STATUS=%s\n' "$STATE_STATUS"
  printf 'CURRENT_PHASE=%s\n' "$STATE_CURRENT_PHASE"
  printf 'ADAPTER_MODE=%s\n' "$STATE_ADAPTER_MODE"
  printf 'CEO_REVIEW_FORCED=%s\n' "$STATE_CEO_REVIEW_FORCED"
  printf 'PROVIDER_SNAPSHOT=%s\n' "$STATE_PROVIDER_SNAPSHOT"
  printf 'PROVIDER_SELECTION=%s\n' "$STATE_PROVIDER_SELECTION"
  printf 'ARCHIVED_STATE=%s\n' "$archive"
}

runtime_abort() {
  [ "$#" -eq 1 ] || { printf '用法: %s abort <宿主项目目录>\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$1"
  state_require_owned_dir "$TRIO_DIR" || return 1
  [ -f "$TRIO_DIR/STATE.md" ] || { printf 'STATE.md 缺失\n' >&2; return 1; }
  session_lock_or_fail || return $?
  state_upgrade_if_needed "$TRIO_DIR/STATE.md"
  state_parse_file "$TRIO_DIR/STATE.md"
  state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" aborted "$STATE_CURRENT_PHASE" "$STATE_COMPLETED_PHASES" "$STATE_QUICK_STREAK" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
  state_parse_file "$TRIO_DIR/STATE.md"
  print_status_summary
}

runtime_record_deps() {
  local provider_snapshot='' provider_selection=''
  [ "$#" -ge 2 ] && [ "$#" -le 4 ] || { printf '用法: %s record-deps <宿主项目目录> <version> [provider_snapshot] [provider_selection]\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$1"
  state_require_owned_dir "$TRIO_DIR" || return 1
  [ -f "$TRIO_DIR/STATE.md" ] || { printf 'STATE.md 缺失\n' >&2; return 1; }
  session_lock_or_fail || return $?
  state_upgrade_if_needed "$TRIO_DIR/STATE.md"
  state_parse_file "$TRIO_DIR/STATE.md"
  provider_snapshot="${3:-$STATE_PROVIDER_SNAPSHOT}"
  provider_selection="${4:-$STATE_PROVIDER_SELECTION}"
  state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" "$STATE_STATUS" "$STATE_CURRENT_PHASE" "$STATE_COMPLETED_PHASES" "$STATE_QUICK_STREAK" "$2" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$provider_snapshot" "$provider_selection" "$(ts_utc)"
  state_parse_file "$TRIO_DIR/STATE.md"
  print_status_summary
  printf 'SUPERPOWERS_VERSION=%s\n' "$STATE_SUPERPOWERS_VERSION"
}

runtime_transition() {
  [ "$#" -eq 3 ] || { printf '用法: %s transition <宿主项目目录> <action> <phase>\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$1"
  state_require_owned_dir "$TRIO_DIR" || return 1
  [ -f "$TRIO_DIR/STATE.md" ] || { printf 'STATE.md 缺失\n' >&2; return 1; }
  local action="$2" phase="$3" next_phase new_completed next_quick_streak
  phase_is_valid "$phase" || { printf '非法 phase:%s\n' "$phase" >&2; return 1; }
  session_lock_or_fail || return $?
  state_upgrade_if_needed "$TRIO_DIR/STATE.md"
  state_parse_file "$TRIO_DIR/STATE.md"

  [ "$STATE_CURRENT_PHASE" = "$phase" ] || { printf '非法迁移:当前 phase=%s,请求 phase=%s\n' "$STATE_CURRENT_PHASE" "$phase" >&2; return 1; }
  [ "$STATE_MODE" = "$(phase_mode_for "$phase")" ] || { printf '非法迁移:mode 与 phase 命名空间不一致\n' >&2; return 1; }

  case "$action" in
    start-guard-yes)
      [ "$STATE_STATUS" = 'awaiting-start-confirmation' ] || { printf '非法迁移:start-guard-yes 仅允许在 awaiting-start-confirmation\n' >&2; return 1; }
      [ "$STATE_MODE" = 'quick' ] || { printf '非法迁移:start-guard-yes 仅允许在 quick mode\n' >&2; return 1; }
      [ "$STATE_CURRENT_PHASE" = "$(phase_initial_for_mode quick)" ] || { printf '非法迁移:start-guard-yes 必须停在 quick 初始阶段\n' >&2; return 1; }
      state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" running "$STATE_CURRENT_PHASE" "$STATE_COMPLETED_PHASES" "$STATE_QUICK_STREAK" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
      ;;
    stage-finished)
      [ "$STATE_STATUS" = 'running' ] || { printf '非法迁移:只有 running 可进入 awaiting-confirmation\n' >&2; return 1; }
      state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" awaiting-confirmation "$STATE_CURRENT_PHASE" "$STATE_COMPLETED_PHASES" "$STATE_QUICK_STREAK" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
      ;;
    confirm-yes)
      [ "$STATE_STATUS" = 'awaiting-confirmation' ] || { printf '非法迁移:confirm-yes 仅允许在 awaiting-confirmation\n' >&2; return 1; }
      new_completed="$(state_completed_append "$STATE_COMPLETED_PHASES" "$STATE_CURRENT_PHASE")"
      next_quick_streak="$STATE_QUICK_STREAK"
      if [ "$STATE_CURRENT_PHASE" = 'quick-writing-plans' ]; then
        next_quick_streak=$((STATE_QUICK_STREAK + 1))
      fi
      if next_phase="$(phase_next_after "$STATE_CURRENT_PHASE" 2>/dev/null)"; then
        state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" running "$next_phase" "$new_completed" "$next_quick_streak" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
      else
        state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" completed "$STATE_CURRENT_PHASE" "$new_completed" "$next_quick_streak" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
      fi
      ;;
    confirm-yes-skip-optional-next)
      [ "$STATE_STATUS" = 'awaiting-confirmation' ] || { printf '非法迁移:confirm-yes-skip-optional-next 仅允许在 awaiting-confirmation\n' >&2; return 1; }
      new_completed="$(state_completed_append "$STATE_COMPLETED_PHASES" "$STATE_CURRENT_PHASE")"
      next_phase="$(phase_next_after "$STATE_CURRENT_PHASE")"
      phase_is_optional "$next_phase" || { printf '非法迁移:下一个阶段不可作为 optional 跳过\n' >&2; return 1; }
      next_phase="$(phase_next_after "$next_phase")"
      state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" running "$next_phase" "$new_completed" "$STATE_QUICK_STREAK" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
      ;;
    confirm-no)
      [ "$STATE_STATUS" = 'awaiting-confirmation' ] || { printf '非法迁移:confirm-no 仅允许在 awaiting-confirmation\n' >&2; return 1; }
      state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" running "$STATE_CURRENT_PHASE" "$STATE_COMPLETED_PHASES" "$STATE_QUICK_STREAK" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
      ;;
    confirm-skip)
      [ "$STATE_STATUS" = 'awaiting-confirmation' ] || { printf '非法迁移:confirm-skip 仅允许在 awaiting-confirmation\n' >&2; return 1; }
      phase_is_optional "$STATE_CURRENT_PHASE" || { printf '非法迁移:当前阶段不可 skip\n' >&2; return 1; }
      next_phase="$(phase_next_after "$STATE_CURRENT_PHASE")"
      state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" running "$next_phase" "$STATE_COMPLETED_PHASES" "$STATE_QUICK_STREAK" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
      ;;
    abort)
      [ "$STATE_STATUS" != 'completed' ] && [ "$STATE_STATUS" != 'aborted' ] || { printf '非法迁移:abort 不允许作用于终态会话\n' >&2; return 1; }
      state_write_file "$TRIO_DIR/STATE.md" "$STATE_MODE" aborted "$STATE_CURRENT_PHASE" "$STATE_COMPLETED_PHASES" "$STATE_QUICK_STREAK" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$(ts_utc)"
      ;;
    *)
      printf '未知 transition action:%s\n' "$action" >&2
      return 2
      ;;
  esac

  state_parse_file "$TRIO_DIR/STATE.md"
  print_status_summary
}

runtime_gate_check() {
  [ "$#" -eq 2 ] || { printf '用法: %s gate-check <宿主项目目录> <gate>\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$1"
  state_require_owned_dir "$TRIO_DIR" || return 1
  local gate="$2"
  case "$gate" in
    eng-review)
      if doc_decision_has_complete_type "$TRIO_DIR/DECISIONS.md" eng-review; then
        printf 'GATE=eng-review\nPASSED=1\n'
        return 0
      fi
      printf '架构评审未通过:DECISIONS.md 缺少 eng-review 条目\n' >&2
      return 1
      ;;
    state-sync)
      [ -f "$TRIO_DIR/STATE.md" ] || { printf 'STATE.md 缺失\n' >&2; return 1; }
      state_upgrade_if_needed "$TRIO_DIR/STATE.md"
      if doc_decision_has_complete_type "$TRIO_DIR/DECISIONS.md" eng-review; then
        state_parse_file "$TRIO_DIR/STATE.md"
        printf 'GATE=state-sync\nPASSED=1\nCURRENT_PHASE=%s\nSUPERPOWERS_VERSION=%s\n' "$STATE_CURRENT_PHASE" "$STATE_SUPERPOWERS_VERSION"
        return 0
      fi
      printf '状态同步未通过:DECISIONS.md 缺少 eng-review 条目\n' >&2
      return 1
      ;;
    *)
      printf '未知 gate:%s\n' "$gate" >&2
      return 2
      ;;
  esac
}

runtime_project_write() {
  [ "$#" -eq 4 ] || { printf '用法: %s project-write <宿主项目目录> <name> <type> <description>\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$1"
  state_require_owned_dir "$TRIO_DIR" || return 1
  session_lock_or_fail || return $?
  doc_project_write "$TRIO_DIR" "$2" "$3" "$4"
}

runtime_decision_append() {
  [ "$#" -eq 6 ] || { printf '用法: %s decision-append <宿主项目目录> <type> <title> <what> <why> <impact>\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$1"
  state_require_owned_dir "$TRIO_DIR" || return 1
  session_lock_or_fail || return $?
  doc_decision_append "$TRIO_DIR" "$2" "$3" "$4" "$5" "$6"
}

runtime_knowledge_append() {
  [ "$#" -eq 4 ] || { printf '用法: %s knowledge-append <宿主项目目录> <title> <context> <takeaway>\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$1"
  state_require_owned_dir "$TRIO_DIR" || return 1
  session_lock_or_fail || return $?
  doc_knowledge_append "$TRIO_DIR" "$2" "$3" "$4"
}

runtime_roadmap_rewrite() {
  [ "$#" -eq 2 ] || { printf '用法: %s roadmap-rewrite <宿主项目目录> <input-file|-->\n' "${0##*/}" >&2; return 2; }
  resolve_host_dir "$1"
  state_require_owned_dir "$TRIO_DIR" || return 1
  session_lock_or_fail || return $?
  doc_roadmap_rewrite "$TRIO_DIR" "$2"
}

[ "$#" -gt 0 ] || { usage; exit 2; }
verb="$1"
shift
case "$verb" in
  bootstrap) runtime_bootstrap "$@" ;;
  status) runtime_status "$@" ;;
  restart) runtime_restart "$@" ;;
  abort) runtime_abort "$@" ;;
  transition) runtime_transition "$@" ;;
  gate-check) runtime_gate_check "$@" ;;
  record-deps) runtime_record_deps "$@" ;;
  project-write) runtime_project_write "$@" ;;
  decision-append) runtime_decision_append "$@" ;;
  knowledge-append) runtime_knowledge_append "$@" ;;
  roadmap-rewrite) runtime_roadmap_rewrite "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
