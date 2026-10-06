# Echo 架构与接口说明

> 本文档记录 Echo 的目录结构、核心设计原则、预留接口与扩展方法。
> 新增或改动功能时，先阅读本文档，确保改动落在正确的位置，
> 保持项目可维护、不混乱。

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
│       │   └── app_colors.dart            # 全局调色板
│       ├── pages/
│       │   ├── template_page.dart         # 空白占位页（只显示标题，可挂 footer）
│       │   └── debug_badge_controls.dart  # 锚点通知/异常的测试按钮（脚手架）
│       ├── services/                      # 与界面无关的能力层
│       │   ├── haptics.dart               # 触感反馈统一入口
│       │   ├── nav_badge_service.dart     # 导航锚点状态：通知/异常接口
│       │   └── search_service.dart        # 搜索服务/数据源/历史接口
│       └── navigation/                    # 智能导航线
│           ├── nav_destination.dart       # ★ 导航目的地配置（页面）
│           ├── quick_action.dart          # ★ 快捷操作配置
│           ├── nav_physics.dart           # 滚动/吸附物理引擎
│           ├── smart_nav_screen.dart      # 主屏：手势识别 + 组装
│           └── widgets/
│               ├── nav_roller.dart        # 滚筒指示器 + 页名标签
│               ├── quick_action_arc.dart  # 快捷操作弧
│               ├── search_capsule.dart    # 导航条 + 翻页圆点 + 搜索面板
│               └── fuse_border_painter.dart # 倒计时边框
├── test/
│   └── widget_test.dart                   # Widget 测试（当前 5 个用例）
└── README.md                              # Flutter 默认工程说明
docs/
├── architecture.md                        # 本文档
└── glossary.md                            # 组件命名称呼表
ideas/
└── smart_line.html                        # 原型：设计与手感基准
```

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
| `icon` | `IconData?` | 页面图标；`null` 时滚筒显示数字序号 |
| `pageBuilder` | `WidgetBuilder` | 页面本体构建器，按需构建 |

默认配置由 `buildDefaultDestinations()` 构建，当前为 4 页：
控制台（console）、聊天（chat）、日志（notes）、我（me）。

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
（`off/open/input`）、倒计时进度 `fuseProgress`、滚筒可见性。
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
GlobalKey 重挂载曾触发框架断言），而是由 `SearchCapsule` 的静态
常量与 `MediaQuery` 推算（见 `smart_nav_screen.dart` 的
`_navGeometry()` / `_searchCapsuleRect()`），视觉与命中共用同一
事实来源：

- **尺寸**：圆点直径 = 导航条高度 = 10；导航条与圆点间距 = 5
  （一个半径）；常规态整体宽 = 半屏宽（两端加圆点后导航条相应
  缩短，总长度不变）；圆点默认色 = 导航条色（tone1），按下色 =
  拇指滑块色（tone2）。
- **纵向热区**：导航条与圆点共用，向上 32、向下 10。
- **横向热区**：导航条 = 自身长度（不扩展）；圆点 = 自身直径的
  2 倍（以圆点为中心），圆点优先判定。
- **拇指滑块**：宽度 = 导航条长度 / 页面数——除当前位置外也大致
  反映总页数；双击直达的 `_pageAtX()` 遵循同一宽度规则。
- **快捷弧**：每个操作项热区 = 按钮直径的 2 倍；手指不在任何热区
  内时选中项为 -1（无高亮），松手不触发、直接收起（可反悔）。
- **搜索态点外部关闭**：由铺在底层的全屏隐形 scrim 处理，
  不再需要包围整簇的 GlobalKey。

### 3.7 导航锚点 `NavBadgeService`

文件：`lib/src/services/nav_badge_service.dart`

导航条内每一页有一个锚点短条，其状态由此服务管理。这是预留的
**通知接口**：任何模块（消息、日志监控等）只依赖抽象接口，不关心 UI。

- **`NavBadgeLevel`**：`normal`（白色静止）/ `notification`
  （绿色呼吸，1.7s 缓动往返）/ `exception`（红色急闪，0.62s 往返）。
- **`NavBadgeService`**（抽象，继承 `ChangeNotifier`）：

  | 方法 | 含义 |
  |---|---|
  | `levelOf(page)` | 读取某页当前锚点状态 |
  | `postNotification(page)` | 置为通知态（绿色呼吸） |
  | `reportException(page)` | 置为异常态（红色急闪） |
  | `markViewed(page)` | 仅 `notification → normal`：在该页连续停留 700ms 才已读 |
  | `resolveException(page)` | 仅 `exception → normal`：显式处理完成才恢复 |

  异常优先级高于通知：异常未处理时查看页面不会改变状态。
- **已读判定：停留而非经过**。`SmartNavScreen` 以独立监听器观察
  `NavPhysicsController`：激活页每次变化都取消旧计时并重新启动
  `Timer(_readDwell = 700ms)`，只有连续停留满 700ms 才调
  `markViewed(page)`。快速扫过（按住圆点连续翻页）、双击导航条
  直达末页时途经的中转页不会被标为已读。
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
- `pages/debug_badge_controls.dart` 为测试脚手架：控制台页可模拟
  「聊天新消息」「日志报错」，日志页有「处理异常」按钮。接入真实
  通知源后此脚手架应移除。

### 3.8 颜色体系：中性亮度四阶阶梯

文件：`lib/src/theme/app_colors.dart`

界面上的白色元素统一为 `tone1`～`tone4`（白 α0.16 / 0.42 / 0.72 /
1.00），四个锚定元素分别对号：**导航条 = tone1、拇指滑块 = tone2、
锚点 = tone3、快捷弧选中按钮 = tone4**。其余元素就近取阶：

- **tone1**：圆点默认、滚筒/搜索胶囊/历史胶囊/弧按钮描边、搜索结果行底；
- **tone2**：圆点按下、滑块、静态光晕、历史胶囊文字、未选中图标/次级文字；
- **tone3**：锚点本体、页名标签、次级按钮文字；
- **tone4**：主文字、滚筒选中页标、快捷弧选中项本体。

另有两类**并列**颜色，不并入阶梯：

- **深色表面层**：`background` / `rollerBackground` / `searchBackground`；
- **功能强调色**：`accentBlue`、`anchorGreen`、`anchorRed`——仅表达
  状态语义（搜索、通知、异常）。

取色规则：新增元素先判断是否状态语义（用功能色），否则按视觉亮度
就近取阶，不自造白透明度。动画中的连续 alpha（滚筒中央刻度脉冲、
锚点呼吸/急闪）允许跨阶插值。

---

## 4. 常见扩展操作

### 新增一个页面
在 `buildDefaultDestinations()` 列表中增加一个 `NavDestination`，
写好 `id / label / pageBuilder`（`icon` 可后补）。
导航线、滚筒、页面搜索会自动纳入，无需改动其他代码。

### 把某个模板页替换为真实页面
把该 `NavDestination` 的 `pageBuilder` 从 `TemplatePage` 换成真实页面
组件（在 `lib/src/pages/` 下新建页面文件）。同时可补上 `icon`。

### 接入快捷操作的真实行为
修改 `buildDefaultQuickActions()` 中对应 `QuickAction` 的 `onSelect`，
替换掉「开发中」占位回调（如扫码、新建会话、语音助手）。

### 新增一类搜索数据源（联系人、文件等）
1. 新建一个类实现 `SearchProvider`；
2. 在 `SmartNavScreen` 创建 `SearchService` 时加入 `providers` 列表。
搜索界面无需改动，结果自动汇总。

### 让搜索历史持久化
新建一个类实现 `SearchHistoryStore`（如基于 shared_preferences 或数据库），
替换 `initState` 中的 `InMemorySearchHistoryStore()` 即可。

### 接入真实通知 / 异常源
取得 `NavBadgeService`（经 `NavBadgeScope.of(context)` 或由上层注入）：
消息到达时调 `postNotification(页索引)`，日志监控捕获错误时调
`reportException(页索引)`，问题修复流程完成时调 `resolveException(页索引)`。
「停留 700ms 即已读」与锚点动画无需接入方处理。需要持久化时，新建一个
`NavBadgeService` 实现替换 `InMemoryNavBadgeService`，并移除
`debug_badge_controls.dart` 测试脚手架。

---

## 5. 开发规范

### 版本号（语义化版本 SemVer）

格式：`MAJOR.MINOR.PATCH+BUILD`，例如 `0.1.0+3`。

- `MAJOR`：正式发布前保持 `0`；
- `MINOR`：功能更新时 +1；
- `PATCH`：Bug 修复时 +1，MINOR 增加时清零；
- `+BUILD`：Android versionCode，**每次构建只增不减**，与版本名无关。

每个版本节点打 git 标签，如 `v0.1.0`。

### 提交信息（Conventional Commits）

使用前缀：`feat:` 新功能 · `fix:` 修复 · `refactor:` 重构 ·
`chore:` 杂项 · `docs:` 文档。标题简述，正文说明原因。

### 命名与文件

- 文件名 `snake_case.dart`，类名 `UpperCamelCase`；
- 非通用配置不放仓库根目录；
- 公共 API 写文档注释，说明「为什么」而不只是「做什么」；
- 提交前保证 `flutter analyze` 无问题、`flutter test` 通过。
