## ADDED Requirements

### Requirement: 统一入口命令 /trio:dev

系统 SHALL 提供唯一的完整流程入口命令 `/trio:dev <需求>`,负责按顺序编排 9 阶段工作流:`/office-hours` → `/plan-ceo-review`(可选) → `/plan-eng-review`(硬门禁) → 状态文件同步 → `writing-plans` → `executing-plans` + `test-driven-development` → `verification-before-completion` → `/qa` → `finishing-a-development-branch`。

#### Scenario: 完整流程首次启动
- **WHEN** 用户在宿主项目根目录执行 `/trio:dev 添加用户登录功能`
- **THEN** 系统依次执行依赖探测、初始化 `.trio/` 目录、调用 `/office-hours`、(若 `--with-ceo` 或项目类型为 user-facing-feature)调用 `/plan-ceo-review`、调用 `/plan-eng-review`、同步 DECISIONS.md、调用 `writing-plans` 生成 ROADMAP.md、调用 `executing-plans` 执行开发、调用 `verification-before-completion`、调用 `/qa`、调用 `finishing-a-development-branch`

#### Scenario: 阶段边界显式确认
- **WHEN** 当前阶段执行完毕,即将进入下一阶段
- **THEN** 系统 MUST 在阶段切换点打印当前进度、下一阶段名称与输入文件,并等待用户显式确认;禁止在单阶段子 skill 内部追加任何用户交互;子 skill 完成信号 ONLY 依赖用户的 `y` 输入,系统 MUST NOT 通过文件 mtime、输出关键字或超时推断完成

#### Scenario: 阶段确认输入语法
- **WHEN** 系统在阶段边界读取用户输入
- **THEN** 系统 MUST 先对输入做 `trim` + `lowercase`,然后按严格白名单匹配:`y` / `yes` 视为确认、`n` / `no` 视为否决、`skip` / `s` 视为跳过;空输入或任何白名单外的值 MUST 重新提问,不设默认动作

#### Scenario: n 输入重试当前阶段
- **WHEN** 用户在任一阶段边界输入 `n` / `no`
- **THEN** 系统 MUST 停留在当前阶段、重新执行当前阶段的子 skill,`STATE.md.current_phase` 不变;MUST NOT 中止整次工作流,MUST NOT 自动回退到上一阶段

#### Scenario: skip 仅对软门禁生效
- **WHEN** 用户在 `/plan-ceo-review` 阶段边界输入 `skip` / `s`
- **THEN** 系统 MUST 跳过该阶段直接进入 `/plan-eng-review`,`completed_phases` 不追加该阶段

#### Scenario: 强制阶段拒绝 skip
- **WHEN** 用户在任何非 `/plan-ceo-review` 阶段输入 `skip` / `s`
- **THEN** 系统 MUST 将其视为无效输入并重新提问,不允许跳过强制阶段

#### Scenario: 产品评审软门禁默认跳过
- **WHEN** 用户调用 `/trio:dev <需求>` 且未传 `--with-ceo`,且 PROJECT.md 未声明 `"type": "user-facing-feature"`
- **THEN** 系统 MUST 跳过 `/plan-ceo-review` 阶段,直接进入 `/plan-eng-review`

#### Scenario: 产品评审显式启用
- **WHEN** 用户调用 `/trio:dev <需求> --with-ceo`
- **OR WHEN** 宿主项目 `.trio/PROJECT.md` 声明 `"type": "user-facing-feature"`
- **THEN** 系统 MUST 执行 `/plan-ceo-review` 并将其产物追加到 DECISIONS.md 后,才进入 `/plan-eng-review`

### Requirement: 架构评审硬门禁

系统 MUST 将 `/plan-eng-review` 设置为硬门禁 —— 在 `.trio/DECISIONS.md` 没有出现「架构决策」条目(`## Decision: <标题>` 且包含 `- **Type**: eng-review` 字段)之前,拒绝进入 `writing-plans` 阶段。

#### Scenario: 架构决策未记录阻止进入执行
- **WHEN** `/plan-eng-review` 阶段运行完毕但未向 DECISIONS.md 追加 `Type: eng-review` 的决策条目
- **THEN** 系统 MUST 中止流程,打印 "架构评审未通过:DECISIONS.md 缺少 eng-review 条目",不调用 `writing-plans`

#### Scenario: 用户试图手工绕过门禁
- **WHEN** 用户手工编辑 DECISIONS.md 添加伪造条目后重新执行 `/trio:dev`
- **THEN** 系统 SHALL 不做人工防御(不负责阻止 hack),但 `/qa` 阶段必须读取 DECISIONS.md 与实际代码对比,对明显漂移给出警告

### Requirement: 小任务旁路命令 /trio:quick

系统 SHALL 提供 `/trio:quick <需求>` 旁路命令,仅包含 3 阶段:`writing-plans` → `executing-plans`(含 TDD)→ `verification-before-completion`,跳过所有决策层与状态文件同步,仅在 KNOWLEDGE.md 追加一条简短条目。

#### Scenario: 小任务旁路完整执行
- **WHEN** 用户执行 `/trio:quick 把日志级别从 info 改为 debug`
- **THEN** 系统 MUST 依次调用 `writing-plans`、`executing-plans`、`verification-before-completion`,不调用任何 gstack skill,不要求 DECISIONS.md 存在

#### Scenario: 小任务仍强制 TDD
- **WHEN** 用户通过 `/trio:quick` 进入 `executing-plans`
- **THEN** 系统 MUST 启用 `test-driven-development` skill,不允许跳过

#### Scenario: 旁路使用计数警告
- **WHEN** STATE.md 记录当前宿主项目中 `/trio:quick` 已连续使用 > 3 次
- **THEN** 系统 MUST 在下次调用时打印提示 "连续小任务已超过 3 次,建议回归 /trio:dev 做一次完整评审"

#### Scenario: 首次使用旁路提示风险
- **WHEN** 用户首次在当前宿主项目调用 `/trio:quick`
- **THEN** 系统 MUST 打印警告 "此命令跳过所有决策审查,仅用于 <50 行或纯配置修改",等待用户确认后继续

### Requirement: 依赖探测与修复指引

系统 MUST 在每次启动(`/trio:dev` 或 `/trio:quick` 首次调用)时依次执行 Superpowers 硬依赖校验、gstack cherry-pick 4 skill 校验、blocklist 扫描,并对缺失或违规情况给出精确修复指令。

#### Scenario: Superpowers 缺失硬失败
- **WHEN** 启动时检测 `~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/writing-plans/` 不存在
- **THEN** 系统 MUST 中止启动,打印 "Superpowers 未安装:请执行 `/plugin marketplace add obra/superpowers-marketplace && /plugin install superpowers@superpowers-marketplace`"

#### Scenario: gstack 4 skill 任一缺失给出软提示
- **WHEN** 启动时检测 `~/.claude/skills/plan-eng-review/SKILL.md` 不存在
- **THEN** 系统 MUST 打印对应 `curl` 安装指令指向 `github.com/garrytan/gstack/plan-eng-review/SKILL.md`,且 MUST NOT 中止启动(允许用户通过 `--minimal` 参数跳过 gstack 层)

#### Scenario: blocklist 违规警告
- **WHEN** 启动时检测到 `~/.claude/skills/` 下存在 blocklist 中 19 个 gstack skill 任一
- **THEN** 系统 MUST 输出 warning 列出违规 skill 并建议删除,但 MUST NOT 中止启动

### Requirement: CLI 参数互斥与宿主项目约束

系统 MUST 在命令解析阶段拒绝矛盾参数组合与非 git 宿主项目,确保后续阶段接收到良定义的输入。

#### Scenario: --minimal 与 --with-ceo 互斥
- **WHEN** 用户执行 `/trio:dev <需求> --minimal --with-ceo`(两个 flag 同时出现)
- **THEN** 系统 MUST 在命令解析阶段立即失败,打印 "`--minimal` 与 `--with-ceo` 互斥,请只保留其一",以退出码 `2` 退出,MUST NOT 进入依赖探测或任何阶段

#### Scenario: 非 git 宿主项目硬失败
- **WHEN** 系统在宿主项目根目录执行依赖探测,未发现 `.git/` 目录(文件或目录均视为未初始化)
- **THEN** 系统 MUST 中止启动,打印 "trio-dev 需要 git 仓库作为宿主,请先执行 `git init`",以退出码 `4` 退出;MUST NOT 自动调用 `git init`

### Requirement: 阶段 ID 命名空间

系统 MUST 为 `STATE.md` 的 `current_phase` 与 `completed_phases` 字段维护固定的阶段 ID 白名单,避免字符串漂移。

#### Scenario: 完整流程阶段 ID
- **WHEN** `/trio:dev` 推进阶段写入 STATE.md
- **THEN** `current_phase` / `completed_phases` 的元素 MUST 来自集合:`office-hours`、`plan-ceo-review`、`plan-eng-review`、`state-sync`、`writing-plans`、`executing-plans`、`verification-before-completion`、`qa`、`finishing-a-development-branch`

#### Scenario: 旁路流程阶段 ID
- **WHEN** `/trio:quick` 推进阶段写入 STATE.md
- **THEN** `current_phase` / `completed_phases` 的元素 MUST 来自集合:`quick-writing-plans`、`quick-executing-plans`、`quick-verification-before-completion`

### Requirement: 属性化不变量(PBT)

系统 MUST 满足以下可被属性化测试证伪的不变量;测试框架 SHALL 按每条 Scenario 的 falsification 策略生成随机输入尝试触发反例。

#### Scenario: completed_phases 单调递增
- **WHEN** 同一次 `/trio:dev` 生命周期内任意两个连续快照 `S_n`、`S_{n+1}`
- **THEN** 系统 MUST 保证 `S_{n+1}.completed_phases ⊇ S_n.completed_phases`,且 `|S_{n+1}.completed_phases| ≥ |S_n.completed_phases|`;falsification 策略:注入非致命错误触发重试、并发子任务失败回滚,断言 `completed_phases` 长度从未缩减

#### Scenario: 阶段图一致性
- **WHEN** 任意持久化的 STATE.md 被读取
- **THEN** `completed_phases` MUST 无重复、全部来自单一命名空间(`dev-*` 与 `quick-*` 不混用),并构成阶段图上的合法路径;`current_phase` MUST 是该路径末端的重试阶段或其唯一可达后继;falsification 策略:构造混合 namespace、跳阶段、重复、乱序阶段的 STATE.md,断言启动校验拒绝

#### Scenario: DECISIONS.md 消费仅取完整三元组
- **WHEN** `writing-plans` 调用 `parse_decisions(DECISIONS.md)`
- **THEN** 输出 MUST 恰等于所有同时包含且仅包含 `What` / `Why` / `Impact` 三字段的 `## Decision:` block 的三元组集合;缺字段、重字段、结构损坏的 block 贡献 0 个结果;falsification 策略:生成缺字段、重复字段、字段乱序、自由文本插入、嵌套标题、Markdown 畸形的 block,断言 consumer 不产生部分三元组
