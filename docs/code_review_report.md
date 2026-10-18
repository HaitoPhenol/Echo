# Echo 已知问题清单

> **本文件是当前版本的开放问题权威清单**（不是规则）：缺陷、结构债务、
> 待决策事项。问题修复后立即移除或标注解决版本；历史论证见归档报告。
>
> **基线**：v0.13.1+39（main，2026-10-16；patch tag 留本地）。
> 条目现状随每次 MINOR 发布顺带复核；标注「待复核」的条目未做完整
> 真机回归。
>
> **2026-10-16 结构债务轮**：G1/G2/G3/G5 已在分支
> `refactor/struct-debt-a` 解决（行为保持重构，441 测试全绿、analyze
> 零问题，经独立子智能体复核），已合入 main；G4 仍挂起，待 Q3 拍板。
>
> **2026-10-16 优化轮**：D2/G13/G11/G12/G6/G8 与 Q2 落地已在分支
> `feat/optimization-a` 处理（445 测试全绿、analyze 零问题，经独立子
> 智能体复审 + MIX 2S 真机冒烟），随本轮合入 main；G4（懒加载）与
> G7（CI）仍挂起。
>
> 历史审查与施工流水（只读归档）：
> - [archive/codebase-review-v0.5.0-2026-10-06.md](archive/codebase-review-v0.5.0-2026-10-06.md)
>   （v0.4.6~v0.5.0，含每条问题的行号证据与改法论证）
> - [archive/ecp-p1-p4-review-log.md](archive/ecp-p1-p4-review-log.md)
>   （ECP 四期交接单、修复回执、复审与真机终审原文）

---

## A. 日记模块（M1–M5 之后）

> **2026-10-18 日模板重设**：日模板改单空段骨架、data 只读块与
> `readonly` 整体退役，自动数据与心情改走文档根 `custom-*` + 胶囊行
> （见 [diary/flutter-tech-plan.md](diary/flutter-tech-plan.md) §5.3）；
> 下表 D1/D7 随之改述。

| # | 问题 | 现状 | 建议 |
|---|---|---|---|
| D1 | **自动数据是假实现**（原「data 块数据是假实现」） | `FakeDiaryDataProvider` 常量（21°C/45%/3 条/多云），2026-10-18 起经编辑页**胶囊行**呈现（不再标「（示例数据）」，data 只读块已退役）；真实 IoT/天气/日程源未接 | 产品化前置；接入只换 provider 实现，`fetchCustomPatch`/胶囊行链路不动 |
| D2 | **空稿预览标注丢失**（疑似回归） | **已解决**（分支 `feat/optimization-a`，2026-10-16）：`day_list_page.dart` 空预览改按 state 区分——draft 恢复「周X（空稿）」（M4 行为），exported/archived 维持星期小字退化；M5 移除标注的注释理由只覆盖后两者，已修正注释并补 widget 回归测试（draft 空稿显标注、exported 空预览不显） | （已修） |
| D3 | **Slash 命令面板、↑/↓ 逐行跳焦未做** | M3 遗留 patch（tech-plan §4.4），不阻塞 | 编辑器打磨 patch，M6 连写前后插入 |
| D4 | **mood 思源聚合出图未通** | custom-mood 数据落盘正确；思源 v3.8.6 属性视图需 Template 字段 `{{ index . "custom-mood" }}` 桥接，移动端未配通 | 思源侧配置活，非 Echo 代码问题 |
| D5 | **撤销快照经 sy codec 的潜在丢块** | tech-plan §7.1：回读含子集外块文档时结构撤销可能跳过只读节点。当前无外部 .sy 导入链路，风险未触发 | 上导入功能前二选一：快照保原始节点 / 含 skippedTypes 禁结构撤销 |
| D6 | **思源平台限制**（非我方缺陷） | Android 思源不响应 ACTION_SEND（只能 SAF 手动导入 zip）；导入会重生成全部块 ID，重复导入=新建同名笔记本，非合并幂等 | 在使用文档中写明流程；不依赖"容器 ID 幂等"假设 |
| D7 | **真实数据源前刷新无可见反馈** | 点胶囊行的数据胶囊重拉三源，对假常量数据零变化；功能不崩但用户无感 | 接真实 provider 时加「更新于 HH:mm」 |
| D8 | **日模板重设真机验收** | **已完成**（2026-10-18，MIX 2S）：`flutter analyze` 零告警、全量 453 项测试已过；真机走查五胶囊齐备、心情点选即时生效、点数据胶囊重拉三源、导出 zip 中今日文档根含 `custom-iot-temp`/`custom-humidity`/`custom-weather`/`custom-schedule-count`；同日紧凑化（正文区上沿 420→340、下沿直达屏幕底 + 停靠条作浮层）已真机实测确认 | （已验） |

日记模块的完整里程碑状态见
[diary/flutter-tech-plan.md](diary/flutter-tech-plan.md)。

## B. 通用工程问题

| # | 问题 | 现状（2026-10-16 复核；G1–G5 见本轮结构债务重构） |
|---|---|---|
| G1 | **`SmartNavScreen` 上帝类** | **已解决**（分支 `refactor/struct-debt-a`，2026-10-16）：主屏 1626 → 1353 行——几何纯函数收敛至 `navigation/dock_layout.dart`，手势记录/触发涟漪移出 `navigation/nav_gesture_records.dart` 与 `widgets/trigger_ripple.dart`，`build()` 内联子树抽为私有构建方法；手势阈值/时长/树形/Key 零改动。手势与浮层编排仍在 State，进一步抽 Resolver 属后续可选打磨 |
| G2 | **`search_capsule.dart` 1152 行装多组件**（旧 P2-02） | **已解决**：拆为 `search_capsule.dart`(596) + `search_pill_morph.dart`(325) + `search_panel_content.dart`(252)；跨文件私有件提升为公共组件名，树形/Key/时长逐字不变 |
| G3 | **分层倒置：services 依赖 navigation** | **已解决**：`NavDestinationSearchProvider` 迁至 `navigation/nav_destination.dart`（与目的地模型同址），`services/search_service.dart` 不再 import navigation，1.4 铁律恢复；navigation→services 为允许的向内依赖 |
| G4 | **页面全部常驻构建**（旧 P2-08） | 仍如此（Row 一次性 build，日记页 State 常驻已被真机验证依赖此特性——自动成稿/防抖 flush 挂在常驻 State）。窗口化懒加载前必须先迁移这些生命周期假设，见 Q3 |
| G5 | **锚点按页序号 int 索引**（旧 P2-10） | **已解决**：`NavBadgeService` 改按 `String destinationId` 索引（内存实现用 `Map`），锚点身份键同步用稳定 id；未知 id 读回 `normal`、写静默忽略；对外 ECP `badge` 命令入参（名/下标）与出参（index+name+level）契约不变 |
| G6 | **无 Semantics 无障碍**（旧 P2-13） | **已解决（最小集）**（分支 `feat/optimization-a`，2026-10-16）：底栏导航条 `label/value` + `onIncrease/onDecrease` 翻页动作；两端圆点/把手/AI/快捷弧/会话行及左滑两按钮加按钮语义（会话行未读追加「未读」）；机能风五个纯装饰层 `ExcludeSemantics`。**挂账**：圆点/把手/AI/快捷弧仅只读 label（`button:true` 却无激活动作，读屏播报为按钮但不可点），激活动作需把 State 回调下沉进各 widget，建议单独安排 |
| G7 | **无 CI**（旧 P2-14 下半） | 测试已从 24 个增至 **445 个**（日记 + ECP 协议/事件/作业覆盖充分），另有 echo-cmd 脚本级回归 15 断言；但仍无 GitHub Actions，门禁全靠本地自觉 |
| G8 | **release 加固缺失**（旧 P2-15） | **部分解决**（分支 `feat/optimization-a`，2026-10-16）：已开 R8（`isMinifyEnabled`/`isShrinkResources` + 保底 `proguard-rules.pro`；release 出包 53.3MB、无 missing class，装机冒烟通过）并接入崩溃钩子（`runZonedGuarded` + `FlutterError.onError`，无远端上报后端仅 `debugPrint`）。**仍挂**：独立 keystore（用户决策项）。release 包人工裁剪检查已随 P3/P4 发布常态化（dex 字符串扫描 + slash 补全计数 + 全新装走查，未发现 ECP 调试面泄漏） |
| G9 | **搜索仍为同步接口、无防抖、无删除入口**（旧 P2-12） | 未变；接真实异步数据源时一并演进 |
| G10 | **墙钟 Timer 散落**（旧 P2-06） | current_state「时间源」有完整清单；帧/墙双轨并存是已知取舍 |
| G11 | **多指触控竞态**（旧 P1-02，待复核） | **已解决**（分支 `feat/optimization-a`，2026-10-16）：复核确认回归成立——`_handleRootPointerDown` 原无「已有手势在途」检查，第二指会覆盖 `_gesture`（劫持前指）或把手 `_handleGesture` 与导航条 `_gesture` 同帧并驱（穿越手势）；按下入口最前面加单指独占守卫（`_gesture`/`_handleGesture`/`_aiHold` 任一非空即忽略新指针），补多指回归用例（该项先用例在无守卫时失败） |
| G12 | **涟漪节点无 Key**（旧 P1-04，待复核） | **已解决**（分支 `feat/optimization-a`，2026-10-16）：复核确认——涟漪可同屏并存，无 key 时框架按位置配对，先结束者被移除后存留项继承其已完成的动画 State（冻结在透明、`onEnded` 不再触发、永不移除）；`RippleSpec` 加自增稳定 id，节点挂 `ValueKey<int>(spec.id)`，补并发双涟漪回归用例 |
| G13 | **触感 invokeMethod 无 catchError**（旧 P1-06，待复核） | **已解决**（分支 `feat/optimization-a`，2026-10-16）：`Haptics` 收口到 `_invoke()`，Android 通道调用统一 `.catchError` 静默降级（规范 1.11，调用方均为 fire-and-forget，此前通道异常会成为未捕获异步错误）；新增 `test/services/haptics_test.dart` mock 通道抛错验证不逃逸 | （已修） |

旧报告中的 P1-05（单页 NaN，当前固定 4 页且短期不变）、P2-03/05/07/09/11
（控制器私有化/几何常量/速度采样/注入/散落色）为低优先卫生项，
论证见归档报告，触碰相关文件时顺手处理，不在此单列。

## C. 待负责人决策（agent 不得自行决定）

- **Q3 懒加载策略**：是否接受"当前页±1"窗口化（离屏页 State 销毁重建）；
  注意 G4——日记页的自动成稿与防抖 flush 现依赖常驻，改造需先迁移。
- **Q4 搜索历史/锚点持久化时点**：锚点改 id 索引（G5）必须先于其持久化。
- **Q5 锚点是否要未读计数**：影响 `NavBadgeService` 接口是否尽早演进。
- **Q6 语言**：是否只有中文（决定 l10n 投入）。
- **Q8 后台返回后搜索 fuse 计时语义**；是否把短延时统一到帧时钟。
- **ECP 后续专项（P4 后，原设计点名"另立专项"，均未立项）**：
  ① MCP 真实通道接入（只读铁律，现仅有 guest 假通道与边界负向测试，
  零传输代码）；② 内置 agent 通道（逐次用户授权面板，见
  [ecp/ecp-design.md](ecp/ecp-design.md) §5.2）；
  ③ 终端页完整 UI（`ControlConsoleCore` 接缝已在 P3 抽好，§7）；
  ④ 审计流水 sqflite 落盘（现内存环，§6）。

已决：Q1 按压色（v0.4.9/10 拍板）、
**Q2 目标设备形态（2026-10-16 拍板，同日落地）**：**手机锁竖屏、
平板不锁方向**；平板/折叠的横屏与大屏 UI 适配暂不做（维持"被拉宽的
竖版"，不承诺体验）。落地方式：Manifest 无法按设备类型区分
screenOrientation，改在 `MainActivity.onCreate` 按
`smallestScreenWidthDp >= 600` 判定——手机 `requestedOrientation =
SCREEN_ORIENTATION_PORTRAIT`、平板 `UNSPECIFIED`（分支
`feat/optimization-a`；MIX 2S 真机取证 `mCurrentAppOrientation=
SCREEN_ORIENTATION_PORTRAIT`、请求横屏不生效）。
Q7 快捷弧数量（v0.5.4 起数量驱动，
不再写死 3）、Q9 发布节奏（已走功能优先路线至 v0.13）、
**Q10 权限模型威胁对象（2026-10-13 拍板）**：不防"临时持机者"，
防 MCP/内置 agent 自动化通道；本地用户最高权限；chat.send 升 3 级、
diary.export 降 2 级、本地通道放开 PIN 首装；终端页为未来愿景。

## D. 保护项（无新证据不得改动，迁移自旧报告 §6）

1. 物理参数为 4 页场景真机手调，不做"通用化/可配置化"；
2. 帧时钟不回退 Stopwatch（确定性测试依赖）；
3. 真实导航条与搜索 pill 不重新合并为"万能变形组件"；
4. 不恢复 GlobalKey 实时测量导航几何；
5. 当前规模不引入状态管理框架（ChangeNotifier + InheritedNotifier 够用）；
6. 不为"干净"提前做大改（懒加载/异步搜索/i18n 等业务需求到来再做）；
7. `ideas/smart_line.html` 等原型是手感基准，不删除。

## 维护规则

- 修复即更新本文件（快通道，governance §4.2）；
- 新条目给：位置、现状证据、建议；不写无法复现的问题；
- 每 MINOR 版本发布时由维护者顺带复审一次；
- 阶段性施工/复审流水不进本文件，结案后整体移入
  [archive/](archive/)（参见 ECP P1–P4 归档）。
