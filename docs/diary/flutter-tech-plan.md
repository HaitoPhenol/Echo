# Echo 日记模块 Flutter 适配技术方案

> 上游需求：智谱清言《日记模块开发计划文档 v1.0》（Android 原生壳 + WebView 方案）。
> 本文件把它落地到 Echo 的 Flutter 工程，是日记模块的实施基线。
> 格式细节以《[sy-format-golden-3.8.6.md](sy-format-golden-3.8.6.md)》为准，本文不重复。
>
> 状态：M0 已完成（2026-10-10），M1 进行中。
> 分工：M1 纯 Dart 格式层为基建（本分支直接交付）；M2 起的页面与编辑器属业务代码，
> 由负责笔记/日记页的 agent 按本方案实施。

---

## 1. 与上游方案的差异总览

| # | 上游（WebView 版） | Echo（Flutter 版） |
|---|---|---|
| 1 | Kotlin+Compose 壳，编辑器在 WebView 跑 JS | 纯 Flutter；编辑器为原生块组件，无 WebView |
| 2 | JS Bridge 负责加载/保存/调接口 | 删除桥接层，Dart 内直接调用 |
| 3 | 编辑器配色提取思源 `--b3-*` CSS | 编辑期用 Echo 深色主题；导出期映射 b3 色号 |
| 4 | java.util.zip / SQLite / Retrofit | `archive` / `sqflite` / 抽象 Provider + 假实现 |
| 5 | 深色模式是 M6 打磨项 | App 深色专用，天然满足 |
| 6 | 顶层笔记本文件夹用 ID | 用笔记本名（金标准修正） |
| 7 | 年→日两级 | 年→月→日三级 + 必出 `sort.json` |
| 8 | 底色 hex | `var(--b3-font-backgroundN)` canonical 串 |
| 9 | 容器文档 ID 随机 | 容器 ID 确定性生成，保证增量导出幂等 |
| 10 | 工期 7 周 | 约 5–6 周（无桥接层、IME 由框架接管） |

保留不变的核心原则：单向数据流（Echo → 思源）、导出即锁定、文件即接口、
金标准验证、格式子集裁剪、降级预案（单输入框 + 手动分块按钮）。

## 2. 模块布局

```
echo/lib/src/diary/
├── sy/                          # M1：思源格式层（纯 Dart，零 Flutter 依赖可单测）
│   ├── sy_id.dart               # 块 ID / 确定性容器 ID 生成
│   ├── sy_types.dart           # 格式子集常量（Spec、节点名、底色 canonical 串）
│   ├── diary_model.dart         # DiaryDocument / DiaryBlock（编辑器面向的模型）
│   ├── sy_serializer.dart       # 模型 ↔ .sy JSON（紧凑、键排序、空块省略 Children）
│   └── sy_zip_exporter.dart     # 模型 → 笔记本 .sy.zip（conf/sort/三级树/UTF-8 位）
├── editor/                      # M2-M3：Flutter 原生块编辑器（业务 agent）
├── template/                    # M4：模板实例化与数据注入
├── storage/                     # M5：sqflite diary_meta + 草稿文件仓
└── export/                      # M5：状态机与 share_plus 分享
echo/test/diary/
├── fixtures/                    # 两份金标准样本（.sy / .sy.zip）
└── sy/*_test.dart               # M1 单测
```

新增依赖按里程碑引入：M1 仅 `archive`；M5 再加 `sqflite`、`path_provider`、
`share_plus`。不提前占依赖。

## 3. M1：格式层设计（本分支交付）

### 3.1 数据模型

```dart
/// 一篇日记（= 思源 NodeDocument）
class DiaryDocument {
  final String id;                 // 22 位块 ID
  final DateTime date;             // 归属自然日（决定年/月/日路由）
  String title;                    // 文档标题，如「10日 周六」
  final Map<String, String> custom; // 文档级 custom-*（weather/mood/sleep...）
  final List<DiaryBlock> blocks;
  DateTime updatedAt;
}

class DiaryBlock {
  final String id;
  SyBlockKind kind;                // paragraph | heading
  int level;                       // heading：1..3
  String text;                     // 纯文本，行内换行用 \n
  int? background;                 // 思源底色号 1..13，null 无底色
  bool readonly;                   // 数据注入块
  DateTime updatedAt;
}
```

解析金标准时子集外节点不进入 `blocks`，但在 `SyDecodeResult.skippedTypes`
中记账，供回读 UI 出占位提示。

### 3.2 ID 生成器

```
普通块   next()  = yyyyMMddHHmmss + '-' + 7 位 [a-z0-9]（进程内去重）
年容器   yearContainer(2026)  = 20260101000000-echo000
月容器   monthContainer(2026-10) = 20261001000000-echo000
日容器   dayContainer(2026-10-10) = 20261010080000-echo000
```

- 随机段字符集 `a-z0-9`；同秒批量生成时集合去重；
- 容器 ID 确定性：同一自然日重复导出得到相同文件路径，从根上规避
  「思源对同 ID 文档覆盖行为不确定」的风险——年/月容器只在首次导出时
  入包（内容恒定为空），日文档因「导出即锁定」也不会二次导出；
- `echo000` 合法（7 位字母数字），并在金标准导入验收中确认思源接受
  非随机后缀。

### 3.3 序列化规则（SySerializer）

- 输出紧凑 JSON，UTF-8 无 BOM；顶层字段序 `ID,Spec,Type,Properties,Children`；
- `Properties` 键字典序输出（实测序 `custom-* < id < title/type < updated`；
  块级 `id < style < updated`）；
- `Spec` 恒 `"2"`；空块/空容器省略 `Children`；
- 段落/标题/底色/updated 等逐字段按金标准文档第 4–5 节；
- 底色：`background=N` →
  `"background-color: var(--b3-font-backgroundN); --b3-parent-background: var(--b3-font-backgroundN);"`；
- 解码：容忍 H1–H6；文本取 `NodeText.Data` 与
  `NodeTextMark.TextMarkTextContent` 顺序拼接；底色用正则
  `var\(--b3-font-background(\d+)\)` 提取；
- 幂等要求：`encode(decode(encode(x))) == encode(x)`（对支持子集）。

### 3.4 打包器（SyZipExporter）

输入：笔记本名 + `List<DiaryDocument>` + 导出时刻；输出 `.sy.zip` 字节。

```
{笔记本名}/.siyuan/conf.json
{笔记本名}/.siyuan/sort.json
{笔记本名}/{年ID}.sy
{笔记本名}/{年ID}/{月ID}.sy
{笔记本名}/{年ID}/{月ID}/{日ID}.sy
...
```

- `conf.json` 14 字段按金标准取值（路径类置空，sortMode=15 等）；
- `sort.json` 含包内全部文档 ID（含容器）映射 `1`；
- 年/月容器为空文档（无 Children），`updated` 取导出时刻；
  年标题 `"yyyy"`、月标题 `"M 月"`、日标题 `"M月d日 周X"`；
- zip 条目仅文件、`/` 分隔；中文名必须置 UTF-8 标志位 0x0800
  （M1 单测直接校验本地文件头字节）；
- `archive` 包若不自动置该位，在打包后用自定义字节处理补齐
  （实现时以其源码行为为准，测试锁死）。

## 4. M2–M3：Flutter 原生块编辑器

### 4.1 组件映射

```
ListView(children: blocks.map(BlockWidget.new))
BlockWidget = Row(
  GestureDetector(块标，48dp 热区, onTap 选中),
  Expanded(TextField(
    controller: block.textController,    // 每块独立
    focusNode: block.focusNode,
    readOnly: block.readonly || doc.locked,
    style: block.level != null ? hStyle : pStyle,
    decoration: 底色 + placeholder)),
)
```

不使用全局 contenteditable 等价物；每块独立持有文本与光标，
结构与金标准块模型一一对应。

### 4.2 交互语义（对齐上游 §5.4 与思源行为）

| 交互 | 实现要点 |
|---|---|
| Enter 分块 | `Focus.onKey` 拦截；`controller.selection.baseOffset` 取光标；前半留原块（ID 不变），后半新建**段落**块并聚焦其首 |
| IME 组词 | `controller.value.composing.isValid` 时跳过一切块操作（等价 isComposing）；组词/上屏本身由框架完成 |
| 块首 Backspace | offset=0 时空块删除（至少保留一块）、否则与上一块合并，**保留上一块 ID** |
| ↑/↓ 越界 | offset 0/末尾判断跳焦；进阶用 `TextPainter.getBoxesForRange` 判首/末行 |
| 块选中/底色 | 块标点击 → 浮层调色板（13 色 + 无色），写 background 色号 |
| 粘贴 | 拦截快捷键，剪贴板纯文本按 `\n` 拆块插入 |
| 撤销 | 结构操作压 50 步 JSON 快照；字符级用 TextField 内建 UndoHistory |
| 自动保存 | 5s 防抖，直接写 `.sy` 草稿文件（无桥）；启动校验草稿完整性 |

### 4.3 Flutter 特有的真机验收项（替换上游"浏览器内核矩阵"风险）

- 国产输入法（搜狗/讯飞/百度）多行回车：有的发 `\n`、有的发 action，
  拦截必须可靠；组词中 Enter 只上屏不分块（上游 T04/T09）；
- 200 个 focusNode 规模下键盘弹收焦点不跳动、输入 <16ms/键；
- 降级预案不变：若 M2 超期，先交付单 `TextField` + 手动分块按钮保 M5。

## 5. M4：模板与数据注入

- 模板：`assets/diary/templates/daily-default.json`，上游 §6.1 的声明式骨架
  （📈自动记录 / data 块 / 💭今天 / 🌙睡前）；
- 每日流程：按日期查 meta → 无则实例化（批量发 ID、默认标题、
  调 provider 填充 data 块与 custom-*）→ 落盘 draft；
- 接口抽象先行：

```dart
abstract interface class DiaryDataProvider {
  Future<IoTSnapshot?> fetchHomeEnvironment();      // custom-iot-temp/humidity
  Future<int?> fetchScheduleCount();                 // custom-schedule-count
  Future<String?> fetchWeather();                    // custom-weather
}
```

  M4 用假实现（21°C/45%、3 条日程），IoT/团队模块就绪后只换实现；
- data 块只读 + ↻ 刷新；保存的是快照不是活引用；写作期间不自动刷新。

## 6. M5：存储、状态机与导出

- `sqflite` 表 `diary_meta(id PK, date, state, created_at, exported_at, file_path)`；
  正文即 `.sy` 草稿文件，位于 `path_provider` 应用目录；
- 状态机 `draft → exported（只读+「已归档」徽标）→ archived（清正文留索引）`；
- 导出：查 draft → SyZipExporter 增量打包（年/月容器按需入包）→
  `share_plus.shareXFiles` 甩给系统面板（用户手动发往思源所在设备）；
  成功后置 exported；
- 用户在思源右键导入完成归档闭环；archived 需用户显式确认（上游 US-06）。

## 7. 里程碑

| 里程碑 | 周期 | 交付物 | 验收 |
|---|---|---|---|
| M0 ✅ | 完成 | 两份金标准样本 + 格式对照表 | 2026-10-10 完成 |
| M1 | 1 周 | sy/ 格式层 + 金标准单测 + 示例包思源导入通过 | 本文 §8 测试全绿；用户在 3.8.6 导入示例包成功 |
| M2 | 1–1.5 周 | 编辑器核心：分块/合并/越界/自动保存/崩溃恢复 | 上游 T01–T05/T08–T09 widget 化；200 块性能 |
| M3 | 1 周 | 选中/底色 13 色桥/转标题/撤销/Slash | T06/T07；底色导出往返一致 |
| M4 | 1 周 | 模板实例化 + Provider 假实现 + data 块刷新 | 晨间自动成稿；失败占位降级 |
| M5 | 1 周 | meta 表/状态机/增量导出/分享/只读 | mood 字段可在思源属性视图出图；T10 |
| M6 | 0.5–1 周 | ≥2 台真机连写 7 天、粘贴/撤销边界 | 全流程零异常 |

依赖关系：M1 独立先行；M4 依赖 M2；M5 依赖 M1+M4。

## 8. 测试策略

- M1 纯 Dart 单测（CI 可跑）：
  - ID：正则、千次级唯一、容器确定性；
  - 序列化：金标准 `.sy` 解码后关键字段（标题、custom、H1–H6、
    首块 background=12）；子集往返幂等；底色 canonical 串逐字符相等；
  - 打包：金标准 zip 解包结构断言（conf 14 键、sort 覆盖全文档、
    三级路径）；自打包字节的 UTF-8 标志位、无目录条目、幂等容器；
- 编辑器用例直接搬上游 T01–T10 写成 widget 测试；
- 每里程碑末人工跑金标准验证回路（格式对照表 §7），思源版本锁定 3.8.6。
