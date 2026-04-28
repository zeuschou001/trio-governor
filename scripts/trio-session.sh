#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ABS=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=scripts/lib/phase-graph.sh
. "$SCRIPT_DIR/lib/phase-graph.sh"
# shellcheck source=scripts/lib/capabilities.sh
. "$SCRIPT_DIR/lib/capabilities.sh"
# shellcheck source=scripts/lib/providers.sh
. "$SCRIPT_DIR/lib/providers.sh"
# shellcheck source=scripts/lib/state-store.sh
. "$SCRIPT_DIR/lib/state-store.sh"
# shellcheck source=scripts/lib/doc-store.sh
. "$SCRIPT_DIR/lib/doc-store.sh"

usage() {
  printf '用法:\n' >&2
  printf '  %s start --mode <dev|quick> [--with-ceo] [--minimal] <宿主项目目录>\n' "${0##*/}" >&2
  printf '  %s phase <宿主项目目录>\n' "${0##*/}" >&2
  printf '  %s confirm <宿主项目目录> <用户输入>\n' "${0##*/}" >&2
  printf '  %s resume --mode <dev|quick> [--with-ceo] [--minimal] <宿主项目目录> <用户输入>\n' "${0##*/}" >&2
}

kv_get() {
  local blob="$1" key="$2"
  printf '%s\n' "$blob" | sed -n "s/^$key=//p" | head -n 1
}

project_type_for_host() {
  local host="$1" file="$host/.trio/PROJECT.md"
  [ -f "$file" ] || return 0
  doc_project_frontmatter_value "$file" type
}

probe_existing_status() {
  local host="$1" status_out=''
  if [ ! -f "$host/.trio/STATE.md" ] || [ ! -f "$host/.trio/.trio-signature" ]; then
    return 1
  fi
  status_out="$("$REPO_ABS/scripts/trio-runtime.sh" status "$host" 2>/dev/null)" || return 1
  printf '%s\n' "$status_out"
}

actual_ceo_review_required() {
  local mode="$1" ceo_review_forced="$2" project_type="$3"
  if [ "$mode" = 'dev' ] && { [ "$ceo_review_forced" = '1' ] || [ "$project_type" = 'user-facing-feature' ]; }; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

phase_yes_action() {
  local phase="$1" ceo_review_forced="$2" project_type="$3" required
  case "$phase" in
    office-hours)
      required="$(actual_ceo_review_required dev "$ceo_review_forced" "$project_type")"
      if [ "$required" = '1' ]; then
        printf 'confirm-yes\n'
      else
        printf 'confirm-yes-skip-optional-next\n'
      fi
      ;;
    *)
      printf 'confirm-yes\n'
      ;;
  esac
}

phase_next_on_yes() {
  local phase="$1" yes_action="$2" next_phase=''
  if [ "$yes_action" = 'confirm-yes-skip-optional-next' ]; then
    next_phase="$(phase_next_after "$phase")"
    phase_is_optional "$next_phase" || return 1
    phase_next_after "$next_phase"
    return 0
  fi
  if next_phase="$(phase_next_after "$phase" 2>/dev/null)"; then
    printf '%s\n' "$next_phase"
  else
    printf 'completed\n'
  fi
}

phase_skip_action() {
  if phase_is_optional "$1"; then
    printf 'confirm-skip\n'
  else
    printf '%s\n' '-'
  fi
}

phase_next_on_skip() {
  if phase_is_optional "$1"; then
    phase_next_after "$1"
  else
    printf '%s\n' '-'
  fi
}

phase_executor() {
  capability_executor_for_phase "$1" "$2"
}

phase_writers() {
  case "$1" in
    office-hours)
      printf 'project-write\n'
      ;;
    plan-ceo-review|plan-eng-review)
      printf 'decision-append\n'
      ;;
    state-sync)
      printf 'record-deps\n'
      ;;
    writing-plans)
      printf 'roadmap-rewrite\n'
      ;;
    executing-plans|qa)
      printf 'knowledge-append\n'
      ;;
    *)
      printf '%s\n' '-'
      ;;
  esac
}

phase_gate() {
  case "$1" in
    state-sync) printf 'state-sync\n' ;;
    *) printf '%s\n' '-' ;;
  esac
}

phase_input_files() {
  case "$1" in
    office-hours)
      printf 'STATE.md\n'
      ;;
    plan-ceo-review)
      printf 'PROJECT.md,STATE.md\n'
      ;;
    plan-eng-review)
      printf 'PROJECT.md,DECISIONS.md,STATE.md\n'
      ;;
    state-sync)
      printf 'DECISIONS.md,STATE.md\n'
      ;;
    writing-plans)
      printf 'PROJECT.md,DECISIONS.md,KNOWLEDGE.md,STATE.md\n'
      ;;
    executing-plans)
      printf 'ROADMAP.md,STATE.md\n'
      ;;
    verification-before-completion)
      printf 'ROADMAP.md,KNOWLEDGE.md,STATE.md\n'
      ;;
    qa)
      printf 'DECISIONS.md,KNOWLEDGE.md,ROADMAP.md,STATE.md\n'
      ;;
    finishing-a-development-branch)
      printf 'ROADMAP.md,KNOWLEDGE.md,STATE.md\n'
      ;;
    quick-writing-plans|quick-executing-plans|quick-verification-before-completion)
      printf 'KNOWLEDGE.md,STATE.md\n'
      ;;
    *)
      printf '%s\n' '-'
      ;;
  esac
}

phase_total_count() {
  local mode="$1" ceo_required="$2"
  case "$mode" in
    quick)
      printf '3\n'
      ;;
    dev)
      if [ "$ceo_required" = '1' ]; then
        printf '9\n'
      else
        printf '8\n'
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

completed_phase_count() {
  local raw="$1" count=0 item=''
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    count=$((count + 1))
  done < <(state_split_completed "$raw")
  printf '%s\n' "$count"
}

normalize_input() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

confirm_allowed_inputs() {
  local skip_action="$1"
  if [ "$skip_action" != '-' ]; then
    printf 'y,yes,n,no,s,skip\n'
  else
    printf 'y,yes,n,no\n'
  fi
}

resume_allowed_inputs() {
  printf 'c,continue,r,restart,a,abort\n'
}

parse_session_request() {
  local expect_raw_input="$1"
  shift

  SESSION_REQUEST_MODE=''
  SESSION_REQUEST_WITH_CEO=0
  SESSION_REQUEST_MINIMAL=0
  SESSION_REQUEST_HOST=''
  SESSION_REQUEST_RAW_INPUT=''

  local raw_input_seen=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode)
        [ "$#" -ge 2 ] || { usage; return 2; }
        SESSION_REQUEST_MODE="$2"
        shift 2
        ;;
      --with-ceo)
        SESSION_REQUEST_WITH_CEO=1
        shift
        ;;
      --minimal)
        SESSION_REQUEST_MINIMAL=1
        shift
        ;;
      -*)
        if [ -n "$SESSION_REQUEST_HOST" ] && [ "$expect_raw_input" = '1' ] && [ "$raw_input_seen" = '0' ]; then
          SESSION_REQUEST_RAW_INPUT="$1"
          raw_input_seen=1
          shift
        else
          usage
          return 2
        fi
        ;;
      *)
        if [ -z "$SESSION_REQUEST_HOST" ]; then
          SESSION_REQUEST_HOST="$1"
        elif [ "$expect_raw_input" = '1' ] && [ "$raw_input_seen" = '0' ]; then
          SESSION_REQUEST_RAW_INPUT="$1"
          raw_input_seen=1
        else
          usage
          return 2
        fi
        shift
        ;;
    esac
  done

  [ -n "$SESSION_REQUEST_HOST" ] || { usage; return 2; }
  case "$SESSION_REQUEST_MODE" in
    dev|quick) ;;
    *) usage; return 2 ;;
  esac
  if [ "$expect_raw_input" = '1' ] && [ "$raw_input_seen" = '0' ]; then
    usage
    return 2
  fi
}

resolve_requested_profile() {
  local mode="$1" with_ceo="$2" minimal="$3"

  if [ "$mode" = 'quick' ] && [ "$with_ceo" -eq 1 ]; then
    printf '%s\n' '--with-ceo 仅适用于 dev 模式' >&2
    return 2
  fi
  if [ "$mode" = 'quick' ] && [ "$minimal" -eq 1 ]; then
    printf '%s\n' '--minimal 仅适用于 dev 模式' >&2
    return 2
  fi
  if [ "$with_ceo" -eq 1 ] && [ "$minimal" -eq 1 ]; then
    printf '%s\n' '--minimal 与 --with-ceo 互斥,请只保留其一' >&2
    return 2
  fi

  REQUESTED_ADAPTER_MODE="$(state_default_adapter_mode_for_mode "$mode")"
  if [ "$mode" = 'dev' ] && [ "$minimal" -eq 1 ]; then
    REQUESTED_ADAPTER_MODE='minimal'
  fi
  REQUESTED_CEO_REVIEW_FORCED=0
  if [ "$with_ceo" -eq 1 ]; then
    REQUESTED_CEO_REVIEW_FORCED=1
  fi
}

session_start_contract() {
  local mode="$1" with_ceo="$2" minimal="$3" host="$4"
  local detect_out='' boot_out='' status_out='' requested_adapter_mode='' requested_ceo_review_forced='' detect_minimal=0

  resolve_requested_profile "$mode" "$with_ceo" "$minimal" || return $?
  requested_adapter_mode="$REQUESTED_ADAPTER_MODE"
  requested_ceo_review_forced="$REQUESTED_CEO_REVIEW_FORCED"

  local existing_status='' existing_mode='' existing_state='' existing_phase='' existing_adapter_mode='' existing_ceo_review_forced=''
  if existing_status="$(probe_existing_status "$host")"; then
    existing_mode="$(kv_get "$existing_status" MODE)"
    existing_state="$(kv_get "$existing_status" STATUS)"
    existing_phase="$(kv_get "$existing_status" CURRENT_PHASE)"
    existing_adapter_mode="$(kv_get "$existing_status" ADAPTER_MODE)"
    existing_ceo_review_forced="$(kv_get "$existing_status" CEO_REVIEW_FORCED)"
  fi

  if [ "$requested_adapter_mode" = 'minimal' ]; then
    detect_minimal=1
  fi

  if [ "$detect_minimal" -eq 1 ]; then
    detect_out="$("$REPO_ABS/scripts/detect-deps.sh" --minimal)"
  else
    detect_out="$("$REPO_ABS/scripts/detect-deps.sh")"
  fi

  boot_out="$("$REPO_ABS/scripts/trio-runtime.sh" bootstrap --mode "$mode" --adapter-mode "$requested_adapter_mode" --ceo-review-forced "$requested_ceo_review_forced" "$host")"
  status_out="$("$REPO_ABS/scripts/trio-runtime.sh" status "$host")"

  local active_mode active_status active_phase completed state_superpowers_version detected_superpowers_version detected_gstack_status
  local active_adapter_mode active_ceo_review_forced start_action='run-phase' restart_mode='' gstack_enabled=0 profile_mismatch=0
  active_mode="$(kv_get "$status_out" MODE)"
  active_status="$(kv_get "$status_out" STATUS)"
  active_phase="$(kv_get "$status_out" CURRENT_PHASE)"
  completed="$(kv_get "$status_out" COMPLETED_PHASES)"
  state_superpowers_version="$(kv_get "$status_out" SUPERPOWERS_VERSION)"
  active_adapter_mode="$(kv_get "$status_out" ADAPTER_MODE)"
  active_ceo_review_forced="$(kv_get "$status_out" CEO_REVIEW_FORCED)"
  detected_superpowers_version="$(kv_get "$detect_out" SUPERPOWERS_VERSION)"
  detected_gstack_status="$(kv_get "$detect_out" PROVIDER_STATUS_gstack)"

  if [ "$active_mode" = 'dev' ] && [ "$active_adapter_mode" = 'full' ] && [ "$detected_gstack_status" = 'available' ]; then
    gstack_enabled=1
  fi

  if [ "$requested_adapter_mode" != "$active_adapter_mode" ] || [ "$requested_ceo_review_forced" != "$active_ceo_review_forced" ] || [ "$mode" != "$active_mode" ]; then
    profile_mismatch=1
  fi

  case "$existing_state" in
    running|awaiting-confirmation)
      start_action='resume-decision'
      restart_mode="$mode"
      ;;
    awaiting-start-confirmation)
      if [ "$profile_mismatch" = '1' ]; then
        start_action='resume-decision'
        restart_mode="$mode"
      fi
      ;;
  esac

  printf 'REQUESTED_MODE=%s\n' "$mode"
  printf 'REQUESTED_ADAPTER_MODE=%s\n' "$requested_adapter_mode"
  printf 'REQUESTED_CEO_REVIEW_FORCED=%s\n' "$requested_ceo_review_forced"
  printf 'ACTIVE_MODE=%s\n' "$active_mode"
  printf 'STATUS=%s\n' "$active_status"
  printf 'CURRENT_PHASE=%s\n' "$active_phase"
  printf 'COMPLETED_PHASES=%s\n' "$completed"
  printf 'DETECTED_SUPERPOWERS_VERSION=%s\n' "$detected_superpowers_version"
  printf 'STATE_SUPERPOWERS_VERSION=%s\n' "$state_superpowers_version"
  printf 'ADAPTER_MODE=%s\n' "$active_adapter_mode"
  printf 'CEO_REVIEW_FORCED=%s\n' "$active_ceo_review_forced"
  printf 'GSTACK_ENABLED=%s\n' "$gstack_enabled"
  printf 'START_ACTION=%s\n' "$start_action"
  printf 'PROFILE_MISMATCH=%s\n' "$profile_mismatch"
  if [ "$start_action" = 'resume-decision' ]; then
    printf 'RESUME_MODE=%s\n' "$existing_mode"
    printf 'RESUME_STATUS=%s\n' "$existing_state"
    printf 'RESUME_PHASE=%s\n' "$existing_phase"
    printf 'RESTART_MODE=%s\n' "$restart_mode"
    printf 'RESTART_ADAPTER_MODE=%s\n' "$requested_adapter_mode"
    printf 'RESTART_CEO_REVIEW_FORCED=%s\n' "$requested_ceo_review_forced"
  else
    printf 'RUN_PHASE=%s\n' "$active_phase"
  fi
  printf 'BOOTSTRAP_MODE=%s\n' "$(kv_get "$boot_out" MODE)"
}

session_start() {
  parse_session_request 0 "$@" || return $?
  session_start_contract "$SESSION_REQUEST_MODE" "$SESSION_REQUEST_WITH_CEO" "$SESSION_REQUEST_MINIMAL" "$SESSION_REQUEST_HOST"
}

session_phase() {
  local host='' status_out='' mode='' status='' current_phase='' completed='' quick_streak='' superpowers_version=''
  local adapter_mode='' ceo_review_forced='' project_type='' ceo_required='' yes_action='' no_action='' skip_action='' next_phase_yes='' next_phase_skip=''
  local executor='' capability='' provider='' provider_kind='' provider_invoke_mode='' provider_entrypoints='' provider_state_policy='none' provider_writer_boundary='-' writers='' gate='' detect_minimal=0 dev_review_suggested=0 resolved_provider=''
  local phase_input_files='' next_phase_input_files_yes='-' next_phase_input_files_skip='-' completed_count='' total_phases='' current_phase_index=''
  local start_guard_required=0 start_guard_kind='-'

  [ "$#" -eq 1 ] || { usage; return 2; }
  host="$1"
  status_out="$("$REPO_ABS/scripts/trio-runtime.sh" status "$host")"
  mode="$(kv_get "$status_out" MODE)"
  status="$(kv_get "$status_out" STATUS)"
  current_phase="$(kv_get "$status_out" CURRENT_PHASE)"
  completed="$(kv_get "$status_out" COMPLETED_PHASES)"
  quick_streak="$(kv_get "$status_out" QUICK_STREAK)"
  superpowers_version="$(kv_get "$status_out" SUPERPOWERS_VERSION)"
  adapter_mode="$(kv_get "$status_out" ADAPTER_MODE)"
  ceo_review_forced="$(kv_get "$status_out" CEO_REVIEW_FORCED)"
  project_type="$(project_type_for_host "$host")"
  [ -n "$project_type" ] || project_type='unknown'

  ceo_required="$(actual_ceo_review_required "$mode" "$ceo_review_forced" "$project_type")"
  if [ "$adapter_mode" = 'minimal' ]; then
    detect_minimal=1
  fi
  if [ "$mode" = 'quick' ] && [ "$quick_streak" -gt 3 ]; then
    dev_review_suggested=1
  fi
  completed_count="$(completed_phase_count "$completed")"
  total_phases="$(phase_total_count "$mode" "$ceo_required")"
  capability="$(capability_for_phase "$current_phase")"

  if [ "$status" = 'completed' ] || [ "$status" = 'aborted' ]; then
    executor='-'
    capability='-'
    provider='-'
    provider_kind='-'
    provider_invoke_mode='-'
    provider_entrypoints='-'
    provider_state_policy='none'
    provider_writer_boundary='-'
    writers='-'
    gate='-'
    yes_action='-'
    no_action='-'
    next_phase_yes='-'
    skip_action='-'
    next_phase_skip='-'
    phase_input_files='-'
    current_phase_index="$total_phases"
  elif [ "$status" = 'awaiting-start-confirmation' ]; then
    start_guard_required=1
    start_guard_kind='quick-risk'
    executor='guard'
    capability="$(capability_for_phase "$current_phase")"
    provider='-'
    provider_kind='-'
    provider_invoke_mode='-'
    provider_entrypoints='-'
    provider_state_policy='none'
    provider_writer_boundary='-'
    writers='-'
    gate='-'
    phase_input_files='STATE.md'
    yes_action='start-guard-yes'
    no_action='abort'
    next_phase_yes="$current_phase"
    skip_action='-'
    next_phase_skip='-'
    current_phase_index=$((completed_count + 1))
    next_phase_input_files_yes="$(phase_input_files "$current_phase")"
  else
    executor="$(phase_executor "$current_phase" "$adapter_mode")"
    writers="$(phase_writers "$current_phase")"
    gate="$(phase_gate "$current_phase")"
    phase_input_files="$(phase_input_files "$current_phase")"
    yes_action="$(phase_yes_action "$current_phase" "$ceo_review_forced" "$project_type")"
    no_action='confirm-no'
    next_phase_yes="$(phase_next_on_yes "$current_phase" "$yes_action")"
    skip_action="$(phase_skip_action "$current_phase")"
    next_phase_skip="$(phase_next_on_skip "$current_phase")"
    current_phase_index=$((completed_count + 1))
    if [ "$next_phase_yes" != 'completed' ]; then
      next_phase_input_files_yes="$(phase_input_files "$next_phase_yes")"
    fi
    if [ "$next_phase_skip" != '-' ]; then
      next_phase_input_files_skip="$(phase_input_files "$next_phase_skip")"
    fi
    case "$executor" in
      adapter)
        resolved_provider="$(providers_resolve_for_phase "$current_phase")"
        capability="$(kv_get "$resolved_provider" PHASE_CAPABILITY)"
        provider="$(kv_get "$resolved_provider" PROVIDER_ID)"
        provider_kind="$(kv_get "$resolved_provider" PROVIDER_KIND)"
        provider_invoke_mode="$(kv_get "$resolved_provider" PROVIDER_INVOKE_MODE)"
        provider_entrypoints="$(kv_get "$resolved_provider" PROVIDER_ENTRYPOINTS)"
        provider_state_policy="$(kv_get "$resolved_provider" PROVIDER_STATE_POLICY)"
        provider_writer_boundary="$(kv_get "$resolved_provider" PROVIDER_WRITER_BOUNDARY)"
        [ "$provider_writer_boundary" != '-' ] || provider_writer_boundary="$writers"
        ;;
      runtime)
        provider='-'
        provider_kind='-'
        provider_invoke_mode='-'
        provider_entrypoints='-'
        provider_state_policy='none'
        provider_writer_boundary="$writers"
        ;;
      dialogue)
        provider='-'
        provider_kind='-'
        provider_invoke_mode='-'
        provider_entrypoints='-'
        provider_state_policy='none'
        provider_writer_boundary="$writers"
        ;;
    esac
  fi

  printf 'MODE=%s\n' "$mode"
  printf 'STATUS=%s\n' "$status"
  printf 'CURRENT_PHASE=%s\n' "$current_phase"
  printf 'COMPLETED_PHASES=%s\n' "$completed"
  printf 'COMPLETED_PHASES_COUNT=%s\n' "$completed_count"
  printf 'CURRENT_PHASE_INDEX=%s\n' "$current_phase_index"
  printf 'TOTAL_PHASES=%s\n' "$total_phases"
  printf 'QUICK_STREAK=%s\n' "$quick_streak"
  printf 'SUPERPOWERS_VERSION=%s\n' "$superpowers_version"
  printf 'ADAPTER_MODE=%s\n' "$adapter_mode"
  printf 'CEO_REVIEW_FORCED=%s\n' "$ceo_review_forced"
  printf 'CEO_REVIEW_REQUIRED=%s\n' "$ceo_required"
  printf 'PROJECT_TYPE=%s\n' "$project_type"
  printf 'PHASE_EXECUTOR=%s\n' "$executor"
  printf 'PHASE_CAPABILITY=%s\n' "$capability"
  printf 'PROVIDER_ID=%s\n' "$provider"
  printf 'PROVIDER_KIND=%s\n' "$provider_kind"
  printf 'PROVIDER_INVOKE_MODE=%s\n' "$provider_invoke_mode"
  printf 'PROVIDER_ENTRYPOINTS=%s\n' "$provider_entrypoints"
  printf 'PROVIDER_STATE_POLICY=%s\n' "$provider_state_policy"
  printf 'PROVIDER_WRITER_BOUNDARY=%s\n' "$provider_writer_boundary"
  printf 'ADAPTER_PROVIDER=%s\n' "$provider"
  printf 'ADAPTER_SKILLS=%s\n' "$provider_entrypoints"
  printf 'PHASE_GATE=%s\n' "$gate"
  printf 'PHASE_WRITERS=%s\n' "$writers"
  printf 'PHASE_INPUT_FILES=%s\n' "$phase_input_files"
  printf 'START_GUARD_REQUIRED=%s\n' "$start_guard_required"
  printf 'START_GUARD_KIND=%s\n' "$start_guard_kind"
  printf 'YES_ACTION=%s\n' "$yes_action"
  printf 'NO_ACTION=%s\n' "$no_action"
  printf 'SKIP_ACTION=%s\n' "$skip_action"
  printf 'NEXT_PHASE_ON_YES=%s\n' "$next_phase_yes"
  printf 'NEXT_PHASE_ON_SKIP=%s\n' "$next_phase_skip"
  printf 'NEXT_PHASE_INPUT_FILES_ON_YES=%s\n' "$next_phase_input_files_yes"
  printf 'NEXT_PHASE_INPUT_FILES_ON_SKIP=%s\n' "$next_phase_input_files_skip"
  printf 'DETECT_MINIMAL=%s\n' "$detect_minimal"
  printf 'DEV_REVIEW_SUGGESTED=%s\n' "$dev_review_suggested"
}

session_confirm() {
  local host='' raw_input='' phase_out='' status='' current_phase='' yes_action='' no_action='' skip_action=''
  local normalized='' applied_action='' allowed_inputs='' phase_after=''

  [ "$#" -eq 2 ] || { usage; return 2; }
  host="$1"
  raw_input="$2"
  phase_out="$("$REPO_ABS/scripts/trio-session.sh" phase "$host")"
  status="$(kv_get "$phase_out" STATUS)"
  current_phase="$(kv_get "$phase_out" CURRENT_PHASE)"
  yes_action="$(kv_get "$phase_out" YES_ACTION)"
  no_action="$(kv_get "$phase_out" NO_ACTION)"
  skip_action="$(kv_get "$phase_out" SKIP_ACTION)"
  allowed_inputs="$(confirm_allowed_inputs "$skip_action")"
  normalized="$(normalize_input "$raw_input")"

  if [ "$status" != 'awaiting-confirmation' ] && [ "$status" != 'awaiting-start-confirmation' ]; then
    printf 'CONFIRM_RESULT=not-awaiting-confirmation\n'
    printf 'NORMALIZED_INPUT=%s\n' "$normalized"
    printf '%s\n' "$phase_out"
    return 0
  fi

  case "$normalized" in
    y|yes)
      applied_action="$yes_action"
      ;;
    n|no)
      applied_action="$no_action"
      ;;
    s|skip)
      if [ "$skip_action" != '-' ]; then
        applied_action="$skip_action"
      fi
      ;;
  esac

  if [ -z "$applied_action" ]; then
    printf 'CONFIRM_RESULT=invalid\n'
    printf 'NORMALIZED_INPUT=%s\n' "$normalized"
    printf 'ALLOWED_INPUTS=%s\n' "$allowed_inputs"
    printf '%s\n' "$phase_out"
    return 0
  fi

  "$REPO_ABS/scripts/trio-runtime.sh" transition "$host" "$applied_action" "$current_phase" >/dev/null
  phase_after="$("$REPO_ABS/scripts/trio-session.sh" phase "$host")"
  printf 'CONFIRM_RESULT=accepted\n'
  printf 'NORMALIZED_INPUT=%s\n' "$normalized"
  printf 'APPLIED_ACTION=%s\n' "$applied_action"
  printf 'ALLOWED_INPUTS=%s\n' "$allowed_inputs"
  printf '%s\n' "$phase_after"
}

session_resume() {
  local start_out='' start_action='' normalized='' allowed_inputs='' applied_action='' phase_after=''
  local restart_mode='' restart_adapter_mode='' restart_ceo_review_forced=''

  parse_session_request 1 "$@" || return $?
  start_out="$(session_start_contract "$SESSION_REQUEST_MODE" "$SESSION_REQUEST_WITH_CEO" "$SESSION_REQUEST_MINIMAL" "$SESSION_REQUEST_HOST")"
  start_action="$(kv_get "$start_out" START_ACTION)"
  normalized="$(normalize_input "$SESSION_REQUEST_RAW_INPUT")"
  allowed_inputs="$(resume_allowed_inputs)"

  if [ "$start_action" != 'resume-decision' ]; then
    printf 'RESUME_RESULT=not-awaiting-decision\n'
    printf 'NORMALIZED_INPUT=%s\n' "$normalized"
    printf '%s\n' "$start_out"
    return 0
  fi

  case "$normalized" in
    c|continue)
      applied_action='continue'
      ;;
    r|restart)
      applied_action='restart'
      ;;
    a|abort)
      applied_action='abort'
      ;;
  esac

  if [ -z "$applied_action" ]; then
    printf 'RESUME_RESULT=invalid\n'
    printf 'NORMALIZED_INPUT=%s\n' "$normalized"
    printf 'ALLOWED_INPUTS=%s\n' "$allowed_inputs"
    printf '%s\n' "$start_out"
    return 0
  fi

  case "$applied_action" in
    continue)
      phase_after="$("$REPO_ABS/scripts/trio-session.sh" phase "$SESSION_REQUEST_HOST")"
      ;;
    restart)
      restart_mode="$(kv_get "$start_out" RESTART_MODE)"
      restart_adapter_mode="$(kv_get "$start_out" RESTART_ADAPTER_MODE)"
      restart_ceo_review_forced="$(kv_get "$start_out" RESTART_CEO_REVIEW_FORCED)"
      "$REPO_ABS/scripts/trio-runtime.sh" restart --mode "$restart_mode" --adapter-mode "$restart_adapter_mode" --ceo-review-forced "$restart_ceo_review_forced" "$SESSION_REQUEST_HOST" >/dev/null
      phase_after="$("$REPO_ABS/scripts/trio-session.sh" phase "$SESSION_REQUEST_HOST")"
      ;;
    abort)
      "$REPO_ABS/scripts/trio-runtime.sh" abort "$SESSION_REQUEST_HOST" >/dev/null
      phase_after="$("$REPO_ABS/scripts/trio-session.sh" phase "$SESSION_REQUEST_HOST")"
      ;;
  esac

  printf 'RESUME_RESULT=accepted\n'
  printf 'NORMALIZED_INPUT=%s\n' "$normalized"
  printf 'APPLIED_ACTION=%s\n' "$applied_action"
  printf 'ALLOWED_INPUTS=%s\n' "$allowed_inputs"
  printf '%s\n' "$phase_after"
}

[ "$#" -gt 0 ] || { usage; exit 2; }
verb="$1"
shift
case "$verb" in
  start) session_start "$@" ;;
  phase) session_phase "$@" ;;
  confirm) session_confirm "$@" ;;
  resume) session_resume "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
