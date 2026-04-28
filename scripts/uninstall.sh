#!/usr/bin/env bash
set -euo pipefail

REPO_ABS=$(cd "$(dirname "$0")/.." && pwd)

remove_link() {
  local path="$1" target="$2"
  [ -L "$path" ] || return 0
  if [ "$(readlink "$path")" = "$target" ]; then
    rm "$path"
  fi
}

remove_link "$HOME/.claude/skills/trio-orchestrator" "$REPO_ABS/skills/trio-orchestrator"
remove_link "$HOME/.claude/commands/trio" "$REPO_ABS/commands/trio"
