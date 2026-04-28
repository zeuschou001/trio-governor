## Scope

本规格定义 `trio` 的内部实现边界,用于保证治理规则可执行。它不定义主要用户表面,也不要求用户理解其中的内部术语、阶段名称或驱动命令。用户可见能力由 `trio-governor` 产品规格定义。

本规格关注外部 adapter 的接入边界、依赖探测和 non-ownership 约束。

## ADDED Requirements

### Requirement: External Dependency Detection

系统 MUST 将外部 skill、工具或插件视为 adapter,并在会话执行前显式探测其可用性。

#### Scenario: 必需 adapter 缺失时硬失败
- **WHEN** 完整流程依赖的必需外部能力缺失
- **THEN** 系统 MUST 明确失败
- **AND** MUST 输出精确的修复建议

#### Scenario: 可选 adapter 缺失时给出软提示
- **WHEN** 可选或软依赖 adapter 不可用
- **THEN** 系统 MAY 给出 warning 和安装提示
- **AND** MAY 根据当前 mode 继续执行合法子集

#### Scenario: minimal 或 quick 路径可跳过部分软依赖
- **WHEN** 当前运行路径允许最小执行集
- **THEN** 系统 MAY 跳过不影响当前路径成立的软依赖检查

### Requirement: Version Recording

系统 MUST 能将外部关键依赖的版本摘要写入会话状态,以便调试和恢复。

#### Scenario: 成功探测后记录版本
- **WHEN** 系统成功探测到关键外部依赖版本
- **THEN** 系统 MUST 将该版本摘要记录到受控状态字段中

#### Scenario: 版本低于建议基线时发出 warning
- **WHEN** 依赖版本低于建议基线但仍可运行
- **THEN** 系统 MUST 发出 warning
- **AND** MAY 继续执行

#### Scenario: 未知版本显式记录为 unknown
- **WHEN** 系统无法确定关键依赖版本
- **THEN** 系统 MUST 显式记录为 `unknown`
- **AND** MUST NOT 伪造版本值

### Requirement: Allowlist and Blocklist Policy

系统 MUST 显式定义哪些外部能力被允许接入当前产品边界,哪些能力即使命中也不由 `trio-dev` 承担。

#### Scenario: 仅允许声明过的 adapter 参与编排
- **WHEN** 编排层请求外部能力
- **THEN** 该能力 MUST 属于已声明的 allowlist 范围

#### Scenario: 命中 blocklist 仅提示不自动处理
- **WHEN** 系统在宿主环境中发现被 blocklist 的外部能力
- **THEN** 系统 MAY 输出 warning
- **AND** MUST NOT 擅自删除、覆盖或修改用户环境

#### Scenario: adapter 名称与声明必须一致
- **WHEN** 系统校验某个外部 skill 或插件
- **THEN** 它的实际标识 MUST 与声明名称一致
- **AND** 名称不匹配 MUST 视为不可用

### Requirement: Adapter Non-Ownership

系统 MUST 明确规定 adapter 仅提供能力,不拥有 trio 会话状态。

#### Scenario: 外部 adapter 不得直接写入 STATE.md
- **WHEN** 外部 skill 或工具执行某一阶段
- **THEN** 它 MUST NOT 直接写入 trio 会话的机器状态

#### Scenario: adapter 产出通过 runtime writer 落盘
- **WHEN** 外部 adapter 产出需要持久化的结果
- **THEN** 这些结果 MUST 通过 trio 的 runtime writer 落盘到 `.trio/`

#### Scenario: adapter 失败不污染既有会话状态
- **WHEN** 某个外部 adapter 执行失败
- **THEN** trio 会话状态 MUST 保持一致
- **AND** MUST NOT 通过半写入状态制造伪完成

### Requirement: Internal Bridge Export Boundary

系统 MUST 允许显式的 internal bridge 导出当前 `.trio` 会话上下文给外部工作流工具消费,但 bridge 仍不拥有 trio 状态。

#### Scenario: bridge export 只写入 `.trio/bridges/`
- **WHEN** 开发者显式执行内部 bridge export
- **THEN** 系统 MUST 仅在 `.trio/bridges/<provider>/<run-id>/` 下生成导出物
- **AND** MUST NOT 修改 `STATE.md`
- **AND** MUST NOT 推进 phase

#### Scenario: bridge export 携带最小上下文快照与 manifest
- **WHEN** 系统生成 bridge export
- **THEN** 系统 MUST 导出当前存在的 `PROJECT.md`、`DECISIONS.md`、`KNOWLEDGE.md`、`ROADMAP.md`、`STATE.md` 子集
- **AND** MUST 生成 machine-readable manifest,记录 provider 身份、阶段上下文与 `STATE.md` ownership 约束

#### Scenario: bridge handoff 生成外部消费包但不回写 trio 状态
- **WHEN** 开发者为某个 bridge provider 生成 handoff
- **THEN** 系统 MUST 在导出目录内生成 provider-specific handoff 指引与输出目录
- **AND** MUST 明确声明 trio 仍拥有 `STATE.md` 与 phase 推进权
- **AND** MUST NOT 因 handoff 生成而改写 trio 会话状态

#### Scenario: bridge review 只生成回流建议
- **WHEN** 开发者审查 bridge `outputs/` 目录中的外部产出
- **THEN** 系统 MUST 仅输出 machine-readable 的回流建议
- **AND** MUST 标明建议对应的 runtime writer 类型与人工确认要求
- **AND** MUST NOT 自动执行 `decision-append`、`knowledge-append` 或 `roadmap-rewrite`
- **AND** MUST NOT 改写 trio 会话状态

#### Scenario: bridge draft 只生成人工执行草稿
- **WHEN** 开发者需要把 review suggestion 收敛成可执行草稿
- **THEN** 系统 MAY 在 bridge 导出目录中生成 draft 文本文件
- **AND** MUST 仅输出带占位符的命令草稿或注释化命令
- **AND** MUST 保持默认不可自动应用语义
- **AND** MUST NOT 自动执行任何 runtime writer
- **AND** MUST NOT 改写 trio 会话状态

#### Scenario: bridge scaffold 只生成待填写模板
- **WHEN** 开发者希望减少手动改写 draft 命令中的占位符
- **THEN** 系统 MAY 生成与 runtime writer 对应的参数模板或说明文件
- **AND** MUST 仅写入 bridge 导出目录
- **AND** MUST 保持“人工填写后再手动执行”语义
- **AND** MUST NOT 自动执行任何 runtime writer
- **AND** MUST NOT 改写 trio 会话状态

#### Scenario: 非 bridge provider 不允许走 bridge export
- **WHEN** 调用方尝试把普通 skill / plugin provider 当成 bridge 使用
- **THEN** 系统 MUST 明确拒绝
- **AND** MUST 提示该 provider 不属于 bridge 边界

### Requirement: Surface-to-Adapter Routing

系统 MUST 将用户入口、对话编排与外部 adapter 调用分层,而不是让 command 或 adapter 自己持有状态机。

#### Scenario: 用户入口仅声明 surface
- **WHEN** 定义 `/trio:dev`、`/trio:quick` 或类似入口
- **THEN** 这些入口 MUST 仅负责暴露 surface 与参数提示
- **AND** MUST NOT 内嵌会话状态机

#### Scenario: orchestrator 负责路由,不负责机器字段
- **WHEN** orchestrator 在阶段边界调度外部 adapter
- **THEN** 它 MAY 负责路由、询问与展示
- **AND** MUST NOT 直接写 trio 机器状态

#### Scenario: adapter 不决定下一阶段
- **WHEN** 某个外部 adapter 完成一次执行
- **THEN** 下一阶段的判定 MUST 由 trio phase machine 决定
- **AND** MUST NOT 由 adapter 自行推进

### Requirement: Runtime-Backed Phase Contract

系统 MUST 为编排层暴露一个 machine-readable 的当前阶段合同,让 adapter 路由、确认语义与 writer 选择都来自运行时状态,而不是 prompt 硬编码。

#### Scenario: 当前阶段合同暴露 executor 与 adapter 路由
- **WHEN** 调用方查询当前阶段合同
- **THEN** 系统 MUST 返回当前 phase 的 executor 类型
- **AND** MUST 返回与该 phase 对应的 adapter provider / skill 集合或明确声明为本地对话 / runtime 步骤

#### Scenario: quick 启动 guard 作为 phase contract 暴露
- **WHEN** 当前会话停在 quick 启动 guard
- **THEN** 系统 MUST 通过当前阶段合同暴露 `guard` executor
- **AND** MUST 暴露唯一合法的 yes/no 动作与 guard 后的下一阶段输入文件

#### Scenario: office-hours 确认语义由运行时 route profile 与项目元信息决定
- **WHEN** 当前阶段为 `office-hours`
- **THEN** 系统 MUST 基于持久化 route profile 与当前 `PROJECT.md` 元信息导出合法的确认动作
- **AND** MUST NOT 依赖调用方记忆最初的启动 flag

#### Scenario: 当前阶段合同暴露 writer 与下一阶段决策
- **WHEN** 调用方在阶段边界查询当前阶段合同
- **THEN** 系统 MUST 返回当前阶段允许使用的 writer 边界
- **AND** MUST 返回确认通过 / 跳过后的下一阶段结果

#### Scenario: 当前阶段合同暴露进度与输入文件
- **WHEN** 调用方在阶段边界查询当前阶段合同
- **THEN** 系统 MUST 返回当前阶段在本次路径中的进度计数
- **AND** MUST 返回当前阶段应读取的最小 `.trio` 文件集合
- **AND** MUST 返回确认通过 / 跳过后下一阶段应读取的最小 `.trio` 文件集合

#### Scenario: 阶段边界输入由 session driver 归一化
- **WHEN** 调用方在阶段边界收到用户原始输入
- **THEN** 系统 MUST 负责 `trim` + `lowercase` + 白名单校验
- **AND** MUST 基于当前阶段合同把输入映射到唯一合法的 runtime transition
- **AND** 对空输入或白名单外值 MUST 返回可重试的 machine-readable 结果,而不是让 prompt 自行推断

#### Scenario: 启动恢复决策也由 session driver 收口
- **WHEN** `session start` 返回 `START_ACTION=resume-decision`
- **THEN** orchestrator MUST 把用户原始输入直接交给 `session resume`
- **AND** MUST NOT 自己维护 `continue` / `restart` / `abort` 的白名单、别名或 restart flag 拼装
- **AND** `session resume` MUST 返回 machine-readable 的 `accepted` / `invalid` / `not-awaiting-decision` 结果
