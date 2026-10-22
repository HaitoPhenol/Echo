# Echo 当前实现现状

> 本文件是 **v0.13.0+38（main，tag `v0.13.0`，2026-10-15，
> ECP P1–P4 全部交付）时点的现状快照**，记录"今天代码实际是怎么实现的"。
> 这些不是规定——工具与手段可以换，
> 但更换时必须满足 [engineering_standards.md](engineering_standards.md)
> 的原则、通过测试与真机验收，并更新本文件。历史 patch 级变更叙述不进
> 本文件（查 git 历史与
> [archive/](archive/) 归档）。
>
> 相关：[架构与接口说明](architecture.md) ·
> [工程规范](engineering_standards.md) · [规则演进机制](governance.md) ·
> [术语表](glossary.md) · [问题清单](code_review_report.md) ·
> [日记模块技术方案](diary/flutter-tech-plan.md)

---

## 技术栈与工程

- **Flutter 3.47.6 / Dart ^3.13.5**；业务三方依赖：
  `archive`（.sy.zip 打包）、`sqflite`（日记 meta 库）、
  `path_provider`（沙盒目录）、`share_plus`（系统分享）；
  测试侧 `sqflite_common_ffi`。其余为 cupertino_icons / flutter_lints。
- 状态管理：**ChangeNotifier + InheritedNotifier**（规模够用，不引框架）。
- Android 原生侧主源集 `MainActivity.kt` 两个 MethodChannel：
  `echo/haptics`（直接驱动 Vibrator，带振幅降级，声明 VIBRATE 权限）、
  `echo/device_stats`（电池温度/瞬时功率/型号/版本/flavor，零权限粘性广播）。
  **debug 源集另有 ECP 三件套**（release 物理不打包，aapt2 已验证）：
  `DebugEchoApp`（Application，反射缓存当前引擎）、
  `DebugControlReceiver`（exported 广播接收器，goAsync 转
  `echo/control` MethodChannel）、debug Manifest（tools:replace
  application name + INTERNET 权限）。
- lint：flutter_lints 默认集；**无 CI**（门禁靠本地 `flutter analyze` +
  `flutter test` 自觉执行）。
- **发布配置**：release 用 debug 签名（独立 keystore 仍待定）；
  **已开 R8**（`isMinifyEnabled`/`isShrinkResources` + 保底
  `proguard-rules.pro`）；**已接全局崩溃钩子**（`runZonedGuarded` +
  `FlutterError.onError`，保留默认输出并 `debugPrint` 标记，无远端上报后端）。
  release 包人工裁剪检查已随 P3/P4 发布常态化（dex 字符串扫描 +
  slash 补全计数 + 全新装走查，见问题清单 G8）。

## 页面与导航

横向 4 页固定（`navigation/nav_destination.dart` 的
`buildDefaultDestinations()`，稳定 id）：

| 序 | id | 页名 | 实现 |
|---|---|---|---|
| 0 | console | **终端** | TemplatePage + debug 面板（3 按钮，仅 debug） |
| 1 | chat | **聊天** | 真实 `ChatPage`：会话列表、左滑操作、未读绿点 |
| 2 | notes | **笔记** | **真实日记模块**（见下节；2026-10-10 起替换纯模板页） |
| 3 | me | **主页** | TemplatePage |

- 主屏 `SmartNavScreen`（1353 行；2026-10-16 结构债务 A 项 G1 后：
  几何纯函数收敛至 `navigation/dock_layout.dart`，手势记录类/涟漪移出
  为独立文件，`build()` 子树抽为私有构建方法）一次性常驻构建全部页面
  （Row + Stack），
  **日记页 State 常驻**：进模块自动成稿、防抖 flush 等生命周期挂在该
  常驻 State 上——改懒加载前必须先迁移这些假设。
- 导航物理为自研 `NavPhysicsController`（position 线性物理 +
  displayPosition 橡胶带/Hermite 双层）；几何单一事实来源
  `DockGeometry`（静态常量+MediaQuery，不用 GlobalKey）。
- 底部三条：把手（竖单/右拖抽屉）、AI 虹彩条（长按弹空壳对话框）、
  导航条（横滑/圆点/双击/上甩快捷弧/长按搜索）。全部手势的坐标、
  死区、互斥与返回键顺序详见
  [usage-guide.md](usage-guide.md)（操作细节以该文件为准）。
- **把手竖单按页独立（2026-10-18）**：`buildPageActions(pageId, ...)`
  按当前页返回操作列表——**笔记页只放一个「今日日记」**（点按经
  `DiaryPageState.openTodayEditor` 把日记内层栈带到今日编辑页；已在
  今日编辑页则静默不重复压栈），其余页暂沿用 3 个占位项（刷新/分享/
  置顶，`buildDefaultPageActions`）。竖单高度/按钮圆心随条数自适应
  （`DockGeometry.menuHeightFor`、`DockLayout.pageMenuPositionsFor`），
  笔记页单项竖单比旧的 3 项固定高度明显缩短。
- 机能风视觉层（v0.6.0 转正，RCR-2026-001）：固定网格/点阵背景、
  顶部读数条、空心大页码、3D 转鼓、衬线页名牌；代码在
  `navigation/widgets/mechanical_*.dart`，token 在
  `theme/app_colors.dart` + `mechanical_style.dart`。
- 浮层（竖单/AI 对话框/抽屉/搜索/快捷弧）同屏至多一个，返回键统一拦截。
- debug 面板（模拟聊天新消息/模拟异常/处理异常）仅挂终端页，
  `kDebugMode` 守卫，release 树摇移除。

## 日记模块（笔记页，M1–M5 已交付）

模块文档：[diary/flutter-tech-plan.md](diary/flutter-tech-plan.md)；
思源格式：[diary/sy-format-golden-3.8.6.md](diary/sy-format-golden-3.8.6.md)。
代码在 `lib/src/diary/`：

| 子目录 | 职责 |
|---|---|
| `sy/` | 思源格式层：`DiaryDocument` 模型、确定性 ID 生成器、子集序列化器、.sy.zip 打包 |
| `data/` | `DiaryRepository` 抽象 + 内存实现 / **sqflite 持久实现**、`DiaryClock`（04:00 日界）、`DiaryDataProvider`（现为 Fake 常量）、debug 种子 |
| `template/` | 模板 JSON 解析、每日成稿 `DiaryComposer`（幂等/并发去重/custom-* 数据面填充） |
| `editor/` | 分块编辑器：命令、控制器（50 步撤销重做、`applyCustomPatch` 批量写文档根 custom-*、`moveBlockAt` 拖拽重排）、块视图（`CustomScrollView` + `SliverReorderableList`、`header` 可挂滚动区首项）、块左侧「类型图标 + 拖拽把手」纵向簇、块标浮层 |
| `export/` | 导出服务（月行增量导出 .sy.zip，`exportMonth`） |
| `ui/` | 年→月→日浏览页、日记编辑页、三态 UI、胶囊行（`diary_capsule_row.dart`，心情入口）、导出渠道弹窗与分享确认流 |

- **生产装配用持久仓储**（M5 起）：sqflite 库
  `<app_flutter>/echo_diary/diary.db`（diary_meta 单表：状态/时间戳/
  title/preview/block_count 反范式），正文
  `diary/{yyyy}/{mm}/{docId}.sy` 原子写（tmp+rename）。
- **三态**：`draft`（可写）/ `exported`（只读横幅）/ `archived`
  （删文件留 meta、列表弱化）。
- **层级列表排序与强调（2026-10-18）**：年/月列表均**倒序**（最新在上，
  仓储仍按升序返回、只在 UI 层反转）；行首亮度**只两档**（均取自亮度
  阶梯）——含今天的项（当前年行、当前月行，后者仅当所浏览年份即当前年
  时）与日页「今天」同档走主文字色（阶 4），其余年/月/日项（含已归档）
  走默认页名标签色（阶 3）；已归档不再另占行首色档，改由「已归档」徽标
  与降档的副文案/箭头标识（口径见 `ui/widgets/diary_list_row.dart`）。
  年行行首文案由「2026」补为「2026 年」，行首定宽列按最长行首取值并限
  单行，避免折行；行纵向内边距 14→5dp，行距由实测 ≈170 设备像素压到
  ≈120（行间分隔由背景网格承担，本行不画线）。
- **跨页大标题行盒统一（2026-10-18）**：`DiaryShell` 大标题挂固定高度
  `StrutStyle`（`MechanicalStyle.pageTitleLineHeight = 1.15` +
  `forceStrutHeight`），强制年/月/日/编辑四页标题行盒恒为
  48 × 1.15 ≈ 55.2dp——消除字体回退导致的差异（纯中文标题「日记」行盒
  50.4dp，含数字标题「2026 年」「10 月」被西文字体 descent 撑到 ≈55.2dp），
  使四页「标题→正文区上沿」距离一致（年页首行由 354 下移到 ≈370 设备
  像素，与月/日页对齐；月/日/编辑页位置不变）。**注意**：改动任一页标题
  的文案/字号/字体，都须复核四页首行纵向位置一致（曾因年页标题为纯中文
  而短一截 16 设备像素，2026-10-18 用户指出）。
- **开屏预进今日编辑页（2026-10-18）**：生产环境（`nav_destination.dart`
  按「无测试注入仓储」判定）给 `DiaryPage` 传 `preEnterToday: true`，内层
  路由栈首帧即「年列表 → 今日编辑页」两层（`onGenerateInitialRoutes`
  一次建好、无入场动画）。日记页随导航页面轨道**离屏常驻**，app 一启动就
  bootstrap，「今天」（04:00 日界）编辑页即在后台就位——用户横滑到笔记页
  直接落在今日日记，无需再点 年→月→日；返回仍回到年列表（栈形态与手动
  进入一致）。只在**进程首启**发生一次，从后台恢复不会重进（bootstrap 只跑
  一次）。测试默认 `preEnterToday: false`，保持从年列表开始的既有断言基线。
  **离屏预进的编辑页不自动跳焦**（`DayEditorPage.autoFocus: false`）：预进
  发生在笔记页仍离屏时，若照常 `requestFocus` 会主动请求 IME、让 app 一启动
  就凭空弹出软键盘（2026-10-19 用户报告并修复）；用户主动进入编辑器
  （年→月→日 / 今日日记快捷 / 补记 / ECP 跳转）仍照常跳焦，光标落在最新段
  正文行。
- **自动成稿**：进笔记页 bootstrap 时 `ensureDay(clock.today())`，
  日模板 `daily-default-v2` 为**概述段 + 空正文段双块骨架**（2026-10-18 日模板重设，
  旧六块骨架废弃）；补记入口在**把手条竖单**（笔记页常驻，2026-10-19
  自月页右上「+」迁来），日期选择器禁未来日。
- **时间戳段机制（2026-10-18；2026-10-19 增补空段不落盘/重打点）**：进
  **编辑页**时 `DiaryComposer.ensureStamp` 先确保「一句话概述今日」段（模板骨架
  首块，12 号底色、普通可编辑段落、恒在文档首位；块级属性
  `custom-echo-pinned='1'` 标志置顶，**不可拖动、其他块也不得排到其上方**；
  旧稿缺失时补建、缺标志时补写）存在，再取
  文档最后一个时间戳块，距其 `updatedAt` 不足 **30 分钟**则复用、否则新建一个
  只读时间戳胶囊（文本 `yyyy-MM-dd HH:mm`，块级属性 `custom-echo-stamp='1'`；无
  块标/无浮层/无 TextField，光标自动落到它的下一行；生成后经**空段清洗**后
  `upsertDraft` 落盘并聚焦）。无时间戳时插到**索引 1（概述段之后）**、已有则
  追加文档末尾并补一个空正文行；已导出（`locked`）不生成。**段 = 一个时间戳
  块 + 其后到下一个时间戳前的块**，语义等同思源**垂直超级块**。分组为
  **运行时派生的位置关系**（`DiaryStamp.edgesOf`），编辑器与导出共用同一套
  边界语义；不引入嵌套模型，`.sy` 落盘仍是扁平结构，导出层
  `SySerializer._rowSegments` 按需包 `row` 超级块。`isUserEmpty` 与列表预览
  `DiaryDaySummary.previewOf` 均跳过 stamp（列表预览不含时间戳）。
  **2026-10-19 增补**：① 落盘清洗 `DiaryComposer.prunedForPersist`——**最后
  一个**时间戳段内（该 stamp 之后、下一 stamp 之前）全空时，把该 stamp 连其
  段内空块一并剔除后再写 `.sy`（空段时间戳只在 UI 存在、下次进编辑页重新生成；
  已被清空的同理）；仅作用于最后一个时间戳，前文已保存段不受影响。② 编辑器
  待启用时间戳改为**按 stamp id 的集合**（`BlockEditorController.pendingStampIds`；
  `pendingStamp` 仍只回答最后一个）：挂载时**所有段内为空的 stamp** 都进入待
  启用，段由空转有内容的首字符落键时把该 stamp 重打点为**当前时间**，此后冻结、
  不再自动更新；内容再清空则复位、再次输入重新打点。删除末段时间戳时，其下
  正文并入上一段，上一段若原为空且待启用即在此刻重打点（2026-10-21 修复）。
  ③ 前端时间戳胶囊上方留 `top:12` 间距。④ 导出时每个
  `row` 超级块**之前**插一个顶层空 `NodeParagraph`（`_blankParagraph`），使
  思源里时间戳段与前文留一空行。
  **2026-10-21 增补**：① 段结构守卫 `_normalizeSegments`——挂载、删除、拖动、
  回车拆分、退格合并、撤销恢复后校验，每个时间戳后缺正文块即补一个空段落
  （只补正文、不凭空造 stamp；`locked` 文档不处理）。② 段框——`BlockWidget`
  按 `StampSegmentEdge` 逐块画左右边线，段首补顶边、段末补底边，段内块垂直
  间距归零，用 `AppColors.tone1` 1px 拼成连续淡框；首个时间戳之前的概述段
  不画框。③ 时间戳与超级块强相关——拖动**时间戳块**时整段（时间戳 + 其后
  到下一个时间戳前的正文块）一起搬移，拖动过程中段内正文由代理里的静态
  预览一起浮起（实块原位透明占位）；整段**只落在段边界**（某时间戳之前
  或文档末尾），落进其他段中间时按拖动方向吸附到该段之后/之前，`moveBlockAt`
  按 `onReorderItem` 的单块下标反算整段落点；正文块仍按单块自由移动
  （可拖入其他段，原段缺正文自动补空行）；删除时间戳只删自身，其下正文
  并入上一段。
- **块类型图标与拖拽重排（2026-10-19）**：块卡左侧改为**「类型图标 +
  拖拽把手」纵向簇**（图标 18dp 宽、把手 24dp 宽，正文相应右移 18dp）：
  类型图标按当前块种类取形（段落 `notes`，H1–H3 `looks_one/two/3`，回读
  H4–H6 退化为 `title`），选中取强调蓝、常态取机能暗灰，与把手同簇同色。
  **簇在纵向按正文首行对齐**（2026-10-22）：块高随行数增长时块标不再落到
  段落中部，偏移按首行行盒中心算（`_handleTopFor`），单行块与居中外观一致；
  拖拽代理里的静态预览同口径，时间戳胶囊单行仍居中。
  把手外包 `ReorderableDelayedDragStartListener`（长按 `kLongPressTimeout`
  起拖，`enabled: !readOnly`），宿主由 `ListView.builder` 换成
  `CustomScrollView` + `SliverReorderableList`，`onReorderItem`（该 SDK
  已弃用 `onReorder`；其回调已替调用方扣除移除偏移）直连
  `BlockEditorController.moveBlockAt`——生效先压一次撤销快照再搬移，
  块对象（ID / 文本控制器 / 焦点节点）整体随位移动不重建，越界收敛到
  `[0, len-1]`，锁定/未变时 no-op。两处必要收口：①`BlockEditorScope` 由
  `InheritedNotifier` 改继承 `InheritedTheme`（拖拽代理经
  `InheritedTheme.capture` 摘进 Overlay 重挂，非 InheritedTheme 不会被
  捕获）；②纯 sliver 版无默认 `proxyDecorator`，需自带一层透明 `Material`
  （块内 `TextField` 断言需 Material 祖先）并叠轻微抬升阴影。时间戳块仍
  只读（无 `TextField`），但自 2026-10-21 起与正文块一样有块标与类型图标、
  可拖动换位，块标菜单仅提供删除；拖动时间戳时整段随之搬移（见上条 ③）。
  `locked`（已导出）文档整篇不可拖。
- **自动数据与心情（2026-10-18 重设）**：温度/湿度/天气/日程与心情写
  文档根 `custom-*`——`composer.fetchCustomPatch(date)` 三源并发取数
  （单源失败不连坐、null 删键），`controller.applyCustomPatch(patch)`
  批量落盘；编辑页以滚动区首项**胶囊行** `DiaryCapsuleRow` 呈现
  （温度→湿度→天气→日程→心情，`Wrap` 换行分散对齐、缺值显 `—`，
  点数据胶囊重拉三源、点心情胶囊弹五档 sheet）。**data 只读块概念整体
  退役**：`SyIdGenerator.dataBlock/dataRoleOf/isDataBlockId`、
  `DiaryBlock.readonly`、`BlockState.isData`/`replaceDataSnapshot`、
  `DiaryDataProvider.isSampleData`、`DiaryMoodChip` 均已删。
- **正文区贴边（2026-10-18 紧凑化）**：`DiaryShell` 去掉标题下 20dp 留白，
  并把头部→标题间距 12→2、标题上移量 -13→-3（两处等量相抵，标题**绘制
  位不变**，只让布局盒下移 10dp）；编辑页另去列表顶部 8dp 内边距 →
  正文区上沿由 ≈420 设备像素上移至 ≈338。底部取消停靠条避让高度，
  正文区下沿**直达屏幕底部**，停靠条按浮层压在其上（`DiaryShell.
  dockReservedHeight` 已删，口径同 ChatPage 列表内边距）。
- **尾部可达留白（2026-10-22）**：正文内容超出视口时，`BlockEditorView`
  在列表尾部补约 1/3 视口高的可滚动留白，滚到底把最后一块抬到屏幕
  下三分之一处（不被底部导航栏压住，便于聚焦操作）；内容装得下时
  留白自动撤除，短文档仍不可空滚。
- **04:00 日界**：`DiaryClock.diaryDate`，hour<4 归前一自然日；
  测试注入时钟，生产取墙钟。
- **空稿清理**：进模块 prune 早于今天的空草稿（meta+.sy 双删）。
- **导出**（2026-10-18 起改为**按月**）：入口在**月列表每行右侧**
  （年列表不再有年导出）；点击后先由 `showModalBottomSheet` 选渠道
  （`DiaryExportChannel.share|save`，关闭弹窗不导出），打包该月 draft
  成一个 zip 后分流：
  - **分享**：share_plus 调系统分享 → 返回后人工「确认已发送」才把该月
    draft 批量置 exported，否认保留草稿可再次导出；
  - **另存**（2026-10-22）：走自建 `echo/files` 通道 + Android
    `ACTION_CREATE_DOCUMENT`（SAF，每次自选目录与文件名、零存储权限，
    Kotlin 侧后台线程把临时 zip 拷到目标 Uri），保存成功即直接迁移
    exported，取消（`userDenied`）则保留草稿。
  `exportMonth` 返回的 `DiaryExportOutcome.channel` 决定 UI 完成/中止文案。
  Android 思源不响应 ACTION_SEND，实际走思源内 SAF 导入。该月所有笔记都
  无未导出（`isMonthFullyExported`）时，导出按钮左侧显「已导出」徽标
  （与日行同款 `DiaryStateBadge`）。
- **导出编码 vs 扁平编码（双链路，2026-10-18）**：**落盘/撤销/导入回读**仍走
  **扁平编码** `SySerializer.encodeJson` / `encodeBytes`（不含超级块与行内
  标记；本轮新增携带**块级** `custom-*`，时间戳标志随草稿往返）；**导出**走
  `encodeExportBytes(doc, ids)`，仅在导出时叠加 ① 文档**首行水平超级块**
  （`Data:'col'`，含 5 个带 `code` 行内标记的胶囊段落，只输出有值槽位）+
  ② 每个「段」一个**垂直超级块**（`Data:'row'`，首块为带 `code` 标记的时间戳
  段落）。`SyZipExporter` 构造增可选 `SyIdGenerator? idGenerator`，
  `DiaryExportService` 传 `repository.idGenerator`（导出的超级块/合成段 ID
  与仓储同源）。胶囊槽位键收口于新增纯 Dart `sy/diary_capsule_items.dart`
  （5 键 + `buildDiaryCapsuleItems`）；共享胶囊组件
  `editor/diary_capsule_chip.dart`（自 `ui/widgets/diary_capsule_row.dart` 的
  私有 `_Capsule` 提取）。控制器守卫：正文首行退格不并入时间戳、段内唯一正文
  行不被删、↑/↓ 纵向移动跳过 stamp、`turnInto`/`setBackground` 对 stamp no-op。
- **每月导出提醒**：存在早于**本月 1 日**的未导出草稿（`oldestDraftBefore`）
  时，笔记页导航锚点走 **exception（红闪）**，且每次冷启动**首次**
  切到笔记页由 `DiaryPageState.maybeShowExportReminder()` 弹一次对话框
  （「去导出」直接压入最早待导出月份的月列表）；漏月持续提醒，直到
  `markExported` 把全部已结束月份的草稿迁出后由数据驱动自动解除
  （`_syncExportReminder` 监听仓储变更重算，`markViewed` 对 exception
  无效，只有真正导出才清）。
- debug 包空库灌种子两篇（上月 28 日 + 昨天，今天不种）；
  release 空仓。测试可注入仓储/时钟。

## ECP 控制面（P1–P4 已全部交付，v0.13.0）

设计 [ecp/ecp-design.md](ecp/ecp-design.md)、命令契约手册
[ecp/ecp-commands.md](ecp/ecp-commands.md)；代码在 `lib/src/control/`。
四期施工/复审流水归档于 [archive/ecp-p1-p4-review-log.md](archive/ecp-p1-p4-review-log.md)。

- **协议**：信封（ok/cmd/ms/result|error/nonce，P4 起 slow 命令首包
  可带 `async/jobId`）、错误码→进程退出码映射、`CommandSpec` 冻结
  动词表、`ControlBus`（注册重名检查、参数解析、级别/确认裁决、
  ≥2 级审计、slow 60s 预算标记）。
- **鉴权**：PIN 只存 PBKDF2 加盐哈希（`echo_control/pin.json`）；
  通道起始级别 mcp=0/adb=2、slash=2，adb/slash 解锁升 3 级，
  mcp 永不解锁（上限 1 只读）；连续 5 次错误冷却
  （30/60/120/240s/5min 退避）；App paused（息屏/切后台）立即
  销毁全部会话；审计不记 PIN 与正文（正文命令标 auditRedact，
  记 `<redacted:N>`）。
- **命令域（40 条；release 物理裁掉 5 条 debugOnly 后 35 条）**：
  sys 9（ping/help/info/status/audit/events/job.get +
  debugOnly clock.set/delay）、auth 4、nav 2、diary 12
  （list/get/ensure/goto/prune/export/state.set/block.set/document.set/
  custom.set + debugOnly reset/seed）、
  chat 6（list/get/open/send/mark-read + debugOnly seed）、
  console 2、badge 5。
- **笔记页控制（P5，`feat/ecp-diary-control` 分支，待合入排号）**：
  `diary.goto` 驱动笔记页内层路由栈（年/月/日/编辑页，给 `--date` 直达
  该日编辑页；先把顶层导航 snap 到 notes）——经 `DiaryNavigatorController`
  纯 Dart 接口收口，命令层不触达 Widget；`diary.export --date` 增日粒度
  打包；`diary.state.set` 在 draft↔exported 间迁移（exported→draft 即
  **恢复导出状态**，仓储新增 `restoreDraft`）；内容写入
  `diary.block.set`/`diary.document.set`/`diary.custom.set`（JSON 补丁，
  `--json` 标 auditRedact、仅 draft 可写）。受控动词表新增
  `block.set/document.set/custom.set/state.set`。
- **slash 指令台（P3）**：搜索栏 `/` 进入，三段补全（命名空间→
  动词→参数）、结果卡片、PIN/确认卡、命令历史；核心
  `control/slash/ControlConsoleCore` 与入口 Widget 解耦，终端页
  是未来第二个消费者（接缝未建页）。
- **事件流（P4）**：`events/` 内存环（256、seq 单调）+
  `sys.events` 游标/长轮询（wait≤8s，事件即唤醒）；五种冻结
  事件 audit.entry/command.finished（owner 级）、
  diary.export.completed（user 级）、chat.incoming（owner 级）、
  nav.changed（guest 级）；services 层零 control 反向依赖，
  ChatStore 自有 incoming Stream 经 `ControlEventBridge` 适配转发。
- **作业化执行（P4，根治接收器 9s 预算）**：slow 命令仅 adb 通道
  立即回 async running，后台跑（`jobs/` 环 32、跨通道隔离），
  `sys.job.get` 轮询终态；轮询走普通广播，**Kotlin 零改动**；
  slash 通道行为不变（进程内直等终态）。
- **同路装配**：`ControlBootstrap.init()` 在 main() 内 await
  （建 echo_control 目录、注册常驻服务）；导航屏注册
  NavPhysicsController，日记页 bootstrap 注册与 UI 同源的
  clock/仓储/composer/导出服务；未注册时命令回 CONFLICT。
- **工作站入口**：`scripts/echo-cmd <命令>`（冷启动轮询 ping、
  kebab→camel 参数、stdin 收 PIN 不进历史、退出码对齐手册；
  P4 起 slow 命令默认自动轮询终态最长 65s，`--no-wait` 只取
  running）。脚本级回归 `scripts/tests/echo_cmd_test.sh`
  （fake-adb，15 断言，无需设备）。
- **门禁**：`test/control/` 协议/鉴权/四域/slash/事件/作业/播种/
  MCP 假通道边界 + manifest↔手册双向一致性；MIX 2S 每期真机
  验收（P4：delay 12s 首包 11ms、导出落盘、事件提前唤醒、
  seed→prune/seed→send 端到端、slash 回归），release dex 六串
  全 0、补全计数 sys7/diary5/chat5。

## 状态与服务

- `ChatStore`（services/，ChangeNotifier + Scope）：内存会话列表，
  新消息/删除/已读/未读，`hasUnread` 聚合；重启清空。聊天锚点数据
  驱动（全部会话已读才恢复），其余页停留 700ms 已读。
- `InMemoryNavBadgeService`：锚点三态（正常/通知/异常），**按目的地
  稳定 id（`NavDestination.id`）索引**（2026-10-16 结构债务 A 项 G5
  已替换原页序 int 索引，为持久化铺路；未知 id 读返 normal、写忽略）。
- `SearchService`：多 Provider 聚合搜索；当前仅"页面搜索"一个源，
  同步接口；历史为内存实现。
- 日记仓储单例在 `DiaryPage` bootstrap 打开（debug 自动成稿+种子），
  测试/装配可注入。

## 平台与适配

- 主验证设备：Android 真机（MIX 2S，1080×2160/440dpi，MIUI）；
  **形态裁定（Q2，2026-10-16）：手机锁竖屏、平板不锁方向**。
  锁向已落地（`MainActivity.onCreate` 按 `smallestScreenWidthDp≥600`
  区分 `requestedOrientation`：手机 PORTRAIT、平板 UNSPECIFIED；MIX 2S
  真机取证 `mCurrentAppOrientation=SCREEN_ORIENTATION_PORTRAIT`）；平板/折叠
  横屏与大屏 UI 适配暂不做——当前无 LayoutBuilder/断点/宽度钳制，大屏上是
  "被拉宽的竖版"，不承诺体验。
- 文案仅中文硬编码，无 l10n；**无障碍已做最小集 Semantics**（底栏导航条
  label/value + `onIncrease/onDecrease` 翻页动作，两端圆点/把手/AI/快捷弧/
  会话行及左滑两按钮加按钮语义，机能风五个纯装饰层 `ExcludeSemantics`；
  圆点/把手/AI/快捷弧的激活动作留待后续按需接线）。
- Impeller 注记：MIX 2S + Flutter 3.47.6 横向滚筒非当前槽位首帧偶发
  白屏，息屏亮屏重建 surface 恢复，与业务代码无关。

## 测试现状

- **499 个 Dart 测试，47 个文件** + echo-cmd 脚本级回归 15 断言：
  - `test/widget_test.dart`（导航/浮层集成）、
    `navigation/`（几何纯函数）、`pages/`（聊天交互）、
    `services/`（触感通道异常降级等）；
  - `test/diary/`：sy 格式层金标准、ID、序列化往返、zip 打包、
    时钟边界、内存/持久仓储、成稿器、编辑器命令/控制器、
    导出服务、年日月浏览 widget、M5 三态/分享流/崩溃恢复；
  - `test/control/`：总线注册/解析/审计脱敏与**过鉴权后
    失败/超时入审计（E3）**、鉴权矩阵
    （通道×级别/退避/前后台即焚/PinStore 规则）、七域命令、
    slash 解析/补全/控制台核心、事件环/长轮询/五事件集成、
    作业轮询/跨通道隔离、播种端到端、MCP 假通道只读边界、
    manifest↔命令手册双向一致性；
  - 另有 testDebug JVM 单测 3 条（接收器 0/2000 uid 白名单，E1）。
- 动画用例逐帧 pump、不用 pumpAndSettle（常驻循环动画）；
  持久仓储测试用 FFI 工厂 + 临时目录。
- 真机回归：M1 格式包思源 3.8.6 导入通过；M2–M5 每个里程碑
  MIX 2S 真机验收（见 tech-plan 里程碑表）；ECP P1–P4 每期
  debug+release 双包真机终审（见
  [archive/ecp-p1-p4-review-log.md](archive/ecp-p1-p4-review-log.md)）。
- 待补：M6 ≥2 台真机连写 7 天。

## 已知问题与待决策

见 [code_review_report.md](code_review_report.md)：日记线 D1–D8
（真实数据源、空稿标注回归、Slash 菜单、mood 桥接等）、
通用工程 G1–G13、待拍板 Q3/Q4/Q5/Q6/Q8（Q2 设备形态已决）。

**本文件的维护规则**：实现手段变化并合并后，立即更新对应条目并在提交
信息中说明；问题修复后从问题清单移除，不要让本文件描述已经不存在的现状。
