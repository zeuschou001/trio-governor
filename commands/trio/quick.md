---
description: trio 显式 quick 兼容入口，适合强制走低风险小改动。
argument-hint: <需求>
---

显式 quick 兼容入口。日常优先直接用 `/trio` 让系统自动分流；只有你确定要强制走小任务旁路时再走这里。风险过高或连续 quick 过多时会被拉回完整流程。
