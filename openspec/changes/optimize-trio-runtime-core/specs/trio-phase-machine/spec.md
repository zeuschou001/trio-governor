## Scope

本规格定义 `trio` 的内部实现边界,用于保证治理规则可执行。它不定义主要用户表面,也不要求用户理解其中的内部术语、阶段名称或驱动命令。用户可见能力由 `trio-governor` 产品规格定义。

本规格关注合法 transition、guard 和 gate enforcement 的内部状态推进规则。

## ADDED Requirements

### Requirement: Dev Phase Graph

系统 MUST 为完整开发流程维护唯一合法的 dev phase graph。

#### Scenario: dev 路径采用固定阶段顺序
- **WHEN** 用户启动完整开发流程
- **THEN** 系统 MUST 按以下顺序推进阶段:
  `office-hours -> plan-ceo-review? -> plan-eng-review -> state-sync -> writing-plans -> executing-plans -> verification-before-completion -> qa -> finishing-a-development-branch`

#### Scenario: plan-ceo-review 为条件阶段
- **WHEN** 当前任务满足 CEO review 条件
- **THEN** 系统 MAY 将 `plan-ceo-review` 纳入当前 dev 路径
- **AND** 若条件不满足,系统 MUST 直接从 `office-hours` 进入 `plan-eng-review`

#### Scenario: state-sync 不得被绕过
- **WHEN** `plan-eng-review` 已结束
- **THEN** 系统 MUST 先进入 `state-sync`
- **AND** MUST NOT 直接进入 `writing-plans`

### Requirement: Quick Phase Graph

系统 MUST 为小任务流程维护独立的 quick phase graph,并与 dev 命名空间严格隔离。

#### Scenario: quick 路径采用固定三阶段顺序
- **WHEN** 用户启动 quick 流程
- **THEN** 系统 MUST 按以下顺序推进阶段:
  `quick-writing-plans -> quick-executing-plans -> quick-verification-before-completion`

#### Scenario: quick 首阶段执行前存在启动 guard
- **WHEN** quick 会话刚被创建或重建
- **AND** 其 `quick_streak=0`
- **THEN** 系统 MUST 在执行 `quick-writing-plans` 前先停在启动 guard
- **AND** 该 guard 通过后 MUST 回到同一个 `quick-writing-plans` 执行点

#### Scenario: quick 会话不得写入 dev phase
- **WHEN** 当前会话 `mode=quick`
- **THEN** 系统 MUST 拒绝任何 dev phase 写入或推进

#### Scenario: quick 最终阶段确认后完成会话
- **WHEN** `quick-verification-before-completion` 完成并被确认通过
- **THEN** 系统 MUST 将会话标记为 `completed`

### Requirement: Transition Actions

系统 MUST 以有限动作集合维护 phase 推进,而不是允许调用方直接改写 phase 状态。

#### Scenario: start-guard-yes 解锁 quick 首阶段执行
- **WHEN** 当前状态为 `awaiting-start-confirmation`
- **THEN** 系统 MUST 接受 `start-guard-yes`
- **AND** MUST 将会话状态改为 `running`
- **AND** MUST 保持 `current_phase=quick-writing-plans`

#### Scenario: stage-finished 仅进入待确认态
- **WHEN** 某一阶段执行结束
- **THEN** 系统 MUST 将会话状态改为 `awaiting-confirmation`
- **AND** MUST 保持 `current_phase` 不变

#### Scenario: confirm-yes 推进到唯一合法后继
- **WHEN** 当前状态为 `awaiting-confirmation` 且调用方确认通过
- **THEN** 系统 MUST 将当前 phase 追加到 `completed_phases`
- **AND** MUST 将 `current_phase` 推进到唯一合法后继
- **AND** 若当前 phase 已是终态,则 MUST 将会话标记为 `completed`

#### Scenario: 可选下游阶段可被显式省略
- **WHEN** 当前状态为 `awaiting-confirmation`
- **AND** 当前阶段的唯一后继是显式 optional 阶段
- **AND** 调用方已确定当前路径不纳入该 optional 阶段
- **THEN** 系统 MAY 接受 `confirm-yes-skip-optional-next`
- **AND** MUST 将当前 phase 追加到 `completed_phases`
- **AND** MUST 直接推进到该 optional 阶段之后的唯一合法后继

#### Scenario: confirm-no 重试当前阶段
- **WHEN** 当前状态为 `awaiting-confirmation` 且调用方选择重试
- **THEN** 系统 MUST 将会话状态改回 `running`
- **AND** MUST 保持 `current_phase` 不变

#### Scenario: confirm-skip 仅对可选阶段合法
- **WHEN** 当前 phase 不是显式可跳过的可选阶段
- **THEN** 系统 MUST 拒绝 `confirm-skip`

#### Scenario: abort 可显式终止非终态会话
- **WHEN** 当前会话尚未进入 `completed` 或 `aborted`
- **THEN** 系统 MAY 接受 `abort`
- **AND** MUST 将会话写为 `aborted`

### Requirement: Confirmation Semantics

系统 MUST 将阶段推进与用户确认显式绑定,禁止隐式推进。

#### Scenario: quick 启动 guard 未通过前不得执行首阶段
- **WHEN** 当前状态为 `awaiting-start-confirmation`
- **THEN** 系统 MUST NOT 执行 `quick-writing-plans`
- **AND** MUST 仅接受 guard 合同定义的输入

#### Scenario: 未确认不得推进
- **WHEN** 某一阶段刚执行结束但尚未收到合法确认
- **THEN** 系统 MUST NOT 推进到下一阶段

#### Scenario: 非白名单输入不得产生默认动作
- **WHEN** 调用方提供非法确认动作
- **THEN** 系统 MUST 拒绝该动作
- **AND** MUST 保持当前状态不变

#### Scenario: 终态阶段的确认写入 completed
- **WHEN** 当前 phase 为当前 mode 的最后一个合法 phase 且确认通过
- **THEN** 系统 MUST 将会话状态写为 `completed`

### Requirement: Gate Enforcement

系统 MUST 在 phase machine 内显式维护门禁,而不是依赖 prompt 层约定俗成。

#### Scenario: 缺少 eng-review 证据时拒绝进入 writing-plans
- **WHEN** 系统在 `plan-eng-review` 之后进行 gate-check
- **THEN** 若 `DECISIONS.md` 中缺少合法的 `eng-review` 结构化证据
- **THEN** 系统 MUST 拒绝进入 `writing-plans`

#### Scenario: state-sync 失败时不得继续下游阶段
- **WHEN** `state-sync` 未成功完成
- **THEN** 系统 MUST 拒绝推进到 `writing-plans`

#### Scenario: qa 可报告漂移但不重写阶段图
- **WHEN** `qa` 发现决策与实现漂移
- **THEN** 系统 MAY 报告风险
- **AND** MUST NOT 擅自重写 phase graph 规则

### Requirement: Phase Namespace Integrity

系统 MUST 保证 phase 命名空间和完成历史的完整性。

#### Scenario: 非白名单 phase 拒绝写入
- **WHEN** 调用方尝试写入未声明的 phase id
- **THEN** 系统 MUST 硬失败

#### Scenario: completed_phases 不得跨 mode 混用
- **WHEN** 当前会话 `mode=dev`
- **THEN** `completed_phases` MUST NOT 包含 `quick-*` 阶段
- **AND** 反之亦然

#### Scenario: completed_phases 必须单调追加
- **WHEN** 系统更新 `completed_phases`
- **THEN** 系统 MUST 仅允许追加合法已完成阶段
- **AND** MUST NOT 删除、重排或回写历史项
