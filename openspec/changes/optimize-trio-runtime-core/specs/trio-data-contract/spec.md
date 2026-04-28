## Scope

本规格定义 `trio` 的内部实现边界,用于保证治理规则可执行。它不定义主要用户表面,也不要求用户理解其中的内部术语、阶段名称或驱动命令。用户可见能力由 `trio-governor` 产品规格定义。

本规格关注 `.trio` 数据面的内部持久化边界、原子写回和结构化记录约束。

## ADDED Requirements

### Requirement: .trio Data Layout

系统 MUST 将 `.trio/` 作为宿主项目上的持久数据面,并在不同 mode 下维护对应的数据布局。

#### Scenario: dev 初始化创建完整数据面
- **WHEN** 用户首次启动完整开发流程
- **THEN** 系统 MUST 创建完整 `.trio/` 数据面
- **AND** MUST 包含会话状态、项目信息、决策记录、知识沉淀和 roadmap 所需文件

#### Scenario: quick 初始化创建最小数据面
- **WHEN** 用户首次启动 quick 流程
- **THEN** 系统 MUST 仅创建 quick 运行所需的最小数据集合
- **AND** MUST NOT 提前创建不必要的文档文件

#### Scenario: archive 目录按需创建
- **WHEN** 系统首次需要归档状态或 roadmap 历史
- **THEN** 系统 MUST 创建 `.trio/archive/`

### Requirement: STATE.md State Model

系统 MUST 将 `STATE.md` 作为 runtime-owned 的唯一机器状态文档。

#### Scenario: STATE.md 包含最小状态机字段
- **WHEN** 系统首次创建或后续更新 `STATE.md`
- **THEN** frontmatter MUST 至少包含:
  `mode`, `status`, `current_phase`, `completed_phases`, `last_updated`, `quick_streak`, `superpowers_version`, `adapter_mode`, `ceo_review_forced`

#### Scenario: 旧版 STATE.md 自动升级
- **WHEN** 读取到缺失 `mode` 或 `status` 的旧版 `STATE.md`
- **THEN** 系统 MUST 基于 phase namespace 推断 `mode`
- **AND** MUST 以默认合法值补齐 `status`
- **AND** MUST 以默认合法值补齐缺失的 route profile 字段
- **AND** MUST 原子回写升级后的状态

#### Scenario: 非法字段值硬失败
- **WHEN** `STATE.md` 中的 `mode` 或 `status` 不在白名单内
- **THEN** 系统 MUST 拒绝继续执行
- **AND** MUST NOT 静默纠正非法值

#### Scenario: quick streak 跨 quick 重建保留,仅在 dev 重建时清零
- **WHEN** 系统重建一个新的 quick 会话
- **THEN** 若上一个已结束会话同样为 quick,系统 MUST 保留其 `quick_streak`
- **AND** 若系统重建的是 dev 会话,则 MUST 将 `quick_streak` 重置为 `0`

### Requirement: PROJECT.md Write-Once Metadata

系统 MUST 将 `PROJECT.md` 视为只写一次的项目元信息文档。

#### Scenario: 首次写入必须走 runtime API
- **WHEN** 系统需要写入正式项目元信息
- **THEN** 写入 MUST 通过受控的 runtime writer 完成
- **AND** MUST NOT 由 skill 或 ad-hoc shell 直接覆盖模板文件

#### Scenario: frontmatter seal 后拒绝覆盖
- **WHEN** `PROJECT.md` 的正式 frontmatter 已存在
- **THEN** 后续任何重写 frontmatter 的请求 MUST 被拒绝

#### Scenario: 项目补充信息通过 addendum 追加
- **WHEN** 后续阶段需要补充项目背景或边界说明
- **THEN** 系统 MUST 通过追加 addendum 而不是覆盖正式元信息

### Requirement: DECISIONS.md Structured Append

系统 MUST 将 `DECISIONS.md` 作为结构化决策日志,而不是自由文本笔记。

#### Scenario: 决策以结构化 block 追加
- **WHEN** 系统记录新的评审或关键决策
- **THEN** MUST 以可解析的结构化 block 形式追加到 `DECISIONS.md`

#### Scenario: eng-review 决策可被门禁消费
- **WHEN** `plan-eng-review` 产出评审结果
- **THEN** 决策记录 MUST 满足 gate-check 的可解析性要求

#### Scenario: 决策写入在锁内完成
- **WHEN** 系统追加决策记录
- **THEN** MUST 在文件级锁保护下完成 re-read、去重和 append

### Requirement: KNOWLEDGE.md Structured Append

系统 MUST 将 `KNOWLEDGE.md` 作为实现与验证阶段的知识沉淀文档。

#### Scenario: 实现经验以结构化条目追加
- **WHEN** 执行阶段产出新的实现经验或约束
- **THEN** 系统 MUST 以结构化条目追加到 `KNOWLEDGE.md`

#### Scenario: QA 结论可沉淀为 knowledge
- **WHEN** QA 阶段识别到复用价值较高的经验
- **THEN** 系统 MAY 将其追加到 `KNOWLEDGE.md`

#### Scenario: knowledge 不得覆盖历史内容
- **WHEN** 系统写入 `KNOWLEDGE.md`
- **THEN** 系统 MUST 仅追加
- **AND** MUST NOT 重写已有历史条目

### Requirement: ROADMAP.md Archive and Rewrite

系统 MUST 将 `ROADMAP.md` 视为“当前有效计划”,历史版本通过 archive 保存。

#### Scenario: 重写前先归档旧 roadmap
- **WHEN** 系统即将写入新的 `ROADMAP.md`
- **THEN** 若当前 `ROADMAP.md` 已存在
- **THEN** 系统 MUST 先将旧版归档到 `.trio/archive/`

#### Scenario: archive 文件名冲突时自动避让
- **WHEN** 目标归档文件名已存在
- **THEN** 系统 MUST 生成不冲突的新归档文件名
- **AND** MUST NOT 覆盖既有归档

#### Scenario: orchestrator 不得直接覆盖 roadmap
- **WHEN** 编排层需要落盘新的 roadmap
- **THEN** MUST 调用受控 writer
- **AND** MUST NOT 直接覆盖 `ROADMAP.md`

### Requirement: Single Writer Boundary

系统 MUST 为 `.trio/` 中的机器管理区域提供唯一写入边界。

#### Scenario: 机器字段仅 runtime 可写
- **WHEN** 任意调用方试图更新 `STATE.md` 的机器字段
- **THEN** 该更新 MUST 通过 runtime writer 完成

#### Scenario: skill 和 command 不直接修改机器区
- **WHEN** skill 或 command 需要反映状态变化
- **THEN** 它们 MUST 通过 runtime verb 间接落盘
- **AND** MUST NOT 直接改写 `.trio/` 机器管理区

#### Scenario: 关键写入必须原子或受锁保护
- **WHEN** 系统更新 `.trio/` 中的关键机器状态或结构化文档
- **THEN** 写入 MUST 为原子替换或在锁保护下完成
