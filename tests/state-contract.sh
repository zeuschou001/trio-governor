#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_eq() { [ "$1" = "$2" ] || { printf 'FAIL %s: want=%s got=%s\n' "$3" "$2" "$1" >&2; exit 1; }; }

check_sig_strict() {
  python3 -c '
import re, sys
b = open(sys.argv[1], "rb").read()
r = rb"^trio-dev v[0-9]+\.[0-9]+\.[0-9]+ initialized at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\n$"
sys.exit(0 if re.match(r, b) else 1)
' "$1"
}

# 非 git 宿主 → 退出码 4
h=$(mktemp -d)
if "$REPO/scripts/trio-init.sh" "$h" >/dev/null 2>&1; then
  printf 'FAIL non-git should exit 4\n' >&2; exit 1
fi
ec=$("$REPO/scripts/trio-init.sh" "$h" >/dev/null 2>&1; echo $?)
assert_eq "$ec" "4" 'non-git exit code'

# 首次初始化生成 .trio/ 与 5 文件
h=$(mktemp -d); (cd "$h" && git init -q .)
"$REPO/scripts/trio-init.sh" "$h" >/dev/null
for f in .trio-signature PROJECT.md DECISIONS.md KNOWLEDGE.md ROADMAP.md STATE.md; do
  [ -f "$h/.trio/$f" ] || { printf 'FAIL missing .trio/%s\n' "$f" >&2; exit 1; }
done

# 签名正则校验(包含 trailing LF)
check_sig_strict "$h/.trio/.trio-signature" || { printf 'FAIL signature regex(含 LF)\n' >&2; exit 1; }

# 签名无 trailing LF → 应被拒收
h2=$(mktemp -d); (cd "$h2" && git init -q .)
mkdir -p "$h2/.trio"
printf 'trio-dev v0.1.0 initialized at 2026-04-18T00:00:00Z' > "$h2/.trio/.trio-signature"
out=$("$REPO/scripts/trio-init.sh" "$h2" 2>&1 && echo "EXIT0" || echo "EXIT$?")
[[ "$out" == *'EXIT1'* ]] || { printf 'FAIL missing LF should be rejected: %s\n' "$out" >&2; exit 1; }

# 权限 0755 / 0644
dir_perm=$(stat -f '%Lp' "$h/.trio" 2>/dev/null || stat -c '%a' "$h/.trio")
assert_eq "$dir_perm" "755" '.trio dir perm'
file_perm=$(stat -f '%Lp' "$h/.trio/PROJECT.md" 2>/dev/null || stat -c '%a' "$h/.trio/PROJECT.md")
assert_eq "$file_perm" "644" 'PROJECT.md perm'

# 二次调用(签名有效)应为 no-op:文件 mtime 不变
sleep 1
mtime_before=$(stat -f '%m' "$h/.trio/PROJECT.md" 2>/dev/null || stat -c '%Y' "$h/.trio/PROJECT.md")
"$REPO/scripts/trio-init.sh" "$h" >/dev/null
mtime_after=$(stat -f '%m' "$h/.trio/PROJECT.md" 2>/dev/null || stat -c '%Y' "$h/.trio/PROJECT.md")
assert_eq "$mtime_after" "$mtime_before" 'reinit mtime unchanged'

# 缺失签名 → 硬失败
h=$(mktemp -d); (cd "$h" && git init -q .)
mkdir -p "$h/.trio"
echo "existing" > "$h/.trio/random.md"
out=$("$REPO/scripts/trio-init.sh" "$h" 2>&1 && echo "EXIT0" || echo "EXIT$?")
[[ "$out" == *'非本插件管理'* ]] || { printf 'FAIL missing sig msg: %s\n' "$out" >&2; exit 1; }
[[ "$out" == *'EXIT1'* ]] || { printf 'FAIL missing sig exit: %s\n' "$out" >&2; exit 1; }

# 签名非法 → 硬失败
h=$(mktemp -d); (cd "$h" && git init -q .)
mkdir -p "$h/.trio"; echo "garbage" > "$h/.trio/.trio-signature"
out=$("$REPO/scripts/trio-init.sh" "$h" 2>&1 && echo "EXIT0" || echo "EXIT$?")
[[ "$out" == *'EXIT1'* ]] || { printf 'FAIL bad sig exit: %s\n' "$out" >&2; exit 1; }

# 崩溃恢复:删除 KNOWLEDGE.md 后 reinit 自动补齐
h=$(mktemp -d); (cd "$h" && git init -q .)
"$REPO/scripts/trio-init.sh" "$h" >/dev/null
rm "$h/.trio/KNOWLEDGE.md"
out=$("$REPO/scripts/trio-init.sh" "$h" 2>&1)
[[ "$out" == *'自动补齐'*'KNOWLEDGE.md'* ]] || { printf 'FAIL crash recovery msg: %s\n' "$out" >&2; exit 1; }
[ -f "$h/.trio/KNOWLEDGE.md" ] || { printf 'FAIL KNOWLEDGE.md not restored\n' >&2; exit 1; }

# quick lazy-init 只建 3 文件
h=$(mktemp -d); (cd "$h" && git init -q .)
"$REPO/scripts/trio-init.sh" --quick "$h" >/dev/null
[ -f "$h/.trio/.trio-signature" ] || { printf 'FAIL quick sig\n' >&2; exit 1; }
[ -f "$h/.trio/STATE.md" ] || { printf 'FAIL quick STATE\n' >&2; exit 1; }
[ -f "$h/.trio/KNOWLEDGE.md" ] || { printf 'FAIL quick KNOWLEDGE\n' >&2; exit 1; }
[ ! -f "$h/.trio/PROJECT.md" ] || { printf 'FAIL quick should not create PROJECT\n' >&2; exit 1; }
[ ! -f "$h/.trio/DECISIONS.md" ] || { printf 'FAIL quick should not create DECISIONS\n' >&2; exit 1; }
[ ! -f "$h/.trio/ROADMAP.md" ] || { printf 'FAIL quick should not create ROADMAP\n' >&2; exit 1; }

# quick STATE.md 初始 phase = quick-writing-plans
grep -q '^current_phase: quick-writing-plans$' "$h/.trio/STATE.md" || { printf 'FAIL quick phase\n' >&2; exit 1; }
grep -q '^mode: quick$' "$h/.trio/STATE.md" || { printf 'FAIL quick mode\n' >&2; exit 1; }
grep -q '^status: awaiting-start-confirmation$' "$h/.trio/STATE.md" || { printf 'FAIL quick status\n' >&2; exit 1; }
grep -q '^adapter_mode: minimal$' "$h/.trio/STATE.md" || { printf 'FAIL quick adapter mode\n' >&2; exit 1; }
grep -q '^ceo_review_forced: 0$' "$h/.trio/STATE.md" || { printf 'FAIL quick ceo review forced\n' >&2; exit 1; }

# dev STATE.md 包含显式 mode/status
grep -q '^mode: dev$' "$REPO/templates/trio-state/STATE.md.tmpl" || { printf 'FAIL template mode field\n' >&2; exit 1; }
grep -q '^status: running$' "$REPO/templates/trio-state/STATE.md.tmpl" || { printf 'FAIL template status field\n' >&2; exit 1; }
grep -q '^adapter_mode: full$' "$REPO/templates/trio-state/STATE.md.tmpl" || { printf 'FAIL template adapter mode field\n' >&2; exit 1; }
grep -q '^ceo_review_forced: 0$' "$REPO/templates/trio-state/STATE.md.tmpl" || { printf 'FAIL template ceo review forced field\n' >&2; exit 1; }

printf 'state-contract tests: OK\n'
