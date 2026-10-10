# M4：日记模板与数据注入 实施计划（v2，按 §5.1/§5.2 裁定修订）

> 权威依据：[flutter-tech-plan.md](file:///home/phenol/Documents/GitHub/Echo/docs/diary/flutter-tech-plan.md) §5、**§5.1（四问裁定）、§5.2（用户硬裁定，效力最高）**、§7 M4 行。
> 分支：从最新 `main`（0.7.1+32，M3 已合入并推送）拉 `feat/diary-m4-templates`。
> 版本铁律：任务分支 pubspec 保持 **0.7.1+32 不动**；**实施完成、门禁与真机验收通过后，等用户显式授权才执行** ff-only 合 main → `chore(release): 0.8.0+33` → 推 main/分支 + 远程 v0.8.0（MINOR tag 可推远程）。不得自动合并。

## Repository Research（main\@777bc61 核实）

* 模板缝：[diary\_template.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/diary_template.dart) 仅 `BlankDiaryTemplate`；[day\_editor\_page.dart:81](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/day_editor_page.dart#L81) findDay 为 null 时实例化，首次输入才落盘。

* 仓储：[diary\_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/diary_repository.dart) `today()` 已是时钟收口点（M3），但内存实现构造函数直接吃 `DateTime Function()? now`，**无 04:00 日界概念**；`availableYears/monthsOfYear` 强制包含当前年月（§5.2 后此保证改由自动成稿承担）。

* 装配点：[diary\_page.dart:23](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/diary_page.dart#L23) 根 State 建仓储并 scope，是模块初始化 fire-and-forget 的天然位置。

* 列表现状：

  * [day\_list\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/day_list_page.dart) 整月逐日枚举（降序）+ 空日 dim 行 + 当前月「今天」置顶特例行，**整段行为在 M4 反转**。

  * [month\_list\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/month_list_page.dart) 月行含「本月/N 篇」弱化/强调态；future 缓存在 `didChangeDependencies`（仅 pop 后手动重建）。

  * [year\_list\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/year_list_page.dart) build 内直接取 future，仓储 notify 即自动重建。

* 块只读链路完整：`DiaryBlock.readonly` → TextField 禁输、拆/合/转标题/底色全拦截（[block\_editor\_controller.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_editor_controller.dart)）、快照按 ID 还原 readonly。

* ID 规范：[sy\_id.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_id.dart) 正则 `^\d{14}-[a-z0-9]{7}$`；日容器为 `{yyyyMMdd}080000-echo000`。data 块可仿发 `{yyyyMMdd}080100-data001`（后缀 7 位合法）。

* custom-\*：文档根任意 custom 金标准证实往返，但**会出现在思源属性面板**——只能写真实用户数据。

* 门禁基线：analyze 零 issue，107 测试全绿；pubspec 未注册任何 assets。

## 硬裁定落地要点（不可偏移）

1. **DiaryClock 日界 04:00**：`diaryDate = now.hour < 4 ? 前一自然日 : 当日`。全模块唯一日期判定源；仓储 `today()` 委托于它。标题、容器 ID、provider 日期参数、清理/补记未来禁用全部走 clock。
2. **进模块自动成稿**：DiaryPage 初始化 fire-and-forget `composer.ensureDay(clock.today())`；日页 `_load()` 走同一 composer 实例的同一方法；`ensureDay` 按日期缓存 in-flight Future 去重，消除预热+快速点进双成稿。无 WorkManager/后台调度。
3. **data 块**：readonly 段落快照，**background=3**（M1 真机验收深蓝反色），导出仍写 `var(--b3-font-background3)`；**确定性块 ID** 定位（`{yyyyMMdd}080100-dataNNN`），不写 `custom-echo-*`、不写模板来源；custom-\* 只写 `custom-iot-temp/custom-iot-humidity/custom-schedule-count/custom-weather` 四个真实数据键。↻ 仅编辑期有效。
4. **列表反转**：日列表只渲染 `daysOfMonth`（倒序），删枚举/dim/置顶；年/月列表只显含日记的年月，删「当前年月恒在列」保证与「本月」弱化态；未来无入口。月页加「+ 补记」：`showDatePicker` 范围过去任意日期（floor 2000-01-01）至今天，未来日 `selectableDayPredicate` 禁用，选定走 `ensureDay` 后进日页。
5. **跨天清理**：模块初始化同一时机 fire-and-forget `repository.pruneEmptyBefore(clock.today(), composer.isUserEmpty)`；今天的空稿保留；无弹窗不阻塞；连续多天一次清完。M4 仅进程内语义，不引 sqflite。
6. **范围封板**：不收 Slash 面板、不收 ↑/↓ 跳焦、不做时间戳流式块、不加 mood/sleep。

## Files and Modules

新增：

* `echo/assets/diary/templates/daily-default.json` — 日模板骨架（见下）

* `echo/lib/src/diary/data/diary_clock.dart` — `DiaryClock`（可注入 `DateTime Function() now`）

* `echo/lib/src/diary/template/diary_template_json.dart` — 模板 JSON model + 解析校验（纯 Dart）

* `echo/lib/src/diary/template/daily_default_template.dart` — 骨架实例化（data 块确定性 ID/readonly/background 3）

* `echo/lib/src/diary/data/diary_data_provider.dart` — 接口（**方法带日记日参数**）+ `FakeDiaryDataProvider`（21°C/45%、3 条日程、`多云`；可注入结果/异常；`isSampleData=true`）

* `echo/lib/src/diary/template/diary_composer.dart` — `ensureDay`（in-flight 去重）、快照渲染、`refreshData`、`isUserEmpty`

* `echo/lib/src/diary/ui/diary_composer_scope.dart` — composer/provider/模板下发

* 测试：`test/diary/data/diary_clock_test.dart`、`test/diary/template/diary_template_json_test.dart`、`test/diary/template/diary_composer_test.dart`，改写/扩展 `in_memory_diary_repository_test.dart`、`diary_browser_test.dart`

修改：

* [echo/pubspec.yaml](file:///home/phenol/Documents/GitHub/Echo/echo/pubspec.yaml)：flutter.assets 注册 `assets/diary/templates/`；**版本号不动**

* [sy\_id.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_id.dart)：`static String dataBlock(DateTime date, int roleIndex)` → `{yyyyMMdd}080100-dataNNN`；`static bool isDataBlockId(String)`（正则 `^\d{14}-data\d{3}$`）

* [diary\_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/diary_repository.dart)：加 `Future<int> pruneEmptyBefore(DateTime cutoff, bool Function(DiaryDocument) isEmpty)`（删除日记日 < cutoff 且判定为空的文档，notify 一次，返回删除数）；接口注释更新「当前年月恒在列」语义移除

* [in\_memory\_diary\_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/in_memory_diary_repository.dart)：构造改吃 `DiaryClock`（替换 `now` 形参）；`availableYears/monthsOfYear` 去掉强制当前年月；实现 prune；debug 种子移除「今天」一篇（自动成稿接管），昨天/上月保留

* [block\_editor\_controller.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_editor_controller.dart)：`BlockState` 加 `bool get isData`（ID 判定）；加可注入回调 `Future<void> Function(BlockState)? dataRefresher`；加 `replaceDataSnapshot({required blockId, text, customPatch})`（压一次撤销快照→改文本/custom→置 dirty）

* [block\_widget.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_widget.dart)：data 块（非 locked）尾部显 ↻ 图标按钮，点击走 `dataRefresher`（转圈态防重入）；确认 background 3 下文字反色可读性（M1 已验，回归截图）

* [day\_editor\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/day_editor_page.dart)：`_load()` 改 `composer.ensureDay(date)`；注入 dataRefresher；自动聚焦改为第一个**可写空段**（跳过 heading/readonly/data）

* [diary\_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/diary_page.dart)：装配 clock（真实 `DateTime.now`）、provider（fake）、rootBundle 模板、composer；initState 后 fire-and-forget：`ensureDay(today)` 与 `pruneEmptyBefore(today, isUserEmpty)`（并发即可，cutoff 不含今天，顺序无歧义）

* 三个列表页：day 去枚举化（倒序真实行，今天行就地标「今天」不置顶，无 dim/sub 兜底）；month 去年月弱化态与「本月」特殊文案（保留篇数）+ trailing「+ 补记」动作 + 日期选择器（未来禁用）→ ensureDay 后 push 日页；month/day 的缓存 future 增加仓储 notify 监听自动重取（防 bootstrap 落盘发生在已入页之后）

* [flutter-tech-plan.md](file:///home/phenol/Documents/GitHub/Echo/docs/diary/flutter-tech-plan.md)：M4 完成状态、交付偏差（无后台调度、确定性 data ID、列表反转）、实际测试基线

## 模板骨架（daily-default.json）

Echo 内部 schema（资产 JSON，非思源格式）：

```json
{
  "id": "daily-default-v1",
  "blocks": [
    { "type": "heading", "level": 2, "text": "📈 自动记录" },
    { "type": "data", "role": 1, "placeholder": "数据暂不可用，点 ↻ 重试" },
    { "type": "heading", "level": 2, "text": "💭 今天" },
    { "type": "paragraph" },
    { "type": "heading", "level": 2, "text": "🌙 睡前" },
    { "type": "paragraph" }
  ]
}
```

校验（违例 `FormatException`，测试锁死）：id 非空、blocks 非空、type ∈ heading/paragraph/data、heading 必带 level 1..6、data 必带正整数 role。

## 数据契约与快照格式

```dart
abstract interface class DiaryDataProvider {
  Future<({double tempC, int humidityPct})?> fetchHomeEnvironment(DateTime diaryDate);
  Future<int?> fetchScheduleCount(DateTime diaryDate);
  Future<String?> fetchWeather(DateTime diaryDate); // 假实现返回「多云」，忽略日期
}
```

* 快照行（测试锁死，全角空格 U+3000 分段，按可得性拼片段）：
  `🌡️ 21°C　💧 45%　📅 3 条日程　☁️ 多云`；fake 期间尾部追加 `（示例数据）`。

* 全源失败/全 null：data 块文本 = 占位 `数据暂不可用，点 ↻ 重试`，custom 四键不写。

* 部分失败：缺片段直接省略，不出 null/空片段。

* 成稿写 custom：`custom-iot-temp='21'`、`custom-iot-humidity='45'`、`custom-schedule-count='3'`、`custom-weather='多云'`；refresh 同步更新这四键（缺源则移除对应旧键）。

* 成稿即落盘（upsertDraft），不是首次输入才落盘。

## isUserEmpty 判定（composer 提供，单测锁死）

对文档块序列：

1. 跳过 readonly 块（data 快照永远不算「写过」）；
2. 跳过与模板声明**多重集等价**的块（同 kind+level+text：三个标题块与两个空段）；
3. 其余块中存在任一 `text.trim().isNotEmpty` → 非空；否则空。

锁死用例：新成稿（已填快照）→空；写过字→非空；写字后删光→空；仅拆出多余空块→空；删掉一个标题但无文字→空（重进会重新成稿/重建，语义可接受）。

## Implementation Steps（依赖序）

1. 拉 `feat/diary-m4-templates`；模板 JSON 资产 + pubspec 注册。
2. `DiaryClock` + 边界单测：03:59:59 归前一天、04:00:00 归当天、跨午夜同日、注入时钟。
3. 仓储改造：clock 注入、去年月强制保证、`pruneEmptyBefore` + 单测；同步改写依赖旧构造/旧保证的现有测试。
4. 模板解析器 + DailyDefaultTemplate（确定性 data ID、readonly、background 3）+ 单测（ID 合正则、可重复实例化幂等）。
5. Provider 接口 + Fake 实现。
6. Composer：ensureDay（findDay 命中即返回；in-flight Map 按 yyyymmdd 去重；并发拉源容错；upsert）、renderSnapshot、refreshData（按日期+role 重算 ID 换文本/改 custom）、isUserEmpty；未来日期 ensureDay 抛 `ArgumentError`（防御，测试）。
7. SyIdGenerator dataBlock/isDataBlockId + 单测。
8. 编辑器接线：BlockState.isData、dataRefresher 回调、replaceDataSnapshot（压快照/置 dirty）；block\_widget ↻ 按钮与 loading 防重入。
9. 装配 scope + DiaryPage bootstrap（ensureToday + prune fire-and-forget）；DayEditorPage 走 ensureDay、聚焦首个可写空段；种子去今天。
10. 列表反转：day/month/year 改写；补记入口与日期选择器；notify 自动重取；**改写**现有「空日弱化行/今天置顶/整月行数/空仓本月弱化」widget 用例为新口径（不是删断言）。
11. 新 widget 测试：进模块今天自动成稿（年/月/日列表自然出现今天）；双 ensureDay 竞态只成稿一次；补记过去空日成稿、未来日不可选；prune 跨天空稿删除/写过字保留/今天空稿保留；↻ 刷新文本与落盘、locked 无 ↻；写作后返回再进不被覆盖。
12. 门禁 analyze + 全量测试；MIX 2S 真机：① 强启后进模块今天已成稿（六块、3 号底色快照、示例数据标注）；② ↻ 刷新；③ 补记过去日期成稿、未来日禁选；④ 改设备时间到 03:57/04:02 冷启验证日界（注入时钟单测为准，设备时间复验）；⑤ 跨天清理（改时钟+构造旧空稿场景，优先用 widget/集成测试驱动，真机辅助）；⑥ 返回各级列表只显真实日记。
13. 更新 tech-plan M4 状态与测试基线。
14. **停下等用户授权** → ff-only 合 main → 0.8.0+33 release 提交 → 推 main 与分支、推远程 v0.8.0 tag。

## Dependencies and Considerations

* 无新三方依赖（rootBundle/dart:convert/材料库 DatePicker）；sqflite 仍在 M5。

* data 快照块是段落：导出必落在金标准子集；↻ 导入思源后自然消失，符合「快照非活引用」。

* ↻ 刷新压撤销快照（可撤销一次刷新结果），并走既有 5s 防抖落盘。

* 自动成稿即占篇数是预期行为（月列表篇数 +1）；空稿次日被 prune，列表随之消失。

* 内存仓储 bootstrap 竞态：in-flight 缓存在 composer 实例（scope 单例），日页与根共享。

* 旧《记录规范》（一句话小结 + `@YYYY/MM/DD HH:mm` 流式记录/回忆条目）仅存档，M4 不实现。

## Validation

* 单测/widget：时钟边界、模板解析、成稿/容错/刷新/幂等去重、isUserEmpty 全用例、prune、列表新口径、补记选择器；基线 107 上增（实际数完成时回填 tech-plan）。

* 序列化回归：data 块编码为 background=3 的 NodeParagraph；custom 仅四个真实数据键；serializer 金标准测试保持绿。

* 门禁：`/snap/bin/flutter analyze` 零 issue、`/snap/bin/flutter test` 全绿。

* MIX 2S（3f6cc09b）真机六项验收（步骤 12），截图存 gitignored `artifacts/`，可发飞书群。

## Risks

* **bootstrap future 在首帧后落盘导致列表闪现**：年页已随 notify 重建；month/day 补 notify 监听；真机确认无闪动/重复行。

* **background 3 在编辑态反色**：M1 验收样本同源，仍做深浅文本对比回归（TextField 文字颜色取调色板既有反色逻辑）。

* **DatePicker 未来禁用语义**：`selectableDayPredicate` + lastDate 双保险，确保 today 含 04:00 日界（用 clock.today() 而非系统日期）。

* **prune 误删**：判定纯函数化且先单测全覆盖；仓储实现只删 isUserEmpty=true 且 date\<today 的文档，今天的文档永不删。

