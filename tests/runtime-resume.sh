#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_line() {
  local file="$1" pattern="$2" label="$3"
  grep -q "$pattern" "$file" || { printf 'FAIL %s\n' "$label" >&2; cat "$file" >&2; exit 1; }
}

h=$(mktemp -d)
(cd "$h" && git init -q .)
"$REPO/trio" runtime bootstrap --mode dev "$h" >/dev/null

stdout=$(mktemp)
"$REPO/trio" runtime status "$h" >"$stdout"
assert_line "$stdout" '^RESUME_AVAILABLE=1$' 'resume available before restart'

legacy="$h/.trio/STATE.legacy"
grep -v '^mode: ' "$h/.trio/STATE.md" | grep -v '^status: ' >"$legacy"
mv "$legacy" "$h/.trio/STATE.md"
"$REPO/trio" runtime status "$h" >"$stdout"
grep -q '^mode: dev$' "$h/.trio/STATE.md" || { printf 'FAIL legacy upgrade mode\n' >&2; exit 1; }
grep -q '^status: running$' "$h/.trio/STATE.md" || { printf 'FAIL legacy upgrade status\n' >&2; exit 1; }
grep -q '^adapter_mode: full$' "$h/.trio/STATE.md" || { printf 'FAIL legacy upgrade adapter mode\n' >&2; exit 1; }
grep -q '^ceo_review_forced: 0$' "$h/.trio/STATE.md" || { printf 'FAIL legacy upgrade ceo review forced\n' >&2; exit 1; }

"$REPO/trio" runtime restart "$h" >"$stdout"
assert_line "$stdout" '^MODE=dev$' 'restart mode'
assert_line "$stdout" '^STATUS=running$' 'restart status'
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'restart phase'
assert_line "$stdout" '^ADAPTER_MODE=full$' 'restart adapter mode'
assert_line "$stdout" '^CEO_REVIEW_FORCED=0$' 'restart ceo review forced'
archive_path=$(sed -n 's/^ARCHIVED_STATE=//p' "$stdout" | head -n 1)
[ -n "$archive_path" ] || { printf 'FAIL restart archive path missing\n' >&2; cat "$stdout" >&2; exit 1; }
[ -f "$archive_path" ] || { printf 'FAIL restart archive not created: %s\n' "$archive_path" >&2; exit 1; }
grep -q '^completed_phases: \[\]$' "$h/.trio/STATE.md" || { printf 'FAIL restart completed phases reset\n' >&2; exit 1; }

"$REPO/trio" runtime abort "$h" >"$stdout"
assert_line "$stdout" '^STATUS=aborted$' 'abort status'
"$REPO/trio" runtime status "$h" >"$stdout"
assert_line "$stdout" '^STATUS=aborted$' 'status after abort'
if grep -q '^RESUME_AVAILABLE=' "$stdout"; then
  printf 'FAIL aborted session should not be resumable\n' >&2
  cat "$stdout" >&2
  exit 1
fi

h2=$(mktemp -d)
(cd "$h2" && git init -q .)
"$REPO/trio" runtime bootstrap --mode quick "$h2" >/dev/null
"$REPO/trio" runtime bootstrap --mode dev "$h2" >"$stdout" 2>"$stdout.stderr"
assert_line "$stdout" '^MODE=quick$' 'cross-mode bootstrap preserves resumable mode'
assert_line "$stdout.stderr" 'restart --mode dev' 'cross-mode bootstrap hint'
"$REPO/trio" runtime restart --mode dev "$h2" >"$stdout"
assert_line "$stdout" '^MODE=dev$' 'cross-mode restart mode'
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'cross-mode restart phase'
assert_line "$stdout" '^ADAPTER_MODE=full$' 'cross-mode restart adapter mode'
[ -f "$h2/.trio/PROJECT.md" ] || { printf 'FAIL cross-mode restart should create PROJECT.md\n' >&2; exit 1; }
[ -f "$h2/.trio/DECISIONS.md" ] || { printf 'FAIL cross-mode restart should create DECISIONS.md\n' >&2; exit 1; }
[ -f "$h2/.trio/ROADMAP.md" ] || { printf 'FAIL cross-mode restart should create ROADMAP.md\n' >&2; exit 1; }

h3=$(mktemp -d)
(cd "$h3" && git init -q .)
"$REPO/trio" runtime bootstrap --mode quick "$h3" >/dev/null
"$REPO/trio" runtime abort "$h3" >/dev/null
"$REPO/trio" runtime bootstrap --mode dev --adapter-mode minimal --ceo-review-forced 1 "$h3" >"$stdout"
assert_line "$stdout" '^MODE=dev$' 'terminal cross-mode bootstrap resets mode'
assert_line "$stdout" '^CURRENT_PHASE=office-hours$' 'terminal cross-mode bootstrap phase'
assert_line "$stdout" '^ADAPTER_MODE=minimal$' 'terminal cross-mode bootstrap adapter mode'
assert_line "$stdout" '^CEO_REVIEW_FORCED=1$' 'terminal cross-mode bootstrap ceo review forced'

printf 'runtime-resume tests: OK\n'
