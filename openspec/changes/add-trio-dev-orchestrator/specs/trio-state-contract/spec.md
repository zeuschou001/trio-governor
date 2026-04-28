## ADDED Requirements

### Requirement: .trio/ 目录结构与签名文件

系统 MUST 在宿主项目根目录创建 `.trio/` 目录,首次创建时写入签名文件 `.trio/.trio-signature`,用于区分本插件管理的目录与用户既存同名目录。

#### Scenario: 签名文件严格格式
- **WHEN** 系统写入 `.trio-signature`
- **THEN** 文件内容 MUST 严格匹配正则 `^trio-dev v[0-9]+\.[0-9]+\.[0-9]+ initialized at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\n$`,固定 lowercase、UTF-8 无 BOM、LF 结尾、无前后空白

#### Scenario: 首次初始化创建目录与签名
- **WHEN** 用户首次在宿主项目执行 `/trio:dev <需求>`,且 `.trio/` 不存在
- **THEN** 系统 MUST 创建 `.trio/` 目录(权限 `0755`),写入 `.trio-signature`,并生成 5 个状态文件(PROJECT.md、DECISIONS.md、KNOWLEDGE.md、ROADMAP.md、STATE.md)的初始骨架(权限 `0644`,UTF-8 无 BOM,LF 换行)

#### Scenario: /trio:quick lazy-init 三文件
- **WHEN** 用户在 `.trio/` 不存在的宿主项目执行 `/trio:quick <需求>` 并通过首次使用风险确认
- **THEN** 系统 MUST 创建 `.trio/` 目录、`.trio-signature`、`STATE.md` 骨架、`KNOWLEDGE.md` 骨架(共三个文件),MUST NOT 创建 `PROJECT.md` / `DECISIONS.md` / `ROADMAP.md`

#### Scenario: 崩溃恢复自动补齐
- **WHEN** 系统启动时发现 `.trio-signature` 存在但缺失任意核心状态文件
- **THEN** 系统 MUST 从 `templates/trio-state/*.tmpl` 补齐缺失文件的骨架,打印 "检测到上次初始化未完成,已自动补齐 <文件列表>",继续启动

#### Scenario: 目录冲突硬失败
- **WHEN** `.trio/` 已存在但不含 `.trio-signature` 文件
- **THEN** 系统 MUST 中止执行,打印 "检测到非本插件管理的 .trio/ 目录,请手动备份后移除",MUST NOT 自动覆盖

### Requirement: PROJECT.md 职责与写入规则

系统 SHALL 使 `PROJECT.md` 作为宿主项目的元信息载体,采用 YAML frontmatter 承载机器可读字段,仅在 `/trio:dev` 首次运行时生成,后续阶段只允许追加不允许重写。

#### Scenario: 首次生成 YAML frontmatter
- **WHEN** `/trio:dev` 首次运行完成 `/office-hours` 阶段
- **THEN** 系统 MUST 以 YAML frontmatter 头部(`---\n...\n---\n`)写入字段:`name`(非空字符串)、`type`(枚举 `user-facing-feature` / `infra` / `refactor` / `bug-fix` 之一)、`created_at`(RFC3339 UTC)、`description`(非空字符串);frontmatter 之后 MAY 追加自由文本正文

#### Scenario: 初始化阶段空壳 frontmatter
- **WHEN** `/trio:dev` 初始化 `.trio/` 但 `/office-hours` 尚未结束
- **THEN** 系统 MUST 写入含四键但值为空字符串的占位 frontmatter;`/office-hours` 完成后 MUST 一次性覆盖写入正式值,此后 MUST 拒绝对 frontmatter 的任何写入

#### Scenario: 后续阶段追加不重写
- **WHEN** `/office-hours` 已完成,任何 skill 尝试改写 PROJECT.md 的 frontmatter
- **THEN** 系统 MUST 拒绝写入,打印 "PROJECT.md frontmatter 为只写一次,请改用追加 `## Addendum: <标题>` 二级标题"

### Requirement: DECISIONS.md 追加协议

系统 SHALL 使 `DECISIONS.md` 作为 `/plan-ceo-review` 与 `/plan-eng-review` 的结构化产物存储,采用纯追加模式,每条决策 MUST 包含时间戳、类型、what/why/impact 三元组。

#### Scenario: 架构评审追加条目
- **WHEN** `/plan-eng-review` 阶段结束
- **THEN** 系统 MUST 向 DECISIONS.md 追加一条格式为:
  ```
  ## Decision: <标题>
  - **Timestamp**: <ISO-8601>
  - **Type**: eng-review
  - **What**: <做什么>
  - **Why**: <理由>
  - **Impact**: <影响范围>
  ```

#### Scenario: 产品评审追加条目
- **WHEN** `/plan-ceo-review` 阶段结束
- **THEN** 系统 MUST 向 DECISIONS.md 追加 `Type: ceo-review` 的同结构条目

#### Scenario: 只消费结构化字段
- **WHEN** `writing-plans` 消费 DECISIONS.md
- **THEN** 系统 MUST 仅读取 `## Decision:` 二级标题下的 What/Why/Impact 三元组,忽略其他自由文本

### Requirement: KNOWLEDGE.md 增量知识沉淀

系统 SHALL 使 `KNOWLEDGE.md` 作为 `executing-plans` 与 `/qa` 阶段的增量知识沉淀载体,追加式写入,消费方为 `writing-plans` 与 `verification-before-completion`。

#### Scenario: 执行阶段沉淀知识
- **WHEN** `executing-plans` 发现非预期的代码行为或环境约束
- **THEN** 系统 MUST 向 KNOWLEDGE.md 追加一条 `## Insight: <标题>` 条目,含 `Learned-at`、`Context`、`Takeaway` 字段

### Requirement: ROADMAP.md 覆盖式重写与归档

系统 SHALL 使 `ROADMAP.md` 作为 `writing-plans` 的产物,采用覆盖式重写,旧版自动归档到 `.trio/archive/ROADMAP-<UTC ms precision ISO-8601>.md`。

#### Scenario: 重写前归档旧版
- **WHEN** `writing-plans` 即将覆盖写入 ROADMAP.md,且该文件已存在
- **THEN** 系统 MUST 先将现有 ROADMAP.md 复制到 `.trio/archive/ROADMAP-<YYYY-MM-DDTHH-mm-ss.SSSZ>.md`(UTC、毫秒精度)再写入新内容;若目标路径已存在则按上文 "归档文件名冲突避让" 逻辑追加后缀

### Requirement: STATE.md 编排器进度追踪

系统 SHALL 使 `STATE.md` 作为 `/trio:dev` 与 `/trio:quick` 编排器自身的进度追踪文件,采用 YAML frontmatter 承载,原地覆盖式更新(写临时文件后 `rename` 原子替换)。

#### Scenario: STATE.md frontmatter 字段
- **WHEN** 任一命令首次创建或更新 STATE.md
- **THEN** 文件 MUST 以 YAML frontmatter 承载字段:`current_phase`(string,阶段 ID 白名单之一)、`completed_phases`(list)、`last_updated`(RFC3339 UTC)、`quick_streak`(非负整数)、`superpowers_version`(string 或 `unknown`);frontmatter 之后 MAY 追加自由文本说明

#### Scenario: 阶段切换更新状态
- **WHEN** `/trio:dev` 从一个阶段进入下一个阶段
- **THEN** 系统 MUST 通过 `写临时文件 → fsync → rename` 原子更新 STATE.md 的 `current_phase`、`last_updated`、`completed_phases` 字段

#### Scenario: /trio:quick 使用计数
- **WHEN** 用户调用 `/trio:quick` 并实际进入 `writing-plans` 阶段
- **THEN** 系统 MUST 递增 `quick_streak`;`/trio:dev` 通过参数解析与依赖探测后 MUST 将 `quick_streak` 重置为 `0`;MUST NOT 基于时间做自动衰减

### Requirement: 并发访问互斥

系统 MUST 在入口处对 `.trio/.lock` 执行 `flock -xn` 独占非阻塞锁,防止同一宿主项目多会话并发写入。

#### Scenario: 并发调用拒绝启动
- **WHEN** 用户在同一宿主项目的第二个终端同时调用 `/trio:dev` 或 `/trio:quick`,第一个会话仍持有 `.trio/.lock`
- **THEN** 第二个会话 MUST 立即打印 "检测到同项目已有活动 trio 会话,请等待其结束",以退出码 `3` 退出,MUST NOT 读写任何状态文件

#### Scenario: 锁自动释放
- **WHEN** 当前会话正常退出、异常崩溃或被信号中断
- **THEN** 系统 MUST 依赖 `flock` 内核级自动释放语义,无需显式删除 `.trio/.lock` 文件,MUST NOT 在下次启动时因残留锁文件失败

### Requirement: 状态文件的写入幂等性

系统 MUST 保证跨会话多次运行同一命令不产生损坏或重复状态:追加式文件不产生重复条目(以时间戳 + 标题判重),覆盖式文件保留归档。

#### Scenario: 决策重复写入去重
- **WHEN** 拟写入 DECISIONS.md 的条目 `- **Timestamp**:` 字段与历史中最后一条同 `Title` + `Type` 条目的 `Timestamp` 字段差值 < 5 秒(两者均按 RFC3339 UTC 解析)
- **THEN** 系统 MUST 忽略第二次写入,打印 "检测到重复决策条目(相同标题+类型且 Timestamp 间距 < 5s),已跳过";时间基准 MUST 是条目自身的 Timestamp 字段,MUST NOT 使用 wall clock 或文件 mtime

#### Scenario: 追加写入持锁
- **WHEN** 任一阶段追加写入 DECISIONS.md / KNOWLEDGE.md
- **THEN** 系统 MUST 先对 `.trio/.locks/<文件名>.lock` 执行 `flock -x`(阻塞等待上限 5 秒),拿锁后重新读取最新文件内容、执行去重检查、再 append;5 秒内拿不到锁 MUST fail-fast 并提示 "并发写入冲突"

#### Scenario: 归档文件名冲突避让
- **WHEN** `writing-plans` 生成的 ROADMAP 归档目标名 `ROADMAP-<YYYY-MM-DDTHH-mm-ss.SSSZ>.md` 已存在
- **THEN** 系统 MUST 依次尝试追加后缀 `-2`、`-3`、... 直至找到不存在的名称,MUST NOT 覆盖既有归档

### Requirement: 属性化不变量(PBT)

系统 MUST 满足以下针对状态契约的属性化不变量;测试 SHALL 按各 Scenario 的 falsification 策略生成反例输入。

#### Scenario: signature_regex_roundtrip
- **WHEN** 系统以 `write_signature(version, timestamp)` 生成 `.trio-signature` 的 bytes `b`
- **THEN** MUST 恒有 `regex_match(sig_re, b) ∧ render(parse(b)) == b`;falsification:对合法 `version/timestamp` 施加 BOM、CRLF、缺末尾 LF、大小写变形、前后空白、额外空格、位数错误、非法时间字段等扰动,断言 parser 拒绝

#### Scenario: malformed_signature_rejected
- **WHEN** 预存的 `.trio-signature` bytes `b` 不满足 `sig_re`
- **THEN** 系统 MUST 以 failure 退出,且启动前后 `.trio/` 下所有已有文件 bytes 集合完全相同;falsification:生成截断、CRLF、BOM、非法 semver、非法时间、无末尾 LF、随机垃圾,断言系统不把坏签名当作 ownership marker 继续写入

#### Scenario: valid_signature_reinit_noop
- **WHEN** `.trio/` 已存在且 `.trio-signature` 通过 regex 校验,用户再次触发初始化(`/trio:dev` 或 `/trio:quick` 的首次钩子)
- **THEN** 系统 MUST 作为 no-op 返回,不修改任何既有文件的 mtime 与 bytes;falsification:连续两次初始化后检查 `.trio/` 下每个文件 mtime 与 sha256 是否与首次初始化完成后完全一致

#### Scenario: project_frontmatter_write_once
- **WHEN** 设 `t*` 为 `/office-hours` 首次把 PROJECT.md 四个 frontmatter 键(`name`/`type`/`created_at`/`description`)都写成非空值的时刻
- **THEN** 对任意后续成功操作 `t > t*`,MUST 恒有 `frontmatter_bytes(PROJECT.md, t) == frontmatter_bytes(PROJECT.md, t*)`;falsification:在 `t*` 之后发起来自其他 skill 的修改/重试/错误恢复,尝试改动任一键、键顺序、分隔符或时间格式而不触发拒绝

#### Scenario: yaml_frontmatter_roundtrip
- **WHEN** 对 PROJECT.md 或 STATE.md 执行 `write(Y) → parse(Y) → render(Y)` 完整往返
- **THEN** 解析出的抽象结构 MUST 与原结构语义等价(键集合、值、类型、列表元素集合一致;list 字段顺序不视作语义)
- falsification:生成深层嵌套、中文多行字符串、键名含特殊符号、非标准缩进,断言 parse 后类型不漂移(字符串不被误读为数字/布尔)

#### Scenario: decisions_dedup_under_5s
- **WHEN** 对任意两条决策 `e1, e2` 满足 `key(e1) == key(e2) == (Title, Type)` 且 `|ts(e1) - ts(e2)| < 5s`
- **THEN** 去重后 `retain([..., e1, e2])` 在该 `(Title, Type)` 等价类中新增保留条目数 MUST 恰为 `1`;falsification:生成边界时间差 `4.999s / 5.000s / 5.001s`、乱序 append、RFC3339 UTC 极值与无关噪声条目

#### Scenario: decisions_append_only_superset
- **WHEN** 记 `K(log)` 为按 dedup 规则保留后的决策块集合,给定任意历史 `H` 与追加序列 `A`
- **THEN** MUST 恒有 `K(H) ⊆ K(append(H, A))`,且 `H` 中既有 block 的 bytes 不被修改或删除;falsification:构造包含重复键、近时窗冲突、远时窗同键、插入自由文本、异常中断恢复的 append 序列,断言实现不 rewrite/compact/reorder/删除

#### Scenario: commutative_decisions_append
- **WHEN** 两组针对 DECISIONS.md 的决策块追加集 `A` 与 `B`,且 `A` 与 `B` 两两无 `(Title, Type)` 冲突
- **THEN** `K(append(append(H, A), B)) == K(append(append(H, B), A))`(作为集合相等);falsification:生成两个互不冲突的块集合,多线程乱序追加,断言最终逻辑决策集合不因顺序而缩减

#### Scenario: roadmap_archive_names_unique
- **WHEN** 给定任意 ROADMAP.md 重写序列 `r1..rn`
- **THEN** 归档路径集合 `P = {archive_path_i}` MUST 两两不同,且每个已创建归档文件在其创建后 bytes 恒定不变,不存在 overwrite;falsification:生成同毫秒时间戳、预占坑 `-2/-3` 后缀、高并发连续重写,尝试触发归档名碰撞

#### Scenario: quick_streak_transition_monotone
- **WHEN** 状态转移函数 `T` 在命令入口被触发
- **THEN** MUST 恒有 `T(dev_after_parse_and_deps, s).quick_streak == 0`、`T(quick_enter_writing_plans, s).quick_streak == s.quick_streak + 1`、其余合法转移保持 `quick_streak` 不变,且不存在 time-based decay;falsification:`dev/quick` 交错、失败边界、风险确认未进入 `writing-plans`、跨日跨时区,尝试让 `quick_streak` 非法自增/自减/衰减

#### Scenario: last_updated_strictly_increasing
- **WHEN** STATE.md 在同一进程生命周期内被连续更新两次
- **THEN** `T_{n+1} > T_n`(严格递增,时钟回拨时 MUST 使用单调时钟保护);falsification:锁定/回拨系统时钟、模拟毫秒级高频连续写入,断言不产生相等或倒序的 `last_updated`

#### Scenario: trio_lock_exclusive_holder
- **WHEN** 任意时刻 `t` 观测 `.trio/.lock`
- **THEN** MUST 恒有 `|holders(.trio/.lock, t)| ≤ 1`;若某会话已持锁,任意并发竞争者 MUST 以 `exit_code == 3` 退出且对所有状态文件的读写副作用计数为 `0`;falsification:多进程同时启动、持锁进程崩溃/信号中断、锁文件残留但无持有者,尝试制造双持锁或 loser 写文件

#### Scenario: crash_resilience_auto_repair
- **WHEN** 初始化 `.trio/` 过程中任意原子步骤被中断(写签名后、写任一骨架文件前被 SIGKILL)
- **THEN** 下一次启动 MUST 从 `templates/trio-state/*.tmpl` 自动补齐缺失骨架并继续;不允许出现永久损坏或死锁;falsification:在 `fs.writeFile` 层随机抛 SIGKILL 并重启,断言下次运行不抛"文件损坏"且无残留锁
