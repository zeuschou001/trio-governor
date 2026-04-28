#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_eq() { [ "$1" = "$2" ] || { printf 'FAIL %s: want=%s got=%s\n' "$3" "$2" "$1" >&2; exit 1; }; }
assert_link_target() {
  [ -L "$1" ] || { printf 'FAIL %s not a symlink\n' "$1" >&2; exit 1; }
  local got; got=$(readlink "$1")
  [ "$got" = "$2" ] || { printf 'FAIL link %s: want=%s got=%s\n' "$1" "$2" "$got" >&2; exit 1; }
}

prep_home() {
  local home="$1"
  mkdir -p "$home/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills"
  for s in writing-plans executing-plans test-driven-development verification-before-completion finishing-a-development-branch; do
    mkdir -p "$home/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/$s"
    echo "x" > "$home/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/$s/SKILL.md"
  done
}

# install 首次
h=$(mktemp -d); prep_home "$h"
HOME="$h" "$REPO/scripts/install.sh" >/dev/null
assert_link_target "$h/.claude/skills/trio-orchestrator" "$REPO/skills/trio-orchestrator"
assert_link_target "$h/.claude/commands/trio" "$REPO/commands/trio"

# install 幂等
before=$(readlink "$h/.claude/skills/trio-orchestrator")
HOME="$h" "$REPO/scripts/install.sh" >/dev/null
HOME="$h" "$REPO/scripts/install.sh" >/dev/null
after=$(readlink "$h/.claude/skills/trio-orchestrator")
assert_eq "$after" "$before" 'idempotent skill link'

# install 错指目标 → 自动重建
rm "$h/.claude/skills/trio-orchestrator"
ln -s "/nonexistent/trio-orchestrator" "$h/.claude/skills/trio-orchestrator"
HOME="$h" "$REPO/scripts/install.sh" >/dev/null
assert_link_target "$h/.claude/skills/trio-orchestrator" "$REPO/skills/trio-orchestrator"

# install 父目录占用为真实文件 → 失败
rm "$h/.claude/skills/trio-orchestrator"
echo "obstruction" > "$h/.claude/skills/trio-orchestrator"
if HOME="$h" "$REPO/scripts/install.sh" >/dev/null 2>&1; then
  printf 'FAIL should refuse regular file obstruction\n' >&2; exit 1
fi
rm "$h/.claude/skills/trio-orchestrator"
HOME="$h" "$REPO/scripts/install.sh" >/dev/null

# uninstall 仅删 2 个 symlink
superpowers_before=$(ls "$h/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills" | sort)
HOME="$h" "$REPO/scripts/uninstall.sh" >/dev/null
[ -L "$h/.claude/skills/trio-orchestrator" ] && { printf 'FAIL skill link still present\n' >&2; exit 1; }
[ -L "$h/.claude/commands/trio" ] && { printf 'FAIL cmd link still present\n' >&2; exit 1; }
superpowers_after=$(ls "$h/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills" | sort)
assert_eq "$superpowers_after" "$superpowers_before" 'uninstall does not touch superpowers'

# uninstall 链接不属于本 repo 不删
mkdir -p "$h/.claude/skills"
ln -s "/other/repo/skills/trio-orchestrator" "$h/.claude/skills/trio-orchestrator"
HOME="$h" "$REPO/scripts/uninstall.sh" >/dev/null
[ -L "$h/.claude/skills/trio-orchestrator" ] || { printf 'FAIL uninstall removed foreign link\n' >&2; exit 1; }

printf 'install tests: OK\n'
