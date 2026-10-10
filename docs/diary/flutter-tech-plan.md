# Echo 日记模块 Flutter 适配技术方案

> 上游需求：智谱清言《日记模块开发计划文档 v1.0》（Android 原生壳 + WebView 方案）。
> 本文件把它落地到 Echo 的 Flutter 工程，是日记模块的实施基线。
> 格式细节以《[sy-format-golden-3.8.6.md](sy-format-golden-3.8.6.md)》为准，本文不重复。
>
> 状态：M0–M3 已完成（2026-10-10）。M1 示例包经思源 3.8.6 真机导入验收通过；
> M2/M3 年→月→日层级与块级编辑器经 MIX 2S 真机国产输入法验收（拆/合块、
> 防抖落盘闭环），发布 v0.7.0。M3 剩余打磨项（工具栏 UI、Slash 菜单、
> 思源主题真实色板）转入后续 patch 迭代。
> 分工：M1 纯 Dart 格式层为基建（已交付于 `lib/src/diary/sy/`）；M2 起的页面
> 与编辑器属业务代码，由负责笔记/日记页的 agent 按本方案实施。

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
├── data/                        # M2：DiaryRepository 抽象 + InMemory 实现（M5 平替换为 sqflite）
├── template/                    # M2 落地接口：DiaryTemplate + BlankDiaryTemplate（M4 扩充模板集）
├── editor/                      # M2-M3：Flutter 原生块编辑器
│   ├── block_editor_controller.dart  # delta 拆/合块、跳焦、命令、50 步撤销、dirty
│   ├── block_commands.dart           # BlockAction + 临时 13 色调色板（M3 换真实 RGB）
│   ├── block_widget.dart             # 块标/段落与 H1-H3 样式/底色/Action 键拦截
│   ├── block_editor_view.dart        # ListView.builder 懒加载
│   └── editor_scope.dart
├── ui/                          # M2-M3：浏览与编辑页
│   ├── diary_page.dart          # 内嵌 Navigator + PopScope 收口系统返回
│   ├── diary_route.dart         # opaque 右侧滑入路由（无边缘手势，避开外层横滑）
│   ├── browser/                 # year/month/day 列表页 + day_editor 编辑页
│   └── widgets/                 # DiaryShell / DiaryListRow
├── storage/                     # M5：sqflite diary_meta + 草稿文件仓
└── export/                      # M5：状态机与 share_plus 分享
echo/test/diary/
├── fixtures/                    # 两份金标准样本（.sy / .sy.zip）
├── sy/*_test.dart               # M1 单测
├── data/ template/ editor/      # M2-M3 单测
└── ui/diary_browser_test.dart   # 层级下钻/落盘预览/200 块懒加载/硬件退格合并
```

新增依赖按里程碑引入：M1 仅 `archive`；M5 再加 `sqflite`、`path_provider`、
`share_plus`。不提前占依赖。

## 3. M1：格式层设计（已交付，见 `echo/lib/src/diary/sy/`）

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

## 4. M2–M3：Flutter 原生块编辑器（已交付于 `lib/src/diary/{editor,ui,data,template}/`）

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

### 4.2 交互语义（对齐上游 §5.4 与思源行为；括注 M2/M3 实际落地）

| 交互 | 实现要点 |
|---|---|
| Enter 分块 | 【已实现，通道有变】不走 `Focus.onKey`（国产 IME 软回车不产生按键事件）：监听 TextEditingValue delta，插入文本含 `\n` 时做前缀/后缀 diff 拆分；前半留原块（ID/kind/底色不变），后半新建**段落**块并按新坐标落焦 |
| IME 组词 | 【已实现】`composing.isValid` 时只同步文本不拆块（实测国产 IME 上屏链路） |
| 块首 Backspace | 【已实现】硬件退格经 `Actions` 覆盖 `DeleteCharacterIntent`（利用 EditableText 的 Action.overridable，条件不满足回落默认行为；Focus 冒泡在空删除时不可靠）：offset=0 空块删除（至少留一块）、非空与上一块合并，**保留上一块 ID** |
| ↑/↓ 越界 | 【已实现，边界版】覆盖 `ExtendSelectionVerticallyToAdjacentLineIntent`，仅首行 offset0 向上 / 末行末尾向下才拦截跳焦；`TextPainter` 逐行判定留待打磨 |
| 块选中/底色 | 【已实现命令，浮层 UI 待打磨】块标点击 selectBlock；`setBackground(1..13/null)`、`turnInto(paragraph/heading 1..3)` 命令就绪且只读/locked 时 no-op；13 色调色板目前为临时暗色值，浮层 UI 与思源主题真实 RGB 待补 |
| 粘贴 | 【已实现】delta 插入文本含多个 `\n` 即一次拆成多块（与分块同通道，无需单独快捷键拦截） |
| 撤销 | 【已实现】结构操作前压 serializer JSON 快照（50 步，含编辑态光标信息）；字符级用 TextField 内建 UndoHistory |
| 自动保存 | 【M2：内存仓储版】dirty 监听 + 5s 防抖 snapshotDocument→upsertDraft；paused/hidden/inactive 与返回时强制 flush；保存态 chip（编辑中/已保存 HH:mm/草稿/只读）。**写 `.sy` 草稿文件与启动完整性校验在 M5 随持久化落地** |

### 4.3 Flutter 特有的真机验收项（替换上游"浏览器内核矩阵"风险）

- 国产输入法（搜狗/讯飞/百度）多行回车：有的发 `\n`、有的发 action，
  拦截必须可靠；组词中 Enter 只上屏不分块（上游 T04/T09）；
- 200 个 focusNode 规模下键盘弹收焦点不跳动、输入 <16ms/键；
- 降级预案不变：若 M2 超期，先交付单 `TextField` + 手动分块按钮保 M5。

**2026-10-10 真机验收结论（MIX 2S，自带国产 IME）**：软键盘「换行」
拆块、空块退格删除、非空块首退格合并（光标落接合处）、5s 防抖落盘
（chip「已保存 HH:mm」）、返回日列表预览与块数刷新全部通过；
200 块懒加载有 widget 测试（ListView.builder，视口外不构建）。

### 4.4 M2/M3 交付偏差与遗留打磨项

- 层级路由须 `opaque:true`：`opaque:false` 时 Flutter 在转场结束后把
  secondaryAnimation 复位为 dismissed，退场淡出失效，两级页面永久叠绘
  （真机实测，已加 widget 回归断言）。机械网格画在内层 Navigator 之外，
  opaque 不影响其透显；Shell 加命中屏障防空白区点击穿透。
- 仓储/模板接口在 M2 即抽象（`DiaryRepository`、`DiaryTemplate`），
  M5 换 sqflite、M4 加模板集均为平替换/增实现，不动调用方。
- 遗留（后续 patch 迭代，不阻塞 M4/M5）：块操作浮层工具栏与 Slash 菜单、
  思源 CSS 变量真实底色 RGB 桥接、↑/↓ 逐行跳焦、月行「当前月/有内容」
  视觉层级、撤销重做的 UI 入口（canUndo/canRedo 接口已就绪）。

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
| M1 ✅ | 完成 | sy/ 格式层 + 金标准单测 + 示例包思源导入通过 | 2026-10-10 完成：38 个日记测试 + 全量 62 测试绿、analyze 0 问题；示例包在 3.8.6 真机导入验收通过 |
| M2 ✅ | 1–1.5 周 | 编辑器核心：分块/合并/越界/自动保存；年→月→日三级浏览页 + DiaryRepository 内存实现 | 2026-10-10 完成：T01/T02/T04/T05/T08/T09 单测化，层级下钻与落盘预览 widget 化，200 块懒加载测试；真机国产 IME 拆/合块+防抖落盘验收。注：**崩溃恢复（进程被杀不丢字）随 M5 持久化一起验收**——M2 仓储为内存实现，5s 防抖只落内存 |
| M3 ✅（核心） | 1 周 | 选中/底色 13 色桥/转标题/撤销/Slash | 2026-10-10 核心完成：selectBlock/setBackground/turnInto 命令 + serializer 往返 + 50 步撤销重做，非法参数/只读守卫齐；底色导出随序列化往返一致。**Slash 菜单与浮层工具栏 UI、撤销按键/按钮绑定、思源真实色板留后续 patch 打磨**（控制器逻辑已就位，M3 打磨只做"接线"） |
| M4 | 1 周 | 模板实例化 + Provider 假实现 + data 块刷新 | 晨间自动成稿；失败占位降级 |
| M5 | 1 周 | meta 表/状态机/增量导出/分享/只读/持久化 | mood 字段可在思源属性视图出图；T10；**杀进程重进后 5s 防抖窗口内的文字不丢（崩溃恢复补验收）** |
| M6 | 0.5–1 周 | ≥2 台真机连写 7 天、粘贴/撤销边界 | 全流程零异常 |

依赖关系：M1 独立先行；M4 依赖 M2；M5 依赖 M1+M4。

### 7.1 已知边界与后续里程碑钩子（M2/M3 代码评审记录，2026-10-10）

- **撤销快照经 sy codec，M5 导入回读时需防丢块**：`BlockEditorController`
  的结构级撤销用 `SySerializer` 编解码做快照（同时持续验证金标准 codec），
  而解码会按格式对照表 §4 跳过子集外块类型。M2–M4 不存在导入回读链路，
  无实际风险；**M5 一旦支持只读回读含子集外块的文档，对该文档执行撤销
  可能丢失这些只读节点**。落 M5 时二选一：撤销快照保留原始节点（不走
  codec），或含 skippedTypes 的文档禁用结构撤销。
- **编辑器只产 H1–H3，解码容忍 H1–H6**：回读文档中的 H4–H6 按 H3 字号
  显示（`block_widget._styleFor` 的 `_` 分支），但模型保留原 level，
  导出往返不丢级别；Echo 自身永远不会新建 H4+。此为有意取舍，M5 回读
  联调时在只读横幅或行内给出"级别降级显示"的视觉提示即可。
- **底色编辑期色板是占位值**：`BlockBackgroundPalette.colors` 为暗色界面
  低饱和临时 RGB（代码内有 TODO），数据层只存 1..13 色号、导出走
  `var(--b3-font-backgroundN)` canonical 串，换真实色板零数据迁移；
  M3 打磨 patch 需从思源 3.8.6 主题 CSS 提取实际取值并做深浅色两套。
- **M2/M3 提前落地但尚无 UI 入口的能力**：turnInto/setBackground/50 步
  撤销重做在控制器层已完成并测试，M3 打磨 patch 只需接线——块标浮层
  （转标题/底色/拖拽）、Slash 命令面板、撤销的按键与工具栏绑定。

## 8. 测试策略

- M1 纯 Dart 单测（CI 可跑）：
  - ID：正则、千次级唯一、容器确定性；
  - 序列化：金标准 `.sy` 解码后关键字段（标题、custom、H1–H6、
    首块 background=12）；子集往返幂等；底色 canonical 串逐字符相等；
  - 打包：金标准 zip 解包结构断言（conf 14 键、sort 覆盖全文档、
    三级路径）；自打包字节的 UTF-8 标志位、无目录条目、幂等容器；
- 编辑器用例直接搬上游 T01–T10 写成测试：M2/M3 已落地为 controller 单测
  （直接赋 TextEditingValue 模拟 IME：拆块/合并/边界跳焦/命令/撤销/
  composing 不拆）与 widget 测试（层级下钻、空日落盘后预览刷新、
  200 块懒加载、硬件退格合并、opaque 路由不叠绘回归）；
- 每里程碑末人工跑金标准验证回路（格式对照表 §7），思源版本锁定 3.8.6。

## 9. 版本与分支记录

- M2/M3 在 `feat/diary-m2-editor` 分支（从 `feat/notes-page` 拉出）交付，
  2026-10-10 发布 **v0.7.0（0.7.0+31）**，分支与 MINOR tag 已推远程
  （未开 PR，不自行合并）。
- 版本规则（项目铁律）：0.MINOR.PATCH + 单调递增 build 号；功能里程碑
  完成 MINOR+1（M4→0.8.0、M5 顺延），bug 修复走 PATCH（功能更新时清零）；
  patch tag 只打本地，远程只推 vX.Y.0 的 MINOR tag；**排号只在合入 main
  时由合并者看 main 当前版本与已有 tag 取号，任务分支 pubspec 保持分叉
  旧值不动**。
- 流程偏差追认：v0.7.0 实际在功能分支上提前排号并推送（应在合并提交中
  完成）；tag 已推送不可变，合入 main 时追认 0.7.0 即可，后续不再提前排号。
- M2/M3 交付时门禁基线：`flutter analyze` 零 issue，全量 95 测试通过。
