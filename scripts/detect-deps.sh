#!/usr/bin/env bash
set -euo pipefail

minimal=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --minimal) minimal=1 ;;
    *) printf '用法: %s [--minimal]\n' "${0##*/}" >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ABS=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=scripts/lib/providers.sh
. "$SCRIPT_DIR/lib/providers.sh"

emit_provider_lines() {
  local id="$1" out="$2" status='' version=''
  status="$(providers_kv_get "$out" PROVIDER_STATUS)"
  version="$(providers_kv_get "$out" PROVIDER_VERSION)"
  printf 'PROVIDER_STATUS_%s=%s\n' "$id" "$status"
  printf 'PROVIDER_VERSION_%s=%s\n' "$id" "$version"
}

superpowers_out="$(providers_detect_one superpowers "$minimal")"
superpowers_status="$(providers_kv_get "$superpowers_out" PROVIDER_STATUS)"
superpowers_version="$(providers_kv_get "$superpowers_out" PROVIDER_VERSION)"

if [ "$superpowers_status" != 'available' ]; then
  providers_install_hints superpowers >&2
  exit 1
fi

printf 'SUPERPOWERS_VERSION=%s\n' "$superpowers_version"

snapshot=''
sep=''
for provider_id in $(providers_registry_ids); do
  case "$provider_id" in
    superpowers)
      provider_out="$superpowers_out"
      ;;
    *)
      provider_out="$(providers_detect_one "$provider_id" "$minimal")"
      ;;
  esac
  emit_provider_lines "$provider_id" "$provider_out"
  snapshot="${snapshot}${sep}${provider_id}=$(providers_snapshot_value "$(providers_kv_get "$provider_out" PROVIDER_STATUS)" "$(providers_kv_get "$provider_out" PROVIDER_VERSION)")"
  sep=','
done
printf 'PROVIDER_SNAPSHOT=%s\n' "$snapshot"

BLOCKLIST=(design-consultation cso careful freeze guard unfreeze learn retro benchmark setup-deploy browse connect-chrome setup-browser-cookies document-release canary ship land-and-deploy autoplan gstack-upgrade)
hits=()
SKILLS_ROOT="$HOME/.claude/skills"
if [ -d "$SKILLS_ROOT" ]; then
  for p in "$SKILLS_ROOT"/*; do
    [ -e "$p" ] || [ -L "$p" ] || continue
    n="${p##*/}"
    for b in "${BLOCKLIST[@]}"; do
      [ "$n" = "$b" ] && hits+=("$n") && break
    done
  done
fi
if [ "${#hits[@]}" -gt 0 ]; then
  printf -v list '%s, ' "${hits[@]}"
  printf '警告: 检测到 %s 个 blocklist skill,建议删除以保持 token 预算:%s\n' "${#hits[@]}" "${list%, }" >&2
fi
