# 结构债务 A 项重构 · 执行记录（临时文档）

> **临时文档**：任务完成并经负责人审阅后删除；内容保留在本轮 task tag 中。
> 分支：`refactor/struct-debt-a`（自 main `c506979` 切出）。
> 基线版本：`0.13.0+38`（分支期间 pubspec 保持不动，排号留到合入 main）。
> 依据：[code_review_report.md](code_review_report.md) §B G1–G5 ·
> [engineering_standards.md](engineering_standards.md) §1（1.1 1.4 1.6 1.10）。

## 1. 范围裁定

| 项 | 本轮 | 理由 |
|---|---|---|
| G3 services→navigation 反向依赖 | ✅ 做 | 违反 1.4【铁律】，行为可保持，零产品影响 |
| G2 `search_capsule.dart` 1152 行多组件 | ✅ 做 | 报告原判"行为零变化的纯拆分" |
| G5 锚点改 destinationId 索引 | ✅ 做 | 行为保持的接口下沉；对外 ECP `badge --page` 契约不变 |
| G1 `smart_nav_screen.dart` 1626 行上帝类 | ✅ 做 | 纯装配/几何/手势记录的机械拆解，不动手感参数 |
| G4 页面常驻→懒加载 | ⛔ 挂起 | 属 Q3 产品决策；日记页自动成稿/防抖 flush 依赖常驻 State 生命周期，须先迁移。不得由 agent 代拍 |

## 2. 逐项计划与进度

| 项 | 具体改法 | 状态 | 提交 |
|---|---|---|---|
| G3 | 把 `NavDestinationSearchProvider` 从 `services/search_service.dart` 移到 `navigation/nav_destination.dart`（与它搜索的模型同址），删除 services 对 navigation 的 import | 待做 | |
| G2 | `search_capsule.dart` 按职责拆为 3 个文件：静态胶囊本体 / 开合 morph（`_CapsuleMorph`+`_PanelEntrance`）/ 建议区内容（`_ResultsView`+`_ResultTile`+`_HistoryChips`+`_HistoryChip`）；跨文件的私有类提升为公共名，文件内辅助仍私有 | 待做 | |
| G5 | `NavBadgeService` 由 `int page` 改为 `String destinationId`；内存实现构造参数 `pageCount`→`destinationIds`；调用方（smart_nav_screen / search_capsule / debug_badge_controls / badge_commands）改用稳定 id；`badge` 命令对外入参（名/下标）与出参（index+name）**不变** | 待做 | |
| G1 | ① 文件尾部自包含类（`_DragGesture`/`_HandleGesture`/`_AiHold`/`_RippleSpec`/`_Ripple`）移出为独立文件；② 几何纯函数（`_dockTop`/各 hit rect/`_pageAtX`/`_quickArcOrigin`/`_computeQuickPositions`/`_pageMenuPositions`）收敛为 `dock_layout` 帮助类；③ `build()` 内联子树抽成 State 私有构建方法。**不改**任何时长/阈值/色值/手势判定 | 待做 | |

## 3. 决策与方法记录

- **G1 拆解方式**：不用 mixin（State 私有字段跨文件 mixin 不可行）；不引入 `part`（项目无先例）；几何走独立帮助类，widget 子树走 State 私有方法抽取（树形与 Key 身份不变，避免 1.6/1.10 事故）。
- **G2 拆分方式**：真实独立文件（拒绝 `part` 的物理拆分），跨文件共享的私有类提升为公共组件名，减少 API 暴露面。
- **门禁**：每项提交后执行 `cd echo && flutter analyze`（零问题）与 `flutter test`（全绿）。
- **子智能体编排**：执行 agent 按项原子提交；审查 agent 对分支全量 diff 复核；调度（主助手）逐项验收门禁与实际 diff。

## 4. 门禁与验证记录

（执行 agent 逐项填写：命令、结果、提交 hash）

## 5. 风险与待汇报

- **G4 挂起**：需负责人对 Q3（是否接受"当前页±1"窗口化懒加载）拍板；落地前必须迁移日记页挂在常驻 State 上的生命周期假设（自动成稿 `ensureDay`、防抖 flush）。
- **G5 波及面**：7 个文件 + 2 个测试；外部 ECP 契约不变，需在报告中说明。
