# 日记导出改为按月 + 导出提醒

## Context（为什么做）

现状：日记导出按**年**粒度 —— 年列表每行尾部的 `_YearExportButton`
调 [`DiaryExportService.exportYear`](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/export/diary_export_service.dart) 打包该年全部 draft，且**没有任何提醒**，用户容易长期忘记导出。

目标：

1. 导出粒度由「年」改为「月」：移除年行导出入口，改在**月列表每行**加导出按钮。
2. 每到新的自然月（1 号起），只要**还有已结束月份存在未导出草稿**，就持续提醒，直到用户真正完成**有效导出**（draft → exported）为止。提醒形式（用户已裁定）：

   * 笔记页导航锚点**红色警告**（exception 级）；

   * **每次冷启动**首次切到笔记页时弹一次对话框，主按钮「去导出」跳转到最早待导出月份所在的月份列表（导出动作仍由用户点月行按钮触发）。

## 关键设计裁定（来自用户）

* 待导出范围 = **所有已结束月份**（早于本月 1 日），漏了几个月会一直提醒到补齐。

* 锚点用 \*\*exception（红色警告）\*\*级：它「不受查看清除」（`markViewed` 不影响 exception），天然满足「到有效导出为止」；消除时机由数据（是否仍有待导出 draft）驱动，接口干净。这也修正了「查看即消」的旧语义（聊天页锚点现状即由未读数据驱动，同一原则）。

* 对话框同一次进程只弹一次；「去导出」只负责跳转，不代替用户执行导出。

## 实施步骤

### A. 仓储层（抽象 + 两个实现）

文件：[diary\_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/diary_repository.dart)、[in\_memory\_diary\_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/in_memory_diary_repository.dart)、[persistent\_diary\_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/persistent_diary_repository.dart)

新增两个方法（含文档注释）：

* `Future<List<DiaryDocument>> draftDocumentsOfMonth(int year, int month)`：该月全部 draft（日期升序），供月导出打包；exported/archived 不入包（对齐现有 `draftDocumentsOfYear`）。

* `Future<DateTime?> oldestDraftBefore(DateTime cutoff)`：最早一篇**早于** cutoff 的 draft 日期，无则 null。一条方法同时供「是否存在待导出」判定与对话框跳转目标。

持久实现走 SQL（`date` 列为 `yyyymmdd` 整数，口径同 `_keyOf`）：

* 月：`WHERE state='draft' AND (date / 100) = ?`（`year*100+month`）。

* 最早：`SELECT MIN(date) FROM ... WHERE state='draft' AND date < ?`，整数解码回 `DateTime`。

### B. 导出服务

文件：[diary\_export\_service.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/export/diary_export_service.dart)

* 新增 `exportMonth(int year, int month, {DiaryExportConfirm? confirmShared})`：逻辑与 `exportYear` 完全一致（打包 → 分享 → 人工确认 → `markExported`），改取 `draftDocumentsOfMonth`；zip 名 `日记-$year-${MM}-${_stamp}.sy.zip`（`_stamp` 复用）。

* `DiaryExportOutcome` 由单一 `year` 改为 `year` + `month`（供 SnackBar 文案与测试断言）。

* 删除 `exportYear`（年 UI 入口移除后即无引用；ECP 走 `buildDraftZip`）。

* `buildDraftZip` 增可选 `month` 参数（与现有 `year` 可组合），scope 文案 `yyyy-MM`；命名保持 `日记-<scope>-<stamp>.sy.zip`。

### C. 月导出 UI

文件：[month\_list\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/month_list_page.dart)、[year\_list\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/year_list_page.dart)、[diary\_list\_row.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/widgets/diary_list_row.dart)（复用其 `trailing`，无需改动）

* 月列表每行 `trailing` 加导出按钮：把原 `_YearExportButton` 迁来改名为 `_MonthExportButton`（图标 `Icons.ios_share`、进行中转圈、任一月导出中其余禁用），`_exportingMonth` 单例互斥。

* `_confirmSent`（「确认已发送？」对话框）随之迁到月页；SnackBar 文案改为按月（如「已分享 N 篇 · 标记为已导出」/「YYYY 年 M 月没有待导出的草稿」）。

* 年列表页：移除 `_YearExportButton`、`_exportYear`、导出相关 import/状态，仅保留导航到月列表。

### D. 导出提醒（锚点 + 对话框）

文件：[diary\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/diary_page.dart)、[smart\_nav\_screen.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart)、[nav\_badge\_service.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/nav_badge_service.dart)（仅复用，无需改接口）

`DiaryPageState`：

* 锚点目的地 id 由 `DiaryPage` 构造参数注入（`nav_destination.dart` 的 notes 分支已有 `spec.id`，直接传 `badgeDestinationId: spec.id`；默认值 `'notes'`），避免在日记页里硬编码页名。

* `didChangeDependencies` 捕获 `NavBadgeScope.maybeOf(context)`（页面在 `NavBadgeScope` 子树内，见 smart\_nav\_screen 的 scope 包裹）。

* bootstrap 完成后，以及 `_repository` 变更通知（`addListener`）时调 `_syncExportReminder()`：
  `oldest = await repo.oldestDraftBefore(DateTime(today.year, today.month, 1))`；非空 → `badges.reportException('notes')`；为空 → `badges.resolveException('notes')`。**数据驱动**，导出成功后 `markExported` 触发 notify → 自动解除（仅当仍有多月未导出才保持红）。`today()` 取仓储同源时钟（04:00 日界）。

* 新增公开 `Future<void> maybeShowExportReminder()`：仓储未就绪 / 本进程已弹过（`_reminderShown`）/ 无待导出 → 直接返回；否则 `showDialog`（标题如「上个月的日记还没导出」，动作「稍后」/「去导出」）。「去导出」用 `_navigatorKey.currentState` 执行
  `pushAndRemoveUntil(DiarySlideRoute(builder: MonthListPage(year: oldest.year), ...), (r) => r.isFirst)`，把内层栈变成 \[年列表, 该年月份列表]，返回回年列表。

`SmartNavScreen`：

* 新增 `_notesPageIndex = _destinations.indexWhere((d) => d.id == 'notes')`。

* 在既有 `_nav` 活跃页监听（已用于已读停留）中，当 `activePage == _notesPageIndex` 且本次进程未请求过（本地 bool `_diaryReminderRequested`）时，置位并调 `_diaryKey.currentState?.maybeShowExportReminder()`（`_diaryKey` 已存在）。

### E. 测试

* 仓储（[in\_memory\_diary\_repository\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/data/in_memory_diary_repository_test.dart) / [persistent\_diary\_repository\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/data/persistent_diary_repository_test.dart)）：`draftDocumentsOfMonth`（只含 draft、日期升序）；`oldestDraftBefore` 边界（cutoff 当天不算、上月末算；无则 null）。

* 导出服务（[diary\_export\_service\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/export/diary_export_service_test.dart)）：`exportYear` → `exportMonth` 全部用例（空月、否认保留、确认迁移、zip 命名）。

* UI（[diary\_m5\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/ui/diary_m5_test.dart)）：「年行导出入口」组改为「月行导出入口」，`_FakeExportService` 的 override 由 `exportYear` 改 `exportMonth`，图标断言改在月列表。

* 提醒（新增于 [diary\_browser\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/ui/diary_browser_test.dart) 或新文件）：用假 `NavBadgeService` 断言「存在早于本月 draft → 上报 exception」「导出后 → resolveException」；`maybeShowExportReminder` 弹框、「去导出」跳 `MonthListPage`、同进程再调不重复弹。

* 全仓 grep `exportYear` / `ios_share` / `DiaryExportOutcome` 后同步受影响断言（[widget\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/widget_test.dart)、[control\_test\_harness.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/control/control_test_harness.dart)、[domain\_commands\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/control/domain_commands_test.dart) 等）。

### F. 文档

* [usage-guide.md](file:///home/phenol/Documents/GitHub/Echo/docs/usage-guide.md)：导出章节由「年行」改「月行」，补提醒规则（红色锚点 + 冷启动对话框 + 「去导出」）。

* [current\_state.md](file:///home/phenol/Documents/GitHub/Echo/docs/current_state.md)：导出粒度现状改「按月」、补导出提醒规则。

* [architecture.md](file:///home/phenol/Documents/GitHub/Echo/docs/architecture.md)：日记导出服务与出口描述、锚点 exception 复用说明。

* [flutter-tech-plan.md](file:///home/phenol/Documents/GitHub/Echo/docs/diary/flutter-tech-plan.md) §6 导出段：年→月（如涉及）。

* [ecp-commands.md](file:///home/phenol/Documents/GitHub/Echo/docs/ecp/ecp-commands.md)：`diary.export` 增 `--month`（可选，与 `--year` 组合）。

## 验证

1. `flutter analyze` 零告警；`flutter test` 全绿（在现有 460 项基础上增删）。
2. 真机（MIX 2S，debug）：

   * ECP `diary.seed --end <上月某日> --days N` 造出「已结束月份」的 draft；

   * 冷启动 → 切笔记页：应见 notes 锚点**红色闪烁** + 弹提醒对话框；

   * 「稍后」后锚点仍在；同进程再切回笔记页不再弹；

   * 点月行导出 → 系统分享 → 「确认已发送」→ 锚点恢复红色消失；再次冷启动不再提醒；

   * 反向：只导出部分月份（另一月仍有 draft）时锚点仍红。
3. ECP（若采纳 `--month`）：`scripts/echo-cmd diary.export --year 2026 --month 9` 产物名含 `2026-09`。

## 备注

* 分支沿用 `rework/diary-ui`（不推送、不排版本号）；本改动为功能更新，版本号待合入 main 时由合并者按 main 与 tag 取号。

* 提醒仅作用于 UI 层；ECP `diary.export` 不触发提醒状态迁移（其本就不迁状态）。

