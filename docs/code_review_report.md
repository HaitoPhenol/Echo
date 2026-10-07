# Echo 代码库可持续性评估报告

> **读者对象**：接手修改本项目的 AI agent / 开发者。
> **审查基线**：git `fed5420`（v0.4.6+16），2026-10-06。
> **复核基线**：git `b28624d`（v0.4.10+20），同日复核——v0.4.7~v0.4.10
> 的改动（胶囊边框/圆角、锚点物理遮挡、按压链路回退）只影响本报告 P1-01
> 与 P2-11 两处，已就地标注；其余 P0/P1/P2 条目涉及的代码在这四版中未变动，
> 结论继续有效。
> **v0.5.0 复核**：git `1ecec32`（v0.5.0+23，底部三条/AI 对话框/侧边抽屉，
> +2835/-283 行）。门禁通过：analyze 零问题、test 11/11。两个 P0 已在
> v0.4.11/12 解决（见下）；P1-03 部分改善（弧按钮按 actions.length 生成，
> 但 `_computeQuickPositions` 角度仍写死 3 个，数量联动仍不完整）；
> P1-02、P1-04、P1-05 经代码核对仍然成立。v0.5.0 新增约 1800 行
> （含 807 行 smart_nav_screen 增量）的完整例行审查待安排，
> 本次仅做门禁与旧条目复核。
> **审查范围**：`echo/lib` 全部 Dart 源码（14 个文件，约 2 700 行）、`test/`、
> Android 原生侧、`docs/`、工程配置。`ideas/smart_line.html` 为设计基准，不在审查范围。
> **审查方法**：逐文件人工阅读 + `flutter analyze`（零问题）+ `flutter test`（5/5 通过）+
> git 历史与文档对照。
> **使用方式**：第 3 节是可直接执行的任务清单（每条含位置、证据、方案、验收标准）；
> 第 4 节是**必须先问项目负责人、不得擅自决定**的问题；第 6 节是"不要乱动"的清单。

---

## 1. 总体结论

Echo 当前是一个**质量明显高于一般原型阶段**的单人项目：注释解释"为什么"、
配置驱动、关键接口已抽象、版本与提交有纪律、物理/渲染两层分离的思路清晰、
踩过的坑（元素身份、帧时钟、逐帧重布局）都已沉淀为文档规范。它不是一堆需要推翻的代码。

当前的主要债务不是"代码烂"，而是**增长临界点上的结构性风险**：

1. **两个超大文件（853 行和 1128 行）正在成为所有功能的交汇点**，
   新需求（真实页面、持久化、更多快捷操作、更多页面）会持续往这里堆代码；
2. **调试脚手架、返回键、多指触控等发布级问题尚未处理**——代码现在像"演示样机"，
   不像"每天要用的 App"；
3. **最复杂的纯逻辑（物理引擎）没有单元测试**，而它恰恰是未来最容易在重构中被改坏的部分；
4. **几处"数量假设"被硬编码**（4 页、3 个快捷操作、半屏几何），
   配置驱动只覆盖了"页面/操作的内容"，没有覆盖"数量变化后的联动"。

建议在开始下一个大功能（真实页面或把手/AI 条）之前，先完成阶段 0/1（见第 5 节），
成本约 1~2 个工作日，能显著降低后续每次改动的风险。
（v0.4.10 复核：P1-01 已由用户自行解决，未决项为 2 个 P0、5 个 P1，其余不变。）

### 评分（1~5，5 最好；按项目所处的"正式发布前实验期"阶段校准，不按成熟商业产品要求）

| 维度 | 评分 | 一句话结论 |
|---|---|---|
| 可持续性（长期演进能力） | 3.5 | 文档与版本纪律优秀；但总线文件、服务不可注入、无 CI，bus factor = 1 |
| 可维护性（日常改动成本） | 3.0 | 小改很舒服（配置 + 注释齐全），动交互内核则需要同时理解 3 个大文件 |
| 可扩展性（加功能的顺滑度） | 3.5 | 加页面/搜索源的路径已经铺好；加"数量"、持久化、异步数据源、懒加载会撞墙 |
| 稳健性（出错与边界情况） | 2.5 | 主路径手感扎实；多指、返回键、发布包内容、空集合边界等存在确切缺陷 |
| 工程卫生 | 4.0 | analyze 干净、测试全绿、提交规范；缺 CI、release 签名/加固、崩溃兜底 |

---

## 2. 值得保留的优点（修改时不得破坏）

后续 agent 在重构中必须保持以下设计，它们是项目经过真机验证换来的资产：

1. **物理位置与显示位置分离**：[nav_physics.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_physics.dart)
   的 `position`（线性）与 `displayPosition`（橡胶带 + Hermite 磁力曲线）分层，
   整数位置严格不动。物理参数（k=240、阻尼 26、衰减 3.1、增益 0.25~0.60 等）均为已验收取值。
2. **帧时钟时间源**：物理与倒计时用 `currentFrameTimeStamp` 而非墙钟，换取测试确定性。
   方向正确，问题只是"拖动速度采样也用了它"（R-16），不要整体回退为 Stopwatch。
3. **真实导航条与搜索 pill 解耦**：见 [search_capsule.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart)
   的 `_CapsuleMorph` 与 `docs/architecture.md` 第 5 节。这是踩过穿帮坑后的方案，不要合并回同一个组件。
4. **几何由静态常量 + MediaQuery 推算**，不用 GlobalKey 实时测量（冷启动首帧踩过框架断言）。
   问题只是"常量散落在两个文件"（R-14），方向不要改回 GlobalKey。
5. **常驻 Stack 子节点带稳定 ValueKey**（pages/scrim/roller/capsule）。
6. **逐帧动画消除重布局的手法**（固定尺寸 Positioned + 只动 opacity + RepaintBoundary）。
7. **接口先行的服务设计**：`SearchProvider` / `SearchHistoryStore` / `NavBadgeService`
   均为抽象接口 + 内存实现，替换路径在文档中写明。
8. **行为必须有反馈**：未实现操作统一"开发中"提示，不允许死按钮。
9. **中性亮度四阶色板** tone1~tone4 与取阶规则。问题只是有漏网的硬编码颜色（R-13）。

---

## 3. 问题清单（可执行任务）

字段说明：

- **优先级**：P0 = 发布/日常使用阻断；P1 = 明确缺陷，近期应修；P2 = 结构性债务，趁改动顺手还；P3 = 卫生项。
- **置信度**：`确定` = 代码可直接证实；`待确认` = 取决于产品意图（同时列入第 4 节）。
- 每条给**建议改法**与**验收**。未标注"纯重构"的改动都应补/改测试。

### ~~P0-01 调试脚手架会无条件进入发布包~~ —— ✅ 已解决（v0.4.11，d238bf6）

**解决记录**：`buildDefaultDestinations()` 的 footer 已加 `kDebugMode`
守卫（[nav_destination.dart:60-64](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_destination.dart#L60-L64)），
debug 构建保留模拟按钮作锚点验收工具，release/profile 构建 footer 为 null。
architecture.md 已同步守卫说明。原始证据与建议保留如下作历史追溯。

**原始位置**：
[nav_destination.dart:59-66](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_destination.dart#L59-L66)
（`ConsoleBadgeControls` / `LogBadgeControls` 曾被无条件挂进页面）、
[debug_badge_controls.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/pages/debug_badge_controls.dart) 全文。

**遗留事项**：release 包的人工检查尚未执行（不阻塞代码合并，发版前过一次）。

---

### ~~P0-02 搜索态/快捷弧打开时按系统返回键直接退出 App~~ —— ✅ 已解决（v0.4.12，df56eb4）

**解决记录**：根树已包 `PopScope`，canPop 随浮层存在与否翻转：
浮层存在时返回键先关浮层（搜索走 `_exitSearch()`、快捷弧走 dismiss），
皆无才执行默认 pop；fuse 自动关闭等路径也会同步更新 canPop。
widget_test.dart 新增 86 行返回键顺序测试。architecture.md 已同步。

**范围扩展（v0.5.0，分支 `feat/handle-ai-bars`，已提交未发版）**：同一 PopScope 的
canPop 判定纳入本页操作竖单、AI 对话框、侧边抽屉三类新浮层，返回键
逐层关闭（键盘打开时由系统先收键盘，下一次返回才关对话框）；新增
竖单/抽屉返回键用例，真机验证不退出 App。

**原始问题**：单路由应用无 `PopScope`/`WillPopScope`，搜索或快捷弧
打开时按返回键系统直接 pop 唯一路由，效果是退出 App，违背 Android
肌肉记忆。

---

### ~~P1-01 按压色常量值与注释/文档三方矛盾~~ —— ✅ 已解决（v0.4.9 / v0.4.10）

**原始问题**：v0.4.6 时按压色代码值为近黑（`inverse` α0.94），与注释/文档
（"近白"/tone2）矛盾，需用户确认意图。

**解决记录**：v0.4.9 拍板滑块按下无外观变化、删除 pressed 状态链路；
v0.4.10 圆点按压色回退为 tone1→tone2（白 α.42），近黑常量 `_pressedChrome`
已删除。architecture.md / glossary.md 已同步。教训沉淀为规范事故 14
（按压态不必须变色；产品拍板后删整条僵尸状态链路）。本条保留仅作历史追溯。

---

### P1-02 多指触控存在竞态：第二指可劫持/穿越当前手势 —— 置信度：确定

> **v0.5.0 复核**：仍开放。唯一手势槽 `_DragGesture? _gesture`
> 仍只有一个（[smart_nav_screen.dart:133](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L133)），
> 未见第二指针忽略逻辑。v0.5.0 新增的只是**浮层互斥**（竖单打开时长按
> AI 条不弹对话框，已有测试），与本条的"横滑中点圆点/多指抢导航条"
> 是不同路径。

**位置**：
[smart_nav_screen.dart:84](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L84)
（只有一个 `_gesture` 槽）、
[248-295](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L248-L295)、
[310-338](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L310-L338)。

**可复现的两条路径**：

1. 一指按住导航条横滑中，另一指点端点圆点：`_fireNavDot()` 立即 `stepPage()`，
   而第一指的 `dragUpdate` 仍带着旧的 `_dragStartPosition` 继续喂位置 →
   页面位置跳变；松手后 fling/snap 判定基于被污染的累计值。
2. 快捷弧已弹出（`_quickArcShown == true`）时，`_handleRootPointerDown`
   只挡了搜索态（[L249](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L249)），
   不挡快捷弧态：第二指按导航条热区会 `beginGrab()` 并启动 450ms 长按计时，
   可在快捷弧未收起时又展开搜索框，两个浮层叠加。

**建议**：

- `_handleRootPointerDown` 最前面加统一闸门：`if (_gesture != null || _quickArcShown || _nav.isSearching) ...`
  ——搜索态保留现有分支，其余情况直接忽略新指针（不要 beginGrab / fireDot / 开长按）；
- 移动/松手回调已有 `event.pointer != gesture.pointer` 校验，保持不变；
- 若希望"第二指抢到控制权"，需显式设计取消旧手势的流程（先 cancel 旧的再开新的），
  当前阶段建议直接忽略，简单且无惊喜。

**验收**：widget 测试模拟双指针序列（drag 中 tapAt 圆点、弧显示中再按下导航条），
断言：不发生 snap 中途的位置跳变、不出现弧+搜索框同屏。

---

### P1-03 快捷弧"操作数量 = 3"仍有硬编码（v0.5.0 部分改善，v0.5.4 已解决） —— 置信度：确定

> **v0.5.4 复核：已解决（分支 feat/quick-arc-curve，合并提交见 main；
> 分支开发时版本号与 main 的 v0.5.3 撞车，合入后顺延 v0.5.4+27 发布）。**
> 几何层彻底重写：
> - `DockGeometry.layoutQuickArc({origin, count})` 纯函数按数量生成布局，
>   按钮沿**弧长等距**（480 段数值积分 + 二分反解弧长比例）分布在以
>   弧长中点为中心、逐级放宽的窗口（0.60→0.96）内；
> - 热区半径 = `(相邻圆心距 − 10)/2`，相邻热区间隙与"按钮→热区"余量
>   均 ≥ 10；数量过多时热区自动缩小，下限 = 按钮半径（热区不小于按钮）；
> - `_quickSelection` 初始 −1，锁定时按触点到按钮的实际距离选中；
>   `QuickActionArc` 增加 `assert(actions.length == positions.length)`，
>   入场错峰按 `i/(count)` 计算、按钮直径单一来源
>   `DockGeometry.quickArcButtonDiameter`；
> - 真机 2/3/4/5 项与纯函数测试 0~10 项全部通过（默认 3 项）。

> **v0.5.0 复核**：弧按钮渲染已改为 `List.generate(widget.actions.length, i)`
> （[quick_action_arc.dart:84](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/quick_action_arc.dart#L84)），
> "组件层画死 3 个"已消除；但位置几何仍恒定生成 3 个——
> `_computeQuickPositions()` 的角度 `[205, 258, 311]` 写死
> （[smart_nav_screen.dart:972-984](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L972-L984)），
> 与 actions 数量无联动、也无 `actions.length == positions.length` 断言。
> 改成 2/4 项时仍是越界/空位置的老问题，条目保持开放，范围缩小为几何层。

**原始位置/证据**：

- 弧位置只生成 3 个：[smart_nav_screen.dart:596-597](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L596-L597)
  硬编码半径 108、角度 `[205, 258, 311]`；
- 初始选中项写死 `_quickSelection = 1`（[L400](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L400)）；
- 入场动画按 2/1/其余 三档写死：[quick_action_arc.dart:67-77](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/quick_action_arc.dart#L67-L77)；
- 组件按 `positions[i]`/`actions[i]` 直接索引：[L84-89](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/quick_action_arc.dart#L84-L89)，
  松手时父级同样直接索引：[smart_nav_screen.dart:473](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L473)。

**影响**：按 architecture.md 第 4 节"也可以调整数量与顺序"的说法把快捷操作改成
2 个或 4 个时：索引越界崩溃，或弧上画 4 个按钮但只有 3 个位置。配置驱动在这里是断的。

**建议（取决于 Q7）**：

- 短期（数量仍固定 3）：在 `initState`/`build` 加
  `assert(_quickActions.length == 3)` 与 `QuickActionArc` 内
  `assert(actions.length == positions.length)`，把"隐式契约"变成启动即炸的显式契约；
  角度/半径提为具名常量并与 `_quickButtonDiameter` 同住一处；
- 中期（数量可变，见 Q7）：位置由一个纯函数 `quickArcGeometry({required int count, ...})`
  根据数量生成（圆心角均分 + 最小间距约束），`QuickActionArc` 只消费坐标；
  入场错峰改为按 `i / count` 计算，不再写 2/1/0 三档。

**验收**：把 `buildDefaultQuickActions()` 临时改为 2/3/4 项分别跑测试与真机，
不崩溃、不错位（验证后恢复）；最终保留固定 3 项时断言必须存在。

---

### P1-04 涟漪节点无 Key，连发两次会继承错误动画状态且永久泄漏 —— 置信度：确定

> **v0.5.0 复核**：仍开放。涟漪渲染依旧是
> `for (final spec in _ripples) Positioned(child: _Ripple(...))`，
> 无 Key（[smart_nav_screen.dart:1085-1094](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L1085-L1094)）；
> v0.5.0 竖单复用同一涟漪机制（触发点更多），泄漏面反而扩大。

**位置**：[smart_nav_screen.dart:692-701](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L692-L701)。

**机理**：`for (final spec in _ripples) Positioned(child: _Ripple(...))` 无 key。
`_Ripple` 的 AnimationController 在 State 里。两次快捷弧触发间隔小于 650ms
（弧收起 360ms 后可立即再甩，实际可达 ~400ms）时，第一个涟漪播完被移除，
框架按类型+位置把旧 State（controller 已 completed）重新配给第二个涟漪：
第二个涟漪直接呈现终态（scale 2.5、透明），且 completed 状态监听不会再次触发，
`onEnded` 不再被调用 → 该节点永远留在 `_ripples` 列表里（不可见但泄漏）。
这正是项目自己在 [architecture.md:293-297](file:///home/phenol/Documents/GitHub/Echo/docs/architecture.md#L293-L297)
记录的身份错位问题，涟漪是漏网之鱼。

**建议**：`_RippleSpec` 增加唯一 id（构造时用自增计数器或 `UniqueKey()`），
`Positioned(key: ValueKey(spec.id), ...)`。

**验收**：新增测试：连发两次 fire（间隔 < 650ms），推进 2s 后断言
`_ripples` 对应节点数归 0（可通过 `find.byType(_Ripple)` 或暴露测试钩子计数）。

---

### P1-05 `SearchCapsule` 中滑块/双击行程在单页时除零产生 NaN —— 置信度：确定

> **v0.5.0 复核**：仍开放。除零式仍在
> （[search_capsule.dart:338-340](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L338-L340)，
> `left = clampedP / (pageCount - 1) * travel` 无 `n <= 1` 防御），
> `_pageAtX` 同样未见守卫。

**位置**：
[search_capsule.dart:344-346](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L344-L346)
（`travel = _barWidth - thumbWidth`，pageCount=1 时为 0，`left = 0/0*0 = NaN`）、
[smart_nav_screen.dart:573-581](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L573-L581)
（`_pageAtX` 除以 0 后 `.round()` 会抛异常）。

**影响**：当前 4 页不触发；但"新增页面"是文档明示的标准操作，反向"删到只剩 1 页"
（调试期、A/B 实验）会直接崩。同类边界：`displayPosition` 的 floor 逻辑在
pageCount=1 时 `r >= pageCount-1`（即 r>=0）提前返回，侥幸安全。

**建议**：统一在导航几何工具函数中处理 `n <= 1`：thumb 全宽、left=0；
`_pageAtX` 在 pageCount<=1 时直接返回 0。更好的做法见 P2-02（几何抽离后集中防御）。

**验收**：构造 pageCount=1 的 `NavPhysicsController` + 单目的地 `SmartNavScreen`
（需要 P2-09 的服务/配置注入先行，否则用直接单测覆盖几何函数），不出现 NaN/异常。

---

### P1-06 触感通道的 Future 未捕获异常 —— 置信度：确定

**位置**：[haptics.dart:15-34](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/haptics.dart#L15-L34)。
调用方全部以 fire-and-forget 方式调用（如 [smart_nav_screen.dart:133](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L133)、[299](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L299)）。

**影响**：通道未注册/引擎竞争/原生侧异常时，`MissingPluginException` 成为
未处理异步异常（Flutter 会打错误日志，release 下无用户感知但污染崩溃上报）。

**建议**：封装处统一 `return _channel.invokeMethod(...).catchError((_) {});`
（触感失败永远不应影响交互主流程）；或启用 `unawaited_futures` lint 并在调用点显式忽略。

**验收**：测试中抛 `MissingPluginException` 时无 unhandled 记录。

---

### P2-01 `SmartNavScreen` 是 853 行的上帝类 —— 置信度：确定

**位置**：[smart_nav_screen.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart)。
一个 State 同时承担：① 原始指针手势识别与方向锁定；② 导航几何推算
（`_navGeometry`/`_searchCapsuleRect`/`_pageAtX`/`_computeQuickPositions`）；
③ 搜索面板状态编排（query/results/focus/历史/结果点击）；④ 快捷弧显隐与选择状态；
⑤ 涟漪列表管理；⑥ 服务装配；⑦ 整树 build（Stack 七层）。

**影响**：任何交互改动都要在这一个文件里定位；`setState` 的影响面是整个底部导航树
（每次按键、每次圆点按压都重建全树，含 4 个页面）；无法单独测试手势判定逻辑。

**建议（纯重构，分小步、每步测试）**，按依赖顺序：

1. 抽 **`NavGeometry`**（纯类/纯函数，输入 screenSize+safeBottom+几何常量，
   输出 bar/dots/searchRect/quickPositions/thumb 行程）。消灭 P1-05 与 P2-05 的重复，
   并使几何可以直接单测；
2. 抽 **`DragGestureResolver`**（输入 pointer down/move/up 序列 + 当前几何，
   输出"锁定方向/无事件"）。方向锁定阈值（8/16/28/1.1/2）集中为具名常量，可单测；
3. 搜索编排抽 **`SearchPanelController`**（ChangeNotifier：query/results/打开关闭/
   历史写入），持有 SearchService，让输入刷新只重建搜索子树而不是整屏（现状每按一个键
   `setState` 整屏）；
4. `SmartNavScreen` 只保留装配与 build。

目标：该文件降到 ~300 行，手势与几何有不依赖 widget 树的单元测试。
**注意**：每一步独立提交，不要一次性大爆炸重写；物理控制器不在本次重构范围。

**验收**：行为零变化（现有 5 个 widget 测试必须原样通过）；新增几何/手势 resolver 单测；
手动真机回归全部 6 种手势（见 glossary 第五节）。

---

### P2-02 `search_capsule.dart` 1128 行装了 9 个组件 —— 置信度：确定

**位置**：[search_capsule.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart)
含 `SearchCapsule`、`_PanelEntrance`、`_CapsuleMorph`、`_ResultsView`/`_ResultTile`、
`_HistoryChips`/`_HistoryChip`、`_NavAnchor`、`_NavDot`。

**建议（纯重构）**：在 `widgets/` 下按组件拆文件，保持私有可见性可用 `part`
或按需改为包内公开：

```
widgets/capsule/search_capsule.dart      # 仅 SearchCapsule + _CapsuleMorph
widgets/capsule/panel_entrance.dart
widgets/capsule/history_chip.dart
widgets/capsule/result_tile.dart
widgets/capsule/nav_anchor.dart
widgets/capsule/nav_dot.dart
```

几何常量（`sideMargin` 等）保留在 `SearchCapsule` 或移到独立的
`nav_geometry_constants.dart`，供 P2-01 与父级共同 import。

**验收**：import 路径更新后 analyze/test 通过；公开 API 不变；逐文件行数均 < 500。

---

### P2-03 `NavPhysicsController` 的全部状态字段都是公开可变 —— 置信度：确定

**位置**：[nav_physics.dart:97-128](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_physics.dart#L97-L128)
`position` / `velocity` / `activePage` / `rollerVisible` / `searchState` / `fuseProgress`
外部均可直接写，且写了不会 `notifyListeners()`。

**影响**：任何 widget 误写 `controller.position = x` 都会造成物理层与 UI 静默不同步；
代码评审时无法区分"读接口"和"内部状态"。目前靠自觉没有出问题，随着调用方增多必然踩中。

**建议**：字段改私有 + 只读 getter（`double get position => _position;` 等），
写操作只允许通过已有的语义方法（`dragUpdate`/`snapTo`/`openSearch`…）。
`searchState` 同理给 getter。改动机械但波及面广（widgets 内多处读取），
配合 P2-02 拆分一起做最省事。

**验收**：analyze 通过即证明无外部非法写入；测试保持全绿。

---

### P2-04 分层倒置：services 层依赖 navigation 层 —— 置信度：确定

**位置**：[search_service.dart:5](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/search_service.dart#L5)
`import '../navigation/nav_destination.dart';`（`NavDestinationSearchProvider`）。
architecture.md 第 1 节声称 services 是"与界面无关的能力层"，
实际依赖方向是 services → navigation → pages（[nav_destination.dart:3-4](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_destination.dart#L3-L4)）。

**影响**：以后复用 SearchService（如把手/AI 条、全局搜索入口）会把导航配置反向拖进来；
新人按文档找代码会找错层。

**建议**：把 `NavDestinationSearchProvider` 从 search_service.dart 移到
`navigation/`（如 `nav_destination_search.dart`），search_service.dart 只留
`SearchResult`/`SearchProvider`/`SearchHistoryStore`/`SearchService` 这些零 UI 依赖类型。
装配点（SmartNavScreen.initState）import 两边即可。同步修正 architecture.md 目录树。

**验收**：services 目录 grep 不到 `navigation`/`pages` 的 import；测试通过。

---

### P2-05 几何常量跨文件重复，字面量与具名常量并存 —— 置信度：确定

**证据**：

- 屏幕边距 14/16 在 build 里写字面量：
  [smart_nav_screen.dart:706-724](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L706-L724)
  （`right: 14`、`bottom: 52 + safeBottom`、`left: 14, right: 14, bottom: 16`），
  而正式常量在 [search_capsule.dart:81-86](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L81-L86)
  （`sideMargin = 14`、`bottomMargin = 16`）；
- 快捷弧按钮尺寸三处：父级
  [`_quickButtonDiameter = 40`](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L405-L409)
  （注释自认"与 QuickActionArc 中 40×40 保持一致"）、组件内
  [40 与 -20 偏移硬编码](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/quick_action_arc.dart#L87-L90)；
- 弧心/半径/角度散在 [`_computeQuickPositions`](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L588-L610)（108、205/258/311、-5）。

**影响**：调一个间距要改多个文件，且编译器不会提醒漏改——正是已发生过的
"热区与视觉对不齐"那类 bug 的温床。

**建议**：P2-01 的 `NavGeometry` 落地后，所有数值只允许出现在一处；
组件不再接受裸 `40`，改从同一常量取。滚筒的 `bottom: 52` 也要给具名常量并注释由来。

---

### P2-06 帧时钟与墙钟 Timer 混用，且控制器内部就不统一 —— 置信度：确定（设计取舍，改动需谨慎）

**证据**：物理与 fuse 用帧时间戳（[nav_physics.dart:85-86](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_physics.dart#L85-L86)）；
但同一控制器的滚筒延时隐藏用墙钟 `Timer(650ms)`（[L420-428](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_physics.dart#L420-L428)）；
屏幕侧另有 5 个墙钟 Timer：长按 450ms、圆点 200ms、焦点 150ms、已读 700ms
（[smart_nav_screen.dart:147](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L147)、[174](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L174)、[302](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L302)、[328](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L328)），
历史胶囊 180ms（[search_capsule.dart:947](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L947)）。

**具体差异场景**：

1. **后台返回**：open 态搜索框在 App 进后台时 Ticker 停摆，回前台帧时间戳跳变，
   `now - burnStart` 直接变大 → fuse 瞬间烧完、搜索框秒关（可能不是期望行为，见 Q8）；
2. `beginGrab()` 不取消 `_rollerHideTimer`（[L153-158](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_physics.dart#L153-L158)）：
   落位后 650ms 内按住不松手，滚筒会在手指按着时自己消失；
3. dispose 未取消的 Timer（圆点 200ms、焦点 150ms、胶囊 180ms）都有 `mounted` 兜底，
   不会崩，但属于不规范写法，且让生命周期推理更费劲。

**建议**：先修第 2 点（一行：`beginGrab` 里 `_rollerHideTimer?.cancel()`）与
第 3 点（统一登记取消）。第 1 点与"是否把所有短延时迁到帧时钟"涉及手感，
等 Q8 答复；若迁移，注意 widget 测试里所有时间推进都走 `pump`，
现有墙钟 Timer 反而依赖真实异步（当前测试能过是因为假异步同时驱动两者）。

---

### P2-07 拖动速度采样在"帧间事件"上会失真 —— 置信度：确定（影响程度待真机量化）

**位置**：[nav_physics.dart:174-192](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_physics.dart#L174-L192)。

**机理**：`dragUpdate` 用 `_now`（上一帧的 `currentFrameTimeStamp`）做时间差。
PointerMove 事件在两帧之间也会到达（触控采样率通常 ≥ 120Hz，与刷新率不一致），
同一帧内连续两个 move 事件拿到相同时间戳 → `dt = 0` → 被钳成固定 0.008s，
于是 `dx/0.008` 给出虚高瞬时速度（再经低通平滑部分掩盖）。
慢拖时增益对速度敏感，可能让"跟手精调"在高刷设备上偏飘。

**建议**：速度估计改用指针事件自带的 `PointerEvent.timeStamp`（在
`_handleRootPointerMove` 把 `event.timeStamp` 一并传入 `dragUpdate`），
物理积分与 fuse 继续用帧时钟——两者解耦。测试中 `TestGesture` 的事件时间戳随
模拟时钟推进，需同步调整现有用例的断言方式。**改完必须真机对比慢拖手感再决定保留与否**，
若实测无差异可仅记录结论不改代码。

---

### P2-08 页面全部常驻构建，与"按需构建"的文档承诺不符 —— 置信度：确定（是否改取决于 Q3）

**位置**：
[smart_nav_screen.dart:645-657](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L645-L657)
（一个 Row 一次性 build 全部页面）、
[nav_destination.dart:14](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_destination.dart#L14)
注释声称 `pageBuilder` "实现按需构建"。

**影响**：控制台/日志/我 3 个 TemplatePage 无所谓；首个真实页面
——聊天页 ChatPage（30 个简单会话行的 ListView）——现已进入常建
行列，当前负载很轻，但该债务自此不再是纯理论问题；更多真实页面接入后：
① 首帧要构建所有页面（冷启动负载正是本项目已踩过的雷区）；
② 离屏页的动画/定时器/订阅全部在跑，耗电与内存随页面数线性增长；
③ 页面无法在离屏时释放资源。

**建议**：这是本项目最需要权衡的结构决策（Q3），候选：

- A. 维持自定义轨道，加"窗口化"构建：只构建 activePage±1 的页面，其余用占位盒子
  （保持自定义物理完全不动，改动局部）；
- B. 迁到 `PageView` + 自定义 `ScrollPhysics`：复用懒加载/手势体系，
  但要把自研 fling/snap/磁力曲线映射到滚动物理，回归风险高，不建议在功能期做。

建议先选 A。无论选哪个，先修正 nav_destination.dart 那句"按需构建"的失实注释。

---

### P2-09 服务在 initState 内硬编码 new，无法注入替换 —— 置信度：确定

**位置**：[smart_nav_screen.dart:115-128](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L115-L128)。

**影响**：架构文档承诺"换持久化实现时界面零改动"，但构造函数没有注入入口，
替换实现必须改这个文件；测试也只能 pump 整个 EchoApp 走内存实现，
无法给单测塞假服务——这是测试只能写成巨型集成用例的根因之一。

**建议**：给 `SmartNavScreen` 增加可选构造参数（带默认值 = 当前内存实现/默认配置）：
`destinations`、`quickActions`、`searchHistory`、`badgeService` 等。
默认值用 `??=` 保持外部调用零变化。配合 P2-01 的控制器拆分效果最好。

---

### P2-10 锚点状态以"页序号 int"为 key，与稳定 id 的设计自相矛盾 —— 置信度：确定（改动时机见 Q 规划）

**位置**：[nav_badge_service.dart:23-35](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/nav_badge_service.dart#L23-L35)
（全部接口用 int page）、
[debug_badge_controls.dart:8-9](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/pages/debug_badge_controls.dart#L8-L9)
硬编码聊天=1、日志=2。

**影响**：NavDestination 专门设计了稳定 `id`（"代码引用页面时永远用它"），
但锚点状态绑序号——调整页面顺序后通知会亮在错误页面；将来持久化锚点状态时，
升级 App 调整顺序即读错状态。

**建议**：`NavBadgeService` 接口改为按 `String destinationId` 索引
（内部 Map 或由调用方做 id↔index 映射）；UI 渲染时按 destinations 的 id 查。
Debug 脚手架同步改用 id。**纯接口变更，趁现在只有 1 个调用方尽早做**；
若短期不做，至少在接口文档里标注"序号依赖当前页面顺序，禁止持久化"。

---

### P2-11 色板之外仍有散落的硬编码颜色 —— 置信度：确定

**位置**：

- [search_capsule.dart:206](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L206)
  `Color(0xFF0F141A)`（pill 底色目标值，与 `AppColors.searchBackground` 同 RGB 不同 alpha，
  但没有命名词）；
- [search_capsule.dart:228](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L228)
  `0x8C000000`、[L426](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L426)
  提示文字 `0xFF5A646E`；
- [nav_roller.dart:76](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/nav_roller.dart#L76)
  `0x73000000`、[L288-292](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/nav_roller.dart#L288-L292)
  直接用 `Colors.white.withValues(alpha: ...)`；
- [quick_action_arc.dart:111](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/quick_action_arc.dart#L111)
  `0x80000000`。

**影响**：tone1~tone4 体系刚建立（v0.4.0），这批漏网值没有命名、
没有归属规则，下次统一调色会漏改。

**建议**：在 AppColors 补两类具名常量：阴影色（如 `shadowStrong`/`shadowSoft`，
或统一一个带透明度档位的黑）、`hintText`；pill 底色目标值若语义是"搜索面实色"，
新增 `searchSurfaceSolid`。替换后 architecture.md 3.8 节补一句"阴影/提示色也是具名常量"。
中央刻度脉冲属于"动画连续 alpha"，按现行规则可保留插值，但基色应用 `tone4` 而不是
裸 `Colors.white`（值相同，语义更清楚）。

> **v0.4.10 复核**：新增的 `_thumbFill = 0xFF838383` 虽是裸十六进制，
> 但属于**合理例外**——它必须是不透明色才能物理遮挡锚点（事故 12），
> tone2 的半透明值无法表达，且代码注释完整记录了等效亮度推导。
> 收口时应将其提为 AppColors 中带语义说明的具名常量（如 `thumbOpaque`），
> 不要求改成半透明值。fuse 倒计时条在 v0.4.7 已改用 tone2。

---

### P2-12 搜索：同步接口、无防抖、无删除入口 —— 置信度：确定（演进时点待规划）

**位置/现象**：

- `SearchProvider.search` 同步返回（[search_service.dart:51-60](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/search_service.dart#L51-L60)），
  注释自己预告了异步需求但接口不支持——接数据库/网络源时是破坏性变更；
- 每次 `onChanged` 立即全量查询并整屏 setState（[smart_nav_screen.dart:195-200](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L195-L200)），
  无防抖；
- `SearchHistoryStore.remove` 已定义（[L116](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/search_service.dart#L116)）
  但 UI 没有任何删除历史的入口，属于死能力；
- 匹配仅 `label.contains(keyword)`（[L88](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/search_service.dart#L88)），
  无大小写折叠/拼音/缩写（中文标签当前无所谓，英文/联系人源接入后会需要）。

**建议（在接入第二个真实数据源时一起做，不必现在）**：
接口演进为 `FutureOr<List<SearchResult>> search(...)` 或直接 `Future<List<SearchResult>>`，
`SearchService.searchAll` 聚合 + 输入侧 150~250ms 防抖 + 取消上一次在途查询；
历史胶囊加长按删除（正好用上 `remove`）。在 architecture.md 里把这个演进时点写明，
避免后人在同步接口上继续堆数据源。

---

### P2-13 无障碍（Semantics）整体缺失 —— 置信度：确定

**位置**：全 lib grep 无 `Semantics`。自定义圆点/导航条/快捷弧完全靠裸指针事件，
TalkBack 用户无法翻页、不知道当前页；`QuickAction.label`
（[quick_action.dart:24](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/quick_action.dart#L24)）
除了占位 SnackBar 外在 UI 中从未被使用。

**建议（发布前至少做最小集）**：
① 两端圆点包 `Semantics(button: true, label: '上一页/下一页', onTap: ...)`；
② 快捷弧按钮用 label 做语义标签；③ 锚点状态在有通知/异常时给语义通知
（`SemanticsService.announce`）；④ 导航条区域整体可被语义聚焦并朗读当前页。
同时在 architecture.md 增加"自定义手势组件必须提供等价语义动作"一条规范。

---

### P2-14 测试结构单一，最复杂逻辑无直接单测，且无 CI —— 置信度：确定

**现状**：[test/widget_test.dart](file:///home/phenol/Documents/GitHub/Echo/echo/test/widget_test.dart)
308 行、5 个用例全部 pump 整个 EchoApp，坐标硬编码（600,560 / 781,560 等），
几何一改全部用例要跟着改；以下高价值行为零覆盖：

- `NavPhysicsController`：fling 衰减/边界撞停/snap 收敛/橡胶带/磁力曲线 f(0)=f(0.5)=f(1)
  /fuse 2s 烧尽自动关闭（这是全项目数学最密、最容易被重构改坏的文件）；
- SearchService / 历史去重裁剪 / NavBadgeService 状态机（含"异常优先于通知"）；
- 交互：双击直达、fuse 自动收起、快捷弧触发与反悔、（修复后）返回键与多指。

**建议**：

1. 新增 `test/navigation/nav_physics_test.dart`：直接 new 控制器 + `TickerProvider`
   测试替身，手动驱动帧回调（帧时钟设计本来就为此而生）；断言位置/速度/回调；
2. 新增 services 的纯 Dart 单测（无 widget）；
3. widget 测试中的坐标改为从几何常量/`NavGeometry`（P2-01）计算，消除魔数；
4. 加最小 CI（如 GitHub Actions：`flutter analyze` + `flutter test`），
   与本地提交纪律配套；否则"提交前保证通过"只靠自觉。

---

### P2-15 发布加固与崩溃兜底缺失 —— 置信度：确定

**证据/建议**：

- [build.gradle.kts:32-38](file:///home/phenol/Documents/GitHub/Echo/echo/android/app/build.gradle.kts#L32-L38)
  release 用 debug 签名、无 R8 压缩/混淆配置——正式分发前需要独立 keystore +
  `signingConfig`（走环境变量/本地 properties，不要提交密钥）；
- [main.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/main.dart) 只有 `runApp`，
  无 `FlutterError.onError` / `runZonedGuarded` 兜底——真机出问题没有任何日志聚合手段。
  建议加统一错误处理钩子（哪怕先只 `debugPrint` + 留上报接口位）；
- `pubspec.yaml` 顶部版本号注释等模板噪音可清理（低优先）。

---

### P3 卫生项（可在相关文件被触碰时顺手处理）

| ID | 位置 | 问题 | 建议 |
|---|---|---|---|
| P3-01 | [nav_physics.dart:53](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_physics.dart#L53)、[L61](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_physics.dart#L61) | 默认 `pageCount = 10` 与注释"模板阶段为 10 页"均过时（实际 4 页） | 默认改为必填或 4，注释更新 |
| P3-02 | ~~[glossary.md:13](file:///home/phenol/Documents/GitHub/Echo/docs/glossary.md#L13)~~ | ~~导航条代码位置写的 `_buildCapsule()` 不存在~~ | ✅ 已在文档重组中改为 `SearchCapsule` / `_navBar()`（v0.4.10 复核） |
| P3-03 | [search_capsule.dart:791-847](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L791-L847) | `_ResultTile` 无任何状态，却是 StatefulWidget + 空 State | 改 StatelessWidget |
| P3-04 | [search_capsule.dart:667-673](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L667-L673) | 动画期间每帧 new 一个 `Listenable.merge` | 在 State 中缓存合并后的 Listenable |
| P3-05 | [nav_physics.dart:287-292](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/nav_physics.dart#L287-L292) | `_muteActivePageCallback` 在 snap 中途被 grab 打断时可能滞留，吞掉下一次跨页 tick | 在 `beginGrab` 重置该标志，或改为"静音到本次运动结束"的作用域设计 |
| P3-06 | [nav_roller.dart:85-114](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/nav_roller.dart#L85-L114) | ShaderMask 子树缩进错位（analyze 不报，阅读受影响） | `dart format` |
| P3-07 | [smart_nav_screen.dart:732-734](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L732-L734) | `items.toSet().toList()` 去重是冗余防御（Store.add 已保证不重复） | 确认后简化为 `List.unmodifiable` 或直接传 |
| P3-08 | `echo/README.md` | Flutter 模板自带说明（计数器示例），与项目无关 | 换为真实简介或删除，文档入口指向 docs/architecture.md |
| P3-09 | 全项目 | 中文文案硬编码在 widget 中，无 l10n 框架 | 若有非中文计划（Q6），在功能扩张前引入 flutter_localizations + ARB；否则记录为"仅中文"决策 |
| P3-10 | [analysis_options.yaml](file:///home/phenol/Documents/GitHub/Echo/echo/analysis_options.yaml) | lint 为默认集 | 可开启 `unawaited_futures`、`prefer_single_quotes`（与现有风格一致）等，逐步收紧 |
| P3-11 | [search_capsule.dart:89-99](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/search_capsule.dart#L89-L99) | `_assemblyWidth`/`_barWidth` getter 与静态方法并存、`28` 等魔数 | P2-05 几何收口时统一 |
| P3-12 | [smart_nav_screen.dart:141](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L141) | 已读监听的 `lastViewedPage` 闭包变量无注释说明为何不放在字段 | 补注释或内聚到独立类（P2-01 后自然归入搜索/导航编排） |

---

## 4. 必须向负责人确认的问题（禁止擅自替产品做决定）

- ~~**Q1（按压色意图）**~~：✅ 已决（v0.4.9/v0.4.10）——圆点按下 tone2、
  滑块按下无外观变化，见 P1-01 解决记录。
- **Q2**：目标平台与形态？当前几何假设"单手握持手机、导航簇占右半屏"，
  平板/折叠屏/横屏上半屏宽的导航条会非常宽，热区与弧半径（108px）都未适配。
  是否只承诺手机竖屏？若是，应在文档写明并考虑对大屏做锁向或居中布局。
- **Q3（决定 P2-08 方案）**：真实页面接入后预期多少页、每页多重？
  是否接受"只构建当前页±1"的窗口化懒加载（离屏页 State 会被销毁重建，
  页面自身需要能恢复状态）？
- **Q4**：搜索历史与锚点状态的持久化计划时点？两者都已留好接口，
  但 P2-10（锚点改 id 索引）最好在第一次写持久化实现**之前**完成，否则要做数据迁移。
- **Q5**：锚点"通知态"语义：同一页连续多条通知只表现为一个绿灯，
  是否需要未读计数（将来亮角标数字）？这影响 `NavBadgeService` 接口是否要尽早演进。
- **Q6**：是否只有中文？决定 P3-09 的 l10n 投入。
- **Q7（决定 P1-03 方案）**：快捷弧操作数量是产品上永远 3 个，还是未来可变？
- **Q8**：App 从后台返回时，搜索 fuse 是应该"暂停计时继续"（当前实际是"按真实经过时间烧完"），
  哪种符合预期？相关：是否接受把所有短延时统一到帧时钟（影响测试写法与手感）。
- **Q9**：发布节奏：下一版是继续做功能（把手/AI 条），还是先做一轮加固版
  （阶段 0~1）？本报告建议后者。

---

## 5. 建议的执行路线图

每个阶段独立可交付、可发版（遵守项目版本纪律 MINOR/PATCH + tag）。
每阶段完成后执行：`flutter analyze` → `flutter test` → 真机回归相关手势 → 文档对照审计。

### 阶段 0：发布前加固（建议 0.5~1 天，发一个 PATCH）

- P0-01 调试脚手架加 `kDebugMode` 守卫
- P0-02 PopScope 拦截返回键（+ 测试）
- P1-02 多指闸门（+ 测试）
- P1-04 涟漪 key（+ 测试）
- P1-06 触感异常吞没
- P2-06 的第 2 点（beginGrab 取消滚筒定时器）
- P3-01/P3-02/P3-06 等顺手的文档与格式修正

风险低、收益高，全部是局部改动，不碰物理与动画结构。
（P1-01 已在 v0.4.9/v0.4.10 解决，不再列入。）

### 阶段 1：一致性收口（约 0.5~1 天）

- P1-03 快捷弧数量契约（先加断言与常量化；等 Q7 决定是否做几何生成）
- P1-05 单页边界防御
- P2-11 颜色常量化
- P2-04 services/navigation 分层倒置修正
- P3 剩余卫生项
- 同步 glossary/architecture 全文审计

### 阶段 2：结构拆分（约 2~3 天，纯重构，行为零变化）

- P2-02 search_capsule 拆文件（先做，降低后续阅读成本）
- P2-01 抽 NavGeometry 与手势 Resolver（+ 直接单测）
- P2-09 服务/配置可注入
- P2-03 控制器字段私有化
- P2-05 几何常量单点化

每一步单独提交，现有 5 个 widget 测试全程保持绿色作为安全网。

### 阶段 3：测试与工程体系（约 1~2 天，可与阶段 2 穿插）

- P2-14 物理引擎/服务单测、CI
- P2-15 release 签名与崩溃钩子（发布计划确定时）

### 阶段 4：面向下一功能的能力建设（按需排期）

- P2-10 锚点改 id 索引（**必须在任何持久化之前**）
- P2-08 页面窗口化懒加载（先回答 Q3）
- P2-12 异步搜索源 + 防抖 + 历史删除
- P2-13 无障碍最小集
- P3-09 国际化（视 Q6）
- P2-07 速度采样改指针时间戳（真机 A/B 后决定）

---

## 6. 明确"不建议改动"的部分（防止过度重构）

以下设计经评估是**合理取舍或真机验证结论**，除非有新证据，后续 agent 不应改动：

1. 不要把物理参数"通用化/可配置化"——它们为 4 页场景手调验收，抽象只会增加理解成本；
   需要时按 architecture.md 3.5 的提示随页面数整体重调即可。
2. 不要把帧时钟改回 Stopwatch（确定性测试依赖它）；P2-07 只建议把"速度采样"分离出去。
3. 不要把真实导航条与搜索 pill 重新合并成一个"万能变形组件"。
4. 不要恢复用 GlobalKey 实时测量导航几何。
5. 不要在当前阶段引入状态管理框架（Riverpod/Bloc 等）：现有 ChangeNotifier +
   InheritedNotifier 规模够用，引入框架本身是更大的复杂度；等服务数量/跨页共享状态
   真的增长后再评估。
6. 不要为了"干净"提前做 P2-08/P2-12/P3-09 这类大改——它们等对应业务需求到来时做，
   现在做属于 YAGNI。
7. `ideas/smart_line.html` 是手感基准，不要删除；代码中"与原型一致"的注释即指向它。

---

## 7. 附：审查证据快照

- 代码规模：lib 14 个 Dart 文件约 2 700 行；最大文件 search_capsule.dart 1128 行、
  smart_nav_screen.dart 853 行、nav_physics.dart 468 行。
- `flutter analyze`：No issues found。
- `flutter test`：5/5 通过（初始渲染、搜索闭环、滚筒/快捷弧互斥、圆点翻页、锚点状态机）。
- git：已打 tag v0.3.0~v0.4.10，提交信息符合 Conventional Commits；
  审查基线（v0.4.6）时工作区干净；v0.4.7~v0.4.10 为用户侧自行迭代的四个版本。
- 依赖：零三方依赖（仅 cupertino_icons + flutter_lints），供应链风险极低。
- 原生侧：仅 Android 一个 MethodChannel（触感），VIBRATE 权限已声明，
  有振幅控制降级；iOS 走系统 HapticFeedback。
- 文档：architecture.md 与 glossary.md 质量高；v0.4.6 审查时发现 3 处
  与代码不一致（P1-01、P3-02、P2-08 注释），其中 P1-01 已在 v0.4.10
  随代码一并修正，P3-02 在本次文档重组中修正，P2-08 注释待改。
