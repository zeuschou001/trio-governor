#!/usr/bin/env bash

provider_id() { printf 'gsd2\n'; }
provider_kind() { printf 'workflow-bridge\n'; }
provider_availability() { printf 'experimental\n'; }
provider_invoke_mode() { printf 'command\n'; }
provider_capabilities() { printf 'external-subflow\n'; }

provider_detect() {
  local status='absent' version='absent' bin=''
  for bin in gsd gsd-pi; do
    if command -v "$bin" >/dev/null 2>&1; then
      status='available'
      version='present'
      break
    fi
  done
  printf 'PROVIDER_ID=%s\n' "$(provider_id)"
  printf 'PROVIDER_STATUS=%s\n' "$status"
  printf 'PROVIDER_VERSION=%s\n' "$version"
  printf 'PROVIDER_SELECTABLE=%s\n' "$(provider_selectable)"
}

provider_version() { printf 'unknown\n'; }
provider_supports() { [ "$1" = 'external-subflow' ]; }
provider_entrypoints_for() { printf '%s\n' '-'; }
provider_writer_boundary_for() { printf '%s\n' '-'; }
provider_state_policy() { printf 'export-only\n'; }
provider_install_hint() { printf '%s\n' '安装 gsd2 CLI 后再启用 bridge'; }
provider_selectable() { printf '0\n'; }
provider_bridge_command_hint() { printf '%s\n' 'manual-handoff'; }
provider_bridge_handoff_markdown() {
  local export_dir="$1" outputs_dir="$2"
  cat <<EOF
## GSD 2 Handoff

- 把这个目录当成一次隔离子流程的只读输入快照。
- 优先阅读 STATE.md、ROADMAP.md、KNOWLEDGE.md; 若存在 PROJECT.md 与 DECISIONS.md,再补齐目标与约束。
- 不要尝试延续 trio phase,也不要改写任何导出文件。

## 建议产出

- $(basename "$outputs_dir")/subflow-summary.md: 子流程目标、范围与结果摘要
- $(basename "$outputs_dir")/patch-plan.md: 建议改动面、风险点与验证方式
- $(basename "$outputs_dir")/followups.md: 若需回流 trio,列出建议补写到 DECISIONS / KNOWLEDGE / ROADMAP 的内容

## 回流约束

- STATE.md 仍由 trio runtime 独占。
- 如果外部子流程形成决策或知识结论,应由开发者回到 trio runtime writer 落盘,而不是覆盖这个 export 目录。
- 这个 export 目录更适合做“分支调查 / 方案草拟 / 局部执行计划”,不适合让 GSD 2 接管主流程。
EOF
}
provider_bridge_review_catalog() {
  cat <<'EOF'
subflow-summary.md|decision-candidate|decision-append|子流程摘要可能需要提炼为决策或实现结论
patch-plan.md|roadmap-rewrite-candidate|roadmap-rewrite|局部执行计划可能适合人工确认后回写 ROADMAP
followups.md|knowledge-candidate|knowledge-append|后续项与经验结论可沉淀到 KNOWLEDGE
EOF
}
