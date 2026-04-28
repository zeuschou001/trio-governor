#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_eq() { [ "$1" = "$2" ] || { printf 'FAIL %s: want=%s got=%s\n' "$3" "$2" "$1" >&2; exit 1; }; }
assert_contains() { [[ "$1" == *"$2"* ]] || { printf 'FAIL %s: missing=%s in=%s\n' "$3" "$2" "$1" >&2; exit 1; }; }

run_with_home() {
  local home="$1"; shift
  HOME="$home" "$@"
}

# Superpowers 缺失硬失败
t=$(mktemp -d)
out=$(run_with_home "$t" "$REPO/scripts/detect-deps.sh" 2>&1 && echo "EXIT0" || echo "EXIT$?")
assert_contains "$out" '/plugin install superpowers@superpowers-marketplace' 'missing superpowers msg'
assert_contains "$out" 'EXIT1' 'missing superpowers exit 1'

# Superpowers 齐全 + 版本过低 warning
t=$(mktemp -d)
mkdir -p "$t/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.6/skills"
for s in writing-plans executing-plans test-driven-development verification-before-completion finishing-a-development-branch; do
  mkdir -p "$t/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.6/skills/$s"
  echo "placeholder" > "$t/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.6/skills/$s/SKILL.md"
done
out=$(run_with_home "$t" "$REPO/scripts/detect-deps.sh" 2>&1)
assert_contains "$out" 'SUPERPOWERS_VERSION=5.0.6' 'version line'
assert_contains "$out" 'PROVIDER_STATUS_superpowers=available' 'superpowers status'
assert_contains "$out" 'PROVIDER_VERSION_superpowers=5.0.6' 'superpowers provider version'
assert_contains "$out" '低于推荐 5.0.7' 'low version warning'

# 多版本选最高
t=$(mktemp -d)
for v in 4.9.9 5.0.7 5.0.6 6.0.0; do
  for s in writing-plans executing-plans test-driven-development verification-before-completion finishing-a-development-branch; do
    mkdir -p "$t/.claude/plugins/cache/claude-plugins-official/superpowers/$v/skills/$s"
    echo "placeholder" > "$t/.claude/plugins/cache/claude-plugins-official/superpowers/$v/skills/$s/SKILL.md"
  done
done
out=$(run_with_home "$t" "$REPO/scripts/detect-deps.sh" 2>&1)
assert_contains "$out" 'SUPERPOWERS_VERSION=6.0.0' 'pick highest'

# gstack 缺失软提示
t=$(mktemp -d)
for s in writing-plans executing-plans test-driven-development verification-before-completion finishing-a-development-branch; do
  mkdir -p "$t/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/$s"
  echo "placeholder" > "$t/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/$s/SKILL.md"
done
out=$(run_with_home "$t" "$REPO/scripts/detect-deps.sh" 2>&1 && echo "EXIT0" || echo "EXIT$?")
assert_contains "$out" 'EXIT0' 'gstack soft missing no fail'
assert_contains "$out" 'PROVIDER_STATUS_gstack=absent' 'gstack missing status'
assert_contains "$out" 'raw.githubusercontent.com/garrytan/gstack/main/plan-eng-review/SKILL.md' 'plan-eng curl'

# gstack 齐全无提示
for s in office-hours plan-ceo-review plan-eng-review qa; do
  mkdir -p "$t/.claude/skills/$s"
  printf -- '---\nname: %s\n---\n' "$s" > "$t/.claude/skills/$s/SKILL.md"
done
out=$(run_with_home "$t" "$REPO/scripts/detect-deps.sh" 2>&1)
[[ "$out" != *"raw.githubusercontent"* ]] || { printf 'FAIL gstack ok but still prompts curl\n' >&2; exit 1; }
assert_contains "$out" 'PROVIDER_STATUS_gstack=available' 'gstack available status'
assert_contains "$out" 'PROVIDER_SNAPSHOT=superpowers=5.0.7,gstack=present,gsd2=absent,trellis=absent' 'provider snapshot'

# frontmatter name 不匹配 → 仍打印 curl
printf -- '---\nname: wrong-name\n---\n' > "$t/.claude/skills/qa/SKILL.md"
out=$(run_with_home "$t" "$REPO/scripts/detect-deps.sh" 2>&1)
assert_contains "$out" 'main/qa/SKILL.md' 'qa name mismatch triggers curl'

# blocklist 命中 warning
mkdir -p "$t/.claude/skills/browse" "$t/.claude/skills/ship"
out=$(run_with_home "$t" "$REPO/scripts/detect-deps.sh" 2>&1)
assert_contains "$out" '检测到 2 个 blocklist skill' 'blocklist hits'
assert_contains "$out" 'browse' 'blocklist browse'
assert_contains "$out" 'ship' 'blocklist ship'

# --minimal 跳过 gstack 提示
out=$(run_with_home "$t" "$REPO/scripts/detect-deps.sh" --minimal 2>&1)
[[ "$out" != *"raw.githubusercontent"* ]] || { printf 'FAIL --minimal still prompts gstack\n' >&2; exit 1; }

printf 'detect-deps tests: OK\n'
