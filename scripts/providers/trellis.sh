#!/usr/bin/env bash

provider_id() { printf 'trellis\n'; }
provider_kind() { printf 'memory-bridge\n'; }
provider_availability() { printf 'experimental\n'; }
provider_invoke_mode() { printf 'export-only\n'; }
provider_capabilities() { printf '%s\n' 'spec-export state-export memory-sync'; }

provider_detect() {
  local status='absent' version='absent'
  if command -v trellis >/dev/null 2>&1; then
    status='available'
    version='present'
  fi
  printf 'PROVIDER_ID=%s\n' "$(provider_id)"
  printf 'PROVIDER_STATUS=%s\n' "$status"
  printf 'PROVIDER_VERSION=%s\n' "$version"
  printf 'PROVIDER_SELECTABLE=%s\n' "$(provider_selectable)"
}

provider_version() { printf 'unknown\n'; }
provider_supports() {
  case "$1" in
    spec-export|state-export|memory-sync) return 0 ;;
    *) return 1 ;;
  esac
}
provider_entrypoints_for() { printf '%s\n' '-'; }
provider_writer_boundary_for() { printf '%s\n' '-'; }
provider_state_policy() { printf 'export-only\n'; }
provider_install_hint() { printf '%s\n' '安装 trellis CLI 后再启用 bridge'; }
provider_selectable() { printf '0\n'; }
provider_bridge_command_hint() { printf '%s\n' 'manual-handoff'; }
provider_bridge_handoff_markdown() {
  local export_dir="$1" outputs_dir="$2"
  cat <<EOF
## Trellis Handoff

- 把这个目录视为一次外部记忆 / 规格整理包,而不是 trio 会话本体。
- 建议映射:
  - PROJECT.md -> 项目目标与边界
  - DECISIONS.md -> 已确认决策与约束
  - ROADMAP.md -> 当前计划与任务结构
  - KNOWLEDGE.md -> 累积上下文 / 经验
  - STATE.md -> trio 当前阶段与 ownership 信号

## 建议产出

- $(basename "$outputs_dir")/spec-summary.md: 外部整理后的规格摘要
- $(basename "$outputs_dir")/task-graph.md: 重组后的任务图或执行建议
- $(basename "$outputs_dir")/memory-notes.md: 可回流 trio 的长期知识点

## 回流约束

- 不要把 Trellis 生成的状态结构直接映射回 trio STATE.md。
- 如果外部整理产出值得保留,应由开发者选择性写回 ROADMAP.md、DECISIONS.md、KNOWLEDGE.md。
- trio 继续拥有流程推进权; Trellis 只负责外部整理与补强。
EOF
}
provider_bridge_review_catalog() {
  cat <<'EOF'
spec-summary.md|decision-candidate|decision-append|外部规格摘要可能需要提炼为决策约束
task-graph.md|roadmap-rewrite-candidate|roadmap-rewrite|外部任务图可能适合人工确认后回写 ROADMAP
memory-notes.md|knowledge-candidate|knowledge-append|外部记忆整理可沉淀为 KNOWLEDGE
EOF
}
