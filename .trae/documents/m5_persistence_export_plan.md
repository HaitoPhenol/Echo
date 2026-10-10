# M5 实施计划：持久化 / 状态机 / 增量导出 / 崩溃恢复 / mood

> 对应 [flutter-tech-plan.md](../../docs/diary/flutter-tech-plan.md) §6 与里程碑表 M5 行。
> 本计划经用户裁定后执行；**不写工期排期**。

## 0. 用户裁定（2026-10-11，已确认）

1. **T10 已从 M5 验收中删除**（用户已改 tech-plan，M5 不再补 T10）。
2. **mood 做最小编辑入口**：编辑器内五档表情选择器，写 `custom-mood`，随导出进入思源属性视图。不做 sleep、不做心情统计。
3. **导出入口在年列表**：每个年行 trailing 放导出按钮，打包**该年全部 `draft`**；笔记本名固定「日记」（思源侧长期汇聚成同一本，容器确定性 ID 保证重复导入幂等）；分享成功返回后该批置 `exported`，再次导出不再包含。
4. **崩溃恢复口径**：保存防抖 5s → **1.5s**；保留进后台（paused/hidden/inactive）立即 flush。真机验收按「输入 → Home → 划掉最近任务 → 冷启」走，要求零丢失；不按 Home 直接 `am force-stop` 的硬杀场景接受 ≤1.5s 窗口损失（不做按键级写库）。

## 1. 仓库现状（调研结论）

- 仓储抽象 [diary_repository.dart](../../echo/lib/src/diary/data/diary_repository.dart)：`DiaryRepository extends ChangeNotifier`，已有 `DiaryDocState { draft, exported, archived }` 枚举、`DiaryDaySummary(date, preview, blockCount, state)`、findDay/upsertDraft/pruneEmptyBefore 等接口与 `DiaryRepositoryScope`。
- 唯一生产实现 [in_memory_diary_repository.dart](../../echo/lib/src/diary/data/in_memory_diary_repository.dart)：Map 以 `yyyyMMdd` 为 key；debug 装种子（上月一篇、昨天一篇），release 空；测试 `seedDebugData:false`；`idGenerator` 公开供 composer 使用；`_summaryOf` 取首个非 readonly 段落文本截 40 字，state 恒 draft。**M5 保留该实现**，全部现存 widget 测试继续走它。
- 编辑器页 [day_editor_page.dart](../../echo/lib/src/diary/ui/browser/day_editor_page.dart)：`_saveDebounce = 5s`；dirty 防抖 upsert；paused/hidden/inactive 与 pop 时 flush；`_readOnly = _document?.locked`，已有「已导出 · 只读」横幅位；`unsupportedBlockTypes` 横幅 M5 不动。
- 控制器 [block_editor_controller.dart](../../echo/lib/src/diary/editor/block_editor_controller.dart)：`attach(doc)` 后一直持有同一 `DiaryDocument` 引用，`snapshotDocument()` 同步块后直接返回它——**doc.custom 天然保留**，加 `setDocumentCustom` 改 map + `_markDirty()` 即可让 mood 走现有保存链路；`locked` 下文本/结构变更全部 no-op。
- 序列化器 [sy_serializer.dart](../../echo/lib/src/diary/sy/sy_serializer.dart)：`encodeBytes/decodeBytes` 已支持文档根 custom 往返；`decodeBytes` 回读 Echo 自产文件，readonly data 块由确定性 ID 在 `attach` 时恢复。
- 导出器 [sy_zip_exporter.dart](../../echo/lib/src/diary/sy/sy_zip_exporter.dart)：`SyZipExporter.build(notebookName, diaries, exportedAt)` 已按年→月→日分组、年/月容器确定性 ID 空文档、含 conf.json/sort.json。M5 只加「选 draft + 写临时 zip + 分享 + 状态迁移」服务层。
- 列表：[year_list_page.dart](../../echo/lib/src/diary/ui/browser/year_list_page.dart) 年行当前无 trailing；[DiaryListRow](../../echo/lib/src/diary/ui/widgets/diary_list_row.dart) **已支持 `trailing` 与 `dim`**；[day_list_page.dart](../../echo/lib/src/diary/ui/browser/day_list_page.dart) 日行 trailing 现为「N 块」。
- 装配 [diary_page.dart](../../echo/lib/src/diary/ui/diary_page.dart)：生产同步 new `InMemoryDiaryRepository`；测试缝 `{clock, dataProvider, repository}`。M5 生产初始化变为异步（开库 + 目录取路径），注入缝保留。
- 依赖现状 [pubspec.yaml](../../echo/pubspec.yaml)：仅 `archive`、`cupertino_icons`；版本 `0.8.0+33`（**任务分支不动**）。

## 2. 数据模型与存储设计

### 2.1 文件布局

- 根目录：`path_provider` `getApplicationDocumentsDirectory()` 下 `echo_diary/`。
- 正文：`echo_diary/diary/{yyyy}/{mm}/{docId}.sy`，UTF-8 编码，内容与导出器同一 SySerializer。
- 写入采用**临时文件 + rename 原子替换**（`*.sy.tmp` → `.sy`），防崩溃产生半截文件。
- meta 中 `file_path` 存相对路径 `diary/{yyyy}/{mm}/{id}.sy`（保留 tech-plan §6 schema 字段，路径本身确定性，列存在是为未来调整留口）。
- 导出 zip 写 `getTemporaryDirectory()` 下 `日记-{year}-{yyyyMMdd-HHmmss}.sy.zip`，分享 Future 返回后删除临时文件。

### 2.2 meta 表（schema version 1）

在 §6 最小字段上**扩展三个反范式列**（title/preview/block_count），月/年列表只读库不解析正文文件；偏差随封板文档记录：

```sql
CREATE TABLE diary_meta(
  id           TEXT PRIMARY KEY,          -- 22 位文档 ID（dayContainer(date) 确定性生成）
  date         INTEGER NOT NULL UNIQUE,   -- yyyyMMdd
  title        TEXT NOT NULL,
  state        TEXT NOT NULL DEFAULT 'draft',  -- draft | exported | archived
  preview      TEXT NOT NULL DEFAULT '',   -- upsert 时按 _summaryOf 同规则算
  block_count  INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL,          -- epoch ms
  updated_at   INTEGER NOT NULL,
  exported_at  INTEGER,                   -- 仅 exported/archived 有值
  file_path    TEXT                       -- archived 后置 NULL
);
```

- 开库走 `openDatabase(version:1, onCreate)`；预留 `onUpgrade`。
- 时间戳全部经注入的 `DiaryClock`，全模块仍禁止裸 `DateTime.now()`。

### 2.3 仓储接口扩展（抽象类 + 两个实现同步补齐）

在 `DiaryRepository` 增加：

- `Future<bool> dayExists(DateTime date)`：只查 meta（archived 也算存在）。
- `Future<DiaryDocState?> stateOfDay(DateTime date)`：无 meta 返回 null。
- `Future<List<DiaryDocument>> draftDocumentsOfYear(int year)`：state=draft，按日期升序。
- `Future<void> markExported(Iterable<DateTime> dates, {required DateTime exportedAt})`。
- `Future<void> archiveDay(DateTime date)`：仅 exported→archived，删 .sy、file_path 置 NULL、留 meta。

既有方法语义调整：

- `findDay`：archived（文件已删）返回 null；exported 返回的文档 `locked = true`。
- `upsertDraft`：仅 state 为 draft 或缺省行允许；对 exported/archived 日期调用抛 `StateError`（UI 只读不会触发，属防御）。
- `daysOfMonth`：preview/blockCount/state 全部来自 meta 反范式列，不再读正文。
- `draftCountOfMonth`：月行「N 篇」改为统计该月**全部 meta 行**（含 exported/archived，都是已成稿日记）。
- `pruneEmptyBefore`：**只清 state=draft**（exported/archived 永不被 prune）；持久实现 = 查候选 draft meta → 读文件跑 `isEmpty` → 删 meta + 删文件。
- 所有变更后 `notifyListeners()`，与现状一致。

### 2.4 PersistentDiaryRepository

新增 `lib/src/diary/data/persistent_diary_repository.dart`：

- 工厂：`static Future<PersistentDiaryRepository> open({required Directory root, SyIdGenerator? idGenerator, DiaryClock? clock, bool seedDebugData = false, DatabaseFactory? dbFactory})`。
- `dbFactory` 注入用于测试（`sqflite_common_ffi` 的 `databaseFactoryFfi`）；生产走默认 sqflite（Android/iOS 自带原生库）。
- debug 首建空库时种子逻辑与内存版一致——把现有种子构造抽成共享 helper（如 `DiarySeedData.build(idGenerator, clock)`），两个实现共用，防止漂移。release 不注入。
- `idGenerator` 仍公开，装配方式不变。

### 2.5 composer 防复活

`DiaryComposer.ensureDay` 顺序改为：`findDay` 命中直接返回；否则 `dayExists(date)` 为真（archived）→ 抛 `StateError`；否则才模板成稿。
`DayEditorPage._load` 在 ensureDay 前先查 `stateOfDay`：archived → 不挂编辑器，渲染「已归档」占位页（返回按钮 + 说明正文已从本机清理）。

## 3. 状态机

```
draft ──导出成功──▶ exported ──用户显式确认「已在思源导入」──▶ archived（终态）
```

- 仅允许上述两条迁移；反向迁移、draft→archived、archived→* 一律 `StateError`。
- **UI 文案映射**（对 §6 括注「exported 显『已归档』徽标」的细化，随本计划审批生效）：
  - `exported`：日行徽标/状态字「已导出」；编辑器横幅「已导出 · 只读」，禁编辑、禁 ↻ data 刷新。
  - `archived`：日行 `dim` 置灰、trailing 显「已归档」、点按不进编辑器（SnackBar 提示）。
  - 「归档」动词只出现在 exported 编辑器里的确认按钮上，语义不冲突。

## 4. 导出功能

### 4.1 DiaryExportService（新增 `lib/src/diary/export/`）

```
Future<DiaryExportOutcome> exportYear(int year)
// outcome: { exportedCount, sharedFile? }；草稿为 0 时不调分享
```

流程：`draftDocumentsOfYear(year)` → 空则直接返回（UI SnackBar「今年没有待导出的草稿」）→ `SyZipExporter.build(notebookName: '日记', diaries)` → 写临时 zip → `Share.shareXFiles([XFile(path, mimeType: 'application/zip')])` → Future 正常返回后 `markExported(...)` 并清理临时文件；分享抛异常则保留 draft 状态、不删临时文件并上抛错误。

- 分享完成只代表系统面板流程结束、不代表对方已收到——这是 share_plus 的平台语义，故状态名为 exported（已打包出 Echo），正文仍在本机只读；用户在思源确认导入后手动 archived。
- 分享通道用 typedef（如 `Future<void> Function(List<XFile>)`）注入，测试不碰平台通道；新增轻量 `DiaryExportServiceScope`（或并入 DiaryComposerScope 装配），`DiaryPage` 测试缝增加 `exportService` 参数。

### 4.2 UI

- 年列表每行 trailing：`IconButton(Icons.ios_share, 视觉密度 compact)`；点按跑 exportYear，期间按钮转圈禁用，结束 SnackBar 反馈「已分享 N 篇 · 标记为已导出」/「今年没有待导出的草稿」/失败文案。
- 日列表：state 徽标（见 §3）；「N 块」在 archived 时不显示。
- 导出后年/月/日列表经 ChangeNotifier 自动刷新。

## 5. 崩溃恢复 / 保存时机

- `_saveDebounce` 5s → **1.5s**。
- 保留 paused/hidden/inactive 立即 flush；pop flush 保留。
- 正文文件 tmp+rename 原子写（§2.1），meta upsert 走单条 SQL 事务，崩溃不会留下「文件有/meta 无」的半态：重开时 findDay 以 meta 为准；孤儿 .sy 可在开库时做一次自愈清理（同目录无 meta 的 .sy 删除），作为兜底。
- 明确不保证：前台运行中被 `am force-stop`/系统直接杀且无 paused 回调时，最后 ≤1.5s 防抖窗口内的输入可能丢失。

## 6. mood（最小入口）

- 新增 `BlockEditorController.setDocumentCustom(String key, String? value)`（null = 移除）+ 读 getter；改 `_doc.custom` 后 `_markDirty()`，随 1.5s/flush 既有链路落盘。
- 编辑器标题栏 trailing 最左侧放心情 chip（当前 emoji 或空心图标 + 极小字「心情」）；点击弹 bottom sheet，固定五档：`😄 🙂 😐 😕 😢` + 「清除心情」。五档为固定离散值，保证思源属性视图可按值聚合成图；不做自由文本/评分/sleep。
- 导出零额外工作：custom 已在 SySerializer 文档根属性中导出。
- 单测显式断言 `custom-mood` encode→decode 往返；真机/思源侧验证属性面板出现、属性视图按 mood 聚合。

## 7. 装配改动（DiaryPage）

- 生产初始化改为异步 bootstrap：`getApplicationDocumentsDirectory()` → `PersistentDiaryRepository.open(root, clock:, seedDebugData: kDebugMode)` → 建 composer → `ensureDay(today)` + `pruneEmptyBefore(today)` → `setState(ready)`；ready 前显示现有 loading 样式。
- 测试注入 `repository` 时跳过开库（现存全部 widget 测试零改动路径）。
- 任务分支 pubspec 保持 `0.8.0+33`。

## 8. 文件清单

**新增**

- `lib/src/diary/data/persistent_diary_repository.dart`
- `lib/src/diary/data/diary_seed_data.dart`（从内存版抽出共享种子）
- `lib/src/diary/export/diary_export_service.dart`
- `lib/src/diary/ui/widgets/diary_mood_picker.dart`（bottom sheet + chip）
- 对应 test 文件（见 §9）

**修改**

- `pubspec.yaml`：新增 `sqflite`、`path_provider`、`share_plus`、`path`（显式声明）；dev_deps 加 `sqflite_common_ffi`（版本以 `flutter pub add` 解析为准）
- `data/diary_repository.dart`：接口扩展 + 文档注释
- `data/in_memory_diary_repository.dart`：实现新接口（内存版状态机、种子改用共享 helper）
- `template/diary_composer.dart`：ensureDay 防复活
- `editor/block_editor_controller.dart`：setDocumentCustom
- `ui/diary_page.dart`：异步开库装配 + exportService 缝
- `ui/browser/year_list_page.dart`：年行导出按钮（由 StatelessWidget 改 Stateful 处理导出进行态，或抽小部件）
- `ui/browser/day_list_page.dart`：state 徽标、archived 置灰拦截
- `ui/browser/day_editor_page.dart`：防抖 1.5s、mood chip、archived 占位、exported 下禁 ↻、归档确认按钮+对话框
- `docs/diary/flutter-tech-plan.md`：封板时回填 M5 完成说明（含 schema 偏差、文案映射）

## 9. 实施步骤（依赖序）

1. 从最新 main 拉 `feat/diary-m5-persistence`（携带用户未提交的 M5 验收微调，先单独提交 `docs(diary): ...`）；`flutter pub add` 依赖；`flutter pub get`。
2. 抽 DiarySeedData；扩展 DiaryRepository 接口；InMemory 同步实现新方法（内存状态机），保证现有测试全绿。
3. PersistentDiaryRepository：schema/开库/原子文件读写/findDay/upsert/list/prune/状态迁移/archive/种子/孤儿文件自愈。
4. composer ensureDay 防复活；DiaryPage 异步装配（生产持久实现、注入缝不变）。
5. 编辑器：防抖 1.5s；mood chip + picker + setDocumentCustom。
6. DiaryExportService + 分享缝；年行导出按钮与反馈。
7. 状态 UI：日行 exported/archived 徽标与拦截；编辑器 exported 只读/禁 ↻ + 归档二次确认（删正文、pop 回列表）+ archived 占位页。
8. 测试补齐（§10）。
9. `/snap/bin/flutter analyze` 零 issue；`/snap/bin/flutter test` 全量绿。
10. MIX 2S 真机 + 思源验收（§11）。
11. 回填 tech-plan M5 行，按 Conventional Commits 语义分提交。
12. **停下等用户显式授权**后才做：ff-only 合 main → `chore(release): 0.9.0+34` → 推 main/分支 → 推远程 tag `v0.9.0`。

## 10. 测试方案

**持久仓储单测（sqflite_common_ffi + 临时目录）**

- 同一目录开两个 repository 实例模拟重启：upsert（含 data 块、custom、mood、底色）→ 新实例 findDay 逐字段一致；data 块重开后 readonly 恢复。
- 列表反范式列：preview/block_count/state 正确；年月聚合含三种状态。
- prune：空 draft 跨「重启实例」被删（meta + 文件）；有字稿保留；exported/archived 不被 prune。
- 状态机：draft→exported（exported_at 落值）→archived（文件消失、meta 留、findDay null、daysOfMonth 仍见该日）；非法迁移与 exported 上 upsert 抛 StateError。
- draftDocumentsOfYear 只含 draft 且按日期升序；原子写：无 `.sy.tmp` 残留。

**导出服务单测（注入假 share + 临时目录）**

- 有 draft：假 share 捕获 XFile → zip 可被 archive 解包：含「日记/.siyuan/conf.json、sort.json」、年/月/日三级、正文 custom-mood 在 JSON 中；返回后仓储内相应日期为 exported。
- 无 draft：不调 share。
- 第二次导出该年为空（增量语义）。
- share 抛错：状态保持 draft、错误上抛。

**Widget 测试（继续注入 InMemory/假实现）**

- 年行导出按钮：成功 SnackBar + 状态刷新；空草稿年提示；进行中按钮禁用。
- 日列表：exported 显「已导出」，archived dim +「已归档」且点按不进编辑器。
- 编辑器：exported 文档只读横幅、↻ 不出现/不可点、归档二次确认后正文删除并返回列表；取消不删。
- mood：chip 打开选择器 → 选 🙂 → 等防抖/触发返回 flush 后仓储内文档 `custom['custom-mood'] == '🙂'`；清除生效。
- archived 日期经补记入口直达 DayEditorPage 时显示占位页、不重新成稿。
- 生命周期 paused 触发落盘（补一条用持久仓储/假仓储断言调用顺序的用例）。

**序列化**：custom-mood 显式 encode→decode 往返用例（若现有 custom 往返用例未覆盖 mood 键）。

## 11. 真机与思源验收（MIX 2S，3f6cc09b，debug 包）

走 echo-device-verify 流程，截图入 gitignored `artifacts/diary-m5/`：

1. **持久化**：冷启进模块自动成稿；写若干字、换底色、选 mood；杀任务冷启后内容/状态全在；年/月/日层级与徽标正确。
2. **崩溃恢复（裁定 4.A）**：
   - 输入后立刻 Home → 最近任务划掉 → 冷启 → 文字零丢失（主验收路径）；
   - 输入后等「已保存」→ `adb shell am force-stop com.everse.echo` → 冷启 → 文字在（验证真落盘）。
3. **跨天空草稿 prune 跨进程复验**：补记前天空稿 + 前天有字稿 → force-stop → **手动改系统日期到次日 ≥04:00**（unroot 机 adb 改不了时间，需在设置里操作）→ 冷启：空稿 meta/文件消失、有字稿保留、今天自动成稿；验完恢复自动网络时间。
4. **导出端到端**（tech-plan M5 验收项，金标准 §7 清单）：年行导出 → 系统分享；
   - 结构侧用 debug 包可读缓存：`adb shell run-as com.everse.echo` 取出临时 zip（或从分享目标落盘），主机解包核对四级路径、conf/sort、容器幂等 ID、custom-mood/weather/iot/schedule-count、底色变量；
   - 若设备已装思源 3.8.6：直接分享导入，核对文档树、属性面板全部 custom-*、**属性视图按 custom-mood 聚合成图**、年/月容器重复导入不产生重复文档；未安装则在验收时请示用户（安装 3.8.6 arm64 包或改为人工补验）。
5. **只读/归档**：导出后该日只读 + 徽标；归档确认后正文文件删除、日行置灰不可进；重启后 archived 索引仍在。
6. 旧疾规避：Impeller 非当前滚筒槽位白屏时用息屏/亮屏 223/224 恢复；若必须临时改导航初始页以便截图，**验收后还原且不提交**；`git diff` 终检不得含 manifest/导航 hack。

## 12. 风险与注意

- **share_plus 成功语义弱**：Future 完成 ≠ 已发送。用 exported/archived 两阶段化解，archived 删正文必须用户显式确认；不做「分享失败自动回滚」之外的状态推断。
- **硬杀无生命周期回调**：≤1.5s 窗口损失已与用户裁定，不做按键级写库。
- **FFI 测试环境**：Linux 主机需系统 libsqlite3（本机具备）；CI 若后续引入要装 `libsqlite3-0`/`libsqlite3-dev`。
- **原子性**：先写 tmp 再 rename + meta 单事务 + 开库孤儿文件自愈，避免半态。
- **误删正文**：archive 仅在 exported 态、且经二次确认对话框（明确文案「将删除本机正文，仅保留索引」）；archived 终态无恢复入口（zip 已在思源）。
- **不引入思源包回读链路**：M5 只读 Echo 自产 .sy，不打开通用导入回读（§7.1 撤销快照风险与此隔离）。
- **不夹带 M4 遗留小问题修复**（用户明确以后细调）。
- Flutter/Dart 命令固定 `/snap/bin/flutter`、`/snap/bin/dart`；网络/设备命令关沙箱执行。
