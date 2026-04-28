## Context

仓库 `/Users/zeus/project/pluign/` 目前只承载一份 README.md(第 1-49 行),描述了作者手工编排 Gstack + GSD + Superpowers 三大框架的日常开发流程。本 change 将该人工流程产品化为单一插件 `trio-dev`,宿主为 Claude Code 的 skill / command 系统。

**既有外部事实(作为设计输入,不可再讨论):**
- Superpowers 已通过 Anthropic 官方 marketplace 安装于本机 `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/`,含 14 个 skill(`brainstorming`、`writing-plans`、`executing-plans`、`test-driven-development`、`verification-before-completion`、`finishing-a-development-branch`、`subagent-driven-development`、`dispatching-parallel-agents`、`requesting-code-review`、`receiving-code-review`、`systematic-debugging`、`using-git-worktrees`、`using-superpowers`、`writing-skills`)。本插件必须复用而非重写其中任何一个。
- gstack 上游仓库 `garrytan/gstack` 提供 23+ skill,本插件 cherry-pick 其中 4 个(`/office-hours`、`/plan-ceo-review`、`/plan-eng-review`、`/qa`),其余 19 个拒绝安装。
- GSD v2 是独立的 TypeScript CLI 进程,不适合作为 skill 集成;本插件仅借鉴 GSD v1 Markdown 风格的 5 个状态文件命名与职责。
- 中立评测(Medium, 2026-04-06)确认"Superpowers 交互式 Q&A 在 build 阶段会阻塞 Claude Code 输入流",是本设计必须规避的硬约束。

**宿主项目假设:** `trio-dev` 被安装到任意宿主项目 A 的根目录,在 A 下生成 `.trio/` 目录承载状态文件。宿主项目 A 的既有代码、git 历史、CI 均不被本插件修改。

## Goals / Non-Goals

**Goals:**
1. 以 ≤4K token 的元信息加载成本,让用户在任意宿主项目中通过 `/trio:dev <需求>` 完整跑完 README 描述的 9 阶段流程。
2. 用 `.trio/` 状态文件作为跨阶段唯一事实源,消除 Gstack / Superpowers 之间的需求重复澄清。
3. 提供 `/trio:quick` 旁路,使两行修改类小任务能跳过决策与状态同步,3 阶段内完成,直接回应 README 第 47 行痛点。
4. 把 `/plan-eng-review` 做成硬门禁(未通过阻止进入 `writing-plans`),防止架构决策被悄悄绕过。
5. 在插件启动时显式探测依赖(Superpowers 硬必需、gstack 4 skill 软提示、blocklist 检测),依赖缺失给出精确修复指令。

**Non-Goals:**
- **不重写** Superpowers / gstack / GSD 的任何既有 skill —— 仅编排。
- **不集成 GSD v2 CLI** —— 任何子进程、管道、TypeScript 运行时一律不引入。
- **不发行到任何 marketplace** —— 仅作为仓库内资产,用户手动 symlink 或复制到 `~/.claude/skills/`。
- **不处理多项目并行开发** —— 单一宿主项目单一会话,git worktree 留给 Superpowers 的 `using-git-worktrees` 负责。
- **不做浏览器测试、部署、安全审计** —— gstack 的 `/cso`、`/ship`、`/browse` 等 19 个被 blocklist 的 skill 对应的能力,本插件一概不提供。
- **不改写宿主项目的 `.gitignore` 或 CI 配置** —— 仅在自己 README 里给出建议文本,是否采纳由用户决定。

## Decisions

### D1. 插件形态选型:薄壳编排器(形态 C)

**决定:** 采用"薄壳 meta-skill + 状态文件规范 + 入口命令"形态,不重写三大框架任何 skill。

**备选方案:**
- (A) 纯编排器:直接透传三个框架的原生命令。代价:token 爆炸,gstack 23 skill 全加载。
- (B) 重写蒸馏:自己重写决策+上下文+执行逻辑。代价:维护成本翻倍且放弃上游红利;与 Superpowers 的 TDD 强制删除逻辑重复造轮子。
- **(C) 瘦身编排器 ← 选用:** cherry-pick 4 个 gstack skill,复用全部 Superpowers,GSD 只借鉴文件规范。代价最小,精准命中 README 列出的 3 个痛点。

**理由:** 形态 A 无法解决 token 污染(README 第 19 行);形态 B 抛弃 Superpowers 官方 marketplace 的一键安装红利且失去上游更新;形态 C 是三者中唯一同时满足「复用红利」与「token 预算」的选项。

### D2. 入口命令结构:两命令(dev + quick),非状态机

**决定:** 只提供两个用户入口 `/trio:dev <需求>` 与 `/trio:quick <需求>`;阶段推进通过**阶段边界用户确认**而非隐式状态机。

**备选方案:**
- (A) 四阶段独立命令 `/trio:decide` / `/trio:pin` / `/trio:execute` / `/trio:qa`:用户负担大,易跳步。
- (B) 隐式状态机,记住当前阶段:持久化状态复杂,不同会话之间易错乱。
- **(C) dev + quick,阶段边界显式确认 ← 选用**

**理由:** README 第 47 行小任务痛点需要旁路,因此必须有 `/trio:quick`;阶段边界用户确认可以规避 Medium 报告的"Superpowers 交互式 Q&A 阻塞输入流"问题——所有交互收敛到 meta-skill 自己掌控的阶段切换点,不在 Superpowers 子阶段内部追加提问。

### D3. 状态文件协议:.trio/ 目录 + 5 文件契约

**决定:** 在宿主项目根目录生成 `.trio/`,包含:

| 文件 | 责任方(谁写) | 消费方(谁读) | 幂等规则 |
|---|---|---|---|
| `PROJECT.md` | `/trio:dev` 首次运行 | 所有阶段 | 仅初次生成,后续只能追加不能重写 |
| `DECISIONS.md` | `/plan-ceo-review`、`/plan-eng-review` 结束后 | `writing-plans` | 追加式,每条决策带时间戳 |
| `KNOWLEDGE.md` | `executing-plans`、`/qa` | `writing-plans`、`verification-before-completion` | 追加式 |
| `ROADMAP.md` | `writing-plans` | `executing-plans` | 每次 `writing-plans` 覆盖式重写,旧版归档到 `.trio/archive/` |
| `STATE.md` | `/trio:dev` 编排器每个阶段结束 | 编排器自身(下次启动恢复进度) | 原地更新 |

**备选方案:** 单文件 `.trio/state.json`。拒绝理由:Superpowers 写计划读文件更适合 Markdown;JSON 让用户不可读。

**理由:** GSD v1 的 5 文件分法在实际项目中被验证能降低 context rot([DEV 文章](https://dev.to/imaginex/a-claude-code-skills-stack-how-to-combine-superpowers-gstack-and-gsd-without-the-chaos-44b3));本插件直接沿用其文件名与职责,学习曲线为零。

### D4. 门禁策略:架构硬禁、产品软禁

**决定:** `/plan-eng-review` 为硬门禁,其产物未写入 `DECISIONS.md` 则 `/trio:dev` 拒绝进入 `writing-plans` 阶段;`/plan-ceo-review` 为默认跳过的软门禁,由 `--with-ceo` 显式启用,或 `PROJECT.md` 声明 `"type": "user-facing-feature"` 时自动启用。

**备选方案:** 两者都硬禁 / 两者都软禁 / 反过来。

**理由:** gstack 官方文档明示"CEO Review (optional): Use your judgment. Recommend it for big product/business changes..."([plan-ceo-review SKILL.md](https://github.com/garrytan/gstack/blob/main/plan-ceo-review/SKILL.md));架构评审则关系到下游 `writing-plans` 的输入形状,放过架构坑会让 TDD 阶段的测试从源头写错。

### D5. 小任务旁路 `/trio:quick` 的阶段集

**决定:** 旁路仅包含 3 阶段:`writing-plans` → `executing-plans`(含 TDD)→ `verification-before-completion`。跳过所有 gstack 阶段和状态文件同步;仅追加一条到 `KNOWLEDGE.md`。

**备选方案:**
- 旁路跳过 TDD:违反 Superpowers 核心契约,拒绝。
- 旁路只跑 `executing-plans`:跳过 `writing-plans` 会让 Superpowers 无法启动 TDD 循环(其 SKILL.md 明确要求先有 plan)。

**理由:** TDD 不可妥协(Superpowers 的 `test-driven-development` skill 会强制删除先写的实现代码),但决策层对两行 config 修改确实过重,删除到 3 阶段是保留 Superpowers 最小骨架的极限。

### D6. 依赖探测与 blocklist 执行

**决定:** `/trio:dev` 首次加载时执行:
1. 探测 Superpowers:检查 `~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/writing-plans/`(版本号用 glob,允许 5.0.7+)。缺失则硬失败,给出 `/plugin marketplace add obra/superpowers-marketplace && /plugin install superpowers@superpowers-marketplace`。
2. 探测 gstack 4 skill:检查 `~/.claude/skills/plan-ceo-review/`、`~/.claude/skills/plan-eng-review/`、`~/.claude/skills/office-hours/`、`~/.claude/skills/qa/`。任一缺失给出具体 wget 指令(指向 `github.com/garrytan/gstack/<skill>/SKILL.md` 的原始路径),但不硬失败——`/trio:dev --minimal` 可跳过 gstack 层。
3. 检测 blocklist:若发现 `~/.claude/skills/` 含 gstack 19 个黑名单 skill 之一(`design-consultation`、`cso`、`careful`、`freeze`、`guard`、`unfreeze`、`learn`、`retro`、`benchmark`、`setup-deploy`、`browse`、`connect-chrome`、`setup-browser-cookies`、`document-release`、`canary`、`ship`、`land-and-deploy`、`autoplan`、`gstack-upgrade`),输出 warning 并建议删除;不硬失败。

**备选方案:** 不做探测,让用户自己踩坑。拒绝理由:README 第 48 行已经明确用户前一次踩过"skill 不全"的坑。

### D7. Token 预算:≤4K 的执行方式

**决定:** 预算分解:
- 入口命令 `trio:dev` / `trio:quick` 两个 command 描述:≤ 400 token
- 1 个 meta-skill `trio-orchestrator/SKILL.md`:≤ 2500 token(含 9 阶段流程图、状态文件协议索引、依赖探测流程)
- 5 个文件模板各 ≤ 200 token,不在启动时加载(lazy load,仅首次生成时写入):≤ 0 token 启动成本
- blocklist 列表内嵌在 meta-skill 中:≤ 300 token
- 合计启动成本 ≈ 3200 token,留 800 token 余量

**备选方案:** 把 9 阶段拆成 9 个独立 skill —— 会爆预算 3 倍以上。拒绝。

**理由:** Claude Code skill metadata 按 SKILL.md 整文件算入上下文([Anthropic skills doc 原理](https://docs.anthropic.com/),2026 版合并 slash commands + skills 为统一格式)。保持单 skill 是守住预算的唯一途径。

### D8. 与 README 叙事的关系

**决定:** 保留 `/Users/zeus/project/pluign/README.md` 第 1-49 行原样不动;在文件末尾追加一节「trio-dev 插件化实现」,链接到 `openspec/changes/add-trio-dev-orchestrator/`。原叙事作为设计动机的"一手证人",后续迭代不再修改这 49 行。

## Risks / Trade-offs

| # | 风险 | 缓解 |
|---|---|---|
| R1 | Superpowers 上游升级到 6.x 时 skill 名可能变 | 依赖探测用 skill 名 + 必备文件而非固定版本号;meta-skill 定期回归测试;在 `installed_plugins.json` 中读取实际版本并记录到 STATE.md,升级时给出 warning |
| R2 | 用户手动安装 gstack 4 skill 时复制错文件 | 探测时校验 SKILL.md 开头 `---` YAML frontmatter 的 `name` 字段必须匹配 `plan-ceo-review` 等 4 个预期值 |
| R3 | `.trio/` 目录与用户现有同名目录冲突 | 首次启动严格检测:`.trio/` 存在且不含本插件签名文件 `.trio/.trio-signature` → 硬失败,要求用户手动迁移 |
| R4 | gstack 更新后 cherry-picked 4 skill 的 prompt 内容改变,破坏 DECISIONS.md 合约 | 在 meta-skill 中写明"只消费 DECISIONS.md 中 `## Decision:` 二级标题下的 `- **What/Why/Impact**` 三元组,其他格式一律忽略",把消费面收敛到结构化字段 |
| R5 | Token 预算超限 | CI/手工:用 `wc -w openspec/changes/*/*.md skills/**/*.md` 换算估算,超 800 token 警戒线触发文档瘦身 |
| R6 | 小任务旁路被滥用,用户在应该决策时走 quick 导致架构漂移 | `/trio:quick` 首次使用打印警告"此命令跳过所有决策审查,仅用于 <50 行或纯配置修改";STATE.md 记录 quick 使用次数,连续 >3 次 quick 建议用户回归 `/trio:dev` |
| R7 | `/plan-eng-review` 硬门禁被用户绕过(直接手写 ROADMAP.md) | 守规则不守 hack —— meta-skill 仅检查 DECISIONS.md 是否存在架构决策条目;用户若刻意绕过不负责阻止,但 `/qa` 会读 DECISIONS.md 对比实现发现漂移 |
| R8 | Medium 文章提到的"交互式 Q&A 阻塞 Claude Code 输入流" | 本插件所有交互收敛到阶段边界由 meta-skill 提问,不在 Superpowers 子 skill 内部追加交互;`executing-plans` 若内部触发交互,由 Claude Code 主会话正常处理,与本插件无关 |

## Migration Plan

**首次安装:**
1. 用户克隆本仓库 `git clone <repo> pluign`。
2. 运行 `trio install`(由本插件提供的 bash 脚本),它会:
   - 校验 Superpowers v5.0.7+ 存在,缺失则打印安装命令并退出。
   - 检查 gstack 4 skill,缺失则打印 4 条 `curl -o ~/.claude/skills/...` 命令。
   - 把本仓库 `skills/trio-orchestrator/` symlink 到 `~/.claude/skills/trio-orchestrator/`。
   - 把本仓库 `commands/trio/` symlink 到 `~/.claude/commands/trio/`。
3. 重启 Claude Code 生效。

**回滚:**
- `trio uninstall` 反向删除 symlink,不动 Superpowers 与 gstack 原有文件。

**升级:**
- 本插件自己的升级通过 `git pull`,symlink 自动生效。
- Superpowers / gstack 的升级不在本插件掌控范围。

## Open Questions

- **Q1**: `/trio:dev` 是否需要支持从中途恢复?(例如上次跑到 `writing-plans` 被中断,下次直接从 `writing-plans` 继续)。当前设计 STATE.md 已记录进度,但恢复逻辑复杂;倾向**首版本不实现,打印提示让用户手工续跑**,放到 v2。
- **Q2**: gstack cherry-pick 列表是否需要配置化?目前硬编码 4 个。若用户想多加一个(例如 `/investigate`),是否允许?倾向**首版本硬编码,v2 允许 `~/.trio/allowlist.json` 扩充**。
- **Q3**: 本插件的 meta-skill 是否应同时兼容 Codex / Gemini CLI?Superpowers 与 gstack 都兼容多 agent,但本插件用的 skill 语法目前紧贴 Claude Code。倾向**首版本仅 Claude Code,GEMINI.md/AGENTS.md 在 v2 补齐**。
