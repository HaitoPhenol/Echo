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
| G3 | 把 `NavDestinationSearchProvider` 从 `services/search_service.dart` 移到 `navigation/nav_destination.dart`（与它搜索的模型同址），删除 services 对 navigation 的 import | 已完成 | `a2f99f0` |
| G2 | `search_capsule.dart` 按职责拆为 3 个文件：静态胶囊本体 / 开合 morph（`CapsuleMorph`+`PanelEntrance`）/ 建议区内容（`ResultsView`+`ResultTile`+`HistoryChips`+`HistoryChip`）；跨文件的私有类提升为公共名，文件内辅助仍私有 | 已完成 | `117794a` |
| G5 | `NavBadgeService` 由 `int page` 改为 `String destinationId`；内存实现构造参数 `pageCount`→`destinationIds`；调用方（smart_nav_screen / search_capsule / debug_badge_controls / badge_commands）改用稳定 id；`badge` 命令对外入参（名/下标）与出参（index+name）**不变** | 已完成 | `f9d8f73` |
| G1 | ① 文件尾部自包含类（`_DragGesture`/`_HandleGesture`/`_AiHold`/`_RippleSpec`/`_Ripple`）移出为独立文件；② 几何纯函数（`_dockTop`/各 hit rect/`_pageAtX`/`_quickArcOrigin`/`_computeQuickPositions`/`_pageMenuPositions`）收敛为 `dock_layout` 帮助类；③ `build()` 内联子树抽成 State 私有构建方法。**不改**任何时长/阈值/色值/手势判定 | 已完成 | `f0059d6` / `dde90d4` / `fecc209`（三提交） |

## 3. 决策与方法记录

- **G1 拆解方式**：不用 mixin（State 私有字段跨文件 mixin 不可行）；不引入 `part`（项目无先例）；几何走独立帮助类，widget 子树走 State 私有方法抽取（树形与 Key 身份不变，避免 1.6/1.10 事故）。
- **G2 拆分方式**：真实独立文件（拒绝 `part` 的物理拆分），跨文件共享的私有类提升为公共组件名，减少 API 暴露面。
- **门禁**：每项提交后执行 `cd echo && flutter analyze`（零问题）与 `flutter test`（全绿）。
- **子智能体编排**：执行 agent 按项原子提交；审查 agent 对分支全量 diff 复核；调度（主助手）逐项验收门禁与实际 diff。
- **G3 实际改法**：整类（含文档注释）原样搬入 `navigation/nav_destination.dart`（与 `NavDestination` 模型同址），navigation→services 向内依赖；`search_service.dart` 删除 navigation import。类名/构造签名/`id`（`'destinations'`）一字未改，唯一调用点 `smart_nav_screen.dart` 零改动。
- **G2 实际拆分边界**：`search_capsule.dart`（592 行）留公共 `SearchCapsule` + 其专属私有件 `_NavAnchor`/`_NavDot`；`search_pill_morph.dart`（325 行）承载 `CapsuleMorph`+`PanelEntrance`（各自 State）；`search_panel_content.dart`（252 行）承载 `ResultsView`+`ResultTile`+`HistoryChips`+`HistoryChip`。跨文件被引用的 6 个类提升为公共名（`CapsuleMorph`/`PanelEntrance`/`ResultsView`/`ResultTile`/`HistoryChips`/`HistoryChip`）；因 `flutter_lints` 的 `use_key_in_widget_constructors` 约束公共 widget，为它们补 `super.key`（各调用处均不传 key，行为零变化）。仅文件内使用的 `_NavAnchor`/`_NavDot` 及 SearchCapsule 私有构建方法保持私有。
- **G5 未知 id 语义**：`InMemoryNavBadgeService` 由 `List` 改 `Map<String, NavBadgeLevel>`；读 `levelOf(未知)` 返回 `normal`，写 `postNotification/reportException/markViewed/resolveException(未知)` 静默忽略（不抛异常、不 notify），替代原 `List` 越界 `RangeError`。
- **G1 实际边界（文件行数）**：`smart_nav_screen.dart` 1634 → **1353** 行（计划记 1626，实测基线为 1634；差异为记录笔误，非本轮改动所致）。新增 `nav_gesture_records.dart`（77 行，公共 `DragGesture`/`HandleGesture`/`AiHold`/`RippleSpec`，字段与文档注释一字未改，仅去下划线）；`dock_layout.dart`（177 行，公共 `DockLayout`）；`widgets/trigger_ripple.dart`（74 行，公共 `TriggerRipple` + 私有 `_TriggerRippleState`，动画 650ms/0.45→2.5×/60px/`tone4`+`tone2` 原样）。
- **G1 几何收敛方式**：新建 `DockLayout`（构造入参 `size`/`safeBottom`/`pageCount`/`drawerK`，全为不可变事实），承载 `dockTop`/`handleRect`/`aiRect`/`handleHitRect`/`aiHitRect`/`navGeometry`/`searchCapsuleRect`/`pageAtX`/`pageMenuPositions` 与静态 `quickArcOrigin`；坐标一律由 `DockGeometry` 静态常量推算，公式逐字搬运、未新增/复制数值。State 侧保留同名薄封装（`_layout` getter + `_handleHitRect`/`_aiHitRect`/`_navGeometry`/`_searchCapsuleRect`/`_pageAtX`/`_pageMenuPositions`），调用点零改动。
- **G1 留在原地（依赖 State 可变字段，无法纯化）**：`_computeQuickPositions()` 仍需写 `_quickPositions`/`_quickHotRadius` 两个 State 缓存字段，故保留在 State，仅内部把弧起点计算改调 `DockLayout.quickArcOrigin(size, safeBottom)` 纯函数。`_handleRect`/`_aiRect`/`_dockTop` 的 State 版本已删除（无外部调用者，其用途仅由 `DockLayout` 内部 getter 承接）。
- **G1 build() 抽取**：新增 State 私有方法 `_buildStaticBackdrop`（mech-bg + mech-coords）、`_buildPageTrack`（pages）、`_buildOverlays`（scrim/快捷弧/涟漪/页码指示器/AI 条/把手条/胶囊簇/slash 层/抽屉/竖单/AI 对话框）。Stack 子项顺序、全部 Key、条件挂载、底部三条几何局部量逐字保持；未新建任何 widget 类。
- **G1 偏离项**：① 删除因 `_Ripple` 移出而失效的 `../theme/app_colors.dart` import；② 删除 `_handleRect`/`_aiRect`/`_dockTop` 的 State 版本（分析器 `unused_element`，实际无调用者）；③ `TriggerRipple` 按 `use_key_in_widget_constructors` 补 `super.key`（调用处均不传 key）；④ 计划所记 1626 行与实测 1634 行之差为记录笔误。
- **G5 收口（原「保留索引键」偏离已解决）**：独立审查指出同一组件内并存"索引身份（`ValueKey('nav-anchor-$i')`）+ id 状态（`levelOf(pageIds[i])`）"两套坐标，页面调序后身份会漂移。本轮把锚点身份键改为稳定 id 键 `ValueKey('nav-anchor-${pageIds[i]}')`，与 G5 的 id 状态索引对齐；`test/widget_test.dart` 中 5 处查找同步改用稳定 id 键（辅助函数 `anchorLevel`/`anchorColor` 按 `const anchorIds = ['console','chat','notes','me']` 的 `anchorIds[i]` 映射，2 处硬编码 `nav-anchor-1` 改为 `nav-anchor-chat`），**仅换键字符串、断言逻辑与期望值不变**。全库已无 `nav-anchor-<索引>` 残留（`grep nav-anchor` 仅剩 id 键）。

## 4. 门禁与验证记录

门禁命令：`cd echo && flutter analyze`（要求零问题）、`flutter test`（要求全绿）。

| 提交 | 项 | hash | flutter analyze | flutter test |
|---|---|---|---|---|
| 0 | 计划文档纳入版本控制 | `d722317` | —（纯文档，不涉代码） | — |
| 1 | G3 services→navigation 解耦 | `a2f99f0` | No issues found | All tests passed（441） |
| 2 | G2 search_capsule 三文件拆分 | `117794a` | No issues found | All tests passed（441） |
| 3 | G5 锚点改 destinationId 索引 | `f9d8f73` | No issues found | All tests passed（441） |
| 4 | G2/G3/G5 记录文档更新 | `c74bc49` | —（纯文档） | — |
| 5 | G1 尾部件移出（记录类 + 涟漪） | `f0059d6` | No issues found | All tests passed（441） |
| 6 | G1 几何收敛至 DockLayout | `dde90d4` | No issues found | All tests passed（441） |
| 7 | G1 build 子树抽为私有构建方法 | `fecc209` | No issues found | All tests passed（441） |
| 8 | G1 记录文档更新 | `feade10` | —（纯文档） | — |
| 9 | G5 收口：锚点身份键改稳定 id 键 | `47c5956` | No issues found | All tests passed（441） |
| 10 | G5 收口记录文档更新 | 见 git log | —（纯文档） | — |

测试基线：本轮全为**行为保持**重构，测试总数恒为 **441**，全部通过。

### 真机冒烟（2026-10-16，MIX 2S `/3f6cc09b`，debug APK）

- `flutter build apk --debug` 成功（Gradle assembleDebug 302.5s）→
  `adb install -r` 成功（Success）→ 冷启动 `MainActivity` 正常；
- logcat 无 App 异常（无 FATAL/AndroidRuntime 业务栈）；
- 在导航条上横向拖动两次（`input swipe 950 2039 700 2039 320`），
  页面由首页翻至「04 主页」，3D 转鼓、页名牌同步更新，导航条 /
  两端圆点 / 滑块 / AI 条均正常渲染——**页面轨道与导航物理未因
  重构退化**；
- 冒烟未覆盖：上甩快捷弧、长按搜索、双击直达、多指边界。这几项
  的 adb 注入本身不可靠（见 engineering_standards 1.15），留待
  负责人手指回归或专项会话；本轮为行为保持重构，未改任何手势
  阈值/时长，风险面限于"代码搬动引入的等价性偏差"，已由 441 个
  测试 + 独立审查逐字核对兜底。

## 5. 独立审查结论与收口

独立审查子智能体复核分支全量 diff，结论**有条件同意**：P0/P1 无；
行为保持、树形/Key/数值逐字核对等价、测试断言未被篡改、门禁复现
全绿。两项 P2 的处置：

- **P2-1 锚点身份键仍为索引键** → **已收口**：`_NavAnchor` 的
  `ValueKey` 改用 `nav-anchor-${pageIds[i]}`，`test/widget_test.dart`
  5 处按键查找同步换成稳定 id（仅改查找键，断言/期望值未动），
  与 G5 的状态索引对齐（提交 `47c5956`）。
- **P2-2 文档失真（architecture / current_state / glossary）** →
  **已随合入修正**：架构目录树补 3 个新文件、§3.3 数据源改址
  navigation、§3.7 锚点方法签名改 `destinationId` 并标注稳定 id 索引、
  debug 面板文案；glossary 涟漪/历史胶囊/结果行归属；current_state
  行数与锚点索引描述——均对齐 0.13.1 现状（提交见 §7）。

## 6. 待负责人裁定

- **G4 挂起**：需对 Q3（是否接受"当前页±1"窗口化懒加载）拍板；
  落地前必须迁移日记页挂在常驻 State 上的生命周期假设（自动成稿
  `ensureDay`、防抖 flush）。本轮未触碰，`_buildPageTrack` 仍全页常驻。
- **本临时文档的去留**：按约定由负责人审阅后删除，内容保留于本轮 tag。

## 7. 合入与交付（2026-10-16）

- 负责人审阅通过（对话内确认），G4 维持挂起。
- **ff-only 合入 main**：main `c506979` → `refactor/struct-debt-a` 分支
  顶（13 提交），无分叉。
- **排号**：`0.13.0+38` → **`0.13.1+39`**（PATCH 递增；构建号永不回退）。
- **文档对齐**：architecture.md / current_state.md / glossary.md 三处
  随合入一次提交修正（P2-2 收口）。
- **tag**：`v0.13.1`（PATCH tag 按铁律**留本地**，不推远程）。
- **临时文档**：本文件在 tag 后单独提交删除，内容保留于 `v0.13.1` tag。
