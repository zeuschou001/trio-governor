# 安装

## 1. 安装 Superpowers 执行依赖(硬依赖,推荐 v5.0.7+)

通过 Claude Code 官方 marketplace 一键安装:

```text
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

版本 `<5.0.7` 仅在启动时打印 warning,不阻塞;5 个必需 skill(`writing-plans` / `executing-plans` / `test-driven-development` / `verification-before-completion` / `finishing-a-development-branch`)任一缺失则硬失败。

## 2. 可选安装 gstack 评审依赖(软依赖)

`trio-dev` 只使用 4 个 gstack skill:`office-hours`、`plan-ceo-review`、`plan-eng-review`、`qa`。缺失时仍可用 `--minimal` 跳过更重的评审路径。

```bash
for s in office-hours plan-ceo-review plan-eng-review qa; do
  mkdir -p ~/.claude/skills/$s
  curl -o ~/.claude/skills/$s/SKILL.md \
    https://raw.githubusercontent.com/garrytan/gstack/main/$s/SKILL.md
done
```

实际依赖检查由 `./trio detect` 完成。

## 3. macOS 的 `flock`

Linux 内置 `flock`。macOS 没有;本仓库 `scripts/bin/flock` 提供 Python shim,脚本会自动 fallback。若想使用系统级 `flock`,执行 `brew install util-linux && brew link --force util-linux`。

## 4. 安装仓库本地开发者工具 `./trio`

```bash
git clone <本仓库> trio-governor && cd trio-governor
./trio install
```

安装脚本会:

1. 运行 `./trio detect`,校验依赖并输出告警。
2. 在 `~/.claude/skills/trio-orchestrator` 与 `~/.claude/commands/trio` 建立指向本仓库的 symlink。
3. 保留治理逻辑与内部驱动在仓库本地执行。
4. 幂等执行:symbolic link 已正确时静默跳过,目标错误时重建,若路径上已存在普通文件或目录则硬失败。

`./trio` 的定位是开发者内部工具,主要用于安装、诊断和内部调试,不是日常用户入口。

重启 Claude Code 后,主入口是 `/trio <需求>`。仓库内保留的显式 `dev` / `quick` 入口仅作为兼容或调试面。内部 runtime / session 驱动仅供插件自身和调试使用。

## 卸载

```bash
./trio uninstall
```

仅删除本插件的 symlink,不触碰 Superpowers、gstack 或宿主项目里的 `.trio/` 数据。
