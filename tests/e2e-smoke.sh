#!/usr/bin/env bash
# 编排原语级端到端冒烟:在隔离 HOME 中模拟 /trio:dev 与 /trio:quick 的阶段序列,
# 验证依赖探测、状态契约、决策追加、硬门禁状态检查等原语组合可用。
# 非 Claude 侧真实 /trio:dev —— 那个需要用户在 Claude Code 里显式触发。
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
MOCK_HOME=$(mktemp -d)
HOST=$(mktemp -d)
trap 'rm -rf "$MOCK_HOME" "$HOST"' EXIT

# 准备 mock ~/.claude:Superpowers 5.0.7 + 4 个 gstack skill
mkdir -p "$MOCK_HOME/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills"
for s in writing-plans executing-plans test-driven-development verification-before-completion finishing-a-development-branch; do
  mkdir -p "$MOCK_HOME/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/$s"
  echo "stub" > "$MOCK_HOME/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/$s/SKILL.md"
done
for s in office-hours plan-ceo-review plan-eng-review qa; do
  mkdir -p "$MOCK_HOME/.claude/skills/$s"
  printf -- '---\nname: %s\n---\n' "$s" > "$MOCK_HOME/.claude/skills/$s/SKILL.md"
done

# 宿主项目为 git repo
(cd "$HOST" && git init -q .)

printf '[1/5] 依赖探测(dev 路径)\n'
HOME="$MOCK_HOME" "$REPO/scripts/detect-deps.sh" > /tmp/trio-e2e-deps 2>&1
grep -q 'SUPERPOWERS_VERSION=5.0.7' /tmp/trio-e2e-deps

printf '[2/5] dev 初始化 .trio/(9 阶段分支)\n'
"$REPO/scripts/trio-init.sh" "$HOST" >/dev/null
for f in PROJECT.md DECISIONS.md KNOWLEDGE.md ROADMAP.md STATE.md .trio-signature; do
  [ -f "$HOST/.trio/$f" ] || { printf 'FAIL 缺少 %s\n' "$f" >&2; exit 1; }
done
grep -q '^mode: dev$' "$HOST/.trio/STATE.md"
grep -q '^status: running$' "$HOST/.trio/STATE.md"
grep -q '^current_phase: office-hours$' "$HOST/.trio/STATE.md"

printf '[3/5] 硬门禁前:DECISIONS.md 无 eng-review 条目(模板为空骨架)\n'
count_before=$(grep -c '^## Decision: ' "$HOST/.trio/DECISIONS.md" || true)
[ "$count_before" = "0" ] || { printf 'FAIL 初始 DECISIONS.md 应为空骨架, 实际=%s\n' "$count_before" >&2; exit 1; }

printf '[4/5] 追加 eng-review 决策 → 硬门禁状态变可通过\n'
"$REPO/scripts/decisions-append.sh" "$HOST" eng-review "引入 .trio 契约" "拆 5 文件" "降低 context rot" "影响所有阶段"
grep -q '^- \*\*Type\*\*: eng-review$' "$HOST/.trio/DECISIONS.md"

printf '[5/5] quick 旁路:独立 host,仅创建 3 文件\n'
HOST2=$(mktemp -d)
(cd "$HOST2" && git init -q .)
"$REPO/scripts/trio-init.sh" --quick "$HOST2" >/dev/null
[ -f "$HOST2/.trio/STATE.md" ] && [ -f "$HOST2/.trio/KNOWLEDGE.md" ] && [ -f "$HOST2/.trio/.trio-signature" ]
[ ! -f "$HOST2/.trio/PROJECT.md" ] && [ ! -f "$HOST2/.trio/DECISIONS.md" ] && [ ! -f "$HOST2/.trio/ROADMAP.md" ]
grep -q '^mode: quick$' "$HOST2/.trio/STATE.md"
grep -q '^status: awaiting-start-confirmation$' "$HOST2/.trio/STATE.md"
grep -q '^current_phase: quick-writing-plans$' "$HOST2/.trio/STATE.md"
rm -rf "$HOST2"

printf '端到端冒烟: OK\n'
printf '备注:完整 /trio:dev 与 /trio:quick 由 Claude Code 解释 SKILL.md 驱动,需重启后在目标宿主项目手动触发;本脚本仅验证其底层脚本原语组合可用。\n'
