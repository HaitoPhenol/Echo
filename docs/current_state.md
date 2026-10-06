# Echo 当前实现现状

> 本文件是 **v0.5.0+23（git `1ecec32`，tag `v0.5.0`；提交位于
> `feat/handle-ai-bars` 分支，尚未合入 main）时点的现状快照**
> ——新增把手条 / AI 条 / 侧边抽屉，
> 记录"今天代码实际是怎么实现的"。这些都不是规定——工具与手段可以换，
> 但更换时必须满足 [engineering_standards.md](engineering_standards.md) 的原则、
> 通过测试与真机验收，并更新本文件。
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

- **4 个占位页**：控制台 / 聊天 / 日志 / 我（见 `navigation/nav_destination.dart`），
  页面本体是只显示标题的 TemplatePage；控制台、日志页挂有调试用模拟按钮。
- 页面**全部常驻构建**（一个 Row 一次性 build）。注意这与 `pageBuilder`
  "按需构建"的注释意图不符，是已知债务；接入真实页面前需评估窗口化懒加载
  （activePage±1）方案，离屏页 State 销毁重建的接受度需用户确认。
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
- 搜索数据源仅接入了"页面搜索"一个；`SearchProvider.search` 当前为同步接口。
- 锚点状态**按页序号 int 索引**，与 NavDestination 稳定 id 的设计相矛盾；
- 做任何锚点持久化之前，必须先改为按 destinationId 索引。
- 调试模拟按钮（模拟聊天新消息 / 日志报错 / 处理异常）由 `kDebugMode`
  守卫（v0.4.11 起），release/profile 包不挂载。
- 返回键（v0.4.12 起）由根 `PopScope` 统一拦截：任一浮层（搜索 / 快捷弧
  / 竖单 / AI 对话框 / 抽屉）存在时先关浮层不退出 App；`feat/handle-ai-bars`
  分支把新浮层全部纳入同一 canPop 判定。
- SnackBar 在 `EchoApp` 主题层固定为 `overlaySurface` 深底白字
  （M3 默认反色浅底与暗色界面冲突，已覆盖）。

## 时间源

- 物理积分与搜索 fuse 烧蚀用**帧时间戳**（currentFrameTimeStamp）；
- 另有若干**墙钟 Timer** 尚未统一：导航条长按 450ms、AI 条长按 450ms、
  焦点延时 150ms、圆点按压视觉 200ms、已读停留 700ms、滚筒延时隐藏
  650ms、历史胶囊闪白 180ms；浮层时长（竖单 340ms、AI 对话框 320ms、
  抽屉 420ms、虹彩 7s 循环）走各自的 AnimationController 墙钟。
- 两套时间线在 App 后台 / 测试 pump 时行为不同，改动时需分别考虑。

## 平台与适配

- 主要在 **Android 真机**验证；几何按手机竖屏、单手握持设计：
  导航簇占右半屏，把手 + AI 条占左半到底边（间距统一 14）。
- 平板 / 折叠屏 / 横屏未适配（vw 比例的三条、半屏宽导航条、弧半径 108
  等在大屏上会失衡），目标设备形态待用户确认。
- 文案仅中文硬编码，未引入 l10n。
- 无 Semantics 无障碍标注，TalkBack 下自定义手势组件不可用。

## 测试现状

- 11 个 widget 测试：初始渲染、搜索闭环、滚筒/快捷弧互斥、圆点翻页、
  锚点状态机、返回键顺序，以及把手竖单（生长/按钮 SnackBar）、AI 条
  （不误触/长按可输入/遮罩关闭）、抽屉（跟手吸附/返回键）、浮层互斥。
  全部 pump 整个 EchoApp，表面固定 800×600、坐标硬编码；锚点用例含
  "锚点始终在树上、仅被物理遮挡"的断言。动画类用例必须逐帧 pump
  （单次 `pump(Duration)` 不驱动挂载当帧启动的 Ticker，见测试文件头注释）。
- 物理引擎、搜索服务、锚点服务等纯逻辑尚无直接单元测试。
- 真机回归：MIUI 真机（1080×2160/440dpi）debug 包已过六条旧手势 +
  三条新组件全流程；`gfxinfo` 对 Flutter 自渲染管线只记录到 1 帧，
  不是有效的帧率指标，精测需 profile 模式。

---

## 已知问题与待决策事项

当前已知缺陷、结构债务与分阶段修复路线，以
[code_review_report.md](code_review_report.md) 为权威清单（含行号、改法、验收）。
需要用户拍板、agent 不得自行决定的开放问题见该报告第 4 节 Q1~Q9
（目标设备形态、懒加载策略、持久化时点、快捷弧数量、语言等）。
其中 Q1（按压色意图）已在 v0.4.9/v0.4.10 拍板：圆点按下 tone2、滑块无变化。

**本文件的维护规则**：实现手段变化并合并后，立即更新对应条目并在提交信息中说明；
问题修复后从问题清单移除，不要让本文件描述一个已经不存在的现状。
