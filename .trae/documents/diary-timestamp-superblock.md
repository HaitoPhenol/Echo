# 日记模板自动化生成机制 · 时间戳块 + 超级块

> 分支：`rework/diary-ui` ｜ 日期：2026-10-18 ｜ 决策来源：用户当日口头定稿 + 本文件参考样本
> 参考样本：`artifacts/模板参考 36859.sy.zip`（解压后 `模板参考/20261018231649-xqmvs3p.sy`）

## 1. 概述（Summary）

在既有「单空段骨架 + 胶囊行（文档根 `custom-*`）」之上，加入**时间戳分段**机制：

* **进入编辑页**时自动确保存在一个时间戳块（`yyyy-MM-dd HH:mm`，年月日时分）；与上一条时间戳**间隔 ≥ 30 分钟**才追加新的，否则复用不新建。
* 时间戳块在 App 内**渲染为只读胶囊 chip**（不输入、不带块标），靠**块级自定义属性** `custom-echo-stamp` 作为标志识别；光标自动落到它的**下一行**。
* **一个时间戳 + 其后的正文块 = 一个「段」**，段在语义上等同思源的**垂直超级块**（`NodeSuperBlock` / `Data:'row'`）；段内回车新建的块自动属于本段（派生式分组天然满足）。
* **导出到思源**时按参考样本生成目标结构：
  1. **文档首行**自动生成一个**水平超级块**（`Data:'col'`），内含 5 个带 `code` 行内标记的胶囊段落（温度/湿度/天气/日程/心情）；
  2. 每个「段」包成一个**垂直超级块**（`Data:'row'`），首段为带 `code` 行内标记的时间戳段落；
  3. 时间戳块同时携带 `custom-echo-stamp` 属性——**思源不渲染自定义属性**，故在思源里保留其原本渲染样式（`code` 行内标记）。

> 核心取舍：**草稿/落盘/撤销编解码保持「扁平块列表」不变**；超级块与胶囊 col 超级块**只在导出编码时叠加**。理由：胶囊 col 超级块按参考说明本就是「导出时生成」，同一导出编码顺带完成 row 分段包裹，即可不动持久化、撤销、导入三条既有链路，风险最小。

## 2. 现状分析（Current State Analysis）

已逐一读源码核对：

| 位置 | 现状 |
| --- | --- |
| [diary_model.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/diary_model.dart) | `DiaryBlock{id,kind,level,text,background,updatedAt}`，**无块级 `custom-*`、无行内标记、无嵌套/超级块**；`DiaryDocument.custom` 仅文档根 |
| [sy_serializer.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_serializer.dart#L101-L126) | `_encodeBlock` 的 Properties 只写 `id`/`style`/`updated`，Children 仅 `[NodeText]`；**不写 `NodeTextMark`、不写块级 custom、不写 `NodeSuperBlock`** |
| [sy_serializer.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_serializer.dart#L132-L184) | `decode` 只认 `NodeParagraph`/`NodeHeading`，其余进 `skippedTypes`；`_extractText` 已能拼 `NodeTextMark.TextMarkTextContent`（**降级为纯文本**）；**不回读块级 `custom-*`** |
| [persistent_diary_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/persistent_diary_repository.dart#L128) | 落盘走 `_serializer.encodeBytes(doc)`（**扁平**），`findDay` 走 `decodeBytes`——与撤销快照同一条扁平编解码 |
| [diary_composer.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/diary_composer.dart) | `ensureDay` 命中即原样返回；`isUserEmpty` 按模板骨架多重集判空；`buildEmptyDraft` 与模板同源；`fetchCustomPatch` 产 4 个数据键 |
| [daily_default_template.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/daily_default_template.dart) | `instantiate` 产出**单空段落**（`daily-default-v2`） |
| [block_widget.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_widget.dart) | 所有块统一 `TextField` + 块标 + 浮层；**无按块属性分派渲染** |
| [block_editor_controller.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_editor_controller.dart) | `handleBackspace`（合并/自删）、`handleVerticalMove`、undo/redo 走扁平 sy 编解码；`_postFocus` 是现成的块级跳焦路径 |
| [diary_capsule_row.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/widgets/diary_capsule_row.dart) | 5 枚胶囊读文档根 `custom-*`；私有 `_Capsule`/`_Emoji`（外观原型）；`ui/widgets/**` 已 import `editor/**`（依赖方向经实测确认） |
| [day_editor_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/day_editor_page.dart#L108-L133) | `_load()`：`existedBefore == null` 时聚焦首个空段落（post-frame `requestFocus`） |
| [diary_export_service.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/export/diary_export_service.dart#L129) → [sy_zip_exporter.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_zip_exporter.dart#L100) | 导出统一走 `SyZipExporter.build` → `encodeBytes`，**导出编码与落盘编码同一个**（需拆开） |
| [diary_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/diary_repository.dart#L136-L138) | 仓储暴露 `idGenerator`（可复用于导出侧生成超级块/胶囊段 ID）；`DiaryDaySummary.previewOf` 取首个非空段落（**会把时间戳当预览，需修**） |
| 参考样本 | 胶囊 col 超级块（5 段 `NodeText '' + NodeTextMark(code) + NodeText ''`）→ 概述段（底色 12）→ 两个 row 超级块（`code` 时间戳段 + 正文段）；说明三条：30 分钟内不建新时间戳 / 一个时间戳=一个垂直超级块 / 超级块内回车并入下一行 |

## 3. 改动清单（Proposed Changes）

### A. 模型层 [diary_model.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/diary_model.dart)

* 新增顶层常量 `const String kEchoStampAttr = 'custom-echo-stamp';`（时间戳块的块级自定义属性键，App 独有解析标志）。
* `DiaryBlock` 增 `Map<String, String> custom`（构造参数可选，默认 `{}`，`final` 引用但内容可变，与 `DiaryDocument.custom` 同风格）。
* `DiaryBlock` 增 `bool get isStamp => custom.containsKey(kEchoStampAttr);`。
* 注释补充：块级 `custom-*` 随 `.sy` 块 `Properties` 往返；思源不渲染自定义属性，故导出后保留其原本（`code` 行内标记）样式。

> 注：此前铁律「禁止把内部管线标识写入**文档根** `custom-*`」针对的是文档根与 data 块；本项系用户明确要求新增的**块级**标志，属用户新裁定，需在 proposals 留日志。

### B. 序列化层 [sy_serializer.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_serializer.dart)

**B1. 扁平编码补块级属性（草稿/落盘/撤销路径）**

* `_encodeBlock`：在 `properties` 里并入 `block.custom` 各键（`_sorted` 已保证字典序）。
* 新增 `import 'sy_id.dart';`（导出编码需要 ID 发生器）。

**B2. 解码补块级属性**

* `decode` 的块循环里，从 `blockProps` 提取 `custom-` 前缀键 → `DiaryBlock.custom`。
* `_extractText` 保持现状（`NodeTextMark` 仍降级为纯文本；块既然有 `isStamp` 标志，App 端不需要保留标记）。

**B3. 新增导出编码（思源目标结构）**

```dart
/// 导出专用编码：在扁平草稿之上叠加思源目标结构
/// （首行胶囊 col 超级块 + 每段 row 超级块 + 行内 code 标记）。
String encodeExportJson(DiaryDocument doc, SyIdGenerator ids);
List<int> encodeExportBytes(DiaryDocument doc, SyIdGenerator ids);
```

* 文档根仍走 `_rootNode`（含文档根 `custom-*`）。
* **首行胶囊 col 超级块**：由 `buildDiaryCapsuleItems(doc.custom)` 产出**有值的槽位**（见 C 节）；为空则不生成该超级块。
  * 每个槽位：`NodeParagraph{ID,Properties{id,updated},Children:[NodeText'' ,NodeTextMark(code)$text, NodeText'']}`，`''` = `\u200b`。
* **段分组**：扫描 `doc.blocks`，遇 `isStamp` 即开新段，段 = 该 stamp 起、到下一个 stamp 前；首个 stamp 之前的块按顶层扁平块输出（新骨架下通常为空，作防御）。
* 每段输出 `NodeSuperBlock{ID,Properties{id,updated},Children:[OpenMarker, LayoutMarker Data='row', …段内块, CloseMarker]}`。
* 段内块编码：
  * stamp 块 → Properties 含 `id`/`custom-echo-stamp`/`updated`，Children 为 `[NodeText'' , NodeTextMark(code) 时间戳文本, NodeText'']`；
  * 正文块 → 复用现有 `_encodeBlock` 的 Properties 规则（`id`/`style`/`updated`）。
* 私有小工具：`_superBlock({required String id, required String layout, required DateTime updated, required List<Map<String,Object?>> children})`、`_codeParagraph(...)`、`_rowSegments(doc)`。
* **`_encodeDocument`（扁平）保持不变**，供落盘/撤销用。

### C. 胶囊数据面收口（新增纯 Dart 文件）

**新增** `lib/src/diary/sy/diary_capsule_items.dart`（无 Flutter 依赖）：

```dart
const String kCapsuleTempKey = 'custom-iot-temp';
const String kCapsuleHumidityKey = 'custom-iot-humidity';
const String kCapsuleWeatherKey = 'custom-weather';
const String kCapsuleScheduleKey = 'custom-schedule-count';
const String kCapsuleMoodKey = 'custom-mood';

/// 单个胶囊槽位的展示数据；[label] 为 null 表示该源本次无值。
class DiaryCapsuleItem { final String key; final String emoji; final String? label;
  /// 导出用整串文本（emoji + label）。
  String? get text; }

/// 五个固定槽位（顺序：温度→湿度→天气→日程→心情）。
List<DiaryCapsuleItem> buildDiaryCapsuleItems(Map<String, String> custom);
```

* 展示文本与参考样本一致：`🌡️21°C` / `💧45%` / `☁️ 多云` / `📅3 条` / 心情 emoji；**缺值槽位不出现在导出超级块中**（App 内仍五槽恒显、缺值显 `—`）。
* `diary_mood_picker.dart` 的 `kDiaryMoodKey` 改为别名 `const String kDiaryMoodKey = kCapsuleMoodKey;`（不产生调用方 ripple）。

### D. 时间戳生成编排 [diary_composer.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/template/diary_composer.dart)

* 新增 `bool ensureStamp(DiaryDocument document)`：
  1. 取文档中**最后**一个 `isStamp` 块；若存在且 `_now().difference(last.updatedAt) < 30 分钟` → 返回 `false`（复用，不新建）；
  2. 否则新建 stamp 块（`id: _ids.next()`、`text: _formatStamp(_now())`、`custom: {kEchoStampAttr: '1'}`、`updatedAt: _now()`）：
     * 文档尚无 stamp → **插到索引 0**（模板已有的那个空段落即成为本段正文行）；
     * 已有 stamp → **追加到文档末尾**（新段），并在其后补一个空段落作为新段正文行；
  3. 保证该 stamp 之后至少有一个非 stamp 块（缺失则补空段落）；
  4. 返回 `true`。
* 新增 `static String _formatStamp(DateTime t)` → `yyyy-MM-dd HH:mm`（补零；**年月日时分**，按用户原话）。
* `isUserEmpty`：块循环开头加 `if (block.isStamp) continue;`（自动生成的时间戳不参与「用户是否写了字」判定）。
* `buildEmptyDraft` / `ensureDay` 文档注释同步（骨架现在是「时间戳段 + 正文行」；`ensureDay` 本身不生成时间戳，生成动作由编辑页入口触发）。

> 触发点放在**编辑页入口**（用户原话「进入编辑页时会自动生成」），不改 `ensureDay` 既有语义，故 `diary.ensure` 等既有用例期望不受影响。

### E. 编辑期控制器 [block_editor_controller.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_editor_controller.dart)

* `handleBackspace`：
  * `prev.block.isStamp` → 返回 `false`（不允许把正文并入时间戳块）；
  * 空块自删前：若该块是**文档末块**且其前一块是 stamp → 返回 `false`（保证每个段至少保留一个正文行）。
* `handleVerticalMove`：跳过 stamp 块——向上取最近的前一个非 stamp 块（无则返回 `false`），向下取最近的后一个非 stamp 块（无则返回 `false`）。
* `turnInto` / `setBackground`：开头加 `if (state.block.isStamp) return;`（防御；UI 无入口）。
* 其余不变（`_splitByInsertion` 新建的仍是普通段落；undo/redo 走扁平编解码，块级 custom 已由 B1/B2 保证往返）。

### F. 编辑期渲染

**F1. 新增** `lib/src/diary/editor/diary_capsule_chip.dart`

* 把 `diary_capsule_row.dart` 里私有的 `_Capsule` / `_Emoji` 提取为公开 `DiaryCapsuleChip`（`{leading, label, onTap, dimmed}`）+ `DiaryCapsuleEmoji`，外观与参数同现状（`AppColors.tone1` + `BorderRadius.circular(999)` + 11px `pageLabel` 文本）。
* 放 `editor/` 的依据：`ui/widgets/**` 已 import `editor/**`（既有依赖方向），反向 import 不新增。

**F2.** [block_widget.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/editor/block_widget.dart)：`build` 开头按块属性分派——`block.isStamp` 时直接返回 `DiaryCapsuleChip(label: block.text)`（不含块标、不含浮层、不含 `TextField`）；其余块维持现状。

**F3.** [diary_capsule_row.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/widgets/diary_capsule_row.dart)：改用 `DiaryCapsuleChip` + `buildDiaryCapsuleItems`，删除私有 `_Capsule`/`_Emoji` 与散落的键名字面量；外观与「五槽恒显、缺值 `—`、心情未设显图标」行为不变。

**F4.** [day_editor_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/ui/browser/day_editor_page.dart) `_load()`：

* 顺序：`existedBefore = findDay` → `document = ensureDay` → `stampAdded = composer.ensureStamp(document)` → `_controller.attach(document)`；
* `stampAdded == true` 时：`await repository.upsertDraft(_controller.snapshotDocument())`（自动生成的时间戳立即落盘）；
* 跳焦：`stampAdded == true` 时聚焦**最后一个 stamp 块的下一块**（post-frame `requestFocus`，沿用现写法）；删除原「聚焦首个空段落」分支（首稿必新增 stamp，该分支已不可达）。

### G. 仓储侧

* [diary_repository.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/data/diary_repository.dart#L69-L75) `DiaryDaySummary.previewOf`：过滤条件加 `&& !b.isStamp`（否则列表预览会显示时间戳）。

### H. 导出层

* [sy_zip_exporter.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/sy/sy_zip_exporter.dart)：构造增 `SyIdGenerator? idGenerator`（默认 `SyIdGenerator()`），持 `_ids`；日文档编码改走 `serializer.encodeExportBytes(doc, _ids)`；年/月容器仍走 `encodeContainer`。
* [diary_export_service.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/diary/export/diary_export_service.dart#L97-L99)：`_exporter = exporter ?? SyZipExporter(idGenerator: repository.idGenerator)`（与仓储同源，避免 ID 冲突）。

### I. 测试

* **新增** `test/diary/sy/sy_serializer_export_test.dart`：导出编码——首行胶囊 col 超级块（含/不含值两种情况）、每段 row 超级块边界（含「首段前的散块」防御用例）、stamp 段为 `NodeTextMark(code)` + 零宽空格包裹、`custom-echo-stamp` 写入块 Properties、Properties 键字典序；并断言**扁平 encode（落盘/撤销）不含 `NodeSuperBlock`**。
* **更新** `test/diary/sy/sy_serializer_test.dart`：块级 `custom-*` 编码/解码往返。
* **新增** `test/diary/template/diary_stamp_test.dart`（或并入 composer 测试）：`ensureStamp` 三态（无 stamp→索引 0 插入；<30 分钟→`false` 不新建；≥30 分钟→末尾追加新段+正文行）、文本格式 `yyyy-MM-dd HH:mm`、`isUserEmpty` 忽略 stamp、`previewOf` 忽略 stamp。
* **更新** `test/diary/editor/block_editor_controller_test.dart`：stamp 三条守卫（不并入 stamp、不删末段唯一正文行、上下移动跳过 stamp）、undo/redo 保留块级 custom。
* **新增/更新** widget 测试（`test/diary/editor/block_format_toolbar_test.dart` 或新增）：stamp 块渲染为胶囊、无 `TextField`/无块标；普通块不受影响。
* **更新** `test/diary/export/diary_export_service_test.dart`、`test/diary/sy/sy_zip_exporter_test.dart`：导出包内日文档含超级块与 code 标记。
* **更新** `test/diary/ui/diary_browser_test.dart`、`test/diary/ui/diary_m5_test.dart`：编辑页出现时间戳胶囊 + 光标落下一行；`test/diary/ui/diary_capsule_row_test.dart`：改用共享 chip 后行为不变。
* **核对** `test/control/domain_commands_test.dart`、`test/control/g4_mcp_boundary_test.dart` 中 `diary.ensure` 期望（`ensureDay` 未改，预期不变）。

### J. 文档对照审计

* [sy-format-golden-3.8.6.md](file:///home/phenol/Documents/GitHub/Echo/docs/diary/sy-format-golden-3.8.6.md)：§5 支持子集新增「`NodeSuperBlock`（row/col）+ `NodeSuperBlockOpenMarker`/`LayoutMarker`/`CloseMarker`、`NodeTextMark(code)`、块级 `custom-*`（**导出编码专属**，落盘/撤销仍扁平）」，§6 子集外名单同步调整。
* [flutter-tech-plan.md](file:///home/phenol/Documents/GitHub/Echo/docs/diary/flutter-tech-plan.md) §5：改述时间戳段 + 30 分钟规则 + 导出结构。
* [current_state.md](file:///home/phenol/Documents/GitHub/Echo/docs/current_state.md)、[glossary.md](file:///home/phenol/Documents/GitHub/Echo/docs/glossary.md)、[usage-guide.md](file:///home/phenol/Documents/GitHub/Echo/docs/usage-guide.md)（速查表/阈值表补 **30 分钟**阈值与「时间戳胶囊」坐标/视觉）、[architecture.md](file:///home/phenol/Documents/GitHub/Echo/docs/architecture.md)（导出编码 vs 扁平编码两条链路）。
* [proposals/README.md](file:///home/phenol/Documents/GitHub/Echo/docs/proposals/README.md)：快通道留日志（块级 `custom-*` 标志取代此前「文档根 custom 禁写内部标识」的适用边界，属用户当场裁定，非铁律变更）。
* [code_review_report.md](file:///home/phenol/Documents/GitHub/Echo/docs/code_review_report.md)：如涉及 `previewOf` 预览口径，登记/关闭对应条目。

### K. 交付（用户追加要求）

* 提交：分支 `rework/diary-ui`（**不改 `pubspec.yaml` 版本号、不推送、不打 tag**）。
* `flutter build apk --release --split-per-abi` → 取 `app-arm64-v8a-release.apk`（约 18–19MB，≤20MB 飞书云盘上限）。
* 上传飞书云盘 Echo 文件夹并回分享链接（走 `echo-remote-report` / lark-drive 技能）；构建后还原被 flutter 改写的 `pubspec.lock`，保持工作区干净；说明该包为 debug 签名的内部分发版。

## 4. 决策与假设（Assumptions & Decisions）

| # | 决策 | 依据 |
| --- | --- | --- |
| 1 | 生成时机：**距上次 ≥30 分钟才新建**，否则复用 | 用户答（AskUserQuestion R1/Q1） |
| 2 | **一并实现完整超级块**（一个时间戳=一个垂直超级块 / 回车自动并入 / 导出 row 超级块） | 用户答（R1/Q2） |
| 3 | 时间戳块在 App 内 = **只读胶囊 chip**，光标落下一行 | 用户答（R1/Q3） |
| 4 | 导出**首行也生成胶囊 col 超级块**（5 个 code 段落） | 用户答（R2/Q1） |
| 5 | **草稿/落盘/撤销保持扁平**；超级块与胶囊 col 只在**导出编码**叠加 | 胶囊 col 按参考说明本就是「导出时生成」；同一导出编码顺带做 row 包裹，可完全不动持久化/撤销/导入链路，风险最小 |
| 6 | **不分层改模型**：段由「stamp 块 + 其后到下一 stamp 前的块」**派生**得出 | 「超级块内回车自动并入」在派生式分组下天然成立（新块落点必在该区间内），无需嵌套结构与深链改动 |
| 7 | 30 分钟判定用 stamp 块的 `updatedAt`（而非解析文本） | stamp 只读、`updatedAt` 不会被后续编辑改写；`updatedAt` 随 `.sy` 往返，避免文本格式与判定逻辑耦合 |
| 8 | 时间戳文本格式 `yyyy-MM-dd HH:mm`（**年月日时分**） | 用户原话「年月日时分」；参考样本带秒，如后续要秒仅改 `_formatStamp` |
| 9 | 时间戳块标志键 `custom-echo-stamp`，值 `'1'` | 用户要求「增加一个块自定义属性作为标志」；思源忽略自定义属性，导出后保留原本 `code` 样式 |
| 10 | 导出胶囊槽位**仅输出有值者**；心情未设不输出占位 | 避免把「无数据」导出成正文档噪音；App 内仍五槽恒显 |
| 11 | 导出胶囊 emoji 与文本沿用 App 显示口径（`°C` 而非样本的 `℃`） | 与 App 内胶囊行保持一致，避免两个口径并存；样本的 `℃` 视为笔误 |
| 12 | 不实现参考样本中的「一句话概述今日」（底色 12）段落 | 用户本轮指令未提出；不做未要求的功能 |
| 13 | 复用模板 `daily-default-v2` 单空段落，作为**首段的正文行** | 时间戳插到索引 0 后，原空段落正好落在 stamp 之后，无需新增骨架块、模板 schema 不变 |
| 14 | `ensureDay` 保持纯成稿，时间戳生成由**编辑页入口**触发 | 用户原话「进入编辑页时会自动生成」；`diary.ensure` 等既有语义与用例不受影响 |
| 15 | 共享 chip 放 `editor/`（非 `ui/`） | `ui/widgets/**` 已 import `editor/**`，反向 import 不新增依赖方向 |
| 16 | stamp 块无块标、无浮层、不可选 | 只读自动生成，无排版/删除入口；`turnInto`/`setBackground` 加防守护 |
| 17 | 每个段至少保留一个正文行（禁止删到只剩 stamp） | 否则文档尾部无任何可输入位置，用户被锁死 |
| 18 | 分支期不改版本号、不推送、不打 tag | 项目铁律 |

## 5. 验证步骤（Verification）

1. **静态门禁**：`cd echo && flutter analyze`（零告警）；`flutter test`（全量 ≥ 现基线 469，新增导出编码/时间戳/守卫用例）。
2. **分支确认**：开工前与提交前 `git branch -vv` 确认在 `rework/diary-ui`；`pubspec.yaml` 版本号保持分叉旧值。
3. **纯逻辑自检（无设备可跑）**：
   * `dart test test/diary/sy/sy_serializer_export_test.dart` 解出的导出 JSON 与参考样本逐字段对照（超级块包裹顺序、`Data` 值、`code` 标记三字段、零宽空格、Properties 字典序）；
   * ECP 路径 `diary.export` 造包 → 解压 → `python3 -m json.tool` 人工核对首行 col 超级块与 row 分段。
4. **真机验收（MIX 2S，先唤醒屏幕；禁止改 `screen_off_timeout`）**：
   * 进今天编辑页 → 顶部出现**时间戳胶囊**（`yyyy-MM-dd HH:mm`，只读），光标自动落在其**下一行**，键盘弹起；
   * 正文写多行、多次回车 → 仍属同一段（`diary.export` 后核对：都在同一个 row 超级块内）；
   * 退出重进（30 分钟内）→ **不新增**时间戳，胶囊不重复；
   * 造 ≥30 分钟场景（ECP 改数据或等时）重进 → 文档末尾**新增**第二个时间戳段 + 新空行；
   * 正文首行按退格 → 不误并入时间戳块；把某段唯一正文行删空 → 该空行保留（不被删掉）；
   * 列表页预览**不含**时间戳；跨天空稿清理仍判为空稿；已导出只读态不受影响。
5. **思源侧验收**：导出 `.sy.zip`（UI 或 `diary.export`）→ 导入思源 3.8.6 →
   * 日文档首行是**水平超级块**（5 个胶囊、显示为行内代码片）；
   * 每段时间戳 = **垂直超级块**，首段为 `code` 标记的时间戳，其后是正文；
   * 思源**属性面板**可见 `custom-echo-stamp`（自定义属性），而**正文不出现**任何异常渲染。
6. **回归**：日/月/年列表、补记入口、月度导出提醒与「已导出」徽标、归档流程、ECP `diary.list/get/ensure/prune/seed/export` 均不受影响。
7. **收尾**：文档对照审计（J 节）完成；`git commit`（分叉内，不推送）；构建 arm64 release 分包上传飞书云盘（K 节）。
