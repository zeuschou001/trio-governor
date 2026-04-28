## ADDED Requirements

### Requirement: 启动元信息可计量

系统 MUST 在每次测量时统计自身元信息的大致 token 占用,该统计不含 Superpowers 与 gstack 既有 skill 的 metadata(那部分由宿主 Claude Code harness 掌控)。

#### Scenario: 启动成本可测算
- **WHEN** 任意开发者 checkout 本仓库
- **THEN** 根目录 `scripts/measure-tokens.sh` 脚本 SHALL 输出本插件 `skills/trio-orchestrator/SKILL.md` + `commands/trio/*.md` 的分项与总 token 统计

#### Scenario: CJK 加权计量
- **WHEN** `scripts/measure-tokens.sh` 对任一文件计量 token
- **THEN** 脚本 MUST 分类计数:ASCII 字符(码点 ≤ 0x7F)按 `4 chars/token` 换算、非 ASCII 字符(含 CJK)按 `1 char × 1.5 token` 换算,对每个文件分别 `ceil()` 后求和,最终结果为全部文件之和;MUST NOT 使用字节数 `wc -c`,MUST NOT 对整体做一次性 floor

#### Scenario: 输出参考阈值
- **WHEN** 测算工具运行
- **THEN** 工具 MAY 同时输出参考阈值,例如 `commands`、`SKILL.md`、`blocklist` 与总量的建议范围
- **AND** MUST NOT 因超出参考阈值而直接失败

### Requirement: 模板文件 lazy load

系统 MUST 将 5 个状态文件模板(`templates/trio-state/{PROJECT,DECISIONS,KNOWLEDGE,ROADMAP,STATE}.md.tmpl`)设为按需加载,不计入启动 token 成本,仅在首次初始化 `.trio/` 时读取。

#### Scenario: 模板不进启动加载
- **WHEN** Claude Code 加载本插件的 skill metadata
- **THEN** 模板文件 MUST NOT 出现在 SKILL.md 的正文或引用路径中,SKILL.md 仅记录模板文件的相对路径字符串

#### Scenario: 首次初始化读取模板
- **WHEN** `/trio:dev` 首次初始化 `.trio/` 目录
- **THEN** 系统 SHALL 从仓库 `templates/trio-state/` 读取 5 个模板文件,写入宿主项目 `.trio/` 对应文件

#### Scenario: 白名单 sed 占位符替换
- **WHEN** 系统从任一模板生成目标状态文件
- **THEN** 系统 MUST 使用仓库内置的白名单替换器(纯 `sed` 逐键替换),仅替换预定义占位符 `{{name}}` / `{{type}}` / `{{created_at}}` / `{{description}}` / `{{version}}` / `{{timestamp}}`;MUST NOT 调用 `envsubst`、mustache 或任何 shell `eval`;若替换后的输出仍包含 `{{` 序列 MUST 硬失败并提示 "模板占位符未全部替换,拒绝写入"

### Requirement: Token 统计不做强制门禁

系统 MUST 允许在 CI(或等价的本地手动流程)中运行 token 测算,但当前阶段不将测算结果作为构建失败门禁。

#### Scenario: 统计脚本默认成功
- **WHEN** `scripts/measure-tokens.sh` 成功读到被测文件
- **THEN** 脚本 MUST 以 0 退出码结束
- **AND** SHOULD 打印统计结果供开发者观察

#### Scenario: 超出参考值仍继续
- **WHEN** 任一分项或总量超过参考值
- **THEN** 脚本 MAY 输出提示
- **AND** MUST NOT 作为强制门禁阻断 CI 或本地流程

### Requirement: 禁止在 SKILL.md 内嵌完整工作流步骤

系统 MUST 禁止在 `skills/trio-orchestrator/SKILL.md` 内嵌完整的 9 阶段工作流详细步骤文本,详细步骤 MUST 以对外部 skill 的跳转引用表达(例如 `调用 Superpowers:writing-plans`),不得复制其内容。

#### Scenario: SKILL.md 只做编排
- **WHEN** 开发者修改 `skills/trio-orchestrator/SKILL.md`
- **THEN** 该文件 MUST 不包含 `writing-plans`、`executing-plans`、`test-driven-development` 等外部 skill 的完整操作细节,仅声明"在此阶段调用 <skill 名>"

#### Scenario: 内嵌检测
- **WHEN** `scripts/measure-tokens.sh` 运行
- **THEN** 脚本 MUST 额外扫描 `skills/trio-orchestrator/SKILL.md`,若发现包含 `## Step` / `### Step` 深度大于 2 层的子步骤,打印 warning "疑似内嵌外部 skill 细节,请改为跳转引用"

### Requirement: 属性化不变量(PBT)

系统 MUST 满足以下针对 token 预算与模板渲染的属性化不变量。

#### Scenario: template_whitelist_total_substitution
- **WHEN** 给定模板 `T`,若 `placeholders(T) ⊆ Whitelist = {{{name}}, {{type}}, {{created_at}}, {{description}}, {{version}}, {{timestamp}}}`,且映射 `M` 对 `placeholders(T)` 全定义且任一值 `v` 中不含 `{{` 序列
- **THEN** 成功渲染结果 `R(T, M)` MUST 满足 `"{{" ∉ R(T, M)`;若渲染后仍包含 `{{` MUST 硬失败拒绝写入;falsification:占位符重复、缺键、未知键、相邻占位符、空值、长值、值中含 braces/shell metacharacters/多行,尝试让 sed 串扰或错误通过

#### Scenario: token_budget_cjk_bounds
- **WHEN** `scripts/measure-tokens.sh` 对 `skills/trio-orchestrator/SKILL.md` + `commands/trio/*.md` 执行 CJK 加权计量(ASCII 按 4 chars/token,非 ASCII 按 1.5 token/char,分文件 ceil 后求和)
- **THEN** 工具 MUST 稳定输出合计统计与分项统计
- **AND** MAY 输出参考阈值提示
- **AND** MUST NOT 因数值高低改变成功退出语义;falsification:构造刚好贴参考边界的 CJK 文本、纯 ASCII 边界、CJK+ASCII 混合接近边界,断言分类与求和正确
