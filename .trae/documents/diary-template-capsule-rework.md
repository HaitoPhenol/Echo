# 日记日模板重设 · 胶囊行方案

> 分支：`rework/diary-ui` ｜ 日期：2026-10-18 ｜ 决策来源：用户当日口头定稿（取代 flutter-tech-plan.md §5 / §5.1 / §5.2 的旧裁定）

## 1. 概述（Summary）

废弃现有日模板骨架（📈 自动记录 / data 快照块 / 💭 今天 / 🌙 睡前），改为：

```
┌─ 大标题（DiaryShell，固定不滚动，非块）
│  ┌─ 胶囊行（滚动区首项，非块，随正文滚动）
│  │   [温度] [湿度] [天气] [日程] [心情]
│  └─ 正文块列表（单空段落起手）
```

* 自动数据（温度 / 湿度 / 天气 / 日程条数）与心情全部改为**胶囊**，横向排布在标题下方；`Wrap` 自适应换行 + `WrapAlignment.spaceBetween` 分散对齐。

* 胶囊底色取导航条胶囊同款（`AppColors.tone1` + `BorderRadius.circular(999)`）。

* 胶囊**不是块、不进** **`.sy`** **块列表**，但**是笔记内容**：数值写进文档根 `custom-*` 属性，导出天然携带（`SySerializer` 已把 `DiaryDocument.custom` 写进 `Properties`）。

* 数据通道不变：`DiaryDataProvider` → `composer.fetchCustomPatch()` → `DiaryDocument.custom` → 胶囊行读取。点按任一数据胶囊 = 重拉全部数据源并落盘；心情胶囊 = 弹原有心情 sheet。

* 删除空行的「写点什么…」提示，删除「（示例数据）」标注。

* 设备上旧模板日记草稿**整体清空重来**（用户裁定），故不做旧骨架兼容/白名单。

## 2. 现状分析（Current State Analysis）

关键事实（已逐一读源码核对）：

| 位置                                                                                                                                 | 现状                                                                                                                                        |
| ---------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| [daily-default.json](file:///home/phenol/Documents/GitHub/Echo/echo/assets/diary/templates/daily-default.json)                     | `daily-default-v1`，6 块：heading 📈 / data role1 / heading 💭 / paragraph / heading 🌙 / paragraph                                          |
| [diary\_template\_json.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/diary_template_json.dart)       | `DiaryTemplateBlockType{heading,paragraph,data}`；`role`/`placeholder` 字段仅 data 用                                                          |
| [daily\_default\_template.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/daily_default_template.dart) | data 块用 `SyIdGenerator.dataBlock(day, role)` 确定性 ID + `readonly:true` + 底色 3                                                              |
| [sy\_id.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_id.dart#L67-L80)                                  | `dataBlock` / `isDataBlockId` / `dataRoleOf` 三个静态成员                                                                                       |
| [diary\_composer.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/diary_composer.dart)                  | `DataSnapshotResult{text, customPatch}`；`fetchSnapshot` 拼「🌡️21°C　💧45%　📅3条日程　☁️多云　（示例数据）」写进 data 块；`_compose` 落盘时写 data 块文本 + custom-\* |
| [block\_editor\_controller.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_editor_controller.dart) | `BlockState.isData`；`dataRefresher` 回调；`replaceDataSnapshot()`；`attach()` 按 ID 恢复 `readonly`                                              |
| [block\_widget.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_widget.dart)                        | **工作区已有未提交改动**：另一 agent 已删掉 ↻ 按钮的调用点与 `_refreshing`/`_onRefreshData`，但 `_DataRefreshButton` 类仍在（现无引用）；L107 `hintText:'写点什么…'`             |
| [diary\_mood\_picker.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/widgets/diary_mood_picker.dart)         | `DiaryMoodChip` 现挂标题栏 trailing；`showDiaryMoodPicker` / `kDiaryMoodKey` / `kDiaryMoodValues`                                               |
| [day\_editor\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/day_editor_page.dart#L100-L137)   | `_load()` 注入 `dataRefresher`；trailing 含 `DiaryMoodChip`；正文经 `BlockEditorView`                                                             |
| [block\_editor\_view.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_editor_view.dart)             | `ListView.builder` 直渲 `editor.blocks`，无 header 位                                                                                          |
| [diary\_shell.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/widgets/diary_shell.dart#L99-L113)             | 大标题固定渲染（`Transform.translate` 上移 13），`Expanded(child: child)` 才是滚动区                                                                       |
| [search\_capsule.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L194-L199)    | 导航条胶囊底色 = `AppColors.tone1` + `Radius.circular(999)`                                                                                      |
| [sy\_serializer.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_serializer.dart#L80-L95)                  | `custom` → `Properties` 的 `custom-*` 键，导出天然携带                                                                                             |

## 3. 改动清单（Proposed Changes）

### A. 模板层

**A1.** **[daily-default.json](file:///home/phenol/Documents/GitHub/Echo/echo/assets/diary/templates/daily-default.json)** — 整份替换

```json
{
  "id": "daily-default-v2",
  "blocks": [
    { "type": "paragraph" }
  ]
}
```

**A2.** **[diary\_template\_json.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/diary_template_json.dart)**

* `enum DiaryTemplateBlockType { heading, paragraph }`（删 `data`）。

* `DiaryTemplateBlockSpec` 删 `role`、`placeholder`。

* `fromJson`：删 `'data'` 分支与 role 校验、placeholder 解析；错误文案改「仅 heading/paragraph」；非 heading 带 level 的校验保留。

**A3.** **[daily\_default\_template.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/daily_default_template.dart)**

* `instantiate` 的 switch 只留 heading / paragraph；删 data 分支、`_dataBackground`。

* 类注释改为「日模板：单空段落骨架，自动数据与心情走文档根 custom-\* + 胶囊行 UI」。

**A4.** **[diary\_composer.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/diary_composer.dart)**

* 删 `DataSnapshotResult` 类。

* `fetchSnapshot` → 改名 `fetchCustomPatch(DateTime) → Future<Map<String, String?>>`：三源并发（`Future.wait`，互不连坐），只产出 `custom-iot-temp` / `custom-iot-humidity` / `custom-schedule-count` / `custom-weather`，值为 `null` 表示该源本次不可用（由调用方删键）。删 fragments 拼接、`_placeholderText`、`isSampleData` 标注。

* `_compose`：删 data 块查找与文本写入，仅 `patch` 非 null 项写进 `document.custom`。

* `isUserEmpty`：`expected` 不再排除 data（模板已无 data）；块循环删 `SyIdGenerator.isDataBlockId(...)` 分支与 `block.readonly` 判定（readonly 字段一并退役，见 C1）。

* `_specKey`：删 `data` 分支。

### B. ID 生成器

**B1.** **[sy\_id.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_id.dart)** — 删 `dataBlock` / `dataRoleOf` / `isDataBlockId` / `_dataBlockPattern`（data 块概念整体退役；旧稿已确认清空，无需向后兼容）。`dayContainer` / `monthContainer` / `yearContainer` 保留。

### C. 编辑期模型与控制器

**C1.** **[diary\_model.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/diary_model.dart)**

* 删 `DiaryBlock.readonly` 字段与构造参数（唯一生产者是 data 块模板与按 ID 恢复逻辑，两者同时退役；该字段从不进 `.sy` 序列化，删除不影响格式层）。

* 同步更新 `DiaryBlock` 注释。

**C2.** **[block\_editor\_controller.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_editor_controller.dart)**

* 删 `BlockState.isData` getter。

* 删 `dataRefresher` 字段及其注释。

* 删 `replaceDataSnapshot()` 整段（含 `// data 快照（M4 ↻ 刷新）` 分节标题）。

* `attach()`：删 `if (SyIdGenerator.isDataBlockId(block.id)) block.readonly = true;`。

* `_restoreSnapshot()`：删 `readonlyById` 收集与回填循环。

* 删所有 `|| state.block.readonly` / `prev.block.readonly` 守卫（L185 / L306 / L315 / L375 / L391）。

* **新增** `applyCustomPatch(Map<String, String?> patch)`：批量写/删 `_doc.custom`，语义与 `setDocumentCustom` 一致（doc 未挂载或 locked → no-op；值未变不动 dirty；变更后 `_markDirty()` + `notifyListeners()`；**不压撤销快照**，与 `setDocumentCustom` 对齐）。

**C3.** **[block\_widget.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_widget.dart)**

* 保留工作区既有未提交改动（删 ↻ 调用点、`_refreshing`、`_onRefreshData`）。

* **补删** 现已无引用的 `_DataRefreshButton` 类（消除 `unused_element` 告警）及其专属 import/常量。

* `final readOnly = editor.locked || block.readonly;` → `final readOnly = editor.locked;`。

* 删 `InputDecoration` 的 `hintText` 与 `hintStyle`（保留 `isCollapsed` / `border` / `contentPadding`）。

**C4.** **[block\_editor\_view.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_editor_view.dart)**

* 新增可选参数 `final Widget? header;`。

* `itemCount = (header == null ? 0 : 1) + states.length`；`index == 0` 且有 header 时返回 `KeyedSubtree(key: ValueKey('diary-capsule-row'), child: header!)`，其余 `index - (header == null ? 0 : 1)` 取块。

* 参数文档注明「header 挂滚动区首项，随正文滚动，不参与块结构」。

### D. UI

**D1. 新增** **[diary\_capsule\_row.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/widgets/diary_capsule_row.dart)**

```dart
DiaryCapsuleRow({
  required BlockEditorController controller,
  VoidCallback? onRefreshData,   // null 或 locked → 数据胶囊不可点
  VoidCallback? onPickMood,      // null 或 locked → 心情胶囊不可点
  bool refreshing = false,       // 刷新中：数据胶囊降透明度且不响应点按
})
```

* 外层 `ListenableBuilder(listenable: controller)`，值全部读 `controller.documentCustom`。

* `Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 6, children: [...])` 实现「一行放不下自动换行 + 分散对齐」。

* 胶囊顺序固定：**温度 → 湿度 → 天气 → 日程 → 心情**（用户列举「心情…还包括温度、湿度、天气」为「下移并入」，故数据在前、心情收尾）。

* 五个槽位恒显（不因缺值消失，避免行高跳变）；缺值显示 `—`（心情缺值显示 `mood_outlined` 图标 + 「心情」小字）。

* 取值：`custom-iot-temp` → `🌡️ 21°C`；`custom-iot-humidity` → `💧 45%`；`custom-weather` → `☁️ 多云`；`custom-schedule-count` → `📅 3 条`；`kDiaryMoodKey` → emoji。

* 私有 `_Capsule`：`Container(color: AppColors.tone1, borderRadius: 999, padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5))`，内为 `Row(mainAxisSize: min)`：emoji/icon（size 12）+ 4px + `Text(fontSize 11, color: AppColors.pageLabel)`；点按用 `GestureDetector(behavior: HitTestBehavior.opaque)`。

* 稳定 key：`ValueKey('diary-capsule-temp' / '-humidity' / '-weather' / '-schedule' / '-mood')`。

* 温度+湿度**各自独立胶囊**（不合并），依据用户「温度、湿度、天气」并列列举。

**D2.** **[diary\_mood\_picker.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/widgets/diary_mood_picker.dart)**

* 删 `DiaryMoodChip` 类（入口已迁入胶囊行，避免两处重复实现）。

* 保留 `kDiaryMoodKey` / `kDiaryMoodValues` / `DiaryMoodSelection` / `showDiaryMoodPicker` / `_DiaryMoodSheet` / `_MoodOption`。

**D3.** **[day\_editor\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/day_editor_page.dart)**

* 新增字段 `DiaryComposer? _composer;`（`_load()` 中与 `_document` 一并存下，供刷新回调复用）。

* 删 `_load()` 中 L105-114 的 `dataRefresher` 注入块。

* 删 trailing 里的 `DiaryMoodChip`（保留 `EditorHistoryButtons` / `_SaveChip` / 只读态「归档」）。

* 新增 `bool _refreshing = false;` 与 `Future<void> _refreshData()`：`_refreshing || _readOnly` 时直接返回；置位后 `await _composer!.fetchCustomPatch(_date)` → `_controller.applyCustomPatch(patch)` → `await _flushSave()`，`finally` 复位（`mounted` 守卫）。

* 新增 `Future<void> _pickMood()`（沿用现实现：sheet → `_controller.setDocumentCustom(kDiaryMoodKey, ...)` → `_flushSave`）。

* `BlockEditorView(header: DiaryCapsuleRow(controller: _controller, refreshing: _refreshing, onRefreshData: _readOnly ? null : _refreshData, onPickMood: _readOnly ? null : _pickMood))`。

* 自动聚焦循环：`!block.readonly && block.kind == paragraph && text.trim().isEmpty` → 删 `!block.readonly &&`。

* 类注释同步（不再提 data 块 ↻）。

**D4.** **[diary\_data\_provider.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/diary_data_provider.dart)**

* 接口删 `bool get isSampleData;`，`FakeDiaryDataProvider` 同步删实现与相关注释（唯一消费者是已删的「示例数据」标注）。

**D5.** **[diary\_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/diary_repository.dart#L66-L72)**

* 列表预览过滤 `.where((b) => !b.readonly && ...)` → 删 `!b.readonly &&`；注释去「跳过 readonly data」措辞。

### E. 测试

* 删「data 块 ID」用例：[sy\_id\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/sy/sy_id_test.dart#L48-L67)。

* 重写模板 fixture（新 schema、单空段）：[diary\_template\_json\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/template/diary_template_json_test.dart)、[diary\_template\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/template/diary_template_test.dart)、[diary\_composer\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/template/diary_composer_test.dart)。

* [diary\_composer\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/template/diary_composer_test.dart)：`fetchSnapshot 容错` 组改为 `fetchCustomPatch` 组（断言 patch 键值 + null 删键 + 单源失败不连坐）；`isUserEmpty` 用例改按新骨架；删 `isSampleData` 实现。

* 删 `replaceDataSnapshot` 用例：[block\_editor\_controller\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/editor/block_editor_controller_test.dart)；新增 `applyCustomPatch` 用例（写入/删键/locked no-op/值未变不置 dirty）。

* data 块 fixture 去 readonly：[persistent\_diary\_repository\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/data/persistent_diary_repository_test.dart#L60-L95)、[in\_memory\_diary\_repository\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/data/in_memory_diary_repository_test.dart#L95-L115)。

* 期望改胶囊文本：[diary\_browser\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/ui/diary_browser_test.dart#L82-L116)（「六块模板快照」→「胶囊行 + 单空段」，`find.text('🌡️ 21°C　…　（示例数据）')` → 逐胶囊 `find.text('21°C')` 等），[diary\_m5\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/ui/diary_m5_test.dart) 同步核查。

* **新增** [diary\_capsule\_row\_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/diary/ui/diary_capsule_row_test.dart)：五胶囊恒显、缺值显 `—`、locked 不可点、点数据胶囊触发回调、点心情胶囊触发回调。

### F. 文档对照审计

* [flutter-tech-plan.md](file:///home/phenol/Documents/GitHub/Echo/docs/diary/flutter-tech-plan.md)：§5 第 3 条（data 块只读 + ↻）、§5.1 第 2/4 条、§5.2 第 4 条加「**2026-10-18 用户定稿取代旧裁定**」注记，正文改述新结构（单空段骨架 + 胶囊行 + custom-\* 数据面）；§5 接口示例补 `fetchCustomPatch` 语义。

* [current\_state.md](file:///home/phenol/Documents/GitHub/Echo/docs/current_state.md)、[architecture.md](file:///home/phenol/Documents/GitHub/Echo/docs/architecture.md)、[glossary.md](file:///home/phenol/Documents/GitHub/Echo/docs/glossary.md)、[usage-guide.md](file:///home/phenol/Documents/GitHub/Echo/docs/usage-guide.md)：更新日记模板/胶囊行现状与词条。

* [code\_review\_report.md](file:///home/phenol/Documents/GitHub/Echo/docs/code_review_report.md)：关闭与 data 块 ↻/readonly 相关的条目（若有），记录本次退役。

* [proposals/README.md](file:///home/phenol/Documents/GitHub/Echo/docs/proposals/README.md)：按快通道留一条「文档过时直接修」日志（本变更系用户当场裁定，非铁律/美术 token 变更，不走 RCR）。

## 4. 决策与假设（Assumptions & Decisions）

| #  | 决策                                    | 依据                                                        |
| -- | ------------------------------------- | --------------------------------------------------------- |
| 1  | 在 `rework/diary-ui` 分支直接编码；沿用工作区未提交改动 | 用户答「直接接手实现」；该改动方向与本次一致                                    |
| 2  | 旧模板草稿整机清空，不做旧骨架清理白名单                  | 用户答「清空本机日记数据，全部重来」                                        |
| 3  | `readonly` 字段整体退役（含 sy 层模型字段）         | 唯一生产者（data 块模板 + 按 ID 恢复）同时退役；字段从不进 `.sy` 序列化，且旧稿清空后无兼容需求 |
| 4  | 温度、湿度各自独立胶囊                           | 用户并列列举「温度、湿度、天气」                                          |
| 5  | 胶囊顺序 温度→湿度→天气→日程→心情                   | 心情为「下移并入」的追加项，收尾更自然；如需调整仅改列表顺序                            |
| 6  | 缺值显示 `—`，五槽恒显不消失                      | 避免行高跳变；保留点按重试的可发现性                                        |
| 7  | 点按任一数据胶囊 = 重拉全部三源                     | 与 `fetchCustomPatch` 单次并发取数语义一致，避免拆源带来的状态分叉               |
| 8  | `applyCustomPatch` 不压撤销快照             | 与既有 `setDocumentCustom`（心情）同纪律；数据刷新是系统动作，不做撤销项            |
| 9  | locked（已导出）态仍显示胶囊行，仅禁用点按              | 「胶囊属于笔记内容」，导出后 custom-\* 仍在文档根，应可见；不可改                    |
| 10 | archived 态不受影响                        | 该态无编辑器，仍走 `_ArchivedPlaceholder`                          |
| 11 | 分支期不改 `pubspec.yaml` 版本号              | 项目铁律：排号只在合入 main 时进行                                      |
| 12 | 「写点什么…」连 `hintText`/`hintStyle` 一并删   | 用户明确要求删提示                                                 |

## 5. 验证步骤（Verification）

1. **静态门禁**：`cd echo && flutter analyze`（须零告警，尤其是已删 `_DataRefreshButton` 后无 `unused_element`）；`flutter test`（全量，目标 ≥ 现基线，新增胶囊行/`applyCustomPatch` 用例）。
2. **分支确认**：开工前与提交前 `git branch -vv` 确认在 `rework/diary-ui`；确认无其他 agent 正在运行（用户已确认接手）。
3. **清数据**（需先取得用户确认，属破坏性操作）：优先用 ECP 日记域重置命令（`/diary.reset` 一类，debug 通道）；若不可用再 `adb shell pm clear com.everse.echo`。执行前记录当前是否已导出重要内容。
4. **真机验收（MIX 2S** **`3f6cc09b`，先唤醒屏幕）**：

   * 新开今天：标题下出现 5 个胶囊，数据为 21°C / 45% / 多云 / 3 条；

   * 窄屏换行：胶囊换行后行内分散对齐（首尾贴边、间距均匀）；

   * 点按任一数据胶囊：可重拉并反映（假实现无变化，可用 `provider` 注入异常路径验证 `—` 与重试）；刷新中不可重复点按；

   * 点按心情胶囊：弹五档 sheet，选中后胶囊即时显示 emoji，落盘后重进仍保留；

   * 正文空段落不再出现「写点什么…」；

   * 胶囊随正文滚动、标题固定不动；

   * 导出后在思源属性面板可见 `custom-iot-temp/humidity`、`custom-schedule-count`、`custom-weather`、`custom-mood`。
5. **回归**：日记日列表/月列表、补记入口、自动成稿、跨天空稿清理（新稿形状能被 `isUserEmpty` 判空并清理）、归档流程均不受影响。
6. **收尾**：文档对照审计（F 节）完成；按用户指示决定是否合并 main / 排号 / 打 tag（合并与推送须先获用户确认）。

