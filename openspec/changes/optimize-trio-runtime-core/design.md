# Design: trio as Workflow Governor

## Summary

`trio` 的定位不是通用 coding CLI,也不是任务执行引擎。它是 Claude Code 上的一层开发流程治理能力,用来在 `quick` 与 `dev` 之间做分流、风险拦截、流程升级和最小恢复。

当前仓库中已经形成了一套可执行内核,包括会话驱动、状态推进、最小持久化和外部 adapter 接入边界。这些实现有价值,但它们不应成为主要用户表面。本设计的目标,是在保留这些内核的前提下,把产品定义重新收敛到治理层。

## Boundary Statement

`trio` 的主要产品表面是开发流程治理,而不是运行时控制台。

用户应当只感知:

- 当前应该走 `quick` 还是 `dev`
- 当前是否需要风险确认
- 当前是继续还是重开
- 当前是否应该回到完整评审

`session`、`runtime`、`phase machine`、`.trio` 机器字段和内部驱动命令都属于内部实现边界。它们用于保证治理规则可执行,但不应成为主要用户心智。

## Product Surface

### User-Visible Concepts

`trio` 对用户只暴露以下概念:

- `quick`
- `dev`
- 风险确认
- 继续
- 重开
- 完整评审建议
- 关键决策记录

系统不得要求用户理解以下内部概念:

- phase graph
- runtime verb
- session verb
- executor / provider / writer
- route profile
- machine-readable 状态字段

### Entry Shape

`trio` 的用户入口保持简单:

- `quick`:低风险、小范围修改
- `dev`:新功能、跨模块改动、架构调整或高风险任务

入口的职责是触发治理判断,而不是让用户操作内部会话系统。

## Governance Model

### 1. Routing

系统在任务开始时判断当前工作应走 `quick` 还是 `dev`。

`quick` 适用于:

- 改动范围局部
- 风险明确且较低
- 不涉及关键结构变化
- 不需要额外关键决策

`dev` 适用于:

- 新功能
- 跨模块修改
- 核心流程变化
- 数据结构或接口变化
- 风险边界不清
- 需要完整评审

### 2. Gating

系统必须在 quick 路径前拦截明显风险,而不是默认放行。

当任务大体适合 `quick`,但仍存在误用风险时,系统可以先要求一次轻量风险确认。当任务已经明显超出 `quick` 边界时,系统必须阻止 quick 直接开始,并引导进入 `dev`。

这里的目标不是增加流程负担,而是避免“本该重做的任务被误走轻流程”。

### 3. Escalation

系统必须在轻流程失真时,把任务升级回完整流程。

升级信号至少包括:

- 连续 quick 次数超过阈值
- quick 过程中暴露出更高风险
- quick 过程中出现新的关键决策需求
- 改动范围从局部扩展到跨模块

升级后的目标不是惩罚用户,而是让任务回到更合适的治理强度。

### 4. Recovery

系统必须支持未完成工作的最小恢复。

当宿主项目存在未结束工作时,系统只要求调用方决定两件事之一:

- 继续
- 重开

恢复语义必须使用任务语义或工作语义,不应要求用户理解内部阶段名。用户看到的应该是“上次工作是否继续”,而不是“当前 phase 停在什么状态”。

## User Interaction Contract

`trio` 的交互应该尽量短、直接、低心智负担。

系统对用户的主要输出应集中在:

- 当前模式
- 当前风险
- 当前建议
- 下一步选择

系统不应逐步展示内部阶段推进,也不应让用户参与内部状态机控制。内部 phase 可以存在,但不应成为用户交互对象。

## Minimal Record Model

`.trio` 的角色应被定义为治理痕迹,而不是产品本体。

它只需要保存治理所需的最小信息,例如:

- 当前工作模式
- 未完成工作的恢复线索
- 少量关键决策
- 必要的上下文记录
- 连续 quick 的治理信号

`.trio` 可以包含内部机器字段,但这些字段服务于实现,不构成主要用户接口。换句话说,用户应该知道“系统记住了必要上下文”,而不是“系统维护了一个复杂状态目录”。

## Internal Kernel

以下模块继续保留,但全部视为内部内核:

### session-core

负责:

- bootstrap
- ownership
- locking
- continue / restart / abort 的内部驱动语义

它支撑恢复能力,但不构成主要用户表面。

### phase-machine

负责:

- 合法状态推进
- 启动 guard
- gate enforcement
- 内部 transition consistency

它支撑风险设卡和流程升级,但内部 phase graph 不应成为用户心智。

### data-contract

负责:

- `.trio` 机器状态
- 原子写回
- 结构化记录
- append / archive / write-once 约束

它支撑最小留痕,但 `.trio` 不是面向用户直接操作的产品界面。

### adapter-bridge

负责:

- 外部依赖探测
- adapter non-ownership
- 接入边界
- 内部路由约束

它支撑与外部能力的衔接,但 adapter / provider 不是产品概念。

## Boundary Rules

为防止产品再次向“第二个 CLI”漂移,系统应长期遵守以下边界:

- 不把 runtime/session 命令当成主要用户接口
- 不把 phase graph 暴露给用户
- 不把 executor/provider/writer 当成产品语言
- 不让 adapter 持有 trio 会话状态
- 不让 `.trio` 演化成通用工作流数据库
- 不把新增 verb、细粒度状态字段或更多 phase 当成产品进展本身

产品进展应体现在治理判断更准确、交互更简洁、升级更合理,而不是内部驱动越来越多。

## Migration Direction

后续收缩应按以下方向推进:

1. 文档改写  
   README、USAGE、command 描述和 skill 说明统一改为治理语言。

2. spec 分层  
   新增产品级 `trio-governor` 规格;现有 `session-core / phase-machine / data-contract / adapter-protocol` 全部降级为 internal implementation specs。

3. 内核退幕后  
   保留现有 runtime/session 能力,但不继续把它们作为产品主叙事扩张。

4. 表面继续简化  
   后续如继续优化,应优先减少用户需要理解的概念数量,而不是增加新的控制入口。

## Design Outcome

本设计希望得到的最终状态是:

- `trio` 被理解为 Claude Code 的开发流程治理层
- 用户只感知模式、风险、升级和恢复
- 内部内核继续存在,但明确退到幕后
- 产品价值来自治理规则,而不是 CLI 表面的复杂度
