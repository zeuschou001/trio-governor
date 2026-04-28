## ADDED Requirements

### Requirement: Superpowers 硬依赖探测

系统 MUST 在启动时验证 Superpowers 插件已安装且提供必需的 5 个 skill(`writing-plans`、`executing-plans`、`test-driven-development`、`verification-before-completion`、`finishing-a-development-branch`),缺失任一则硬失败。

#### Scenario: 探测成功继续启动
- **WHEN** 启动时在 `~/.claude/plugins/cache/claude-plugins-official/superpowers/<version>/skills/` 下找到全部 5 个必需 skill 目录
- **THEN** 系统 SHALL 将探测到的实际版本号写入 STATE.md 的 `superpowers_version` 字段,继续后续流程

#### Scenario: 多版本解析优先级
- **WHEN** `~/.claude/plugins/cache/claude-plugins-official/superpowers/` 下存在多个形如 `X.Y.Z` 的一级目录
- **THEN** 系统 MUST 枚举全部目录,按 semver 语义排序,从高到低扫描,选中第一个同时包含全部 5 个必需 skill 的版本;若所有版本均缺失任一必需 skill 则按 "任一必需 skill 缺失硬失败" 处理

#### Scenario: 任一必需 skill 缺失硬失败
- **WHEN** 启动时检测到 5 个必需 skill 任一目录不存在
- **THEN** 系统 MUST 中止启动,打印完整修复指令 `/plugin marketplace add obra/superpowers-marketplace && /plugin install superpowers@superpowers-marketplace`,退出码非 0

#### Scenario: 版本过低警告
- **WHEN** 探测到 Superpowers 版本 < 5.0.7
- **THEN** 系统 MUST 打印 warning "当前 Superpowers 版本 <version> 低于推荐 5.0.7,可能存在兼容性问题",但 MUST NOT 中止启动

### Requirement: gstack cherry-pick 4 skill 软依赖

系统 SHALL 软依赖 gstack 的 4 个 cherry-picked skill(`office-hours`、`plan-ceo-review`、`plan-eng-review`、`qa`),缺失时给出精确安装指令但允许 `--minimal` 模式跳过。

#### Scenario: 软依赖缺失给出修复指令
- **WHEN** 启动时检测到 `~/.claude/skills/plan-eng-review/SKILL.md` 不存在
- **THEN** 系统 MUST 打印 `mkdir -p ~/.claude/skills/plan-eng-review && curl -o ~/.claude/skills/plan-eng-review/SKILL.md https://raw.githubusercontent.com/garrytan/gstack/main/plan-eng-review/SKILL.md`,并对其余缺失 skill 依次打印

#### Scenario: 最小模式跳过软依赖
- **WHEN** 用户调用 `/trio:dev <需求> --minimal`
- **THEN** 系统 MUST 跳过 gstack 4 skill 探测,跳过决策层阶段(`/office-hours`、`/plan-ceo-review`、`/plan-eng-review`),仅运行 Superpowers 层(`writing-plans` 及之后)加 `/qa`(若 `/qa` 也缺失则跳过)

### Requirement: SKILL.md frontmatter 签名校验

系统 MUST 校验 gstack 4 skill 的 SKILL.md 首部 YAML frontmatter 的 `name` 字段匹配预期值,防止用户复制了错误文件。

#### Scenario: frontmatter name 字段匹配
- **WHEN** 探测 `~/.claude/skills/plan-eng-review/SKILL.md` 存在
- **THEN** 系统 MUST 读取其 YAML frontmatter 的 `name` 字段,与预期值 `plan-eng-review` 做精确字符串匹配

#### Scenario: frontmatter 不匹配报错
- **WHEN** 探测到 SKILL.md 存在但 `name` 字段不匹配预期值(例如用户放错了文件)
- **THEN** 系统 MUST 打印 "`~/.claude/skills/plan-eng-review/SKILL.md` 的 frontmatter name 为 <实际值>,预期 plan-eng-review;请重新下载",视为该 skill 缺失

### Requirement: gstack blocklist 扫描

系统 MUST 维护一份 19 个 gstack skill 的 blocklist(`design-consultation`、`cso`、`careful`、`freeze`、`guard`、`unfreeze`、`learn`、`retro`、`benchmark`、`setup-deploy`、`browse`、`connect-chrome`、`setup-browser-cookies`、`document-release`、`canary`、`ship`、`land-and-deploy`、`autoplan`、`gstack-upgrade`),在启动时扫描 `~/.claude/skills/` 检测违规。

#### Scenario: 发现 blocklist skill 打印 warning
- **WHEN** 启动时扫描 `~/.claude/skills/` 第一级子项(不递归),以 basename 与 19 个 blocklist 名称做 case-sensitive 精确匹配,符号链接与真实目录同等对待(不解引用其目标)
- **THEN** 系统 MUST 列出全部违规 skill 名称,打印 "检测到 <N> 个 blocklist skill,建议删除以保持 token 预算:<list>",但 MUST NOT 中止启动

#### Scenario: 无违规静默通过
- **WHEN** 启动时未发现任何 blocklist skill
- **THEN** 系统 MUST NOT 产生任何输出,静默继续

### Requirement: 安装与卸载脚本

系统 SHALL 提供 `trio install` 与 `trio uninstall` 两个 bash 脚本,分别完成 symlink 建立与删除,脚本 MUST 是幂等的(重复执行不报错不损坏状态)。

#### Scenario: install 首次执行
- **WHEN** 用户在仓库根目录执行 `./trio install`
- **THEN** 脚本 MUST 校验 Superpowers 存在(缺失则退出并打印修复指令),执行 `mkdir -p ~/.claude/skills ~/.claude/commands` 确保父目录存在,随后以仓库绝对路径为 target 建立 `~/.claude/skills/trio-orchestrator -> <repo_abs>/skills/trio-orchestrator` 与 `~/.claude/commands/trio -> <repo_abs>/commands/trio` 两个 symlink,打印 "安装完成,请重启 Claude Code"

#### Scenario: 仓库路径迁移检测
- **WHEN** 用户在 `trio install` 已执行但仓库目录已被移动的情况下再次运行 `./trio install`
- **THEN** 脚本 MUST 检测 symlink 目标绝对路径与当前 `<repo_abs>` 不一致,先 unlink 原链接再以新 `<repo_abs>` 重建;MUST NOT 复制仓库文件、MUST NOT 使用相对路径

#### Scenario: install 重复执行
- **WHEN** symlink 已存在时再次执行 `./trio install`
- **THEN** 脚本 MUST 检测 symlink 目标正确则静默跳过,目标错误则先 unlink 再重建,不报错

#### Scenario: uninstall 只删除本插件
- **WHEN** 用户执行 `./trio uninstall`
- **THEN** 脚本 MUST 仅删除本插件的 2 个 symlink,MUST NOT 触碰 Superpowers 与 gstack 的任何文件

### Requirement: 属性化不变量(PBT)

系统 MUST 满足以下针对安装协议的属性化不变量。

#### Scenario: superpowers_highest_valid_semver
- **WHEN** 给定 `~/.claude/plugins/cache/claude-plugins-official/superpowers/` 下一级目录集合 `V`
- **THEN** 选中版本 `v*` MUST 满足 `v* = max_semver({ v ∈ V | semver(v) ∧ has_all_5_required_skills(v) })`;若该集合为空,结果 MUST 为 failure;falsification:混合合法/非法目录名、多 semver、缺失部分 skill、预发布样式、非排序 FS 枚举顺序,尝试让实现选错较低版本或错误接受不完整版本

#### Scenario: blocklist_exact_first_level_match
- **WHEN** 对任意 `~/.claude/skills/` 一级子项集合 `S` 执行扫描
- **THEN** 扫描结果 MUST 恒等于 `{ basename(x) | x ∈ S ∧ basename(x) ∈ Blocklist }`,其中匹配为 case-sensitive 精确、非递归,symlink 与真实目录等价(不解引用);falsification:大小写变体、前后缀污染、嵌套目录、symlink 指向任意目标、同名文件+目录混合、随机枚举顺序,尝试让 scanner 漏报/误报/递归吸入目标内容

#### Scenario: trio_install_idempotent
- **WHEN** 执行 `trio install` 共 `N ≥ 2` 次(无并发、无外部状态变更)
- **THEN** 文件系统终态 MUST 与执行 1 次完全一致:两个 symlink 的 `readlink` 输出相同、指向的绝对路径相同、`~/.claude/skills/` 与 `~/.claude/commands/` 未新增或覆盖其他文件;falsification:在两次之间人为 unlink/错指目标/污染父目录,断言第 N 次执行后终态仍等价于 N=1 基线
