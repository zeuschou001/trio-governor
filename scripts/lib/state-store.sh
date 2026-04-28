#!/usr/bin/env bash

trim_spaces() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

ts_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

archive_stamp() {
  date -u +%Y-%m-%dT%H-%M-%SZ
}

atomic_write() {
  local out="$1" tmp=''
  tmp="$out.tmp.$$"
  cat >"$tmp"
  python3 -c 'import os,sys; f=open(sys.argv[1], "rb"); os.fsync(f.fileno()); f.close()' "$tmp"
  mv "$tmp" "$out"
}

state_signature_valid() {
  python3 -c '
import re, sys
try:
    b = open(sys.argv[1], "rb").read()
except FileNotFoundError:
    sys.exit(1)
r = rb"^trio-dev v[0-9]+\.[0-9]+\.[0-9]+ initialized at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\n$"
sys.exit(0 if re.match(r, b) else 1)
' "$1"
}

state_validate_mode() {
  case "$1" in
    dev|quick) return 0 ;;
    *) return 1 ;;
  esac
}

state_validate_status() {
  case "$1" in
    running|awaiting-start-confirmation|awaiting-confirmation|completed|aborted) return 0 ;;
    *) return 1 ;;
  esac
}

state_default_adapter_mode_for_mode() {
  case "$1" in
    dev) printf 'full\n' ;;
    quick) printf 'minimal\n' ;;
    *) return 1 ;;
  esac
}

state_validate_adapter_mode() {
  case "$1" in
    full|minimal) return 0 ;;
    *) return 1 ;;
  esac
}

state_validate_ceo_review_forced() {
  case "$1" in
    0|1) return 0 ;;
    *) return 1 ;;
  esac
}

state_default_provider_snapshot() {
  local version="${1:-unknown}"
  printf 'superpowers=%s,gstack=unknown,gsd2=unknown,trellis=unknown\n' "$version"
}

state_default_provider_selection() {
  printf '%s\n' 'discovery=gstack,product-review=gstack,architecture-review=gstack,planning=superpowers,execution=superpowers,verification=superpowers,qa=gstack,finish=superpowers'
}

state_split_completed() {
  local raw="${1:-[]}" inner part
  raw="$(trim_spaces "$raw")"
  raw="${raw#\[}"
  raw="${raw%\]}"
  raw="$(trim_spaces "$raw")"
  [ -n "$raw" ] || return 0
  IFS=',' read -r -a parts <<<"$raw"
  for part in "${parts[@]}"; do
    part="$(trim_spaces "$part")"
    [ -n "$part" ] && printf '%s\n' "$part"
  done
}

state_serialize_completed() {
  if [ "$#" -eq 0 ]; then
    printf '[]\n'
    return 0
  fi
  local out='[' item
  for item in "$@"; do
    [ "$out" = '[' ] || out="$out, "
    out="$out$item"
  done
  printf '%s]\n' "$out"
}

state_completed_contains() {
  local raw="$1" needle="$2" item
  while IFS= read -r item; do
    [ "$item" = "$needle" ] && return 0
  done < <(state_split_completed "$raw")
  return 1
}

state_completed_append() {
  local raw="$1" phase="$2" item
  if state_completed_contains "$raw" "$phase"; then
    printf '%s\n' "$raw"
    return 0
  fi
  local items=()
  while IFS= read -r item; do
    items+=("$item")
  done < <(state_split_completed "$raw")
  items+=("$phase")
  state_serialize_completed "${items[@]}"
}

state_validate_quick_streak() {
  case "$1" in
    ''|*[!0-9]*)
      printf 'STATE.md 包含非法 quick_streak:%s\n' "$1" >&2
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

state_validate_path() {
  local mode="$1" status="$2" current="$3" completed="$4" quick_streak="$5"
  local initial terminal phase seen=' ' item
  local completed_items=()
  local path=()

  initial="$(phase_initial_for_mode "$mode")" || return 1
  terminal="$(phase_terminal_for_mode "$mode")" || return 1

  while IFS= read -r item; do
    completed_items+=("$item")
  done < <(state_split_completed "$completed")

  if [ "${#completed_items[@]}" -gt 0 ]; then
    for phase in "${completed_items[@]}"; do
      phase_is_valid "$phase" || { printf 'STATE.md 包含非法 completed_phase:%s\n' "$phase" >&2; return 1; }
      [ "$(phase_mode_for "$phase")" = "$mode" ] || { printf 'STATE.md 的 completed_phases 与 mode 命名空间不一致\n' >&2; return 1; }
      case "$seen" in
        *" $phase "*) printf 'STATE.md 的 completed_phases 含重复阶段:%s\n' "$phase" >&2; return 1 ;;
      esac
      seen="$seen$phase "
    done
  fi

  [ "$(phase_mode_for "$current")" = "$mode" ] || { printf 'STATE.md 的 current_phase 与 mode 命名空间不一致\n' >&2; return 1; }

  if [ "$status" = 'awaiting-start-confirmation' ]; then
    [ "$mode" = 'quick' ] || { printf 'STATE.md 的 awaiting-start-confirmation 仅允许用于 quick mode\n' >&2; return 1; }
    [ "$current" = "$initial" ] || { printf 'STATE.md 的 awaiting-start-confirmation 必须停在 quick 初始阶段\n' >&2; return 1; }
    [ "${#completed_items[@]}" -eq 0 ] || { printf 'STATE.md 的 awaiting-start-confirmation 不允许已有 completed_phases\n' >&2; return 1; }
    [ "$quick_streak" = '0' ] || { printf 'STATE.md 的 awaiting-start-confirmation 必须使用 quick_streak=0\n' >&2; return 1; }
  fi

  if [ "$status" = 'completed' ]; then
    state_completed_contains "$completed" "$current" || { printf 'STATE.md 的 completed 状态缺少终态阶段\n' >&2; return 1; }
    [ "$current" = "$terminal" ] || { printf 'STATE.md 的 completed 状态必须停在终态阶段\n' >&2; return 1; }
    if [ "${#completed_items[@]}" -gt 0 ]; then
      path=("${completed_items[@]}")
    fi
  else
    if state_completed_contains "$completed" "$current"; then
      printf 'STATE.md 的 current_phase 不得重复出现在 completed_phases 中\n' >&2
      return 1
    fi
    if [ "${#completed_items[@]}" -gt 0 ]; then
      path=("${completed_items[@]}" "$current")
    else
      path=("$current")
    fi
  fi

  [ "${#path[@]}" -gt 0 ] || { printf 'STATE.md 缺少可解析阶段路径\n' >&2; return 1; }
  [ "${path[0]}" = "$initial" ] || { printf 'STATE.md 的阶段路径必须从 %s 开始\n' "$initial" >&2; return 1; }

  local idx from to
  for ((idx=1; idx<${#path[@]}; idx++)); do
    from="${path[idx-1]}"
    to="${path[idx]}"
    phase_can_transition_to "$from" "$to" || { printf 'STATE.md 包含非法阶段跳转:%s -> %s\n' "$from" "$to" >&2; return 1; }
  done
}

state_parse_file() {
  local file="$1"
  STATE_MODE=$(sed -n 's/^mode: //p' "$file" | head -n 1)
  STATE_STATUS=$(sed -n 's/^status: //p' "$file" | head -n 1)
  STATE_CURRENT_PHASE=$(sed -n 's/^current_phase: //p' "$file" | head -n 1)
  STATE_COMPLETED_PHASES=$(sed -n 's/^completed_phases: //p' "$file" | head -n 1)
  STATE_LAST_UPDATED=$(sed -n 's/^last_updated: "\(.*\)"$/\1/p' "$file" | head -n 1)
  [ -n "$STATE_LAST_UPDATED" ] || STATE_LAST_UPDATED=$(sed -n 's/^last_updated: //p' "$file" | head -n 1)
  STATE_QUICK_STREAK=$(sed -n 's/^quick_streak: //p' "$file" | head -n 1)
  STATE_SUPERPOWERS_VERSION=$(sed -n 's/^superpowers_version: //p' "$file" | head -n 1)
  STATE_ADAPTER_MODE=$(sed -n 's/^adapter_mode: //p' "$file" | head -n 1)
  STATE_CEO_REVIEW_FORCED=$(sed -n 's/^ceo_review_forced: //p' "$file" | head -n 1)
  STATE_PROVIDER_SNAPSHOT=$(sed -n 's/^provider_snapshot: //p' "$file" | head -n 1)
  STATE_PROVIDER_SELECTION=$(sed -n 's/^provider_selection: //p' "$file" | head -n 1)
}

state_write_file() {
  local file="$1" mode="$2" status="$3" phase="$4" completed="$5" quick_streak="$6" version="$7" adapter_mode="$8" ceo_review_forced="$9"
  local provider_snapshot='' provider_selection='' ts=''
  if [ "$#" -ge 12 ]; then
    provider_snapshot="${10}"
    provider_selection="${11}"
    ts="${12:-}"
  else
    provider_snapshot="$(state_default_provider_snapshot "$version")"
    provider_selection="$(state_default_provider_selection)"
    ts="${10:-}"
  fi
  [ -n "$ts" ] || ts="$(ts_utc)"
  atomic_write "$file" <<EOF
---
mode: $mode
status: $status
current_phase: $phase
completed_phases: $completed
last_updated: "$ts"
quick_streak: $quick_streak
superpowers_version: $version
adapter_mode: $adapter_mode
ceo_review_forced: $ceo_review_forced
provider_snapshot: $provider_snapshot
provider_selection: $provider_selection
---

# State

由 \`/trio:dev\` 与 \`/trio:quick\` 编排器原地覆盖写入。
EOF
}

state_initial_status_for_mode() {
  local mode="$1" quick_streak="${2:-0}"
  case "$mode" in
    dev)
      printf 'running\n'
      ;;
    quick)
      if [ "$quick_streak" = '0' ]; then
        printf 'awaiting-start-confirmation\n'
      else
        printf 'running\n'
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

state_reset_file() {
  local file="$1" mode="$2" adapter_mode="${3:-}" ceo_review_forced="${4:-0}" quick_streak="${5:-0}" version="${6:-unknown}" provider_snapshot="${7:-}" provider_selection="${8:-}"
  [ -n "$adapter_mode" ] || adapter_mode="$(state_default_adapter_mode_for_mode "$mode")"
  [ -n "$provider_snapshot" ] || provider_snapshot="$(state_default_provider_snapshot "$version")"
  [ -n "$provider_selection" ] || provider_selection="$(state_default_provider_selection)"
  state_write_file "$file" "$mode" "$(state_initial_status_for_mode "$mode" "$quick_streak")" "$(phase_initial_for_mode "$mode")" '[]' "$quick_streak" "$version" "$adapter_mode" "$ceo_review_forced" "$provider_snapshot" "$provider_selection" "$(ts_utc)"
}

state_require_owned_dir() {
  local trio_dir="$1" sig_file=''
  sig_file="$trio_dir/.trio-signature"
  if [ -e "$trio_dir" ] && [ ! -d "$trio_dir" ]; then
    printf '检测到非本插件管理的 .trio/ 目录,请手动备份后移除\n' >&2
    return 1
  fi
  if [ ! -d "$trio_dir" ]; then
    printf '未检测到 trio 会话,请先执行 bootstrap\n' >&2
    return 1
  fi
  if ! state_signature_valid "$sig_file"; then
    printf '检测到非本插件管理的 .trio/ 目录,请手动备份后移除\n' >&2
    return 1
  fi
}

state_upgrade_if_needed() {
  local file="$1"
  state_parse_file "$file"

  [ -n "$STATE_CURRENT_PHASE" ] || { printf 'STATE.md 缺少 current_phase\n' >&2; return 1; }
  phase_is_valid "$STATE_CURRENT_PHASE" || { printf 'STATE.md 包含非法 current_phase:%s\n' "$STATE_CURRENT_PHASE" >&2; return 1; }

  local changed=0
  if [ -z "$STATE_MODE" ]; then
    STATE_MODE="$(phase_mode_for "$STATE_CURRENT_PHASE")"
    changed=1
  fi
  if [ -z "$STATE_STATUS" ]; then
    STATE_STATUS=running
    changed=1
  fi
  [ -n "$STATE_COMPLETED_PHASES" ] || { STATE_COMPLETED_PHASES='[]'; changed=1; }
  [ -n "$STATE_LAST_UPDATED" ] || { STATE_LAST_UPDATED='1970-01-01T00:00:00Z'; changed=1; }
  [ -n "$STATE_QUICK_STREAK" ] || { STATE_QUICK_STREAK=0; changed=1; }
  [ -n "$STATE_SUPERPOWERS_VERSION" ] || { STATE_SUPERPOWERS_VERSION=unknown; changed=1; }
  [ -n "$STATE_ADAPTER_MODE" ] || { STATE_ADAPTER_MODE="$(state_default_adapter_mode_for_mode "$STATE_MODE")"; changed=1; }
  [ -n "$STATE_CEO_REVIEW_FORCED" ] || { STATE_CEO_REVIEW_FORCED=0; changed=1; }
  [ -n "$STATE_PROVIDER_SNAPSHOT" ] || { STATE_PROVIDER_SNAPSHOT="$(state_default_provider_snapshot "$STATE_SUPERPOWERS_VERSION")"; changed=1; }
  [ -n "$STATE_PROVIDER_SELECTION" ] || { STATE_PROVIDER_SELECTION="$(state_default_provider_selection)"; changed=1; }

  state_validate_mode "$STATE_MODE" || { printf 'STATE.md 包含非法 mode:%s\n' "$STATE_MODE" >&2; return 1; }
  state_validate_status "$STATE_STATUS" || { printf 'STATE.md 包含非法 status:%s\n' "$STATE_STATUS" >&2; return 1; }
  state_validate_quick_streak "$STATE_QUICK_STREAK" || return 1
  state_validate_adapter_mode "$STATE_ADAPTER_MODE" || { printf 'STATE.md 包含非法 adapter_mode:%s\n' "$STATE_ADAPTER_MODE" >&2; return 1; }
  state_validate_ceo_review_forced "$STATE_CEO_REVIEW_FORCED" || { printf 'STATE.md 包含非法 ceo_review_forced:%s\n' "$STATE_CEO_REVIEW_FORCED" >&2; return 1; }
  state_validate_path "$STATE_MODE" "$STATE_STATUS" "$STATE_CURRENT_PHASE" "$STATE_COMPLETED_PHASES" "$STATE_QUICK_STREAK" || return 1
  if [ "$STATE_MODE" = 'quick' ] && [ "$STATE_ADAPTER_MODE" != 'minimal' ]; then
    printf 'STATE.md 的 quick mode 必须使用 minimal adapter_mode\n' >&2
    return 1
  fi
  if [ "$STATE_MODE" = 'quick' ] && [ "$STATE_CEO_REVIEW_FORCED" != '0' ]; then
    printf 'STATE.md 的 quick mode 不允许 ceo_review_forced=1\n' >&2
    return 1
  fi

  if [ "$changed" -eq 1 ]; then
    state_write_file "$file" "$STATE_MODE" "$STATE_STATUS" "$STATE_CURRENT_PHASE" "$STATE_COMPLETED_PHASES" "$STATE_QUICK_STREAK" "$STATE_SUPERPOWERS_VERSION" "$STATE_ADAPTER_MODE" "$STATE_CEO_REVIEW_FORCED" "$STATE_PROVIDER_SNAPSHOT" "$STATE_PROVIDER_SELECTION" "$STATE_LAST_UPDATED"
  fi
}

state_try_resume_available() {
  local lock_file="$1"
  exec 8>"$lock_file"
  if flock -xn 8; then
    exec 8>&-
    return 0
  fi
  exec 8>&-
  return 1
}
