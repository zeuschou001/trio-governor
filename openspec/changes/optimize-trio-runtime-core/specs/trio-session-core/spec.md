## Scope

本规格定义 `trio` 的内部实现边界,用于保证治理规则可执行。它不定义主要用户表面,也不要求用户理解其中的内部术语、阶段名称或驱动命令。用户可见能力由 `trio-governor` 产品规格定义。

本规格关注 bootstrap、ownership、locking、resume / restart / abort 的内部驱动契约。

## ADDED Requirements

### Requirement: Session Ownership

系统 MUST 将宿主项目中的 `.trio/` 会话视为 `trio-dev` 管理的唯一开发会话对象,并且仅在 ownership 校验通过时接管该会话。

#### Scenario: 非 git 宿主拒绝启动
- **WHEN** 用户在不含 `.git/` 的目录中启动 `trio-dev`
- **THEN** 系统 MUST 立即失败并提示宿主需要先初始化为 git 仓库
- **AND** 系统 MUST NOT 创建、修改或接管任何 `.trio/` 状态

#### Scenario: 非本插件管理的 `.trio/` 目录拒绝接管
- **WHEN** 宿主目录已存在 `.trio/`,但签名文件缺失或签名不匹配
- **THEN** 系统 MUST 拒绝接管并提示用户手动备份后移除冲突目录
- **AND** 系统 MUST NOT 覆盖现有目录内容

#### Scenario: 已签名会话允许自动补齐
- **WHEN** 宿主目录中的 `.trio/` 签名有效,但核心文件存在缺失
- **THEN** 系统 MUST 按模板自动补齐缺失文件
- **AND** 系统 MUST 保留已存在的有效状态内容

### Requirement: Bootstrap and Locking

系统 MUST 提供显式 bootstrap 语义,并通过项目级锁防止同一宿主上的并发会话互相污染状态。

#### Scenario: dev 会话首次 bootstrap
- **WHEN** 用户首次启动完整开发流程
- **THEN** 系统 MUST 创建或接管 `.trio/`
- **AND** MUST 将会话初始化为 `mode=dev`
- **AND** MUST 将会话状态设置为首个合法 phase 的 `running`

#### Scenario: quick 会话首次 bootstrap
- **WHEN** 用户首次启动 quick 流程
- **THEN** 系统 MUST 创建 quick 所需的最小状态集合
- **AND** MUST 将会话初始化为 `mode=quick`
- **AND** MUST 将会话状态设置为 `quick-writing-plans` 的 `awaiting-start-confirmation`

#### Scenario: quick 首次执行前必须先通过启动 guard
- **WHEN** 系统创建或重建一个 `quick_streak=0` 的 quick 会话
- **THEN** 系统 MUST 在真正执行 `quick-writing-plans` 前先停在 machine-readable 的启动 guard 状态
- **AND** 调用方 MUST 通过 session driver 清除该 guard,而不是自行跳过

#### Scenario: 非零 quick streak 的 quick 重建必须保留 streak 并跳过 guard
- **WHEN** 宿主目录已有已结束的 quick 会话,且其 `quick_streak > 0`
- **AND** 系统按 quick mode 重建新会话
- **THEN** 系统 MUST 保留原有 `quick_streak`
- **AND** MUST 直接将会话重建为 `quick-writing-plans` 的 `running`

#### Scenario: 已有活动会话持锁时拒绝进入
- **WHEN** 同一宿主项目已有进行中的 trio 会话持有活动锁
- **THEN** 系统 MUST 拒绝新的 bootstrap 或运行请求
- **AND** MUST NOT 对现有状态做任何写入

#### Scenario: 已结束会话在新 bootstrap 时自动重建
- **WHEN** 宿主目录已有已签名会话,且状态为 `completed` 或 `aborted`
- **THEN** 系统 MUST 归档旧 `STATE.md`
- **AND** MUST 按本次请求的 mode 重建新会话

#### Scenario: 可恢复会话与请求 mode 不一致时保留现场
- **WHEN** 宿主目录已有 `running`、`awaiting-start-confirmation` 或 `awaiting-confirmation` 会话,且其 `mode` 与本次 bootstrap 请求不一致
- **THEN** 系统 MUST 保留现有会话状态
- **AND** MUST 提示调用方先做 `continue` 或显式 `restart --mode <requested-mode>` 决策

### Requirement: Session Route Profile

系统 MUST 将影响阶段路由的会话配置显式持久化,避免 resume 后依赖调用方重新记忆启动 flag。

#### Scenario: 首次 bootstrap 持久化 route profile
- **WHEN** 调用方以 `dev` 模式启动,并请求 `minimal` 或显式 CEO review
- **THEN** 系统 MUST 将等价的 route profile 写入 runtime-owned 状态
- **AND** 后续继续同一会话时 MUST 以该 profile 作为真相来源

#### Scenario: 活动会话遇到不同 route profile 请求时保留现状
- **WHEN** 宿主目录已有 `running`、`awaiting-start-confirmation` 或 `awaiting-confirmation` 会话
- **AND** 新请求的 adapter route 或 CEO review 强制策略与当前会话不一致
- **THEN** 系统 MUST 保留活动会话的 route profile
- **AND** MUST 仅在调用方显式选择 `restart` 后切换到新 profile

#### Scenario: quick 会话强制最小 route profile
- **WHEN** 系统创建或重建 `quick` 会话
- **THEN** 系统 MUST 将 route profile 固定为 `adapter_mode=minimal`
- **AND** MUST NOT 允许 `ceo_review_forced=1`

### Requirement: Status Discovery

系统 MUST 支持读取当前会话摘要,以便调用方判断是否存在可继续的开发会话。

#### Scenario: 进行中的会话暴露 resume 信息
- **WHEN** 当前会话状态为 `running`、`awaiting-start-confirmation` 或 `awaiting-confirmation`
- **THEN** 系统 MUST 返回 machine-readable 的状态摘要
- **AND** MUST 暴露 `RESUME_AVAILABLE=1`

#### Scenario: 状态摘要暴露当前 route profile
- **WHEN** 调用方查询当前会话状态
- **THEN** 系统 MUST 返回当前 route profile 的 machine-readable 摘要
- **AND** 该摘要 MUST 至少包含当前 `adapter_mode` 与 `ceo_review_forced`

#### Scenario: 已完成会话不再暴露 resume
- **WHEN** 当前会话状态为 `completed`
- **THEN** 系统 MUST 返回当前会话摘要
- **AND** MUST NOT 将该会话标记为可恢复

#### Scenario: 已中止会话不再被视为可继续
- **WHEN** 当前会话状态为 `aborted`
- **THEN** 系统 MUST 返回当前会话摘要
- **AND** MUST NOT 将该会话标记为可恢复

### Requirement: Resume, Restart, and Abort

系统 MUST 明确定义继续、重开与中止语义,避免调用方以覆盖文件的方式自行实现恢复逻辑。

#### Scenario: 可恢复会话必须在执行前做继续决策
- **WHEN** 系统检测到宿主项目存在 `RESUME_AVAILABLE=1` 的会话
- **THEN** 调用方 MUST 在继续执行任何外部能力前先做 `continue` 或 `restart` 决策

#### Scenario: 启动期 continue/restart/abort 输入由 session driver 归一化
- **WHEN** 调用方把启动期的原始用户输入交给 `session resume`
- **THEN** 系统 MUST 负责 `trim` + `lowercase` + `continue|restart|abort` 别名校验
- **AND** 对合法输入 MUST 执行唯一合法动作
- **AND** 对空输入或白名单外值 MUST 返回可重试的 machine-readable 结果

#### Scenario: session driver 重启时沿用启动契约给出的 route profile
- **WHEN** 调用方通过 `session resume` 选择 `restart`
- **THEN** 系统 MUST 使用启动契约中的 `RESTART_MODE`、`RESTART_ADAPTER_MODE` 与 `RESTART_CEO_REVIEW_FORCED`
- **AND** MUST NOT 要求调用方自行重组 restart flags

#### Scenario: restart 先归档旧状态后重建
- **WHEN** 调用方选择 `restart`
- **THEN** 系统 MUST 先归档旧 `STATE.md`
- **AND** MUST 重建一个新的同 mode 会话
- **AND** MUST NOT 通过直接覆盖旧 `STATE.md` 模拟重开

#### Scenario: restart 可显式切换 mode
- **WHEN** 调用方选择 `restart --mode <target>`
- **THEN** 系统 MUST 先归档旧 `STATE.md`
- **AND** MUST 以 `<target>` 作为新会话的 mode 重建首阶段状态

#### Scenario: abort 保留历史并显式终止
- **WHEN** 调用方选择中止当前开发会话
- **THEN** 系统 MUST 将状态写为 `aborted`
- **AND** MUST 保留既有历史、决策与产物索引

### Requirement: Runtime I/O Contract

系统 MUST 提供稳定、可消费的 runtime I/O 边界,以供 command、skill 或测试脚本调用。

#### Scenario: stdout 仅输出 machine-readable 状态
- **WHEN** 调用 runtime 状态相关能力
- **THEN** stdout MUST 仅包含 `KEY=VALUE` 行
- **AND** MUST NOT 混入自然语言说明或 markdown

#### Scenario: stderr 承担人类诊断信息
- **WHEN** 系统需要输出 warning、修复建议或非法输入说明
- **THEN** 这些信息 MUST 写入 stderr
- **AND** MUST NOT 污染 stdout 协议

#### Scenario: 未知操作立即失败
- **WHEN** 调用方请求未知的 runtime verb
- **THEN** 系统 MUST 以参数错误失败
- **AND** MUST NOT 读写宿主项目 `.trio/`
