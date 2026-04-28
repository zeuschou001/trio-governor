## 1. 仓库骨架与元信息

- [x] 1.1 在 `/Users/zeus/project/pluign/` 创建目录结构:`skills/trio-orchestrator/`、`commands/trio/`、`templates/trio-state/`、`scripts/`、`tests/`
- [x] 1.2 创建 `package.json`(仅用于版本号管理,`name: "trio-dev"`,`version: "0.1.0"`)或 `VERSION` 文本文件;不引入任何 npm runtime 依赖
- [x] 1.3 在 README.md 末尾(第 49 行之后)追加 `## trio-dev 插件化实现` 章节,链接到 `openspec/changes/add-trio-dev-orchestrator/`
- [x] 1.4 创建 `.gitignore`,忽略 `.trio/archive/`、`node_modules/`(防御性)

## 2. 状态文件模板(trio-state-contract)

- [x] 2.1 编写 `templates/trio-state/PROJECT.md.tmpl`,含占位字段 `{{name}}`、`{{type}}`、`{{created_at}}`、`{{description}}`
- [x] 2.2 编写 `templates/trio-state/DECISIONS.md.tmpl`,骨架含 `# Decisions Log` 与 `## Decision:` 示例
- [x] 2.3 编写 `templates/trio-state/KNOWLEDGE.md.tmpl`,骨架含 `## Insight:` 示例
- [x] 2.4 编写 `templates/trio-state/ROADMAP.md.tmpl`,空骨架仅含 `# Roadmap`(由 writing-plans 覆盖写)
- [x] 2.5 编写 `templates/trio-state/STATE.md.tmpl`,含字段 `current_phase: init`、`completed_phases: []`、`quick_streak: 0`、`superpowers_version: unknown`
- [x] 2.6 编写 `templates/trio-state/.trio-signature.tmpl`(纯文本,含占位 `{{version}}` 与 `{{timestamp}}`)

## 3. 入口命令(trio-orchestration 的 commands)

- [x] 3.1 编写 `commands/trio/dev.md`,定义 `/trio:dev <需求>` 入口,描述用途与参数 `--with-ceo`、`--minimal`,不内嵌工作流细节(细节在 meta-skill 中);保持 ≤ 200 token
- [x] 3.2 编写 `commands/trio/quick.md`,定义 `/trio:quick <需求>` 小任务旁路入口;保持 ≤ 200 token

## 4. Meta-skill 核心(trio-orchestration)

- [x] 4.1 编写 `skills/trio-orchestrator/SKILL.md`,含 YAML frontmatter(`name: trio-orchestrator`、`description: ...`);正文含 9 阶段流程 ASCII 图、阶段切换协议、硬门禁与软门禁规则、旁路协议;禁止内嵌外部 skill 细节;总长 ≤ 2500 token
- [x] 4.2 在 SKILL.md 中以结构化列表内嵌 blocklist 的 19 个 gstack skill 名(≤ 300 token)
- [x] 4.3 在 SKILL.md 中声明状态文件读写协议:每个文件的责任方、消费方、幂等规则,引用 `.trio-signature` 冲突检测流程
- [x] 4.4 在 SKILL.md 中声明"所有用户交互仅在阶段边界发生"的硬约束(规避 Medium 报告的 Superpowers Q&A 阻塞问题)
- [x] 4.5 在 SKILL.md 中声明 `/plan-eng-review` 硬门禁检查算法(扫描 DECISIONS.md 的 `Type: eng-review` 条目)

## 5. 依赖探测与安装协议(trio-install-protocol)

- [x] 5.1 编写 `scripts/detect-deps.sh`(或 node script),实现 Superpowers 5 个必需 skill 的目录探测;缺失输出安装命令并退出码非 0
- [x] 5.2 在 detect-deps 中加入 Superpowers 版本号提取逻辑(从路径 `superpowers/<version>/` 提取),版本 < 5.0.7 打印 warning
- [x] 5.3 实现 gstack 4 skill 探测逻辑,缺失打印对应 `curl` 安装指令(指向 github raw URL)
- [x] 5.4 实现 SKILL.md YAML frontmatter `name` 字段校验(确认用户没放错文件)
- [x] 5.5 实现 blocklist 19 skill 扫描,违规列出并打印 warning
- [x] 5.6 编写 `trio install` bash 脚本:调用 detect-deps,建立 2 个 symlink,幂等性处理(已存在 symlink 时检查目标正确性)
- [x] 5.7 编写 `trio uninstall` bash 脚本:仅删除本插件的 2 个 symlink,不触碰其他文件
- [x] 5.8 编写 `trio install` / `trio uninstall` 的入口 `trio` 脚本(bash dispatcher,把 `trio install` 路由到 `scripts/install.sh`)

## 6. Token 预算工具(trio-token-budget)

- [x] 6.1 编写 `scripts/measure-tokens.sh`:对 `skills/trio-orchestrator/SKILL.md`、`commands/trio/*.md` 做字符数统计,按 4 chars/token 换算
- [x] 6.2 在 measure-tokens 中实现分项报告:总数 + 各文件单项,输出参考阈值与当前统计
- [x] 6.3 在 measure-tokens 中实现 SKILL.md 子步骤深度扫描(`grep -c '^### Step' / '^## Step'`),超过 2 层深度打印 warning
- [x] 6.4 统计脚本默认成功退出,仅提供测量信息与提示,不作为强制门禁

## 7. CI 与测试

- [x] 7.1 编写 `.github/workflows/budget.yml`(或等价本地 `scripts/ci.sh`),运行 measure-tokens;为本地仓库仅提供本地脚本即可
- [x] 7.2 编写 `tests/detect-deps.bats`(或 shell 脚本),mock 不同依赖状态,验证 detect-deps 正确区分 硬失败 / 软提示 / blocklist warning
- [x] 7.3 编写 `tests/install.bats`,验证 install 幂等性(连跑 2 次结果相同)、uninstall 不触碰 superpowers 目录
- [x] 7.4 编写 `tests/state-contract.bats`:初始化 `.trio/`、验证 `.trio-signature` 生成、二次初始化(无签名)硬失败、`PROJECT.md` 二次重写被拒绝
- [x] 7.5 编写 `tests/decisions-protocol.bats`:验证 DECISIONS.md 追加格式校验、5 秒内重复条目去重

## 8. 硬门禁与旁路集成

- [x] 8.1 在 SKILL.md 中写明 `/plan-eng-review` 硬门禁流程(无 `Type: eng-review` 条目则拒进 `writing-plans`)
- [x] 8.2 在 SKILL.md 中写明 `/plan-ceo-review` 软门禁触发条件(`--with-ceo` 或 PROJECT.md `type: user-facing-feature`)
- [x] 8.3 在 `commands/trio/quick.md` 中声明 `/trio:quick` 强制启用 `test-driven-development`,不允许跳过
- [x] 8.4 在 SKILL.md 中写明 `quick_streak > 3` 的警告触发与重置逻辑

## 9. 文档与最终验收

- [x] 9.1 在仓库根目录写一份 `INSTALL.md`,分 3 节:前置依赖(Superpowers)、4 个 gstack skill 手动安装、`trio install` 执行
- [x] 9.2 在仓库根目录写一份 `USAGE.md`,分两部分:`/trio:dev` 完整流程走查、`/trio:quick` 小任务走查
- [x] 9.3 在 `USAGE.md` 中用一张表格说明 `.trio/` 每个文件的责任方、消费方、幂等规则(与 design.md 的 D3 对齐)
- [x] 9.4 运行 `scripts/measure-tokens.sh` 记录当前统计结果,作为后续瘦身参考
- [x] 9.5 在干净的 `~/.claude/` mock 目录中端到端手工跑一遍 `/trio:dev "测试需求"` → `/trio:quick "测试需求"`,验证 9 阶段 / 3 阶段分别走通
- [x] 9.6 运行 `openspec validate add-trio-dev-orchestrator --strict` 确保所有 spec 通过严格校验
