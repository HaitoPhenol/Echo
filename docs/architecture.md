# Echo 架构与接口说明

> 本文档记录 Echo 的目录结构、核心设计原则、预留接口与扩展方法。
> 新增或改动功能时，先阅读本文档，确保改动落在正确的位置，
> 保持项目可维护、不混乱。
>
> 其他文档：[工程规范](engineering_standards.md)（原则 / 门禁 / 事故档案）·
> [规则演进机制](governance.md) · [现状快照](current_state.md) ·
> [术语表](glossary.md) · [问题清单](code_review_report.md) ·
> [根目录工作提示](../AGENT.md)

---

## 1. 设计原则

1. **配置驱动**：页面、快捷操作等「有哪些」的信息集中在配置文件里描述，
   界面从配置读取，不在各处硬编码。新增一项内容 = 加一条配置，不改框架。
2. **接口与实现分离**：面向抽象（抽象类）编程。例如搜索历史存储只依赖
   `SearchHistoryStore` 接口，当前是内存实现，以后换持久化实现时界面零改动。
3. **单一事实来源**：每类信息只有一个来源（如页面信息只来自
   `NavDestination` 列表），避免多个地方各写一份导致不一致。
4. **行为必须有反馈**：未实现的功能走统一的「开发中」占位提示，
   不允许出现「按了没反应」的死按钮。
5. **界面与逻辑分层**：`services/` 放可复用的能力（搜索、触感），
   `navigation/` 放导航相关组件与配置，`pages/` 放页面本体。

---

## 2. 目录结构

```
echo/
├── lib/
│   ├── main.dart                          # 入口，挂载 EchoApp
│   └── src/
│       ├── app/
│       │   └── echo_app.dart              # MaterialApp、主题装配
│       ├── theme/
│       │   ├── app_colors.dart            # 全局调色板（tone 四阶 + 机能风 mech 色组）
│       │   └── mechanical_style.dart      # 机能风几何/排印/时长常量（颜色在 AppColors）
│       ├── pages/
│       │   ├── chat_page.dart             # 聊天页（数据驱动会话列表：左滑操作/未读绿点）
│       │   ├── template_page.dart         # 模板页（大标题 + SEC kicker，可挂 footer）
│       │   └── debug_badge_controls.dart  # 锚点通知/异常的测试按钮（脚手架）
│       ├── services/                      # 与界面无关的能力层
│       │   ├── chat_store.dart            # 聊天会话数据：增删/已读未读 + 未读聚合
│       │   ├── haptics.dart               # 触感反馈统一入口
│       │   ├── nav_badge_service.dart     # 导航锚点状态：通知/异常接口
│       │   └── search_service.dart        # 搜索服务/数据源/历史接口
│       └── navigation/                    # 智能导航线
│           ├── nav_destination.dart       # ★ 导航目的地配置（页面）
│           ├── quick_action.dart          # ★ 快捷操作配置（全局快捷弧）
│           ├── page_action.dart           # ★ 本页操作配置（把手竖单）
│           ├── dock_geometry.dart         # 底部三条几何单一事实来源
│           ├── nav_physics.dart           # 滚动/吸附物理引擎
│           ├── smart_nav_screen.dart      # 主屏：手势识别 + 组装
│           └── widgets/
│               ├── mechanical_background.dart  # 机能风固定背景（网格/点阵/十字）
│               ├── mechanical_coords_bar.dart  # 顶部设备状态读数条
│               ├── mechanical_page_number.dart # 每页空心大页码 01-04
│               ├── mechanical_page_drum.dart   # 3D 页码转鼓指示器
│               ├── mechanical_page_name_plate.dart # 横滑时左下浮现的衬线页名牌（赛博故障入场）
│               ├── quick_action_arc.dart  # 快捷操作弧
│               ├── search_capsule.dart    # 导航条 + 翻页圆点 + 搜索面板
│               ├── fuse_border_painter.dart # 倒计时边框
│               ├── handle_bar.dart        # 把手条（常态小条）
│               ├── handle_menu.dart       # 本页操作竖单（生长动画）
│               ├── ai_bar.dart            # AI 条（虹彩流动 + 光晕）
│               ├── ai_dialog.dart         # AI 对话框（聊天面板）
│               └── side_drawer.dart       # 侧边抽屉（毛玻璃空壳）
├── test/
│   ├── widget_test.dart                   # 导航/浮层 Widget 集成测试（11 个用例）
│   ├── navigation/
│   │   └── dock_geometry_test.dart        # 快捷弧布局纯函数测试（6 个用例）
│   └── pages/
│       └── chat_page_test.dart            # 会话列表交互测试（7 个用例）
└── README.md                              # Flutter 默认工程说明
docs/
├── architecture.md                        # 本文档：架构与接口
├── engineering_standards.md               # 工程原则、交付门禁、事故档案
├── current_state.md                       # 当前实现现状快照（会随版本更新）
├── code_review_report.md                  # 已知问题清单与修复路线
├── glossary.md                            # 组件命名称呼表
├── governance.md                         # 规则演进机制（RCR 流程、级别、复审）
├── maintainer-charter.md                 # AI 维护者常设职责（审查/问题登记/文档维护）
├── proposals/                            # 规则变更提案与登记册（永不删除）
│   ├── README.md
│   └── 2026-10-09-mechanical-visual-tokens.md # RCR-2026-001 机能风视觉层
├── templates/
│   └── rule-proposal.md                  # RCR 提案模板
└── component-reports/                     # 组件阶段开发总结（归档，只增不改）
    └── smart-nav-line-v0.4.10-2026-10-06.md
ideas/
├── smart_line.html                        # 原型：导航线设计与手感基准
├── another_two_lines.html                 # 原型：把手条 / AI 条 / 抽屉基准
└── mechanical_style_page.html             # 原型：机能风页面背景与转鼓（稿号 Lxx 出处）
AGENT.md                                   # 给开发 agent 的工作提示（入口）
```

> 各文档的阅读时机见 [AGENT.md](../AGENT.md) 的文档地图。

带 ★ 的两个文件是日常扩展最常修改的地方。

---

## 3. 核心接口

### 3.1 导航目的地 `NavDestination`

文件：`lib/src/navigation/nav_destination.dart`

描述导航线上可到达的一页，是页面信息的唯一来源：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `String` | 程序内稳定标识，代码引用页面时用它，不依赖排列顺序 |
| `label` | `String` | 页面名称（页名标签、搜索结果用） |
| `icon` | `IconData?` | 页面图标；`null` 时搜索结果等位置显示数字序号 |
| `pageBuilder` | `WidgetBuilder` | 页面本体构建器，按需构建 |

默认配置由 `buildDefaultDestinations()` 构建，当前为 4 页：
终端（console）、聊天（chat）、笔记（notes）、主页（me）。
其中**聊天页已替换为真实页面** `ChatPage`（`pages/chat_page.dart`，
会话数据来自 `ChatStore`，见 3.10）：无标题栏；列表初始为空，
空态整屏居中显示 13px 小字「暂无消息」（tone2），有会话时切换为
铺满轨道的 ListView。会话行高 72px——每行含 48px 圆形头像占位框
（tone1 空心圆描边）、昵称（tone4 16px）与消息预览（tone2 14px，
均单行省略），行间分隔线为屏宽 80%、水平居中的 1px tone1 细线，
内边距避让状态栏与底部悬浮停靠条。行交互：

- **未读绿点**：未读会话行右上角显示 8px 呼吸绿点（anchorGreen，
  1.7s 缓动往返 + 同色发光，参数与导航锚点 `_NavAnchor` 完全一致）；
  点按未读行即标记已读、绿点消失（已读行点按无行为）。
- **左滑操作区**：行内向左拖动露出右侧操作按钮（恒为两个、每个宽
  76px，总宽不随读状态变化）——左为读状态切换（已读行显示「未读」、
  未读行显示「已读」，tone2 底/inverse 字），右为「删除」
  （anchorRed 底/tone4 字，移除该会话）。
  拖动按速度（>300/s）或半程吸附开合（180ms easeOut），同屏全局
  只展开一行（展开另一行先收回），竖向滚动列表时自动收回。
  操作按钮常驻树中、由不透明行前景物理遮挡（与锚点/滑块同思路）。

其余三页仍是 TemplatePage。

### 3.2 快捷操作 `QuickAction`

文件：`lib/src/navigation/quick_action.dart`

描述上甩快捷弧上的一个操作：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `String` | 稳定标识 |
| `icon` | `IconData` | 弧上图标 |
| `label` | `String` | 操作名称 |
| `onSelect` | `void Function(BuildContext)` | 松手选中时执行的行为 |

默认配置由 `buildDefaultQuickActions()` 构建，当前为三个「开发中」占位项。

### 3.3 搜索体系

文件：`lib/src/services/search_service.dart`

- **`SearchResult`**：一条搜索结果（`title` 标题、`subtitle` 来源分类、
  `icon` 图标、`onSelect` 点击行为）。
- **`SearchProvider`**（抽象接口）：一类搜索数据源，实现
  `List<SearchResult> search(String query)`。
- **`NavDestinationSearchProvider`**：已实现的「页面搜索」数据源，
  在页面名称中匹配，点击结果直接跳转。
- **`SearchService`**：聚合入口，持有全部 provider 与历史存储，
  `searchAll(query)` 跨数据源汇总结果。
- **`SearchHistoryStore`**（抽象接口）：历史存储，含
  `items` / `add()` / `remove()`。
- **`InMemorySearchHistoryStore`**：当前实现，内存保存、重启清空。
- **返回键拦截**：任一浮层（搜索态 open/input、快捷弧、本页操作竖单、
  AI 对话框、侧边抽屉）存在时，系统返回键由 `SmartNavScreen` 的
  `PopScope` 拦截——先关最上层浮层（搜索走 `_exitSearch()`、快捷弧
  `dismiss(fire: false)`、竖单/对话框走各自的 `dismiss()`、抽屉反向
  吸附），不退出 App；全部皆无时默认行为不变。搜索态翻转通过控制器
  监听触发根树重建，使 PopScope 的 canPop 在 fuse 自动关闭等路径下
  也保持同步。

### 3.4 触感反馈 `Haptics`

文件：`lib/src/services/haptics.dart`

- `Haptics.tick()`：轻微短震——翻页、快捷项切换；
- `Haptics.confirm()`：确认震——展开搜索、快捷操作触发。

Android 端走原生 `Vibrator` 服务（通道 `echo/haptics`，见
`android/app/src/main/kotlin/.../MainActivity.kt`），不受系统
「触感反馈」开关限制；iOS 走系统触感生成器。

### 3.5 导航物理 `NavPhysicsController`

文件：`lib/src/navigation/nav_physics.dart`

持有页面位置 `position`（线性物理位置）、速度、搜索状态
（`off/open/input`）、倒计时进度 `fuseProgress`、转鼓/页名牌可见性。
继承 `ChangeNotifier`，组件通过 `AnimatedBuilder` 监听刷新。

渲染一律使用 `displayPosition`（橡胶带 + 页内磁力曲线）：靠近整页
粘滞、两页之间滑落，整数位置严格不变；物理层始终保持线性，两层分离。
物理参数（fling 衰减、snap 弹簧、越界橡胶带、速度增益、磁力曲线）
均为已验收取值，非必要不调整。页面数量变化时需重新评估增益范围。

程序化翻页接口：`stepPage(delta)` 供两端翻页圆点调用（-1 / +1），
边界页不动；调用期间以 `_muteActivePageCallback` 静音激活页回调，
触感由调用方负责，避免一次点击双震。

### 3.6 几何与热区规则

常规态组件几何不在运行时用 GlobalKey 测量（冷启动首帧负载高时
GlobalKey 重挂载曾触发框架断言），而是由 `DockGeometry`（底部三条
全部尺寸/间距，见 3.9）与 `SearchCapsule` 的静态常量配合
`MediaQuery` 推算（见 `smart_nav_screen.dart` 的 `_navGeometry()` /
`_searchCapsuleRect()`），视觉与命中共用同一事实来源：

- **尺寸**：圆点直径 = 导航条高度 = 10；导航条与圆点间距 = 5
  （一个半径）；常规态整体宽 = 半屏宽（两端加圆点后导航条相应
  缩短，总长度不变）；圆点默认色 = 导航条色（tone1），按下翻页时
  提亮到 tone2（白 α.42）；**滑块按下无外观变化**（按压变色方案
  多次被否，见规范事故 14）。
- **纵向热区**：导航条与圆点共用，向上 32、向下 10。
- **横向热区**：导航条 = 自身长度（不扩展）；圆点 = 自身直径的
  2 倍（以圆点为中心），圆点优先判定。
- **拇指滑块**：宽度 = 导航条长度 / 页面数——除当前位置外也大致
  反映总页数；双击直达的 `_pageAtX()` 遵循同一宽度规则。
- **快捷弧**：按钮沿四分之一椭圆弧（半轴 116×184，起点切向竖直、
  末端切向水平，拟合用户真实手指轨迹）**弧长等距**排布，整体居中
  在弧长中点附近（`DockGeometry.layoutQuickArc`，纯函数、按操作
  数量自动布局）；热区半径随数量自适应——`(相邻圆心距−10)/2`，
  相邻热区及按钮↔热区边缘间隙均 ≥ 10；数量过多时热区缩小，下限
  = 按钮半径（热区不小于按钮本身）。手指不在任何热区内时选中项
  为 -1（无高亮），松手不触发、直接收起（可反悔）。
- **搜索态点外部关闭**：由铺在底层的全屏隐形 scrim 处理，
  不再需要包围整簇的 GlobalKey。

### 3.7 导航锚点 `NavBadgeService`

文件：`lib/src/services/nav_badge_service.dart`

导航条内每一页有一个锚点短条，其状态由此服务管理。这是预留的
**通知接口**：任何模块（消息、某业务模块的异常等）只依赖抽象接口，不关心 UI。

- **`NavBadgeLevel`**：`normal`（白色静止）/ `notification`
  （绿色呼吸，1.7s 缓动往返）/ `exception`（红色急闪，0.62s 往返）。
- **`NavBadgeService`**（抽象，继承 `ChangeNotifier`）：

  | 方法 | 含义 |
  |---|---|
  | `levelOf(page)` | 读取某页当前锚点状态 |
  | `postNotification(page)` | 置为通知态（绿色呼吸） |
  | `reportException(page)` | 置为异常态（红色急闪） |
  | `markViewed(page)` | 仅 `notification → normal`：默认在该页连续停留 700ms 才已读；聊天页例外（见下） |
  | `resolveException(page)` | 仅 `exception → normal`：显式处理完成才恢复 |

  异常优先级高于通知：异常未处理时查看页面不会改变状态。
- **已读判定：停留而非经过**。`SmartNavScreen` 以独立监听器观察
  `NavPhysicsController`：激活页每次变化都取消旧计时并重新启动
  `Timer(_readDwell = 700ms)`，只有连续停留满 700ms 才调
  `markViewed(page)`。快速扫过（按住圆点连续翻页）、双击导航条
  直达末页时途经的中转页不会被标为已读。
- **聊天页例外：锚点由会话未读数据驱动**。聊天页锚点不走停留计时
  （激活到该页时不启动 700ms 计时器），而由装配层监听 `ChatStore`
  的 `_syncChatBadge()` 同步：存在任意未读会话即
  `postNotification`，**聊天页内所有会话都已读时**才 `markViewed`
  恢复默认；左滑「设为未读」会重新点亮锚点。异常态优先级不变。
- **帧时钟**：导航物理不使用墙钟（`Stopwatch`），而以物理帧的
  `currentFrameTimeStamp` 为时间源（在 tick 回调内缓存）。真机上与
  真实时间一致；测试中随 `pump` 推进，停留/倒计时逻辑可确定性验证。
  搜索倒计时边框的烧蚀基准同样惰性记录于展开后的首个物理帧，避免
  帧外的过期时间戳（首帧前为 0）导致倒计时瞬间烧完。
- **`InMemoryNavBadgeService`**：当前实现，内存保存每页状态，
  变化时 `notifyListeners()`。
- **`NavBadgeScope`**（`InheritedNotifier`）：向子树提供服务，
  锚点通过 `NavBadgeScope.of(context)` 获取并随通知自动重建；
  `SmartNavScreen` 创建实例并包在最外层。
- 锚点渲染在 `search_capsule.dart` 的 `_NavAnchor`：竖短条 + 同色
  发光，光晕由导航条外层裁剪，不超出条外。动画期间以 `AnimatedBuilder`
  逐帧重建（无逐帧重建会导致光效冻结）。
- **锚点始终全部挂载、画在滑块下层，不做位置显隐**：当前页段被不透明
  滑块物理遮挡，拖动时从滑块边缘自然滑入滑出；常态色与滑块视觉一致
  （白 α.42 叠 tone1 ≈ 滑块灰），离开滑块时无色差（见规范事故 12/13）。
- `pages/debug_badge_controls.dart` 为测试脚手架，三个按钮全部挂在
  终端页：「模拟：聊天新消息」（调 `ChatStore.addIncoming()`，
  不直接操作锚点）、「模拟：异常」（终端页锚点进入红闪）、「处理异常」
  （无异常时禁用并显示「当前无待处理异常」）；笔记页不挂任何调试按钮。
  终端页下标由 `buildDefaultDestinations()` 按稳定 id
  （`indexWhere((d) => d.id == 'console')`）解析后经构造参数传入，
  脚手架内不写死页序。接入真实通知/异常源后此脚手架应移除。
  脚手架由 `kDebugMode` 守卫：仅 debug 构建挂入页面，release/profile
  构建 footer 为 null、组件随树摇移除，不会出现在发布包中。

### 3.8 颜色体系：中性亮度四阶阶梯

文件：`lib/src/theme/app_colors.dart`

界面上的白色元素统一为 `tone1`～`tone4`（白 α0.16 / 0.42 / 0.72 /
1.00），四个锚定元素分别对号：**导航条 = tone1、圆点按下 / 锚点常态 =
tone2、快捷弧选中按钮 = tone4**；**拇指滑块是特例**：使用不透明灰
`_thumbFill`（0xFF838383），亮度等同「tone1 底 + tone2 滑块」的合成
结果（白量 ≈.513），之所以不用半透明 tone2，是因为滑块要不透明地物理
遮挡下层锚点（见规范事故 12/13）。其余元素就近取阶：

- **tone1**：圆点默认、搜索胶囊/历史胶囊/弧按钮描边、搜索结果行底；
- **tone2**：圆点按下、锚点常态本体、静态光晕、历史胶囊文字、未选中图标/次级文字；
- **tone3**：次级按钮文字；
- **tone4**：主文字、快捷弧选中项本体。

另有两类**并列**颜色，不并入阶梯：

- **深色表面层**：`background` / `rollerBackground` / `searchBackground`
  / `overlaySurface`（本页操作竖单、AI 对话框、SnackBar）/
  `drawerSurface`（侧边抽屉，另叠 18px 毛玻璃）；
- **功能强调色**：`accentBlue`、`anchorGreen`、`anchorRed`——仅表达
  状态语义（搜索、通知、异常）。
- **AI 虹彩色**：AI 条流动六色是该组件的专属识别色，不属于中性阶梯
  也不进共享色板，就地定义在 `widgets/ai_bar.dart`。
- **机能风视觉层色组**（`mech*` 前缀，RCR-2026-001 收编）：
  固定背景、三层纹理/点阵、读数条、空心大页码、kicker、3D 转鼓、
  页名牌共用的 13 个皮肤 token（`mechBackground` / `mechFineGrid`(α.05) /
  `mechCoarseGrid`(α.10) / `mechGridDot`(α.22) / `mechCoordsDim/Hi` /
  `mechPageNumberStroke` / `mechInk`(#D8D8D8) / `mechInkDim`(#646464) /
  `mechDrumPanel` / `mechDrumLine` / `mechDrumNumber` /
  `mechDrumProgressTrack`），与四阶阶梯并列、互不混用，详见 3.11。
- SnackBar 不走 M3 默认反色浅底：`EchoApp` 主题统一为
  `overlaySurface` 底 + 白字、贴底固定（`snackBarTheme`）。

取色规则：新增元素先判断是否状态语义（用功能色），否则按视觉亮度
就近取阶，不自造白透明度；机能风视觉层元素（背景纹理/读数条/
转鼓等）取 `mech*` 色组，不向 tone 阶归并。动画中的连续 alpha
（锚点呼吸/急闪）允许跨阶插值。

### 3.9 底部三条、本页操作与侧边抽屉

原型：`ideas/another_two_lines.html`。屏幕底部同一水平线等高地排列
**把手条 / AI 条 / 导航条整体**（导航条含两端圆点，整体右对齐、宽
半屏）。全部几何收在 `dock_geometry.dart` 的 `DockGeometry`，
`SearchCapsule` 与 `SmartNavScreen` 都从这里取数：

| 量 | 公式（w = 屏宽） |
|---|---|
| 统一间距 / 底边距 / 条高 | 14 / 16 / 10（`dotGap` = 5） |
| 把手条 | 左边距 14，宽 12vw |
| AI 条 | 左边距 `14 + 把手宽 + 14`，宽 `38vw - 56`（恰好填满中段） |
| 导航条整体 | 宽 `w/2`、右边距 14；条本体 = 整体宽 − 两端圆点与间距 |
| 竖单按钮直径 | `(把手宽 - 12).clamp(32, 42)`；边缘留白 = `(把手宽 − 按钮直径)/2`（横纵同值，端弧与端按钮**同心圆**）；竖单高 = 3 按钮 + 间距 10×2 + 上下留白 |
| 抽屉 | 宽 `min(78vw, 340)`；打开时把手停靠在 `抽屉宽 + 14` |

手势全部在 `SmartNavScreen` 的根指针路由中按热区分发（
`_handleRootPointerDown` / 把手 / AI 两组 move/up）：

- **点按把手条** → 挂载 `HandleMenu`：由 10px 小条用 340ms
  Cubic(0.3,1.2,.4,1) 向上生长成胶囊，三个圆形按钮白圆底 + inverse
  图标错峰弹入；生长/收回期间 `IgnorePointer` 拦截（注意该节点必须
  在逐帧重建的 builder 内部，status 翻转才会生效），完全展开后按钮
  才接受点击；触发操作后在按钮位置播放涟漪并自动收起。竖单挂载的
  同一帧常态把手隐藏，收回卸载同帧回归（与导航条/pill 交接同规则）。
- **右拖把手条** → 跟手拉出 `SideDrawer`：横向位移 >6px 且占优时
  锁定横拖，抽屉进度 0↔1 直接跟手；松手按进度/速度吸附开合
  （跟手不经过控制器；吸附时长开启 420ms、关闭 100ms，关闭非常干脆），
  把手条同步滑动到抽屉右缘外侧的停靠位。抽屉面板
  右圆角 22、18px 毛玻璃 + `drawerSurface`，**当前是空壳**：面板
  内容留空、`IgnorePointer` 不接事件；遮罩黑 α.44，点遮罩/返回键
  关闭。
- **AI 条**：`AiBar` 是 7s 匀速循环的虹彩六色流动条（条外上下各
  溢 4px 同色模糊光晕）。流动只平移着色器起点、条体矩形固定不动；
  按压态整体 brightness ×1.3、光晕 α .55→.95，**把手条按压无外观
  变化**（沿用滑块的既定结论）。手势：移动 >8px 取消、长按 450ms
  呼出 `AiDialog`；单击无行为。
- **AI 对话框**：22 圆角浮层（left/right 14、bottom 38+安全区），
  入场 320ms；自管 FocusNode/TextEditingController，挂载后下一帧
  自动聚焦唤起输入法。**当前消息区为空、发送按钮恒禁用、提交无
  行为**——只做到可打字；收起时先 unfocus 再反向播放（返回键先收
  键盘再关对话框是系统层顺序，无需自己处理）。
- **互斥**：竖单、AI 对话框、抽屉、搜索态、快捷弧任一存在时，
  其余手势被遮罩/阻断标志拦截；`_dismissPeerOverlays()` 保证同屏
  只有一个浮层。

**本页操作配置 `PageAction`**（`page_action.dart`）：字段
`id / icon / label / onSelect(BuildContext)`，与 `QuickAction`
同构但语义是「作用于当前页」（今后可按页返回不同列表）；
`buildDefaultPageActions()` 当前为刷新 / 分享 / 置顶三个占位，
`onSelect` 统一弹「「X」功能开发中」SnackBar（1s，先清旧条）。

Stack 分层在 `SmartNavScreen.build`（机能风层见 3.11）：
固定背景（MechanicalBackground）→ 顶部读数条 → 横向页面轨道
（轨道内每页一层空心大页码、页面本体透明） → 搜索 scrim → 快捷弧 →
涟漪 → 3D 页码转鼓 → AI 条 → 把手条 → 搜索胶囊
→（条件）抽屉 + 停靠把手 →（条件）竖单 scrim + 竖单
→（条件）AI scrim + 对话框；所有条件插入节点带稳定 `ValueKey`，
逐帧层只动 transform/opacity，背景/虹彩/抽屉/竖单各自
`RepaintBoundary` 隔离。

### 3.10 聊天会话服务 `ChatStore`

文件：`lib/src/services/chat_store.dart`

聊天列表的数据层，页面只依赖本服务读写会话，不直接操作导航锚点
（页面层不反向依赖 navigation 层）：

- **`ChatConversation`**：不可变值对象，字段 `id`（稳定标识，
  列表 key 与定向更新都以它为准、不用下标）、`nickname`、`preview`、
  `unread`；状态变更走 `copyWith({bool? unread})`。
- **`ChatStore extends ChangeNotifier`**：构造即空列表
  （页面展示「暂无消息」空态），会话只能经 `addIncoming()` 产生。方法：

  | 方法 | 含义 |
  |---|---|
  | `conversations` | 当前会话（新消息在最前），unmodifiable 视图 |
  | `hasUnread` | 是否存在任意未读会话（锚点联动的聚合依据） |
  | `addIncoming()` | 列表最前插入一条未读会话（id `incoming-N`） |
  | `remove(id)` | 删除指定会话 |
  | `markRead(id)` / `markUnread(id)` | 置已读 / 置未读 |

  当前为内存实现、重启清空；接入消息模块时替换实现（或持久化），
  `ChatPage` 无需改动。
- **`ChatStoreScope`**（`InheritedNotifier<ChatStore>`）：
  `ChatStoreScope.of(context)` / `.maybeOf(context)`；由
  `SmartNavScreen` 创建实例并包在 `NavBadgeScope` 外层。
- **锚点桥接**：`SmartNavScreen` 在 initState 中以
  `indexWhere(id == 'chat')` 找到聊天页下标并 `addListener`
  （见 3.7 聊天页例外）；聊天页停留不启动 700ms 已读计时器。

### 3.11 机能风视觉层

原型：`ideas/mechanical_style_page.html`（稿标题「滚筒页码 ·
机能风」，注释中「稿 Lxx」为该文件行号）。经 RCR-2026-001
采纳为正式皮肤，由**固定层 / 页面层 / 指示器层**三部分组成；
颜色全部在 [AppColors] 的 `mech*` 色组（全量迁移表见提案第 3 节），
几何 / 排印 / 时长在 `theme/mechanical_style.dart` 的
`MechanicalStyle`。

- **固定背景** `MechanicalBackground`（widgets/mechanical_background.dart）：
  `mechBackground`(#0C0C0C) 底上叠三层纹理——细网格 32dp
  （1dp，白 α.05）、粗网格 128dp（1dp，白 α.10）、128dp 交点
  r=1 点阵（白 α.22）；三层相对屏左上整体右下偏移 16dp（负向起点
  循环保证铺满）。顶部一对十字标定：中心在「状态栏下沿 + 8dp 与
  frameInset 取大」高度、左右各 14dp 处，边长 22、1dp、与粗网格
  同色；无实体描边框、无底部十字。静态 `CustomPaint` 外包
  `RepaintBoundary`，`shouldRepaint` 仅随顶部边界变化，翻页动画
  不引发背景重绘；只画表皮、不接手势。
- **顶部读数条** `MechanicalCoordsBar`：状态栏下沿（coordsTop=0）
  居中，9sp、字距 3.6（.4em），文案 `DEV 型号 · T 电池温度 ·
  P 瞬时功耗`；数据来自原生 MethodChannel `echo/device_stats`
  （MainActivity.kt，零三方库零权限），5 秒轮询、异常降级显示
  「—」；`IgnorePointer` 不挡手势。
- **页面层**：`TemplatePage` 底色透明，内容为机能风 kicker +
  大标题——kicker（终端 SEC.01 // CONSOLE、笔记 SEC.03 // NOTES、
  主页 SEC.04 // ME；11sp w700、字距 3.85，`mechInk` / `mechInkDim`；
  中文页名改为「终端」「笔记」「主页」后，英文 kicker 仍保留
  CONSOLE / NOTES / ME）
  与 48sp w700、字距 5.76（.12em）大标题；Flutter 在末字后也
  追加一个字距，用 −字距/2 的 `Transform.translate` 做光学居中
  （真机像素校验三/二/单字标题墨水中心均为屏中 540）。
  横向轨道内每页另铺一个空心大页码 `MechanicalPageNumber`
  （120sp、1dp `mechPageNumberStroke` 描边、填充透明；top =
  5vh、right = 0.14w − 32dp），随页面一起横滑。聊天页行前景
  同样透明，左滑操作区改由 `CustomClipper` 按露出宽度裁剪遮挡。
- **3D 页码转鼓** `MechanicalPageDrum`（替代旧横向圆点胶囊，
  旧 NavRoller 已删除）：`Positioned(right: 14, bottom:
  52 + safeBottom)`，面板宽 176dp（视窗 148 + 左右内边距各 14；
  早期稿右侧带刻度列时为 206dp，刻度列删除后收窄给页名牌让位）。
  面板为 `mechDrumPanel`(#0F0F0F) + 1px `mechDrumLine`(#262626)
  方边框，左上 / 右下各一道 16px、2px 直角亮线（`mechInk`）；
  顶行只有 blip（6px 方块、1.2s steps(2) 闪烁）+ PAGE 标签
  （10sp、.3em、`mechInkDim`），原稿右上 NO.0N 装饰编号已删。
  主体是 148×96 视窗内 R=190 的圆柱（perspective 520）：贴 N 个
  56sp w700、字距 2.24 的数字牌片做 rotateY 旋转，透视平移走齐次
  w 侧；背面剔除（|world|≥90°）、远面先画近面后画；视窗左右为
  `mechDrumLine` 虚线竖边。底部 2px 进度条（轨道
  `mechDrumProgressTrack`、填充 `mechInk`）。显隐由
  rollerVisible 驱动，两个指示器统一走
  `MechanicalIndicatorLifecycle`：**仅横滑 dragStart 唤醒**
  （圆点点按 stepPage、双击 snapTo 直达不显示）；入场 fade 220ms
  +rise 340ms；**正常收回**（落位 650ms 定时器）播 340ms
  「水平百叶窗」故障退场——10 条横带按固定乱序错峰、每条两明两暗
  后熄灭，前段叠 3px 衰减横抖，单 ClipPath 合成不倍增转鼓重绘；
  **上甩切快捷弧 / 进入搜索态**（`rollerInstantHide`）为互斥瞬隐，
  不播退场。
- **左下页名牌** `MechanicalPageNamePlate`（稿 #pgname）：
  `Positioned(left: DockGeometry.sideMargin, bottom: 52 + safeBottom)`
  ——**左右边距与转鼓同源**（均 14dp，原稿 left:5vw 在 393dp 宽屏
  约 19.6dp 不与转鼓右边对齐，已改），**色块底边
  与转鼓面板底边对齐**（原稿 bottom:26px 未采用）。内容为 64sp
  w700、字距 5.12（.08em）的当前页名（带稿 0/2/12 柔和投影）+
  下方 56×3 的 `mechInk` 短横线，
  文字走系统 **serif 通用族**（`fontFamily: 'serif'`，不打包字体；
  Android 西文 NotoSerif、中文回退 NotoSerifCJK，Bold 面由引擎
  合成），即原型 `--serif` 栈的宋体效果；色块 panel α.90。
  **面板框仿转鼓但向右开口**（`_PlateFramePainter`）：1px
  `mechDrumLine` 细线左边通高、上边通宽、底边只画左半、右边不画
  （视作被右侧内容挡住的延续面板）；左上与左下两个实角各加 16px/2px
  `mechInk` 亮角标（参数同转鼓 `drumCorner*`，转鼓为左上/右下）。
  与转鼓共用同一 rollerVisible / 同一组时长曲线，同升同收；
  拖动跨过页中点时按 nearestPage 硬切页名；圆点/双击路径同样
  不显示。页名取自 `NavDestination.label`，3~4 字长名与转鼓的
  横向避让目前靠字数短，未做截断/缩放（已知留白项）。
  **赛博故障层**：单个 `AnimationController`（t=1 稳态，
  时长 `nameGlitchDuration` 620ms）驱动三水平切片
  （上 .0-.38 / 中 .32-.70 / 下 .64-1.0+12px，重叠防缝；下片
  底边外扩 12px 容纳下行笔画与投影）错时闪烁接通、整字幅度递减的数码抖动、
  `mechInkDim` 灰色重影副本（极简单色风）、确定性时间表的 1px
  白线横扫、下划线延迟展开（1.08 过冲）。
  触发只有两个边沿：**唤醒当帧播一次**；**可见期内 activePage
  硬切（成功翻页）立即从头重播**，连续跨页连击不断。首/末页边界
  回弹 activePage 不变不触发；收回时入场故障即时回稳态，由共有的
  MechanicalIndicatorLifecycle 接管「水平百叶窗」退场，
  上甩/搜索路径仍瞬隐。
- **保留项（验收时确认不动）**：粗网格 α 维持 .10（长列表灰色
  预览文案在粗线恰好穿字时略花、随滚动变化，整体可读）；kicker
  未打包真等宽字体（`fontFamily: monospace` 在 Flutter/Android
  不解析，要真等宽需引 Roboto Mono 等字体，包体/许可另议）。

---

## 4. 常见扩展操作

### 新增一个页面
在 `buildDefaultDestinations()` 列表中增加一个 `NavDestination`，
写好 `id / label / pageBuilder`（`icon` 可后补）。
导航线、转鼓、页名牌、页面搜索会自动纳入，无需改动其他代码。

### 把某个模板页替换为真实页面
把该 `NavDestination` 的 `pageBuilder` 从 `TemplatePage` 换成真实页面
组件（在 `lib/src/pages/` 下新建页面文件）。同时可补上 `icon`。

### 接入快捷操作的真实行为
修改 `buildDefaultQuickActions()` 中对应 `QuickAction` 的 `onSelect`，
替换掉「开发中」占位回调（如扫码、新建会话、语音助手）。

### 接入本页操作的真实行为 / 按页配置
修改 `buildDefaultPageActions()` 中对应 `PageAction` 的 `onSelect`；
要按页面给出不同操作时，把当前 State 持有的固定列表改为依据
当前页 index 构建（`PageAction` 语义即「作用于当前页」）。
竖单项数变化时同步检查 `DockGeometry.menuHeightFor` 的高度公式。

### 向侧边抽屉填充内容
`SideDrawer` 面板当前为空壳（内容 `IgnorePointer`）。填充时在面板
内放入真实内容节点、解除内容忽略，宽度与停靠位仍由 `DockGeometry`
决定，不要在组件内另写尺寸。

### 新增一类搜索数据源（联系人、文件等）
1. 新建一个类实现 `SearchProvider`；
2. 在 `SmartNavScreen` 创建 `SearchService` 时加入 `providers` 列表。
搜索界面无需改动，结果自动汇总。

### 让搜索历史持久化
新建一个类实现 `SearchHistoryStore`（如基于 shared_preferences 或数据库），
替换 `initState` 中的 `InMemorySearchHistoryStore()` 即可。

### 接入真实通知 / 异常源
取得 `NavBadgeService`（经 `NavBadgeScope.of(context)` 或由上层注入）：
消息到达时调 `postNotification(页索引)`，某模块发生异常时调
`reportException(页索引)`，异常处理流程完成时调 `resolveException(页索引)`。
「停留 700ms 即已读」与锚点动画无需接入方处理；**聊天页是数据驱动
例外**——接入真实消息模块时实现/替换 `ChatStore`（见 3.10），锚点
联动由 `SmartNavScreen` 的监听完成，不要直接 post 聊天页通知。
需要持久化时，新建一个 `NavBadgeService` 实现替换
`InMemoryNavBadgeService`，并移除 `debug_badge_controls.dart` 测试脚手架。

---

## 5. 开发规范索引

通用工程规范统一收在 [engineering_standards.md](engineering_standards.md)，
本文不再重复维护，改规范去那里改。索引：

- **版本与提交**（1.1）：SemVer 与只增不减的 versionCode、git tag、
  Conventional Commits、不主动提交；
- **文档一致、单一事实来源、依赖方向、视觉取色**（1.2~1.5）：
  含本文件第 1 节五条设计原则的通用表述；
- **动画交互**（1.6~1.10）：稳定 Key、形态解耦、几何事实来源、
  帧时钟/墙钟、消除逐帧重布局、多 Controller 与不可变状态比较、
  描边/阴影在裁剪层外、圆角显式夹取、物理遮挡而非显隐；
- **反馈与手感**（1.11~1.12）：无死按钮、非关键能力静默降级、
  真机验收六种手势；
- **命名、依赖审慎**（1.13~1.14）与**交付门禁、测试写法**（第 2 节）。

历史上踩过的坑统一登记在规范文件第 3 节事故档案（含症状→根因→原则），
本文件各处只引用编号、不重复叙述。

本文第 1 节的设计原则是上述规范在架构层面的投影；两处若有冲突，
以 engineering_standards.md 为准并修正本文。

### 架构层面必须记住的两条视觉事实

- 真实导航条与搜索 pill 是两个解耦组件：常规态只挂真实导航条，
  搜索开始的同一帧隐藏、挂载起始外观一致的 pill；收回反向播放后
  同帧卸载 pill、重新显示真实导航条（规范 1.7 / 事故 3）。
- 锚点常态与滑块视觉同色（白 α.42 叠 tone1 ≈ 不透明灰滑块），
  锚点常挂载、被滑块物理遮挡，拖动时"融入"滑块边缘滑入滑出
  （规范 1.10 / 事故 12、13）。
- 底部三条（把手 / AI / 导航）视觉分离但共用同一几何来源
  `DockGeometry`；把手与竖单、常态把手与抽屉停靠把手同样是
  「同帧交接、不做位移动画穿帮」的条件挂载，不要合并成常驻组件。
