#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

h=$(mktemp -d)
(cd "$h" && git init -q .)
"$REPO/trio" runtime bootstrap --mode dev "$h" >/dev/null

"$REPO/trio" runtime project-write "$h" "trio-dev" "internal-tool" "runtime writers smoke" >/dev/null
grep -q '^name: "trio-dev"$' "$h/.trio/PROJECT.md" || { printf 'FAIL project name\n' >&2; exit 1; }
grep -q '^type: "internal-tool"$' "$h/.trio/PROJECT.md" || { printf 'FAIL project type\n' >&2; exit 1; }
grep -q '^description: "runtime writers smoke"$' "$h/.trio/PROJECT.md" || { printf 'FAIL project description\n' >&2; exit 1; }

if "$REPO/trio" runtime project-write "$h" "again" "again" "again" >/dev/null 2>&1; then
  printf 'FAIL project-write should seal frontmatter\n' >&2
  exit 1
fi

"$REPO/trio" runtime knowledge-append "$h" "锁语义" "bootstrap" "runtime 负责唯一 writer" >/dev/null
grep -q '^## Insight: 锁语义$' "$h/.trio/KNOWLEDGE.md" || { printf 'FAIL knowledge title\n' >&2; exit 1; }
grep -q '^- \*\*Takeaway\*\*: runtime 负责唯一 writer$' "$h/.trio/KNOWLEDGE.md" || { printf 'FAIL knowledge takeaway\n' >&2; exit 1; }

printf '# New roadmap\n- step 1\n' | "$REPO/trio" runtime roadmap-rewrite "$h" -- >/dev/null
grep -q '^# New roadmap$' "$h/.trio/ROADMAP.md" || { printf 'FAIL roadmap rewrite\n' >&2; exit 1; }
ls "$h/.trio/archive"/ROADMAP-*.md >/dev/null 2>&1 || { printf 'FAIL roadmap archive\n' >&2; exit 1; }

printf 'runtime-writers tests: OK\n'
