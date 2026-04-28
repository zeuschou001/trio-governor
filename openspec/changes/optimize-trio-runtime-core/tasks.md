## 0. Spec 重组

- [x] 0.1 将本 change 的 capability tree 从 `trio-runtime-core` / `trio-orchestration` / `trio-state-contract` 重组为 `trio-session-core` / `trio-phase-machine` / `trio-data-contract` / `trio-adapter-protocol`
- [x] 0.2 重写 proposal / design / specs,让 requirement 按 ownership 边界归位
- [x] 0.3 将 `trio-runtime-core` 降级为实现载体概念,不再作为长期 capability 名称
- [x] 0.4 新增 `trio-governor` 产品级 capability,显式定义 trio 的治理表面
- [x] 0.5 将 `trio-session-core` / `trio-phase-machine` / `trio-data-contract` / `trio-adapter-protocol` 标注为 internal implementation specs

## 1. Session Core Runtime

- [x] 1.1 扩展根入口 `trio`,新增 `runtime` 子命令并分发到 `scripts/trio-runtime.sh`
- [x] 1.2 创建 `scripts/trio-runtime.sh`,定义 dispatcher 骨架与统一 usage / exit code
- [x] 1.3 创建 `scripts/lib/state-store.sh`,集中维护 `STATE.md` 解析、升级、原子写回
- [x] 1.4 在 runtime 中实现 `status`、`restart`、`abort`,落地 `RESUME_AVAILABLE` 与显式会话终态
- [x] 1.5 实现 bootstrap / locking 规则,让 session ownership 不再散落在旧脚本中
- [x] 1.6 将 `adapter_mode` / `ceo_review_forced` 收归 runtime-owned 状态,保证 route profile 可恢复

## 2. Phase Machine

- [x] 2.1 创建 `scripts/lib/phase-graph.sh`,集中维护 dev / quick phase graph、可选阶段与下一阶段规则
- [x] 2.2 在 runtime 中实现 `transition <host> <action> <phase>`,覆盖 `stage-finished` / `confirm-yes` / `confirm-no` / `confirm-skip`
- [x] 2.3 在 runtime 中实现 `gate-check <host> <gate>`,让 `eng-review` 与 `state-sync` 规则不再由 skill 自己推断
- [x] 2.4 实现 quick/dev 命名空间校验与 `completed_phases` 单调性
- [x] 2.5 实现 `quick_streak` 仅由 runtime 递增

## 3. Data Contract Writers

- [x] 3.1 创建 `scripts/lib/doc-store.sh`,集中维护 PROJECT / DECISIONS / KNOWLEDGE / ROADMAP 的结构化写入
- [x] 3.2 让 `scripts/trio-init.sh` 成为 `runtime bootstrap` 的兼容 wrapper,不再持有独立状态规则
- [x] 3.3 让 `scripts/decisions-append.sh` 成为 `runtime decision-append` 的兼容 wrapper
- [x] 3.4 新增 `runtime project-write`、`knowledge-append`、`record-deps` 与 `roadmap-rewrite`,补齐 write-once / append / archive 规则
- [x] 3.5 扩展 writer 锁与原子写回,覆盖 `STATE.md`、`DECISIONS.md`、`KNOWLEDGE.md`、`ROADMAP.md`

## 4. Adapter 与 Surface Boundary

- [x] 4.1 固化 `scripts/detect-deps.sh` 的 stdout/stderr 合约,确保 runtime 可直接消费 `SUPERPOWERS_VERSION=...`
- [x] 4.2 重写 `skills/trio-orchestrator/SKILL.md`,删除细粒度文件协议与底层实现细节,仅保留阶段顺序、用户交互约束、adapter 调用与 runtime verb 调用点
- [x] 4.3 更新 `commands/trio/dev.md` / `quick.md`,把“surface 只做路由”说明补齐,保持简短
- [x] 4.4 在 orchestrator 启动序列中加入恢复协商:`continue` / `restart`
- [x] 4.5 明确 allowlist / blocklist 与 adapter non-ownership 行为在实现与文档中的对应位置
- [x] 4.6 新增 `./trio session phase`,把当前阶段的 executor / adapter / writer / confirm 合同从 `SKILL.md` 下沉到可执行 driver
- [x] 4.7 在 `./trio session phase` 中暴露进度计数与当前/下一阶段输入文件,支撑阶段边界展示
- [x] 4.8 新增 `./trio session confirm`,把边界输入归一化与 confirm action 映射从 prompt 下沉到 driver
- [x] 4.9 新增 `./trio session resume`,把启动期 `continue` / `restart` / `abort` 决策与 restart flag 组装从 prompt 下沉到 driver
- [x] 4.10 将 quick 首次风险确认下沉为 runtime-owned 启动 guard,并通过 `session phase` / `session confirm` 暴露
- [x] 4.11 新增 `./trio bridge`,为 gsd2 / trellis 提供 internal-only export/status 骨架,但保持 bridge non-ownership
- [x] 4.12 为 gsd2 / trellis 增加 internal handoff 包生成能力,输出 provider-specific 指引但不接管 trio 状态
- [x] 4.13 新增 `./trio bridge review`,读取 handoff outputs 并生成仅建议型的回流动作
- [x] 4.14 新增 `./trio bridge draft`,把 review suggestion 收敛成手动执行草稿文件
- [x] 4.15 新增 `./trio bridge scaffold`,为 draft suggestion 生成待填写的参数模板

## 5. Validation 与文档

- [x] 5.1 新增 `tests/runtime-status.sh`,验证 machine-readable stdout、stderr 诊断与非法 verb 退出码
- [x] 5.2 新增 `tests/runtime-transition.sh`,覆盖 `confirm-yes` / `confirm-no` / `confirm-skip` / 非法跳转
- [x] 5.3 新增 `tests/runtime-resume.sh`,覆盖 `RESUME_AVAILABLE=1`、continue、restart、旧 `STATE.md` 自动升级
- [x] 5.4 扩展 `tests/state-contract.sh`,验证 `mode` / `status` 字段、`PROJECT.md` seal、`ROADMAP.md` 归档
- [x] 5.5 扩展 `tests/e2e-smoke.sh`,从“原语级冒烟”提升为“runtime + orchestrator 原语级冒烟”
- [x] 5.6 更新 README / USAGE / INSTALL,统一 `session-core / phase-machine / data-contract / adapter-protocol` 口径
- [x] 5.7 更新 `scripts/measure-tokens.sh` 预算阈值,把 `SKILL.md` 目标从 2500 收紧到 1800 token
- [x] 5.8 运行 `openspec validate optimize-trio-runtime-core --strict`
- [x] 5.9 运行 `./scripts/ci.sh`,确认 wrapper 迁移后所有旧测试与新增 runtime 测试通过
- [x] 5.10 新增 `tests/session-phase.sh`,覆盖阶段合同、route profile 恢复与 quick 提示信号
- [x] 5.11 扩展 `tests/session-phase.sh`,覆盖阶段输入文件与进度字段
- [x] 5.12 新增 `tests/session-confirm.sh`,覆盖边界输入归一化、invalid 重试与 skip/confirm-no 路径
- [x] 5.13 新增 `tests/session-resume.sh`,覆盖启动期 `not-awaiting` / `invalid` / `continue` / `restart` / `abort` 路径
- [x] 5.14 扩展 runtime/session/state/e2e 测试,覆盖 quick 启动 guard、`awaiting-start-confirmation` 与 guard 清除后的恢复语义
- [x] 5.15 重写 README / USAGE / commands / SKILL 的对外叙事,把产品定位收敛为 workflow governor
- [x] 5.16 新增 bridge export 测试,验证 `.trio/bridges/` 快照与 non-ownership 边界
- [x] 5.17 扩展 bridge 测试,覆盖 handoff 包、provider-specific 指引与 latest handoff 状态
- [x] 5.18 扩展 bridge 测试,覆盖 review suggestion、unmapped outputs 与 state non-mutation
- [x] 5.19 扩展 bridge 测试,覆盖 draft 文件生成、latest draft 状态与手动执行占位符
- [x] 5.20 扩展 bridge 测试,覆盖 scaffold 模板生成、latest scaffold 状态与 state non-mutation
