# 归档索引

这里放**已结案、不再随版本更新**的阶段性文档：审查报告、施工交接单、
复审流水。归档内容**只读、只增不改**——结论被后续推翻时也不删改，
而是在新文档里写明；git 历史是最终事实来源。

当前有效的文档在 `docs/` 上层：[问题清单](../code_review_report.md)、
[现状快照](../current_state.md)、[架构说明](../architecture.md)、
[工程规范](../engineering_standards.md)。

| 文件 | 时间 | 内容 |
|---|---|---|
| [ecp-p1-p4-review-log.md](ecp-p1-p4-review-log.md) | 2026-10-12 ~ 10-15 | ECP P1–P4 四期的施工交接单（§E–H）、修复回执、维护者复审与 MIX 2S 真机终审原文。四期分别交付 v0.10.0 / v0.11.0 / v0.12.0 / v0.13.0；现行规则以 [ecp/ecp-design.md](../ecp/ecp-design.md) 为准 |
| [codebase-review-v0.5.0-2026-10-06.md](codebase-review-v0.5.0-2026-10-06.md) | 2026-10-06 | v0.4.6~v0.5.0 全量代码审查：每条问题的行号证据与改法论证（旧 P0/P1/P2 编号的权威出处） |
| [smart-nav-line-v0.4.10-2026-10-06.md](smart-nav-line-v0.4.10-2026-10-06.md) | 2026-10-06 | 智能导航线组件 v0.4.10 阶段开发总结 |

## 归档规则

- 什么东西进归档：已完成里程碑的**施工流水**（交接单、逐轮回执、
  终审记录）与不再演进的**阶段性审查报告**；
- 什么不进：仍开放的问题（留 code_review_report.md）、现行规则与
  架构（留 ecp/、engineering_standards 等）、append-only 的提案
  登记册（留 proposals/README.md）；
- 移动时修好所有相对链接，归档文件头注明对应版本与现行文档位置；
- 目录原 `docs/component-reports/` 于 2026-10-15 并入本目录。
