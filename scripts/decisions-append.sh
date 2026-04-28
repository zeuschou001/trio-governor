#!/usr/bin/env bash
set -euo pipefail

[ "$#" -eq 6 ] || {
  printf '用法: %s <宿主项目目录> <type> <title> <what> <why> <impact>\n' "${0##*/}" >&2
  exit 2
}

REPO_ABS=$(cd "$(dirname "$0")/.." && pwd)
exec "$REPO_ABS/scripts/trio-runtime.sh" decision-append "$@"
