#!/usr/bin/env bash
set -euo pipefail

REPO_ABS=$(cd "$(dirname "$0")/.." && pwd)

ensure_link() {
  local path="$1" target="$2" cur=''
  if [ -L "$path" ]; then
    cur="$(readlink "$path")"
    [ "$cur" = "$target" ] && return 0
    rm "$path"
    ln -s "$target" "$path"
    return 0
  fi
  if [ -e "$path" ]; then
    printf '安装失败:%s 已存在且不是符号链接\n' "$path" >&2
    exit 1
  fi
  ln -s "$target" "$path"
}

"$REPO_ABS/scripts/detect-deps.sh" "$@" >/dev/null
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/commands"
ensure_link "$HOME/.claude/skills/trio-orchestrator" "$REPO_ABS/skills/trio-orchestrator"
ensure_link "$HOME/.claude/commands/trio" "$REPO_ABS/commands/trio"
printf '安装完成,请重启 Claude Code\n'
