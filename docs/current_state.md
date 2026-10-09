# Echo 当前实现现状

> 本文件是 **v0.6.2+30（main，tag `v0.6.2`）时点的现状快照**
> ——底部三条（把手 / AI / 导航）、侧边抽屉，快捷弧沿手指轨迹
> 椭圆弧的弧长等距布局（`DockGeometry.layoutQuickArc`，数量驱动），
> 全屏套有机能风视觉层（固定背景/读数条/大页码/转鼓/衬线页名牌，
> 见架构 3.11），
> 记录"今天代码实际是怎么实现的"。这些都不是规定——工具与手段可以换，
> 但更换时必须满足 [engineering_standards.md](engineering_standards.md) 的原则、
> 通过测试与真机验收，并更新本文件。机能风视觉层经 RCR-2026-001
> 采纳转正，详见
> [proposals/2026-10-09-mechanical-visual-tokens.md](proposals/2026-10-09-mechanical-visual-tokens.md)。
>
> **v0.6.1（patch，已合并 main）**：首页中文页名控制台→**终端**
> （英文 kicker 保留 CONSOLE）；转鼓精简（删顶行右上 NO.0N 编号与
> 视窗右侧刻度列，面板 206→176dp，mech 色组 15→13 token）；新增
> **左下衬线页名牌**（64sp 系统 serif、底边与转鼓对齐、同升同收，
> 叠加赛博故障入场：唤醒播一次、成功翻页重播、边界回弹不播，
> 副本为 mechInkDim 灰色重影的极简单色风）。
>
> **v0.6.2（patch，已合并 main）**：页名牌左边距与转鼓右边距对齐
> 为 DockGeometry.sideMargin 14dp；页名面板改仿转鼓的开口框
> （左/上通线、底边半线、右边不画，左上/左下 16px 亮角标）；
> 第四页页名「我」改「主页」，四页统一两字（英文 kicker 仍 ME）；
> 指示器退场改 340ms 水平百叶窗故障（横带错峰两明两暗），抽出
> 两个指示器共用的 MechanicalIndicatorLifecycle，上甩/进搜索
> 仍瞬隐。
>
> **未发布（分支 `feat/notes-page`，版本号待合入 main 时排）**：
> 日志页改名**笔记**（label「日志」→「笔记」、英文 kicker
> LOGS→NOTES，SEC.03 保留），笔记功能暂不做、笔记页不挂任何
> 调试按钮；异常模拟/处理从日志页收拢到终端页调试面板
> （终端页共三个按钮：模拟聊天新消息 / 模拟异常 / 处理异常），
> 终端页下标由 nav_destination 按稳定 id 解析后经构造参数传入，
> 消除脚手架写死页序（P2-10 的脚手架一半已还，接口按 int 索引的
> 债务仍在）。
>
> 相关文档：[架构与接口说明](architecture.md) ·
> [工程规范](engineering_standards.md) · [规则演进机制](governance.md) ·
> [术语表](glossary.md) · [问题清单](code_review_report.md)

---

## 技术栈与工程

- **Flutter**，Dart SDK ^3.13.5；零三方业务依赖（仅 cupertino_icons、
  flutter_lints）。
- 状态管理用 **ChangeNotifier + InheritedNotifier**：当前规模下的选择，不是禁令；
  服务数量与跨页共享状态真正增长后再评估框架。
- Android 原生侧只有一个 MethodChannel `echo/haptics`（触感，直接驱动 Vibrator，
  有振幅控制降级，已声明 VIBRATE 权限）；iOS 走系统 HapticFeedback。
- lint 为 flutter_lints 默认集；无 CI。
- **发布配置**：Android release 尚用 debug 签名，无独立 keystore / R8 加固；
  无全局崩溃钩子（FlutterError.onError / runZonedGuarded）。

## 页面与导航

- **4 个页面**：终端 / 聊天 / 笔记 / 主页（见 `navigation/nav_destination.dart`；
  首页中文页名 v0.6.1 起由「控制台」改「终端」，第三页由「日志」改「笔记」
  （分支 feat/notes-page，版本号待合入 main 时排定）；英文 kicker 分别为
  CONSOLE / NOTES / ME）。
  聊天页已替换为真实页面 `ChatPage`（`pages/chat_page.dart`，数据来自
  `services/chat_store.dart` 的 `ChatStore`）：**无标题栏**，
  列表初始为空，空态整屏居中显示 13px 小字「暂无消息」（tone2）；
  有会话时整页 ListView 铺满轨道（会话行高 72px：48px 圆形头像占位框
  （tone1 空心描边）+ 昵称 tone4 16px + 消息预览 tone2 14px 单行省略，
  行间分隔线为屏宽 80%、水平居中的 1px tone1 细线；顶部避让状态栏、
  底部预留 26px 停靠条高度）。行交互已接通数据：
  **左滑**露出右侧操作区（恒为两个等宽按钮、总宽恒定：左为读状态切换，
  已读行显示「未读」、未读行显示「已读」，tone2 底；右为「删除」anchorRed 底），
  按速度/半程 180ms 吸附、全局只开一行、竖滚自动收回；
  未读行右上角有**呼吸绿点**（anchorGreen，1.7s 往返，与导航锚点同参数），
  点按未读行即已读；终端页「模拟：聊天新消息」经 `ChatStore.addIncoming()`
  在最前插入未读会话。
  其余三页仍是只显示标题的 TemplatePage；仅终端页挂锚点调试面板
  （模拟聊天新消息 / 模拟异常 / 处理异常，共 3 个按钮），笔记与主页无调试按钮。
  **四页均套有机能风视觉层（v0.6.0 转正，RCR-2026-001）**：主屏 Stack
  最底层为固定的网格/点阵/十字背景（RepaintBoundary 静态层），状态栏下沿
  是设备读数条，页面底色透明；模板页带 SEC kicker 与 48sp w700 大字距标题，
  每页轨道内有空心大页码；右下角为精简后的 3D 数字转鼓（176dp，顶行仅
  blip+PAGE、底部跟手进度条，仅横滑唤醒，圆点/双击路径不显示；旧横向
  圆点胶囊 NavRoller 与原稿 NO.0N 编号/右侧刻度列均已删），横滑时左下角
  同步浮现衬线页名牌（与转鼓底边对齐、同升同收）。架构说明见 3.11。
- 页面**全部常驻构建**（一个 Row 一次性 build）。注意这与 `pageBuilder`
  "按需构建"的注释意图不符，是已知债务（P2-08）；聊天页已成为首个
  常驻的真实页面（空态仅一个 Center+Text，有会话时为 itemExtent
  定高 ListView，负载很轻），更多真实页面接入前需评估
  窗口化懒加载（activePage±1）方案，离屏页 State 销毁重建的接受度需用户确认。
- 导航物理为自研 `NavPhysicsController`：`position`（线性物理）与
  `displayPosition`（橡胶带 + Hermite 磁力曲线）两层分离；fling 指数摩擦、
  snap 弹簧、速度自适应增益等参数均为 **4 页场景下手调验收值**，页面数变化需整体重评。
- 几何全部由静态常量 + MediaQuery 推算，不用 GlobalKey
  （原因见规范事故 4）：底部三条（把手 / AI / 导航整体）统一收在
  `navigation/dock_geometry.dart` 的 `DockGeometry`（12vw 把手、
  38vw-56 AI 条、50vw 右对齐导航整体、间距统一 14、底边距 16），
  导航条自身的剩余常量仍在 `SearchCapsule`。
- **底部三条（v0.5.0）**：左下角把手条（点按呼出本页操作竖单，
  配置在 `page_action.dart`，当前刷新/分享/置顶三个「开发中」占位；
  右拖跟手拉出侧边抽屉，松手吸附，把手同步滑到抽屉右缘停靠位）；
  中段 AI 虹彩流动条（7s 循环 + 光晕，长按 450ms 呼出对话框；对话框
  当前消息区为空、发送键恒禁用，仅可打字）；右侧导航条整体不变。
  抽屉与 AI 对话框均为**空壳**，内容留待后续。竖单 / 对话框 / 抽屉 /
  搜索 / 快捷弧互斥，同屏至多一个浮层。
- 搜索开合为**真实导航条与独立搜索 pill 双组件交接**（`_CapsuleMorph` 驱动）。
- **滑块为不透明灰** `_thumbFill`（0xFF838383，亮度等同旧 tone1+tone2
  合成白量 ≈.513）；**锚点始终全部挂载、画在滑块下层**，当前页段靠不透明
  滑块物理遮挡，无位置显隐逻辑（v0.4.7/8 改，事故 12/13）。
- 按压反馈（v0.4.9/10 拍板）：端点圆点按下 tone1→tone2，**滑块按下无
  外观变化**，State 中无按压视觉字段；历史上的变黑/描边/近黑方案均已回退。
- 快捷操作弧固定 3 项（应用 / 新建 / 语音，均为"开发中"占位），数量在角度数组、
  初始选中项、入场动画三处写死。

## 状态与服务

- 搜索历史（`InMemorySearchHistoryStore`）与锚点状态
  （`InMemoryNavBadgeService`）均为**内存实现，重启清空**；抽象接口已定义，
  待业务接入时换持久化实现。
- **聊天会话数据 `ChatStore`**（`services/chat_store.dart`，ChangeNotifier，
  经 `ChatStoreScope` 提供）：内存保存会话列表，支持新消息插入 / 删除 /
  已读 / 置未读，`hasUnread` 聚合未读态；重启清空。
- **聊天页锚点为数据驱动例外**：`SmartNavScreen` 监听 `ChatStore`
  （`_syncChatBadge`）——有未读即绿色呼吸，**页内所有会话已读才恢复**，
  停留 700ms 计时器对聊天页不启动；「置未读」会重新点亮锚点。
  其余页面仍是「停留 700ms 即已读」。
- 搜索数据源仅接入了"页面搜索"一个；`SearchProvider.search` 当前为同步接口。
- 锚点状态**按页序号 int 索引**，与 NavDestination 稳定 id 的设计相矛盾
  （code_review_report P2-10：脚手架一侧的写死序号已消除，但接口层债务仍在）；
  做任何锚点持久化之前，必须先改为按 destinationId 索引。
- 调试模拟按钮（模拟聊天新消息 / 模拟异常 / 处理异常）全部收拢在
  终端页一个面板，由 `kDebugMode` 守卫（v0.4.11 起），release/profile
  包不挂载；「聊天新消息」调 `ChatStore.addIncoming()`，异常模拟/处理
  作用于终端页自身，其下标由 `buildDefaultDestinations()` 按 id
  （indexWhere(id == 'console')）解析后经构造参数传入，脚手架内已无
  写死页序；笔记页（原日志页）不挂任何调试按钮。
- 返回键（v0.4.12 起）由根 `PopScope` 统一拦截：任一浮层（搜索 / 快捷弧
  / 竖单 / AI 对话框 / 抽屉）存在时先关浮层不退出 App；`feat/handle-ai-bars`
  分支把新浮层全部纳入同一 canPop 判定。
- SnackBar 在 `EchoApp` 主题层固定为 `overlaySurface` 深底白字
  （M3 默认反色浅底与暗色界面冲突，已覆盖）。

## 时间源

- 物理积分与搜索 fuse 烧蚀用**帧时间戳**（currentFrameTimeStamp）；
- 另有若干**墙钟 Timer** 尚未统一：导航条长按 450ms、AI 条长按 450ms、
  焦点延时 150ms、圆点按压视觉 200ms、已读停留 700ms（仅非聊天页，
  聊天页锚点改由 ChatStore 数据驱动）、转鼓/页名牌延时隐藏
  650ms、历史胶囊闪白 180ms；浮层时长（竖单 340ms、AI 对话框 320ms、
  抽屉开 420ms / 关 100ms、虹彩 7s 循环、会话行左滑吸附 180ms）
  走各自的 AnimationController 墙钟。
- 两套时间线在 App 后台 / 测试 pump 时行为不同，改动时需分别考虑。

## 平台与适配

- 主要在 **Android 真机**验证；几何按手机竖屏、单手握持设计：
  导航簇占右半屏，把手 + AI 条占左半到底边（间距统一 14）。
- 平板 / 折叠屏 / 横屏未适配（vw 比例的三条、半屏宽导航条、弧半径 108
  等在大屏上会失衡），目标设备形态待用户确认。
- 文案仅中文硬编码，未引入 l10n。
- 无 Semantics 无障碍标注，TalkBack 下自定义手势组件不可用。

## 测试现状

- 共 24 个测试，分三个文件：`widget_test.dart` 11 个导航/浮层集成用例
  （初始渲染、搜索闭环、转鼓/快捷弧互斥、圆点翻页、**双击导航条直达且
  中转页不算已读**、锚点状态机、返回键顺序，以及把手竖单、AI 条、抽屉、
  浮层互斥；锚点用例覆盖「聊天页停留不清除、全部已读才恢复」的数据驱动
  机制），全部 pump 整个 EchoApp、表面固定 800×600、坐标硬编码；
  `navigation/dock_geometry_test.dart` 6 个快捷弧布局纯函数用例；
  `pages/chat_page_test.dart` 7 个聊天页用例（初始空态、滚动避让、
  新消息插入与点按已读、左滑双按钮/置未读/删除、吸附重播不弹回、
  再次拖动连续性、竖滚自动收回，直接 pump ChatPage + ChatStore）。
  锚点用例含"锚点始终在树上、仅被物理遮挡"的断言。动画类用例必须逐帧
  pump（单次 `pump(Duration)` 不驱动挂载当帧启动的 Ticker，见测试文件
  头注释）；呼吸绿点是无限动画，相关用例不能用 `pumpAndSettle`
  （永久超时），以固定帧数 pump 等待 180ms 吸附完成。
- 物理引擎、搜索服务、锚点服务等纯逻辑尚无直接单元测试。
- 真机回归：MIUI 真机（1080×2160/440dpi）debug 包已过六条旧手势 +
  三条新组件全流程；`gfxinfo` 对 Flutter 自渲染管线只记录到 1 帧，
  不是有效的帧率指标，精测需 profile 模式。
  **v0.6.0 机能风版本六手势回归**：横滑（转鼓跟手）/圆点点按/
  上甩快捷弧（含热区外反悔）/长按搜索胶囊真机通过；双击直达与多指边界
  因 user 版无 root、adb 无法在 300ms 窗内有序注入双击/多指，以
  widget 双击用例 + pointer 过滤代码走查兜底，**留人工真机复核**；
  背景静态层重绘隔离经结构核查 + 密集交互录屏无肉眼掉帧；转正合并后
  已再次构建 debug 包装机复验无功能缺失。

---

## 已知问题与待决策事项

当前已知缺陷、结构债务与分阶段修复路线，以
[code_review_report.md](code_review_report.md) 为权威清单（含行号、改法、验收）。
需要用户拍板、agent 不得自行决定的开放问题见该报告第 4 节 Q1~Q9
（目标设备形态、懒加载策略、持久化时点、快捷弧数量、语言等）。
其中 Q1（按压色意图）已在 v0.4.9/v0.4.10 拍板：圆点按下 tone2、滑块无变化。

**v0.6.0 转正遗留**：
① 人工真机复核双击导航条直达与双指同按边界（G4/G6，widget 用例与
代码走查已兜底）；
② 可选项（用户已看过未要求）：粗网格 α .10→.08 微调（长列表灰文案
偶被穿线）、打包 Roboto Mono 让 kicker 真等宽（包体/许可另议）。

**本文件的维护规则**：实现手段变化并合并后，立即更新对应条目并在提交信息中说明；
问题修复后从问题清单移除，不要让本文件描述一个已经不存在的现状。
