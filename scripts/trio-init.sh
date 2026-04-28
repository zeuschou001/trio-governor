#!/usr/bin/env bash
set -euo pipefail

usage() { printf '用法: %s [--quick] <宿主项目目录>\n' "${0##*/}" >&2; }

mode=dev
if [ "$#" -eq 2 ] && [ "$1" = '--quick' ]; then
  mode=quick
  shift
fi
[ "$#" -eq 1 ] || { usage; exit 2; }

REPO_ABS=$(cd "$(dirname "$0")/.." && pwd)
exec "$REPO_ABS/scripts/trio-runtime.sh" bootstrap --mode "$mode" "$1"
