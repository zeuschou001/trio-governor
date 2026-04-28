#!/usr/bin/env bash

provider_id() { printf 'superpowers\n'; }
provider_kind() { printf 'plugin-provider\n'; }
provider_availability() { printf 'required\n'; }
provider_invoke_mode() { printf 'plugin-skill\n'; }
provider_capabilities() { printf '%s\n' 'planning execution verification finish tdd'; }

provider_detect() {
  local minimal="${1:-0}" superpowers_root='' required_skills=() versions=() v='' s='' selected='' ok=1 status='' version=''
  superpowers_root="$HOME/.claude/plugins/cache/claude-plugins-official/superpowers"
  required_skills=(writing-plans executing-plans test-driven-development verification-before-completion finishing-a-development-branch)

  if [ -d "$superpowers_root" ]; then
    while IFS= read -r v; do
      versions+=("$v")
    done < <(
      for p in "$superpowers_root"/*; do
        [ -e "$p" ] || [ -L "$p" ] || continue
        v="${p##*/}"
        [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && printf '%s\n' "$v"
      done | sort -t. -k1,1n -k2,2n -k3,3n
    )
  fi

  for ((i=${#versions[@]}-1; i>=0; i--)); do
    v="${versions[i]}"
    ok=1
    for s in "${required_skills[@]}"; do
      [ -f "$superpowers_root/$v/skills/$s/SKILL.md" ] || { ok=0; break; }
    done
    [ "$ok" -eq 1 ] && { selected="$v"; break; }
  done

  if [ -z "$selected" ]; then
    status='absent'
    version='absent'
  else
    status='available'
    version="$selected"
    IFS=. read -r MA MI PA <<<"$selected"
    if (( 10#$MA < 5 || (10#$MA == 5 && 10#$MI == 0 && 10#$PA < 7) )); then
      printf '警告: 当前 Superpowers 版本 %s 低于推荐 5.0.7,可能存在兼容性问题\n' "$selected" >&2
    fi
  fi

  printf 'PROVIDER_ID=%s\n' "$(provider_id)"
  printf 'PROVIDER_STATUS=%s\n' "$status"
  printf 'PROVIDER_VERSION=%s\n' "$version"
  printf 'PROVIDER_SELECTABLE=%s\n' "$(provider_selectable)"
}

provider_version() { printf 'unknown\n'; }

provider_supports() {
  case "$1" in
    planning|execution|verification|finish|tdd) return 0 ;;
    *) return 1 ;;
  esac
}

provider_entrypoints_for() {
  local capability="$1"
  case "$capability" in
    planning) printf 'writing-plans\n' ;;
    execution) printf 'executing-plans,test-driven-development\n' ;;
    verification) printf 'verification-before-completion\n' ;;
    finish) printf 'finishing-a-development-branch\n' ;;
    tdd) printf 'test-driven-development\n' ;;
    *) printf '%s\n' '-' ;;
  esac
}

provider_writer_boundary_for() {
  local capability="$1" phase="${2:-}"
  case "$capability" in
    planning)
      if [ "$phase" = 'quick-writing-plans' ]; then
        printf '%s\n' '-'
      else
        printf 'roadmap-rewrite\n'
      fi
      ;;
    execution|tdd) printf 'knowledge-append\n' ;;
    verification|finish) printf '%s\n' '-' ;;
    *) printf '%s\n' '-' ;;
  esac
}

provider_state_policy() { printf 'none\n'; }

provider_install_hint() {
  printf '%s\n' '/plugin marketplace add obra/superpowers-marketplace && /plugin install superpowers@superpowers-marketplace'
}

provider_selectable() { printf '1\n'; }
