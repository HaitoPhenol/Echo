# Echo 组件命名称呼表

> 讨论界面时统一使用本表中的称呼，避免「那个东西」「下面那条」
> 之类的歧义。每个称呼同时记录了代码中的对应文件，方便定位。
>
> 其他文档：**[使用与操作指南（含手势坐标）](usage-guide.md)** ·
> [架构与接口说明](architecture.md) ·
> [工程规范](engineering_standards.md) · [现状快照](current_state.md) ·
> [问题清单](code_review_report.md) · [根目录工作提示](../AGENT.md)

---

## 一、导航组件

| 称呼 | 说明 | 代码位置 |
|---|---|---|
| **智能导航线 / 导航线** | 整套底部手势导航体系的总称 | `navigation/` |
| **导航条** | 屏幕右下角的圆角小条，导航线的主体；常规态视觉上仅 10px 高 | `widgets/search_capsule.dart` 的 `SearchCapsule`（本体为 `_navBar()`） |
| **翻页圆点 / 圆点** | 导航条左右两端各一个的小圆点（直径 = 导航条高度）；点一下向左/右翻一页，按下即触发并振动、由 tone1 提亮到 tone2 | `search_capsule.dart` 的 `_NavDot` |
| **拇指滑块** | 导航条内部的**不透明灰色**小块（0xFF838383，视觉亮度等同 tone1 底上叠 tone2），位置代表当前页、随手指移动；宽度 = 导航条长度 / 页面数，可大致反映总页数；**按下无外观变化** | `search_capsule.dart` 的 `_thumb()` |
| **导航锚点 / 锚点** | 导航条内部、每一页对应一个的竖直小短条（稍短于导航条高度）；始终挂载、画在滑块下层，常态为 tone2（白 α.42）且不发光，被不透明滑块物理遮挡；该页有通知时绿色呼吸、有异常时红色急闪；发光被裁剪在导航条内，不超出条外 | `search_capsule.dart` 的 `_anchors()` / `_NavAnchor`，状态来自 `services/nav_badge_service.dart` |
| **隐形触控区** | 导航条/圆点上方约 32px、下方约 10px 的不可见纵向热区，视觉不变但更好按中；横向热区不扩展：圆点热区 = 自身直径 2 倍、导航条热区 = 自身长度 | `smart_nav_screen.dart` 的 `_navGeometry()` / `_handleRootPointerDown()` |
| **页码转鼓 / 转鼓** | 横滑时在右下角浮现的机能风 3D 指示器（176dp 宽）：方边框面板内一条绕圆柱旋转的数字牌片序列，当前页牌片对齐视窗中心；顶行仅 blip + PAGE 标签（原稿 NO.0N 编号、右侧刻度列已精简删除），底部 2px 跟手进度条；替代旧横向圆点胶囊（NavRoller 已删）；**仅横滑唤醒**，圆点点按、双击直达不显示；正常收回播水平百叶窗故障退场（340ms），上甩/进搜索瞬隐 | `widgets/mechanical_page_drum.dart` 的 `MechanicalPageDrum` |
| **数字牌片** | 转鼓圆柱上每一页的一张大号数字片（两位页码 01～04），按页间距绕 R=190 圆柱做 rotateY，远面先画近面后画、背面剔除 | `mechanical_page_drum.dart` |
| **页名牌** | 横滑时在左下角与转鼓同时浮现的衬线页名：半透明色块内 64sp w700 宋体（系统 serif 族）页名 + 56×3 短横线；面板框仿转鼓但向右开口（左/上通线、底边半线、右边不画，左上/左下亮角标），色块底边与转鼓底边对齐；跨页中点硬切文字，与转鼓同显隐；叠加赛博故障动画（唤醒播一次、成功翻页重播、边界回弹不播），详见「赛博故障」 | `widgets/mechanical_page_name_plate.dart` 的 `MechanicalPageNamePlate` |
| **赛博故障（glitch）** | 页名牌的故障风动画层：文字切三条水平片错时闪烁接通、整字数码抖动、mechInkDim 灰色重影副本（极简单色风）、1px 白线横扫、下划线延迟展开；单控制器 620ms，t=1 稳态；唤醒边沿或可见期内 activePage 硬切时从头播，首/末页回弹不播；收回不走本层，由 MechanicalIndicatorLifecycle 播水平百叶窗退场 | `mechanical_page_name_plate.dart` 内 `_Glitch*`、`MechanicalStyle.nameGlitch*` |
| **退场百叶窗** | 页名牌与转鼓共用的故障风退场（`MechanicalIndicatorLifecycle`）：整体切 10 条横带按固定乱序错峰、每条两明两暗后熄灭，前段叠 3px 衰减横抖；总时长 340ms 与旧 fade/rise 相同，单 ClipPath 合成；上甩切快捷弧、进入搜索态走 `rollerInstantHide` 瞬隐不播 | `widgets/mechanical_indicator_lifecycle.dart`、`MechanicalStyle.indicatorExit*` |
| **磁力曲线 / 吸附曲线** | 拖动时的非线性位置映射：靠近整页粘滞、两页之间滑落，产生吸附感；页面轨道、转鼓、滑块共用 | `nav_physics.dart` 的 `displayPosition` |

## 二、底部三条（把手 / AI）与侧边抽屉

| 称呼 | 说明 | 代码位置 |
|---|---|---|
| **底部三条 / 停靠区** | 屏幕底部同一水平线等高排列的三部分：把手条（左）、AI 条（中）、导航条整体（右）；几何统一来自 `DockGeometry` | `navigation/dock_geometry.dart` |
| **把手条 / 把手** | 左下角 12vw 宽的 tone1 小圆角条，高 10；点按弹竖单、右拖拉抽屉；**按压无外观变化** | `widgets/handle_bar.dart` 的 `HandleBar` |
| **本页操作竖单 / 竖单** | 点按把手后从把手位置向上生长的胶囊：340ms 生长、白圆底按钮错峰弹入；当前含刷新 / 分享 / 置顶三个占位操作，点按触发涟漪并自动收起 | `widgets/handle_menu.dart` 的 `HandleMenu`；配置 `navigation/page_action.dart` |
| **停靠位** | 抽屉完全打开时把手条停靠的位置（抽屉右缘 + 14px）；拖抽屉过程中把手与抽屉同步跟手 | `DockGeometry.dockedHandleLeftFor` |
| **AI 条** | 把手右侧的虹彩六色流动条（7s 循环），带同色模糊光晕；单击无行为，长按 450ms 呼出 AI 对话框；按压时整体增亮、光晕加强 | `widgets/ai_bar.dart` 的 `AiBar` |
| **AI 对话框** | 长按 AI 条升起的 22 圆角浮层面板：当前消息区为空、发送键恒禁用，只做到可唤起输入法打字；点遮罩/返回键关闭 | `widgets/ai_dialog.dart` 的 `AiDialog` |
| **侧边抽屉 / 抽屉** | 右拖把手拉出的左侧面板（宽 78vw 封顶 340，右圆角 22，毛玻璃）；**当前是空壳**：内容留空不接事件；遮罩黑 α.44，点遮罩/返回键关闭 | `widgets/side_drawer.dart` 的 `SideDrawer` |

## 三、快捷操作

| 称呼 | 说明 | 代码位置 |
|---|---|---|
| **快捷操作弧 / 快捷弧** | 从导航条向上甩后弹出的弧形菜单，当前含 3 个操作 | `widgets/quick_action_arc.dart` |
| **操作项** | 快捷弧上的单个圆形按钮（当前：应用 / 新建 / 语音，均为占位）；热区 = 按钮直径的 2 倍 | `navigation/quick_action.dart` |
| **涟漪** | 松手触发时，操作项处向外扩散的圆形动画 | `smart_nav_screen.dart`（`_RippleSpec` + 扩散涟漪） |

## 四、搜索

| 称呼 | 说明 | 代码位置 |
|---|---|---|
| **搜索态 / 搜索框** | 长按导航条后，由独立的搜索 pill（与真实导航条解耦、切换帧交接）展开的全宽输入框 | `widgets/search_capsule.dart` |
| **历史胶囊** | 搜索框为空时，上方显示的「最近搜索」小标签：无底色，仅细描边 | `search_capsule.dart` 的 `_HistoryChip` |
| **搜索结果行** | 输入关键词后显示的单条结果（图标 + 标题 + 来源） | `search_capsule.dart` 的 `_ResultTile` |
| **倒计时边框 / 烧蚀边框** | 搜索框外围的细蓝线，2 秒内逐渐消失，烧完自动收起 | `widgets/fuse_border_painter.dart` |

## 五、聊天页

| 称呼 | 说明 | 代码位置 |
|---|---|---|
| **会话行** | 聊天列表的一行（高 72px）：48px 空心圆头像框 + 昵称（tone4 16px）+ 消息预览（tone2 14px），行间为屏宽 80%、水平居中的 1px tone1 分隔线；数据来自 `ChatStore`，以会话 id 为行 key | `pages/chat_page.dart` 的 `ChatListRow`，数据在 `services/chat_store.dart` |
| **空态「暂无消息」** | 会话列表为空时整屏居中的 13px tone2 小字提示；此时不构建 ListView，收到首条消息（`addIncoming()`）后切换为列表，删光全部会话后回到空态 | `pages/chat_page.dart` 的 `ChatPage.emptyHint` |
| **未读绿点** | 未读会话行右上角的 8px 绿色呼吸点（anchorGreen，1.7s 往返 + 发光，与导航锚点同色同节奏）；点按该行使其已读、绿点消失 | `pages/chat_page.dart` 的 `UnreadDot` |
| **左滑操作区** | 会话行向左拖动后从右侧露出的操作按钮组（恒为两个、每个宽 76px、总宽恒定）：左为读状态切换（已读行显示「未读」、未读行显示「已读」，tone2 底/inverse 字），右为「删除」（anchorRed 底/tone4 字）；全局只展开一行，竖滚列表自动收回 | `pages/chat_page.dart` 的 `_SwipeToReveal` |

## 六、状态称呼

| 称呼 | 含义 |
|---|---|
| **常规态** | 停靠区平时的状态：左下角把手条、中段 AI 条、右下角导航条整体（含两端圆点） |
| **搜索待输入态（open）** | 搜索框已展开、输入框未聚焦；倒计时边框运行中 |
| **搜索输入态（input）** | 输入框已聚焦、键盘弹出；倒计时取消 |
| **通知态（锚点）** | 某页有未查看通知：该页锚点绿色呼吸；默认在该页连续停留 700ms 才视为已读，快速扫过/双击跳转途经的页面不算；**聊天页例外**——由会话未读数据驱动，页内所有会话已读才恢复（左滑置未读会重新点亮） |
| **异常态（锚点）** | 某页报告异常：该页锚点红色急闪；仅查看不会解除，须显式处理完成才恢复 |

## 七、手势称呼

### 导航条手势

| 称呼 | 动作 |
|---|---|
| **横滑** | 按住导航条左右拖动，翻页（慢拖精调 / 快甩多页） |
| **点圆点翻页** | 点一下左/右圆点，立即向左/右翻一页（按下即触发，不等松手） |
| **上甩** | 按住导航条快速向上，打开快捷操作弧 |
| **快捷弧反悔** | 上甩后手指移出所有操作项热区（高亮消失）再松手，不触发、直接收起 |
| **双击直达** | 快速双击导航条，按第二下的横向位置直接跳到对应页 |
| **长按** | 按住导航条不动约 0.45 秒，展开搜索框 |

### 把手 / AI 条手势

| 称呼 | 动作 |
|---|---|
| **点按把手** | 点一下把手条，本页操作竖单向上生长；点按钮触发操作并收起，点遮罩/按返回键只收起 |
| **右拖把手** | 按住把手向右拖：抽屉跟手滑出、把手同步移向停靠位；松手按进度吸附开/合 |
| **长按 AI 条** | 按住 AI 条约 0.45 秒呼出 AI 对话框并自动弹键盘；按住后移动超过 8px 取消，单击无任何行为 |
| **浮层互斥** | 竖单 / AI 对话框 / 抽屉 / 搜索 / 快捷弧同屏至多一个；浮层打开时其余手势被遮罩拦截，返回键先关浮层 |

## 八、色板（中性亮度四阶阶梯）

深色底上的白色透明度层级，代号 tone1～tone4（讨论时可称「阶 1」～「阶 4」），
代码常量见 `theme/app_colors.dart` 的 `AppColors.tone1`～`tone4`。
新增元素就近取阶，不再自造白透明度。

| 色板色 | 亮度 | 代表元素 |
|---|---|---|
| **tone1 / 阶 1** | 白 α0.16 | 导航条、圆点默认、各处细描边 |
| **tone2 / 阶 2** | 白 α0.42 | 圆点按下、**锚点常态**、静态光晕、未选中图标；拇指滑块视觉同此亮度，但实现为不透明灰 0xFF838383（需物理遮挡锚点，见规范事故 12） |
| **tone3 / 阶 3** | 白 α0.72 | 次级文字、未强调标签 |
| **tone4 / 阶 4** | 白 α1.0 | 快捷弧选中按钮、主文字 |

功能色不参与阶梯：`accentBlue`（搜索强调）、`anchorGreen / anchorRed`
（锚点通知/异常状态、会话未读绿点、左滑删除按钮）。AI 条的虹彩六色是其专属识别色，就地定义在
`widgets/ai_bar.dart`，也不进色板。深色表面层另有 `overlaySurface`
（竖单 / AI 对话框 / SnackBar）与 `drawerSurface`（抽屉）。

### 机能风 mech 色组

`mech*` 前缀的 13 个 token 是**机能风视觉层专用皮肤色**（RCR-2026-001
收编时 15 个；转鼓精简后 `mechDrumUnit` / `mechDrumTickOff` 随 NO.0N
编号与刻度列一并删除），与 tone1～tone4 **并列、互不归并**：tone 阶服务于
导航/浮层体系，mech 色组服务于固定背景、读数条、大页码、转鼓与页名牌。
新增机能风元素取 mech 色组，不向 tone 阶自造映射；详见架构 3.11 与
[proposals/2026-10-09-mechanical-visual-tokens.md](proposals/2026-10-09-mechanical-visual-tokens.md)。

| 分组 | token |
|---|---|
| 背景与纹理 | `mechBackground`(#0C0C0C)、`mechFineGrid`(白α.05)、`mechCoarseGrid`(白α.10)、`mechGridDot`(白α.22) |
| 读数条/页码 | `mechCoordsDim`(白α.30)、`mechCoordsHi`(白α.55)、`mechPageNumberStroke`(白α.10) |
| 墨水 | `mechInk`(#D8D8D8)、`mechInkDim`(#646464) |
| 转鼓/页名牌 | `mechDrumPanel`(#0F0F0F，页名牌取同色 α.90)、`mechDrumLine`(#262626)、`mechDrumNumber`(#E1E1E1)、`mechDrumProgressTrack`(白α.05) |

---

## 九、机能风视觉层

经 RCR-2026-001 采纳为正式皮肤的一套背景/排印/指示器语言，原型出自
`ideas/mechanical_style_page.html`，架构说明见 3.11。颜色取 mech 色组，
几何/排印/时长常量在 `theme/mechanical_style.dart` 的 `MechanicalStyle`。

| 称呼 | 说明 | 代码位置 |
|---|---|---|
| **机能风视觉层** | 整套机能风皮肤的总称：固定背景 + 读数条 + 透明页面层（kicker/大标题/空心大页码）+ 页码转鼓与衬线页名牌，与导航手势体系叠加共存 | `navigation/widgets/mechanical_*.dart`、`theme/mechanical_style.dart` |
| **固定背景** | 所有页面共用的静态 `CustomPaint` 底：#0C0C0C 上叠 32dp 细网格、128dp 粗网格、128 交点 r=1 点阵，整体右下偏移 16dp；外包 `RepaintBoundary`，翻页不重绘、不接手势 | `widgets/mechanical_background.dart` 的 `MechanicalBackground` |
| **十字标定** | 背景顶部左右各一道的 22×1dp 直角十字线（状态栏下沿 +8dp、左右 inset 14dp，粗网格同色），无实体边框、无底部十字 | `mechanical_background.dart` |
| **读数条 / 设备读数条** | 状态栏下沿居中的 9sp 大字距读数：`DEV 型号 · T 电池温度 · P 瞬时功耗`，MethodChannel `echo/device_stats` 每 5 秒轮询、异常显「—」，`IgnorePointer` 不挡手势 | `widgets/mechanical_coords_bar.dart` 的 `MechanicalCoordsBar` |
| **SEC kicker** | 模板页大标题上方的 11sp w700 大字距小标签（终端 SEC.01 // CONSOLE、笔记 SEC.03 // NOTES、主页 SEC.04 // ME；中文页名改为「终端」「笔记」「主页」后，英文 kicker 仍保留 CONSOLE/NOTES/ME），亮段 `mechInk`、暗段 `mechInkDim`；当前 `fontFamily: monospace` 在 Flutter/Android 不解析，并非真等宽 | `pages/template_page.dart` |
| **空心大页码** | 每页轨道内随页面一起横滑的 01～04 描边数字：120sp、1dp `mechPageNumberStroke` 描边、无填充，top = 5vh、right = 0.14w − 32dp | `widgets/mechanical_page_number.dart` 的 `MechanicalPageNumber` |
| **透明页面层** | 页面底色全部透明、让固定背景透出的约定；模板页如此，聊天页行前景也透明，左滑操作区改由 `CustomClipper` 按露出宽度裁剪遮挡 | `pages/template_page.dart`、`pages/chat_page.dart` 的 `_RevealClipper` |
| **衬线页名牌 / 页名牌** | 横滑唤醒时左下角浮现的当前页名（稿 #pgname）：`mechDrumPanel` α.90 色块、64sp w700 系统 serif（Android 中文回退 NotoSerifCJK 即宋体效果）、字距 .08em、下配 56×3 mechInk 短横线；边框仿转鼓而向右开口：左/上 1px 通线、底边只画左半、右边不画，左上与左下各 16px/2px mechInk 亮角标；左边距与转鼓右边距同源（DockGeometry.sideMargin 14dp，原 5vw 已改）、底边与转鼓底边对齐（52+safeBottom）；与转鼓同一 rollerVisible 同升同收，跨中点按 nearestPage 硬切；叠加赛博故障层（见第一节「赛博故障（glitch）」） | `widgets/mechanical_page_name_plate.dart` 的 `MechanicalPageNamePlate` |

---

新增组件时同步更新本表。
