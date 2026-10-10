# M2/M3（首批）：年→月→日浏览层级 + 块级所见即所得编辑器

## 目标与本轮范围

按 flutter-tech-plan.md §4，在笔记页（导航第 3 页 `notes`）内交付：

1. **年→月→日三级浏览层级**：进入笔记页即年列表，逐层下钻到某日，
   系统返回键/页内返回逐层退出；
2. **简单块级 WYSIWYG 编辑器**：每块独立文本与光标，Enter 分块、
   块首 Backspace 合并/删空块、↑↓ 跳焦、IME 组词保护、粘贴按换行拆块、
   只读块/锁定文档不可编辑、H1–H3 与块底色如实渲染、结构撤销（控制器层）、
   5s 防抖自动保存 + 进后台立即落盘。
3. **为持续打磨预留接口**：M3 的块标调色板、转标题、Slash 菜单、撤销 UI
   本轮只在控制器层实现命令并单测，不做 UI；存储、模板、导出全部面向
   抽象接口编程，M4/M5 换实现不改编辑器。

不在本轮：sqflite/文件草稿（M5）、模板与数据注入（M4）、调色板/Slash UI、
导出/分享、搜索数据源接入（接口已明确，后续接 SearchProvider）。

## Repository Research（现状结论）

- 页面装配：[nav_destination.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_destination.dart)
  的 `buildDefaultDestinations()` 集中描述 4 页；`notes` 当前是居中大字的
  TemplatePage。页面在 [smart_nav_screen.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L1142-L1153)
  的横向 Row 里**同时常驻构建**（非 PageView），翻走不销毁，编辑器状态天然保留。
- 状态范式：`ChangeNotifier 服务 + InheritedNotifier Scope`（[chat_store.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/chat_store.dart)
  是范本），Scope 在 SmartNavScreenState（约 L1357）统一装配。日记沿用同一范式。
- 页面视觉：无标题栏、透明底透 MechanicalBackground、列表行样式参考
  [chat_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/pages/chat_page.dart)
  （安全区内边距、底部留 26px 避让停靠条、tone1 分隔线）。
- M1 格式层可直接复用：`DiaryDocument/DiaryBlock` 可变模型、
  `SyIdGenerator.next()` 块 ID（应用级单例注入，测试传 fake）、
  `SySerializer`（可做撤销快照与往返断言）、`SySerializer.dayTitle()`
  （「10月10日 周六」）。
- 依赖：本轮**不新增任何依赖**（sqflite/path_provider/share_plus 按计划留 M5）。
- 关键技术判断（软键盘可靠性）：Android 国产输入法对回车有的发按键事件、
  有的只产生含 `\n` 的文本 delta。因此回车分块/块首退格**不依赖 Focus.onKey**，
  主通道用 TextEditingController 的值差异（TextEditingDelta：插入文本含
  `\n` 即拆块、删除 delta 起点为 0 即合并），组词中（composing 有效）一律
  放行不拆；onKey 仅用于外接键盘 ↑↓ 跳焦。onKey 回车方案只在硬键盘上可靠，
  不作为主通道。真机 IME 验收走 echo-device-verify。

## 架构与目录

```
echo/lib/src/diary/
├── sy/                         # M1，不动
├── data/
│   ├── diary_repository.dart      # 抽象仓储 + DiaryDaySummary/DiaryDocState
│   └── in_memory_diary_repository.dart # M2 内存实现（含开发种子数据）
├── template/
│   └── diary_template.dart        # DiaryTemplate 接口 + BlankDiaryTemplate
├── editor/
│   ├── block_editor_controller.dart # BlockState/结构命令/撤销栈/脏标记
│   ├── editor_scope.dart           # EditorScope（InheritedNotifier，页面内）
│   ├── block_widget.dart           # 块标(48dp) + TextField
│   ├── block_editor_view.dart      # ListView.builder 懒加载
│   └── block_commands.dart         # 命令枚举（转标题/底色等），M3 UI 绑定
└── ui/
    ├── diary_page.dart             # 笔记页主体：嵌套 Navigator + PopScope
    ├── diary_route.dart            # 路由参数与生成器
    ├── widgets/diary_shell.dart    # 统一页框：细头(返回箭头+层级标题)+安全区
    └── browser/
        ├── year_list_page.dart
        ├── month_list_page.dart
        ├── day_list_page.dart
        └── day_editor_page.dart    # 装配控制器、自动保存、生命周期落盘
```

### 关键抽象（扩展缝）

```dart
/// 日记仓储：M2 内存实现；M5 替换为 sqflite meta + .sy 草稿文件，
/// 编辑器与浏览页只依赖本接口。
abstract interface class DiaryRepository {
  Future<List<int>> availableYears();
  Future<List<int>> monthsOfYear(int year);
  Future<List<DiaryDaySummary>> daysOfMonth(int year, int month);
  Future<DiaryDocument?> findDay(DateTime date);
  Future<void> upsertDraft(DiaryDocument doc);   // 首次输入才真正产生草稿
}

/// 日摘要（列表行用）；state 现在恒 draft，M5 状态机直接填值。
class DiaryDaySummary { DateTime date; String preview; int blockCount; DiaryDocState state; }
enum DiaryDocState { draft, exported, archived }

/// M4 模板缝：本轮只有 BlankDiaryTemplate（单个空段落），
/// M4 增加 assets/diary/templates/daily-default.json 的实现。
abstract interface class DiaryTemplate {
  String get id;
  DiaryDocument instantiate(DateTime date, SyIdGenerator ids);
}
```

### 编辑器控制器职责

`BlockEditorController extends ChangeNotifier`（不持有任何文件/数据库概念）：

- `attach(DiaryDocument)` / `DiaryDocument detach()`：块模型 ↔ BlockState
  （每块一个 TextEditingController + FocusNode，按块 id 映射、detach 统一 dispose）；
- 文本变更经块内监听走 delta 主通道：
  `handleInsertion(block, oldVal, newVal)` 含 `\n` → 拆成多块；
  `handleDeletion` 删除区间起点为 0 → 合并上一块（保留上一块 ID），
  空块删除但至少留一块；composing 有效直接 return；
- 结构命令（本轮实现+单测，M3 接 UI）：`turnInto(kind, level)`、
  `setBackground(1..13)/clearBackground()`、`insertPlainText(String)`（粘贴）、
  `moveFocusUp/Down()`（先按 offset 0/末尾判断，TextPainter 首末行判定留待打磨）；
- 撤销：结构操作前压 JSON 快照（SySerializer.encodeJson），50 步，
  暴露 `canUndo/canRedo/undo/redo`；字符级撤销用 TextField 内建；
- `ValueListenable<bool> dirty`：任何改动置脏并更新 block/doc 的 updatedAt。

DayEditorPage 负责编排：打开日（findDay 为空则模板实例化空草稿）、
持有控制器、5s 防抖调 `upsertDraft`、`WidgetsBindingObserver` 进后台/
页面 pop 时立即 flush。持久化目标只依赖 DiaryRepository，M5 零改编辑器。

### 层级与导航

- DiaryPage 内嵌一个 `Navigator`（root route `/` 年列表），路由：
  `/`、`/year/:y`、`/year/:y/month/:m`、`/day/:y/:m/:d`；
  自定义右滑入+淡入 240ms 深色 PageRoute（不用 Cupertino 手势返回，
  避免与外层横向导航轨抢手势）；
- `PopScope` 把 Android 返回键接到嵌套 Navigator.pop；
- 年/月行：右侧 chevron；月行显示有草稿天数；日列表枚举整月每一天，
  有草稿显示首行预览，无草稿日弱化显示，点按即进编辑器（首次按键才落盘）；
  当年有「今天」快捷入口置顶；
- 编辑器头显示日期大标题（dayTitle），正文为 BlockEditorView；
  locked/readonly 块 TextField readOnly（M5 导出锁定直接生效）。

### 装配

在 SmartNavScreenState 的 Scope 链（ChatStoreScope/NavBadgeScope 旁）加：
应用级 `SyIdGenerator` 单例 + `DiaryRepositoryScope`（内存实现含种子：
今天/昨天/上月各一篇示例）。`nav_destination.dart` 中 `'notes'`
改为 `DiaryPage()`，删除该页 TemplatePage 分支（console/me 不变）。

## Implementation Steps（依赖序）

1. `data/`：DiaryDocState/DiaryDaySummary/DiaryRepository 接口 + 内存实现
   （种子工厂、空日 findDay 返回 null、upsert 后列表立即可见）+ 单测；
2. `template/`：DiaryTemplate 接口 + BlankDiaryTemplate + 单测（标题/空段落/ID）；
3. `editor/block_editor_controller.dart`：BlockState、attach/detach、
   delta 拆块/合并/删块、focus 跳转、turnInto/底色/粘贴、撤销栈、dirty；
4. `editor/block_widget.dart` + `block_editor_view.dart`：块标 48dp、
   选中态视觉、TextField 样式（段落/标题字号走 MechanicalStyle 常量、
   底色用编辑期临时色板映射，导出仍写 CSS 变量）、懒加载 ListView；
5. `ui/`：diary_shell + 年/月/日三个列表页 + DiaryPage 嵌套 Navigator/PopScope；
6. DayEditorPage：模板实例化、防抖保存、后台 flush、只读/锁定透传；
7. 装配 Scope、切换 nav_destination notes 分支；
8. 种子数据走 kDebugMode 常量隔离（release 空仓）。

## Validation

- `flutter analyze` 零 issue；`flutter test` 全量绿（现有 38 个不回归）；
- 新增控制器单测（对应上游 T01–T05/T08–T09）：
  分块 ID 与聚焦语义、合并保留上块 ID、至少一块、组词中不拆、
  ↑↓ 跳焦、含换行粘贴拆多块、只读/锁定 no-op、撤销恢复、
  H1–H3/底色经 SySerializer 往返逐字符一致；
- Widget 测试：年→月→日→编辑器下钻与返回、输入后返回日列表预览更新、
  200 块文档 pump 无异常且末端分块可用；
- 真机（echo-deviceverify 流程，MIX 2S 竖屏）：国产输入法回车分块、
  组词中回车只上屏、键盘弹收焦点、横滑离开笔记页再回来内容保留、
  杀进程行为符合「内存仓 M2 不持久」预期并在汇报中说明。

## Risks

- **软键盘回车差异**：delta 主通道 + 组词保护，真机必验；若个别 IME
  连 delta 都不按规范给，退化为 onKey + value 双保险（已预留两个入口）。
- **M2 存储为内存实现**：符合计划「依赖 M5 才引入」的纪律，但杀进程丢稿。
  自动保存/崩溃恢复机制本轮全部建好，M5 只换仓储实现；若你希望本轮就
  文件落盘，可把 path_provider 提前引入（一处接口实现的工作量），请在
  审批时定夺。
- **M1 解码丢弃子集外块**：本轮只编辑 Echo 自产文档；打开含
  skippedTypes 的文档时编辑器顶部出「含暂不支持块」横幅（只读提醒缝），
  不静默编辑。
- **200 块焦点性能**：ListView.builder 懒构建 + BlockState 按需创建；
  真机帧率不达标再做 controller 池化，不提前优化。
- 分支建议：从当前 `feat/notes-page` 拉 `feat/diary-m2-editor` 开发，
  不 push、不合并，验收后再议。
