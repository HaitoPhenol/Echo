# Echo 日记模块 Flutter 适配技术方案

> 上游需求：智谱清言《日记模块开发计划文档 v1.0》（Android 原生壳 + WebView 方案）。
> 本文件把它落地到 Echo 的 Flutter 工程，是日记模块的实施基线。
> 格式细节以《[sy-format-golden-3.8.6.md](sy-format-golden-3.8.6.md)》为准，本文不重复。
>
> 状态：M0–M3 已完成（2026-10-10）。M1 示例包经思源 3.8.6 真机导入验收通过；
> M2/M3 年→月→日层级与块级编辑器经 MIX 2S 真机国产输入法验收（拆/合块、
> 防抖落盘闭环），发布 v0.7.0。M3 打磨 patch（`feat/diary-m3-toolbar`，
> 2026-10-10）补齐块标浮层工具栏（正文/H1–H3、13 色真实底色+无色）、
> 编辑页标题栏撤销/重做入口、月行视觉层级；13 色取思源 3.8.6 midnight
> 主题 CSS 实值。浮层经真机两轮打磨：宽度实测收敛为与块等宽（色块自动
> 折行不出屏），朝上/朝下按屏幕剩余空间翻转；编辑块行两轮收紧（块标列
> 48→24、外边距归零，正文累计左移约 40dp）。**Slash 菜单仍留后续 patch**
> （控制器逻辑已就位，只差接线）。
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
│   ├── block_commands.dart           # BlockAction + 13 色调色板（M3 patch 已换思源 midnight 真实 RGB）
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
| 块选中/底色 | 【M3 patch 已接线】块标点击 selectBlock 弹出 OverlayPortal 浮层（正文/H1–H3、13 色+无色，只读禁用；点全屏屏障取消选中并关闭）；`setBackground(1..13/null)`、`turnInto(paragraph/heading 1..3)` 命令只读/locked 时 no-op；13 色为思源 3.8.6 midnight 主题实值，13 号近白底自动切深墨字 |
| 粘贴 | 【已实现】delta 插入文本含多个 `\n` 即一次拆成多块（与分块同通道，无需单独快捷键拦截） |
| 撤销 | 【M3 patch 已接线】结构操作前压 serializer JSON 快照（50 步，含编辑态光标信息）；编辑页标题栏撤销/重做按钮由 canUndo/canRedo 驱动（只读/locked 禁用）；字符级用 TextField 内建 UndoHistory |
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

**2026-10-10 M3 打磨 patch 真机验收结论（MIX 2S）**：块标浮层转
正文/H1–H3、13 色切换（13 号近白深字、6/8 号极深底白字可读性）、
无色清除、点外部屏障关闭且取消选中、浮层应用后保持；标题栏撤销/重做
随 canUndo/canRedo 启停并正确回退/恢复；月页「N 篇 / 本月 · N 篇」
两态（空仓「本月」弱化态由 widget 测试覆盖）层级区分明确。真机反馈
驱动两轮补丁：① 浮层不再超屏——锚点从块标改为整块容器，宽度实测
收敛为块宽（色块 Wrap 折行 9+5），朝上/朝下由浮层实测高度与屏幕上下
剩余空间决定（底部块自动翻上），新增两个 widget 回归；② 块行紧凑化
两轮（块标列 48→34→24、水平外边距 10→4→0、文字内距 10→6→2），
正文起点累计左移约 40dp，浮层随动对齐复验通过。

### 4.4 M2/M3 交付偏差与遗留打磨项

- 层级路由须 `opaque:true`：`opaque:false` 时 Flutter 在转场结束后把
  secondaryAnimation 复位为 dismissed，退场淡出失效，两级页面永久叠绘
  （真机实测，已加 widget 回归断言）。机械网格画在内层 Navigator 之外，
  opaque 不影响其透显；Shell 加命中屏障防空白区点击穿透。
- 仓储/模板接口在 M2 即抽象（`DiaryRepository`、`DiaryTemplate`），
  M5 换 sqflite、M4 加模板集均为平替换/增实现，不动调用方。
- 遗留（后续 patch 迭代，不阻塞 M4/M5）：Slash 命令面板、↑/↓ 逐行跳焦。
  M3 打磨 patch（2026-10-10）已交付：块标浮层工具栏（正文/H1–H3/13 色/
  无色/屏障关闭）、思源 CSS 变量真实底色 RGB（13 号近白底配深墨字）、
  月行「本月 · N 篇 / N 篇 / 本月」三态（仓储补 `today()` 时钟收口与
  `draftCountOfMonth`）、标题栏撤销/重做入口；MIX 2S 真机逐项验收通过。

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

### 5.1 M4 计划评审裁定（2026-10-10，针对 m4_templates_plan.md 四问）

1. **「晨间自动成稿」= 进入日记模块时今天已成稿，不做真后台定时**
  （详见 §5.2 的成稿生命周期；月日列表口径以 §5.2 第 3 条为准，
   **不枚举空日**）：
   `DiaryPage`（模块根）初始化即 fire-and-forget 调
   `composer.ensureDay(today)`（findDay 为 null 才成稿并落盘）；
   日页 `_load()` 走**同一个** `ensureDay`（点进其它空日仍进入即成稿；
   provider 契约带日期参数，M4 假实现忽略日期，真实 provider 自行判空）。
   `ensureDay` 必须按日期缓存 in-flight Future，消除模块预热与快速点进
   的竞态双成稿。不引入 WorkManager/后台调度（M4 无此依赖；真实 IoT
   源就绪后若有需要在 M5 之后单独立项）。
   - ~~空模板弱化行~~ 方案作废，改按 §5.2 第 3 条：空日不出现在列表，
     跨天的空草稿在下次运行时后台删除。
2. **data 块 = 只读段落快照（计划方向正确），禁止造思源自定义节点**：
   金标准子集外节点回读即被降级丢弃（对照表 §6），自定义节点导入风险
   不可控；快照段落思源 3.8.6 必开。两条细化：
   - **块底色用 3 号**（M1 真机验收样本即 background=3 的只读 data 块，
     深色主题深蓝反色已获用户确认）；导出仍写
     `var(--b3-font-background3)` canonical 串。
   - **内部索引不得写文档根 `custom-*`**：所有 custom-* 都会出现在思源
     属性面板与属性视图字段集（M1 验收截图已证），
     `custom-echo-data-*`/`custom-echo-template` 是内部管线，暴露即噪声。
     data 块改用**确定性块 ID** 定位（同年/月/日容器方案）：
     `SyIdGenerator` 增静态方法，形如 `{yyyyMMdd}080100-data001`
     （角色序号递增，仍合 14 位时间戳+7 位正则），refresh 按日期+角色
     算 ID；成稿来源模板 id 不进文档（M5 可存 meta）。只有真实用户数据
     （iot-temp/iot-humidity/schedule-count/weather）写 custom-*。
   - ↻ 是 Echo 编辑期 affordance；导入思源后只剩静态快照文本，无刷新入口，
     这是「快照非活引用」的预期表现。
3. **M4 范围不含 Slash 面板与 ↑/↓ 逐行跳焦**：§4.4 已定性为不阻塞
   M4/M5 的编辑器打磨遗留，混入只会稀释 M4 主题；M4 交付物 = 模板资产 +
   provider 假实现 + composer（成稿/容错/刷新）+ ↻ UI + 真机验收，
   一项不砍也不扩张。
4. **骨架与假数据文案保持计划版本**：📈自动记录 / 💭今天 / 🌙睡前三段 +
   data 块 + 两个空段即 M1 验收样本结构；21°C/45%、3 条日程与 §5 契约
   一致。快照行格式在 composer 测试里锁死一种（全角空格分段，emoji 方案
   自定但全模板统一），假数据期间以 chip/尾部标注「示例数据」。
   custom-mood/custom-sleep 不进 M4（属用户手填/心情选择 UI，后续里程碑）。

### 5.2 日记日时钟、成稿生命周期与列表口径（2026-10-10 用户裁定，效力高于前述设想）

用户依据长期沿用的旧记录习惯（另一个 app 的《记录规范》：年→月→日层级，
月页只链接实际创建的日子，日文档含当日一句话小结与时间戳记录/补记条目）
作出以下四条裁定。**M2 交付的日列表"整月逐日枚举 + 空日弱化行"行为在
M4 反转。**

1. **日界 = 凌晨 04:00**：00:00–03:59 仍属于前一天。
   - 设单一"日记日时钟"缝（与 M3 已收口的仓储 `today()` 同源，
     可命名 `DiaryClock`）：`diaryDate(now) = now.hour < 4
     ? 前一自然日 : 当日自然日`。全模块禁止直接用 `DateTime.now()` 的
     日期判定"今天"（标题、容器 ID、provider 日期、清理判定都走它）。
   - 确定性容器 ID（`SyIdGenerator.dayContainer`）等输入仍是纯日期，
     时钟只负责把墙上时间映射到日记日。
2. **任意时间进入笔记模块即自动成稿当天日记**：`DiaryPage` 初始化
   fire-and-forget `ensureDay(clock.today())`（findDay 命中即跳过），
   点进月页时今天的日记必已在行；同一天反复进模块不重复成稿
   （in-flight Future 按日期去重）。
3. **月/日列表只显示真实存在的日记，不枚举未来与空日**：
   - 日列表数据源仅为仓储 `daysOfMonth`（升序/UI 倒序展示），
     删除 `DayListPage` 的整月天数枚举、空日弱化行、"今天置顶"特例行
     （今天由自动成稿保证自然出现在列表里）。
   - 年/月列表同理：只有含日记的年月出现；当前年月由自动成稿保证存在。
   - **不提供未来日期入口**（"1 号点进 31 号"式入口取消）；保留补记
     过去日记的能力（旧规范的"回忆"用法）：月页放一个「+ 补记」动作，
     日期选择器可选范围 = 有日记需求的任意**过去日期及今天**，
     未来日期禁用；选定后同样走 `ensureDay`。
4. **空草稿跨天后台清理**：
   - 模块初始化（ensureToday 同一时机）执行
     `pruneEmptyBefore(clock.today())`：删除所有日记日 **早于今天** 的
     "什么都没写"的草稿，fire-and-forget，无弹窗、不阻塞浏览；
     今天的空草稿保留（当天还可能写）。连续多天未打开则一次性清理多天。
   - "空"的判定（composer 提供，单测锁死）：忽略 readonly data 块与
     模板骨架预填块（与模板声明等价的 heading/段落），其余块中**不存在
     任一 trim 后非空文本**即为空。用户写了字又自己删光，次日同样清理；
     data 快照内容不作为"写过"的依据。
   - M4 内存仓储下清理仅活于进程内，接口与判定先行并测试；M5 持久化
     后自动获得真实的跨进程清理语义。

旧规范的日文档形态（一句话当日小结 + `@YYYY/MM/DD HH:mm` 时间戳记录
段落、可在之后补写"回忆"条目）作为**长期形态参考**存档：M4 仍交付
📈/💭/🌙 三段 + data 快照模板，不引入时间戳流式块；时间戳记录/补记
排版是否升级为独立块类型，在模板体系稳定后单独立项，导出仍须落在
金标准子集（段落/标题）内。

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
| M3 ✅（核心 + 打磨 patch） | 1 周 | 选中/底色 13 色桥/转标题/撤销/Slash | 2026-10-10 核心完成：selectBlock/setBackground/turnInto 命令 + serializer 往返 + 50 步撤销重做，非法参数/只读守卫齐；底色导出随序列化往返一致。同日 M3 打磨 patch 接线完成：块标浮层（正文/H1–H3/13 色/无色）、标题栏撤销重做按钮、月行三态，底色换思源 midnight 实值（MIX 2S 真机验收）。**仅余 Slash 菜单留下个 patch** |
| M4 | 1 周 | 模板实例化 + Provider 假实现 + data 块刷新；04:00 日记日时钟、进模块自动成稿、空草稿跨天清理、月日列表去枚举化（§5.2） | 晨间自动成稿；失败占位降级；3:59 归属前一天/4:00 归属当天单测；空日不入列表；跨天空草稿被清理、写过字的保留；补记日期选择器禁未来 |
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
- **底色编辑期色板已换思源实值（M3 patch）**：`BlockBackgroundPalette.colors`
  取自思源 3.8.6 midnight 主题 `--b3-font-background1..13` 暗色实值
  （fillOf 不透明；13 号近白经 luminance 判定切深墨字），数据层仍只存
  1..13 色号、导出走 `var(--b3-font-backgroundN)` canonical 串，零数据迁移。
  浅色主题两套取值仍留待 M6。
- **控制器能力的 UI 接线状态**：turnInto/setBackground/50 步撤销重做已在
  M3 patch 完成接线——块标浮层（转标题/底色）、标题栏撤销/重做按钮；
  **Slash 命令面板与块拖拽浮层入口仍未接线**，留下个 patch。
- **浏览层时钟收口于仓储**：M3 patch 给 `DiaryRepository` 增加 `today()`，
  月/日列表的当年当月可达性与「今天/本月」高亮不再直取 `DateTime.now()`，
  M5 持久化实现须同步提供该方法（内存实现为可注入时钟）。

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
- M3 打磨 patch 在 `feat/diary-m3-toolbar` 分支（从已合入 M2/M3 的本地
  main 拉出，2026-10-10）交付，含 4 个提交（M3 功能、浮层屏内自适应、
  块行两轮收紧、文档），同日 ff-only 合入 main 后排 **0.7.1+32**，
  本地打 v0.7.1（patch tag 不推远程）；任务分支 pubspec 全程保持
  0.7.0+31 未动。
  注：本地 main ff-only 合入 M2/M3 后远程 push 曾因网络（github.com:443
  超时）滞后，M3 patch 合入时一并补推 main 与两个日记功能分支。
- 版本规则（项目铁律）：0.MINOR.PATCH + 单调递增 build 号；功能里程碑
  完成 MINOR+1（M4→0.8.0、M5 顺延），bug 修复走 PATCH（功能更新时清零）；
  patch tag 只打本地，远程只推 vX.Y.0 的 MINOR tag；**排号只在合入 main
  时由合并者看 main 当前版本与已有 tag 取号，任务分支 pubspec 保持分叉
  旧值不动**。
- 流程偏差追认：v0.7.0 实际在功能分支上提前排号并推送（应在合并提交中
  完成）；tag 已推送不可变，合入 main 时追认 0.7.0 即可，后续不再提前排号。
- M2/M3 交付时门禁基线：`flutter analyze` 零 issue，全量 95 测试通过；
  M3 打磨 patch 后基线更新为 107 测试通过（新增色板映射、浮层开关/命令、
  标题栏撤销重做、月行三态、仓储 today/draftCountOfMonth、浮层屏内自适应
  两条回归等用例）。
