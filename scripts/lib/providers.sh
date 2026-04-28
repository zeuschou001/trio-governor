#!/usr/bin/env bash

TRIO_PROVIDER_REPO_ABS="${REPO_ABS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TRIO_PROVIDER_IDS="superpowers gstack gsd2 trellis"

providers_kv_get() {
  local blob="$1" key="$2"
  printf '%s\n' "$blob" | sed -n "s/^$key=//p" | head -n 1
}

providers_frontmatter_name() {
  local file="$1" line='' started=0 name=''
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$started" -eq 0 ]; then
      [ "$line" = '---' ] || return 1
      started=1
      continue
    fi
    if [ "$line" = '---' ]; then
      [ -n "$name" ] && printf '%s\n' "$name"
      [ -n "$name" ]
      return $?
    fi
    if [ -z "$name" ] && [[ "$line" == name:* ]]; then
      name="${line#name:}"
      name="${name#"${name%%[![:space:]]*}"}"
      name="${name%"${name##*[![:space:]]}"}"
      name="${name%\"}"
      name="${name#\"}"
      name="${name%\'}"
      name="${name#\'}"
    fi
  done <"$file"
  return 1
}

providers_unload() {
  unset -f provider_id provider_kind provider_availability provider_invoke_mode provider_capabilities provider_detect provider_version provider_supports provider_entrypoints_for provider_writer_boundary_for provider_state_policy provider_install_hint provider_selectable provider_bridge_command_hint provider_bridge_handoff_markdown provider_bridge_review_catalog 2>/dev/null || true
}

providers_module_path() {
  printf '%s/scripts/providers/%s.sh\n' "$TRIO_PROVIDER_REPO_ABS" "$1"
}

providers_load_provider() {
  local id="$1" path=''
  path="$(providers_module_path "$id")"
  [ -f "$path" ] || return 1
  providers_unload
  # shellcheck source=/dev/null
  . "$path"
}

providers_registry_ids() {
  local id=''
  for id in $TRIO_PROVIDER_IDS; do
    printf '%s\n' "$id"
  done
}

providers_snapshot_value() {
  local status="$1" version="$2"
  case "$status" in
    available)
      case "$version" in
        ''|unknown|present|partial|absent) printf 'present\n' ;;
        *) printf '%s\n' "$version" ;;
      esac
      ;;
    partial) printf 'partial\n' ;;
    absent) printf 'absent\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

providers_detect_one() {
  local id="$1" minimal="${2:-0}"
  providers_load_provider "$id" || return 1
  provider_detect "$minimal"
}

providers_detect_all() {
  local minimal="${1:-0}" id='' out='' status='' version='' snapshot='' token='' sep=''
  for id in $(providers_registry_ids); do
    out="$(providers_detect_one "$id" "$minimal")"
    status="$(providers_kv_get "$out" PROVIDER_STATUS)"
    version="$(providers_kv_get "$out" PROVIDER_VERSION)"
    printf 'PROVIDER_STATUS_%s=%s\n' "$id" "$status"
    printf 'PROVIDER_VERSION_%s=%s\n' "$id" "$version"
    token="$(providers_snapshot_value "$status" "$version")"
    snapshot="${snapshot}${sep}${id}=${token}"
    sep=','
  done
  printf 'PROVIDER_SNAPSHOT=%s\n' "$snapshot"
}

providers_default_provider_for_capability() {
  case "$1" in
    discovery|product-review|architecture-review|qa) printf 'gstack\n' ;;
    planning|execution|verification|finish|tdd) printf 'superpowers\n' ;;
    external-subflow) printf 'gsd2\n' ;;
    spec-export|state-export|memory-sync) printf 'trellis\n' ;;
    *) return 1 ;;
  esac
}

providers_default_selection() {
  printf '%s\n' 'discovery=gstack,product-review=gstack,architecture-review=gstack,planning=superpowers,execution=superpowers,verification=superpowers,qa=gstack,finish=superpowers'
}

providers_pick_for_capability() {
  local capability="$1" id=''
  id="$(providers_default_provider_for_capability "$capability" 2>/dev/null || true)"
  [ -n "$id" ] || return 1
  providers_load_provider "$id" || return 1
  provider_supports "$capability" || return 1
  [ "$(provider_selectable)" = '1' ] || return 1
  printf 'PROVIDER_ID=%s\n' "$(provider_id)"
  printf 'PROVIDER_KIND=%s\n' "$(provider_kind)"
  printf 'PROVIDER_AVAILABILITY=%s\n' "$(provider_availability)"
  printf 'PROVIDER_INVOKE_MODE=%s\n' "$(provider_invoke_mode)"
  printf 'PROVIDER_STATE_POLICY=%s\n' "$(provider_state_policy)"
}

providers_resolve_for_phase() {
  local phase="$1" capability='' pick='' provider_id_value=''
  capability="$(capability_for_phase "$phase")"
  printf 'PHASE_CAPABILITY=%s\n' "$capability"
  pick="$(providers_pick_for_capability "$capability" 2>/dev/null || true)"
  provider_id_value="$(providers_kv_get "$pick" PROVIDER_ID)"
  if [ -z "$provider_id_value" ]; then
    printf 'PROVIDER_ID=-\n'
    printf 'PROVIDER_KIND=-\n'
    printf 'PROVIDER_AVAILABILITY=-\n'
    printf 'PROVIDER_INVOKE_MODE=-\n'
    printf 'PROVIDER_ENTRYPOINTS=-\n'
    printf 'PROVIDER_WRITER_BOUNDARY=-\n'
    printf 'PROVIDER_STATE_POLICY=none\n'
    return 0
  fi

  providers_load_provider "$provider_id_value" || return 1
  printf '%s\n' "$pick"
  printf 'PROVIDER_ENTRYPOINTS=%s\n' "$(provider_entrypoints_for "$capability" "$phase")"
  printf 'PROVIDER_WRITER_BOUNDARY=%s\n' "$(provider_writer_boundary_for "$capability" "$phase")"
}

providers_install_hints() {
  local id="$1"
  providers_load_provider "$id" || return 1
  provider_install_hint
}
