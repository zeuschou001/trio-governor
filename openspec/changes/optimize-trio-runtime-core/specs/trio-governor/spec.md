## ADDED Requirements

### Requirement: Single Conversational Entry

系统 MUST 以单一对话入口承载主要产品表面,而不是要求用户先学习多个模式命令。

#### Scenario: `/trio` 作为主要入口
- **WHEN** 用户要开始一个开发任务
- **THEN** 系统 MUST 允许用户直接通过 `/trio <需求>` 描述目标
- **AND** MUST 由系统自行判断更适合 `quick` 还是 `dev`

#### Scenario: 仅在必要时追问
- **WHEN** 用户已经给出足够的目标与范围
- **THEN** 系统 MUST 直接进入治理判断与内部流程
- **AND** MUST NOT 为了暴露模式或内部步骤而额外追问

#### Scenario: 显式模式入口仅作兼容面
- **WHEN** 调用方仍使用显式 `dev` 或 `quick` 入口
- **THEN** 系统 MAY 将其视为兼容或强制路由面
- **AND** MUST NOT 将其作为主要产品叙事

### Requirement: Surface Simplicity

系统 MUST 将 `trio` 的主要用户表面限制为开发流程治理,而不是内部运行时控制。

#### Scenario: 用户只感知治理信号
- **WHEN** 系统与用户交互
- **THEN** 系统 MUST 只暴露与治理直接相关的概念
- **AND** 这些概念 MUST 限定为 `quick`、`dev`、风险确认、继续、重开、完整评审建议

#### Scenario: 内部实现术语不得成为主要用户接口
- **WHEN** 系统对外展示状态、建议或恢复选项
- **THEN** 系统 MUST NOT 要求用户理解内部 phase 名称、runtime verb 或机器字段

### Requirement: Task Routing

系统 MUST 在任务开始时将当前工作判定为 `quick` 或 `dev`。

#### Scenario: 低风险局部修改可走 quick
- **WHEN** 当前任务范围局部、风险明确且不涉及关键结构变化
- **THEN** 系统 MAY 允许进入 `quick`

#### Scenario: 高风险或边界不清任务必须走 dev
- **WHEN** 当前任务涉及新功能、跨模块修改、核心流程变化或风险边界不清
- **THEN** 系统 MUST 要求进入 `dev`

### Requirement: Risk Gating

系统 MUST 在 quick 路径前对明显风险进行拦截,而不是默认放行。

#### Scenario: quick 启动前允许做轻量风险确认
- **WHEN** 当前任务倾向 quick,但仍存在误用风险
- **THEN** 系统 MAY 先要求一次轻量风险确认

#### Scenario: 不适合 quick 的任务不得直接开始
- **WHEN** 系统判断当前任务已超出 quick 边界
- **THEN** 系统 MUST 阻止 quick 直接开始
- **AND** MUST 引导调用方切换到 `dev`

### Requirement: Flow Escalation

系统 MUST 在轻流程失真时把任务升级回完整流程。

#### Scenario: 连续 quick 过多时发出回归 dev 信号
- **WHEN** 当前宿主项目连续 quick 次数超过阈值
- **THEN** 系统 MUST 给出回到 `dev` 的明确信号

#### Scenario: quick 执行过程中暴露更高风险时允许升级
- **WHEN** quick 路径中暴露出更高风险、更大范围的改动或新的关键决策需求
- **THEN** 系统 MUST 允许或要求升级到 `dev`

### Requirement: Minimal Recovery

系统 MUST 支持未完成工作的最小恢复,但不得把内部状态机暴露给用户。

#### Scenario: 未完成工作可继续或重开
- **WHEN** 宿主项目存在未结束工作
- **THEN** 系统 MUST 要求调用方在“继续”与“重开”之间做决定

#### Scenario: 恢复语义不得要求用户理解内部阶段
- **WHEN** 系统向用户展示恢复选项
- **THEN** 系统 MUST 使用任务语义或工作语义
- **AND** MUST NOT 使用内部 phase 名称作为主要提示文案

### Requirement: Minimal Record

系统 MUST 只保留治理所需的最小痕迹。

#### Scenario: 关键治理信息需要被记录
- **WHEN** 系统需要支持恢复、升级或关键决策回看
- **THEN** 系统 MUST 保留必要的最小记录

#### Scenario: 内部机器字段不构成用户心智
- **WHEN** 系统持久化内部状态
- **THEN** 系统 MAY 使用内部机器字段
- **AND** MUST NOT 将这些字段作为主要用户接口暴露
