#!/usr/bin/env bash

provider_id() { printf 'gstack\n'; }
provider_kind() { printf 'skill-provider\n'; }
provider_availability() { printf 'optional\n'; }
provider_invoke_mode() { printf 'skill\n'; }
provider_capabilities() { printf '%s\n' 'discovery product-review architecture-review qa'; }

provider_detect() {
  local minimal="${1:-0}" found=0 total=0 s='' f='' actual='' status='' version=''
  for s in office-hours plan-ceo-review plan-eng-review qa; do
    total=$((total + 1))
    f="$HOME/.claude/skills/$s/SKILL.md"
    actual=''
    [ -f "$f" ] && actual="$(providers_frontmatter_name "$f" 2>/dev/null || true)"
    if [ "$actual" = "$s" ]; then
      found=$((found + 1))
      continue
    fi
    if [ "$minimal" -eq 0 ]; then
      printf 'mkdir -p ~/.claude/skills/%s && curl -o ~/.claude/skills/%s/SKILL.md https://raw.githubusercontent.com/garrytan/gstack/main/%s/SKILL.md\n' "$s" "$s" "$s" >&2
    fi
  done

  if [ "$found" -eq "$total" ]; then
    status='available'
    version='present'
  elif [ "$found" -eq 0 ]; then
    status='absent'
    version='absent'
  else
    status='partial'
    version='partial'
  fi

  printf 'PROVIDER_ID=%s\n' "$(provider_id)"
  printf 'PROVIDER_STATUS=%s\n' "$status"
  printf 'PROVIDER_VERSION=%s\n' "$version"
  printf 'PROVIDER_SELECTABLE=%s\n' "$(provider_selectable)"
}

provider_version() { printf 'present\n'; }

provider_supports() {
  case "$1" in
    discovery|product-review|architecture-review|qa) return 0 ;;
    *) return 1 ;;
  esac
}

provider_entrypoints_for() {
  local capability="$1"
  case "$capability" in
    discovery) printf 'office-hours\n' ;;
    product-review) printf 'plan-ceo-review\n' ;;
    architecture-review) printf 'plan-eng-review\n' ;;
    qa) printf 'qa\n' ;;
    *) printf '%s\n' '-' ;;
  esac
}

provider_writer_boundary_for() {
  local capability="$1"
  case "$capability" in
    discovery) printf 'project-write\n' ;;
    product-review|architecture-review) printf 'decision-append\n' ;;
    qa) printf 'knowledge-append\n' ;;
    *) printf '%s\n' '-' ;;
  esac
}

provider_state_policy() { printf 'none\n'; }

provider_install_hint() {
  printf '%s\n' '安装 gstack allowlist 技能后重试'
}

provider_selectable() { printf '1\n'; }
