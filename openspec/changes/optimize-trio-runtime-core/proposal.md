## Why

`trio` 的目标应该是成为 Claude Code 上的一层开发流程治理能力,而不是另一个面向用户的通用编排 CLI。

当前实现已经把 `quick/dev` 分流、风险确认、恢复决策和最小留痕做成了可执行内核,这部分方向没有问题;真正的问题是,`runtime/session/phase` 等内部机制开始占据产品表面,导致用户心智逐渐偏向“再学一套 CLI”,而不是“在 Claude Code 上获得更好的流程治理”。

这次 change 的核心目的不是推翻现有内核,而是重新收紧产品边界:保留可执行治理能力,把 `runtime/session/phase machine` 降级为内部实现,把对外叙事收回到分流、设卡、升级和恢复四件事上。

## What Changes

- **NEW**: 新增一个产品级 capability:`trio-governor`
  - 用来定义 `trio` 对用户真正承诺的能力边界
  - 只覆盖任务分流、风险拦截、流程升级和最小恢复
- **NEW**: 将现有 capability 重新定位为内部实现规格
  - `trio-session-core`
  - `trio-phase-machine`
  - `trio-data-contract`
  - `trio-adapter-protocol`
- **NEW**: 重写 change 的产品叙事
  - 在 `design.md` 中显式区分“产品表面”和“内部内核”
  - 在文档与 skill 中弱化 `runtime/session/phase` 术语
- **NEW**: 收缩对外表面
  - 用户主要只感知 `quick`、`dev`、风险确认、继续 / 重开、完整评审建议
  - 不再把内部 phase graph、runtime verb、machine-readable 状态字段作为主要产品语言
- **BREAKING**: 冻结继续扩张“第二个 CLI”方向
  - 不再把新增 runtime verb、细粒度 phase 暴露、adapter 协议细节当成产品目标
  - 后续内核演进只服务于治理能力,不再扩张用户心智

## Non-Goals

- 不把 `trio` 做成通用 coding CLI
- 不把 `trio` 做成任务执行引擎
- 不替代 Claude Code 的读代码、改代码、跑命令、跑测试能力
- 不要求用户理解 `session/runtime` verb
- 不要求用户理解内部 phase graph
- 不把 `.trio` 演化成通用工作流数据库
- 不在本次 change 中重写现有内核实现,只调整能力边界和产品定义

## Capabilities

### New Capabilities

- `trio-governor`
  - 定义 `trio` 的产品级治理表面
  - 约束用户只感知模式选择、风险确认、流程升级和最小恢复

### Modified Capabilities

- `trio-session-core`
  - 从“产品能力”降级为“内部会话驱动契约”
  - 继续负责 bootstrap、resume / restart / abort、locking 和 ownership

- `trio-phase-machine`
  - 从“用户可见流程系统”降级为“内部状态推进与 guard / gate 引擎”
  - 继续负责合法 transition、启动 guard 和 gate enforcement

- `trio-data-contract`
  - 从“产品数据面叙事”降级为“内部最小持久化边界”
  - 继续负责 `.trio` 的机器状态、原子写回和结构化记录

- `trio-adapter-protocol`
  - 从“产品集成能力”降级为“内部 adapter bridge”
  - 继续负责依赖探测、接入约束和 non-ownership 边界

## User-Facing Shape

本次调整后,`trio` 对用户的主要表面应收敛为:

- 一个主入口
  - `/trio <需求>`
- 一组兼容显式入口
  - `dev`
  - `quick`
- 三类治理信号
  - 风险确认
  - 继续 / 重开
  - 回到完整评审的建议
- 一类升级机制
  - 连续 quick 过多,或 quick 过程中暴露更高风险时,回到 `dev`

用户不应再被要求理解:

- 当前 phase 名称
- 当前 executor / provider / writer
- 当前应该调用哪个 runtime verb
- `.trio` 内部有哪些机器字段

## Impact

### Specs

- 新增 `specs/trio-governor/spec.md` 作为产品级规格
- 修改以下规格的定位与表述,使其明确为 internal implementation specs
  - `specs/trio-session-core/spec.md`
  - `specs/trio-phase-machine/spec.md`
  - `specs/trio-data-contract/spec.md`
  - `specs/trio-adapter-protocol/spec.md`

### Design

- 重写 `design.md` 的开头与结构
- 增加清晰的 boundary statement
- 将“产品表面”与“内部内核”拆成两个明确层次

### Documentation

- 重写 README 的产品定义
- 重写 USAGE 的用户语言
- 收缩 `commands/trio/dev.md` 与 `commands/trio/quick.md` 的描述
- 重写 `skills/trio-orchestrator/SKILL.md` 的前半部分,使其从“协议驱动”改为“治理驱动”

### Implementation

- 本次 change 的重点是产品边界与规格重构,不要求立即推翻现有 runtime/session 实现
- 现有内核应被保留,并继续作为治理规则的执行载体
- 后续若做代码调整,也应以“隐藏内部实现、简化用户表面”为方向,而不是继续扩张 CLI 表面
