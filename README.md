# trio-governor

`trio` 是 Claude Code 上的一层开发流程治理插件。它的主入口是 `/trio <需求>`,负责在 `quick` 与 `dev` 之间做分流、风险拦截、流程升级和最小留痕。

## 它解决什么问题

Claude Code 很擅长执行代码工作,但不天然负责开发流程治理。`trio` 用来补这一层:

- 判断当前任务该走快速旁路还是完整流程
- 在风险升高时阻止“直接开做”
- 在连续小修过多时把任务拉回完整评审
- 为未完成工作保留最小恢复线索

## 主要入口

- `/trio <需求>`: 默认入口。用户只描述目标,`trio` 自己判断该走 `quick` 还是 `dev`
- 显式 `dev` / `quick` 入口: 仅保留为兼容或强制路由面,不再作为主要心智

## 两种模式

- `quick`: 适合低风险、小范围修改,例如局部修复、配置调整、样式或文案修改
- `dev`: 适合新功能、跨模块改动、架构调整和较高风险任务

## 它如何介入

`trio` 不替代 Claude Code 做代码工作。它只在以下时刻介入:

- 任务开始时:判断走 `quick` 还是 `dev`
- 风险不清楚时:要求先做风险确认或直接升级流程
- 连续 quick 过多时:建议回到 `dev` 做一次完整评审
- 上次工作未完成时:要求决定继续还是重开

## 最小留痕

`trio` 只保留治理所需的最小痕迹,例如:

- 当前工作模式
- 少量关键决策
- 必要的上下文记录
- 未完成任务的恢复线索

## 开发者工具

仓库根目录下的 `./trio` 不是主要用户入口。它是仓库本地开发者工具,主要用于:

- 安装与卸载
- 依赖诊断
- 内部 runtime / session 调试
- 外部 bridge export / handoff / review / draft / scaffold / status 调试

日常使用应优先走 `/trio`。`./trio` 与显式 `dev` / `quick` 入口都属于内部调试或兼容面。

## 文档

- 安装:[`INSTALL.md`](INSTALL.md)
- 使用:[`USAGE.md`](USAGE.md)
- 设计文档与规范:[`openspec/changes/optimize-trio-runtime-core/`](openspec/changes/optimize-trio-runtime-core/)

## 本地验证

```bash
./scripts/measure-tokens.sh
./scripts/ci.sh
openspec validate optimize-trio-runtime-core --strict
```

`measure-tokens` 当前只做计量统计,不作为强制门禁。内部实现包含若干 runtime / session 驱动,通过 `./trio` 暴露给开发者做安装与调试,不构成主要用户接口。
