## Why

仓库 `/Users/zeus/project/pluign/README.md` 记录的「Gstack(决策)+ GSD(上下文)+ Superpowers(执行)」日常开发流程目前只是人工编排,存在三个阻断日常使用的问题:

1. **上下文污染** —— Gstack 全量 23 个 skill 元信息一次加载 >10K token(README 第 19、44 行),不做 cherry-pick 主会话还没开始写代码就已经被 skill metadata 占满。
2. **小任务过重** —— Superpowers 的 7 阶段强制管道对两行配置修改同样启动全流程,仪式感压倒产出(README 第 47 行)。
3. **跨阶段合约缺失** —— 决策层(gstack)的产物、上下文层(GSD)的状态文件、执行层(Superpowers)的 plan 之间没有统一"合约",每阶段都要重复澄清需求,决策会悄悄漂移。

## What Changes

- **NEW**: 在 `/Users/zeus/project/pluign/` 交付一个瘦身编排插件 `trio-dev`,形态为"薄壳 meta-skill + 状态文件规范 + 统一入口命令",不重写 Superpowers / gstack / GSD 的任何既有 skill。
- **NEW**: 引入统一入口 `/trio:dev <需求>`,负责串联 9 阶段工作流(`/office-hours` → `/plan-ceo-review`(可选)→ `/plan-eng-review`(硬门禁)→ 状态文件同步 → `writing-plans` → `executing-plans` + `test-driven-development` → `verification-before-completion` → `/qa` → `finishing-a-development-branch`)。
- **NEW**: 引入小任务旁路 `/trio:quick <需求>`,跳过决策与状态同步,直达 `writing-plans` → `executing-plans` → `verification-before-completion`,解决 README 第 47 行的"两行修改走全流程"痛点。
- **NEW**: 定义 `trio-state` 文件规范 —— 在宿主项目根目录生成 `.trio/` 子目录,收纳借鉴自 GSD 的 5 个文件:`PROJECT.md`、`DECISIONS.md`、`KNOWLEDGE.md`、`ROADMAP.md`、`STATE.md`,作为三层之间的合约数据面,禁止任何阶段绕开写入。
- **NEW**: 定义 `/plan-eng-review` 为硬门禁,未通过不可进入 `writing-plans`;`/plan-ceo-review` 为可选门禁,默认跳过,由 `/trio:dev --with-ceo` 显式启用。
- **NEW**: 定义安装协议 —— 本插件硬依赖 Superpowers v5.0.7(Anthropic 官方 marketplace 一键装),启动时检测 `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/` 存在;gstack 仅允许安装 cherry-pick 的 4 个 skill(`/office-hours`、`/plan-ceo-review`、`/plan-eng-review`、`/qa`),其余 19 个明确列入 `blocklist`;GSD 零安装,仅通过文件模板借鉴。
- **NEW**: 设定 token 预算硬指标:启动时插件自身加载的元信息总占用 ≤ 4K token(见 design.md 测算)。
- **BREAKING**: 不兼容宿主项目已存在的非标 `.trio/` 目录;若检测到冲突必须显式报错,拒绝静默覆盖。

## Capabilities

### New Capabilities
- `trio-orchestration`: 统一入口命令与 9 阶段工作流编排、阶段门禁与小任务旁路
- `trio-state-contract`: `.trio/` 状态文件的结构、读写协议、跨阶段合约与幂等规则
- `trio-install-protocol`: 依赖探测、Superpowers 硬依赖校验、gstack cherry-pick 安装指引、skill blocklist 执行
- `trio-token-budget`: 插件自身元信息加载的 ≤4K token 预算与违规检测

### Modified Capabilities
<!-- 本仓库 openspec/specs/ 当前为空,无既有 capability 受影响 -->

## Impact

- **新增代码目录**:`/Users/zeus/project/pluign/skills/trio-*/`(多个薄壳 skill)、`/Users/zeus/project/pluign/commands/trio/`(入口命令)、`/Users/zeus/project/pluign/templates/trio-state/`(GSD 借鉴的文件模板)。
- **新增文档**:README.md 需追加「安装与使用」章节,指向本 change;现有 README.md 第 1-49 行的叙事保留不动。
- **外部依赖**:
  - 硬依赖:Superpowers v5.0.7(已安装于 `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/`)。
  - 手动依赖:gstack 的 4 个 cherry-picked skill 需用户手动放入 `~/.claude/skills/`(README 第 48 行提到的兜底安装流程)。
  - 无运行时依赖 GSD 的任何 CLI;v2 TypeScript CLI 明确不集成。
- **受影响的宿主项目行为**:安装后会在宿主项目根目录创建 `.trio/` 目录,需要在宿主项目 `.gitignore` 建议配置中说明(由插件 README 提示,不强制修改用户文件)。
- **不受影响**:既有 `openspec/`、`.claude/commands/`、`.claude/skills/`(OpenSpec 自身生成的工件)一律不改。
