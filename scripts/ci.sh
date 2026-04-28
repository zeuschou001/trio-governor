#!/usr/bin/env bash
set -euo pipefail

REPO_ABS=$(cd "$(dirname "$0")/.." && pwd)

"$REPO_ABS/scripts/measure-tokens.sh"

for t in "$REPO_ABS"/tests/*.sh; do
  [ -f "$t" ] || continue
  printf '\n=== %s ===\n' "$(basename "$t")"
  bash "$t"
done

printf '\nCI 全部通过\n'
