#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

assert_count() {
  local file="$1" pattern="$2" want="$3" label="$4"
  local got; got=$(grep -c "$pattern" "$file" || true)
  [ "$got" = "$want" ] || { printf 'FAIL %s: want=%s got=%s\n' "$label" "$want" "$got" >&2; exit 1; }
}

# 准备 host
h=$(mktemp -d); (cd "$h" && git init -q .)
"$REPO/scripts/trio-init.sh" "$h" >/dev/null

# 初始模板不含任何 ## Decision: 条目
initial=$(grep -c '^## Decision: ' "$h/.trio/DECISIONS.md" || true)
[ "$initial" = "0" ] || { printf 'FAIL 初始 DECISIONS.md 应无示例 Decision 条目, 实际=%s\n' "$initial" >&2; exit 1; }

# 追加一条 eng-review
"$REPO/scripts/decisions-append.sh" "$h" eng-review "解耦模块" "拆 A 与 B" "降低耦合" "影响 C"
assert_count "$h/.trio/DECISIONS.md" '^## Decision: 解耦模块$' 1 'first append count'
grep -q '^- \*\*Type\*\*: eng-review$' "$h/.trio/DECISIONS.md" || { printf 'FAIL type field\n' >&2; exit 1; }
grep -q '^- \*\*What\*\*: 拆 A 与 B$' "$h/.trio/DECISIONS.md" || { printf 'FAIL what field\n' >&2; exit 1; }

# 5s 内重复同标题+类型 → 去重
out=$("$REPO/scripts/decisions-append.sh" "$h" eng-review "解耦模块" "拆 A 与 B" "降低耦合" "影响 C" 2>&1)
[[ "$out" == *'检测到重复决策条目'* ]] || { printf 'FAIL dedup msg: %s\n' "$out" >&2; exit 1; }
assert_count "$h/.trio/DECISIONS.md" '^## Decision: 解耦模块$' 1 'still one after dedup'

# 不同 Type 不去重
"$REPO/scripts/decisions-append.sh" "$h" ceo-review "解耦模块" "产品视角确认" "用户侧不感知" "仅内部重构"
assert_count "$h/.trio/DECISIONS.md" '^## Decision: 解耦模块$' 2 'different Type appends'
assert_count "$h/.trio/DECISIONS.md" '^- \*\*Type\*\*: ceo-review$' 1 'ceo-review count'

# 不同 Title 不去重
"$REPO/scripts/decisions-append.sh" "$h" eng-review "升级依赖" "升级 X" "修复 CVE" "影响 Y"
assert_count "$h/.trio/DECISIONS.md" '^## Decision: 升级依赖$' 1 'different Title appends'

# 5s 之后可再次追加
sleep 6
"$REPO/scripts/decisions-append.sh" "$h" eng-review "解耦模块" "拆 A 与 B" "降低耦合" "影响 C"
assert_count "$h/.trio/DECISIONS.md" '^## Decision: 解耦模块$' 3 'after 5s append works'

# 非法 type → 退出码 2
if "$REPO/scripts/decisions-append.sh" "$h" bogus "T" "w" "y" "i" >/dev/null 2>&1; then
  printf 'FAIL bogus type accepted\n' >&2; exit 1
fi

# 无 DECISIONS.md (quick 初始化) → 退出码 1
h2=$(mktemp -d); (cd "$h2" && git init -q .)
"$REPO/scripts/trio-init.sh" --quick "$h2" >/dev/null
if "$REPO/scripts/decisions-append.sh" "$h2" eng-review "T" "w" "y" "i" >/dev/null 2>&1; then
  printf 'FAIL quick host should reject decisions append\n' >&2; exit 1
fi

printf 'decisions-protocol tests: OK\n'
