# Echo 已知问题清单

> **本文件是当前版本的开放问题权威清单**（不是规则）：缺陷、结构债务、
> 待决策事项。问题修复后立即移除或标注解决版本；历史论证见归档报告。
>
> **基线**：v0.9.0+34（main，2026-10-11，M1–M5 日记模块已合入）。
> 最近一次清点：2026-10-11（静态快核；标注「待复核」的条目来自
> v0.5.0 旧报告，未做完整真机回归）。
>
> 历史审查：[component-reports/codebase-review-v0.5.0-2026-10-06.md](component-reports/codebase-review-v0.5.0-2026-10-06.md)
> （v0.4.6~v0.5.0，含每条问题的行号证据与改法论证，只读归档）。

---

## A. 日记模块（M1–M5 之后）

| # | 问题 | 现状 | 建议 |
|---|---|---|---|
| D1 | **data 块数据是假实现** | `FakeDiaryDataProvider` 常量（21°C/45%/3 条/多云），界面标「（示例数据）」；真实 IoT/天气/日程源未接 | 产品化前置；接入只换 provider 实现，成稿链路不动 |
| D2 | **空稿预览标注丢失**（疑似回归） | `day_list_page.dart` 空预览统一退化为星期小字；M4 §5.2 的「（空稿）」标注在 M5 反范式预览改造时被一并移除（注释理由只对 archived 成立，draft 空稿被误伤） | 小修：按 state 区分，draft 空稿恢复标注 |
| D3 | **Slash 命令面板、↑/↓ 逐行跳焦未做** | M3 遗留 patch（tech-plan §4.4），不阻塞 | 编辑器打磨 patch，M6 连写前后插入 |
| D4 | **mood 思源聚合出图未通** | custom-mood 数据落盘正确；思源 v3.8.6 属性视图需 Template 字段 `{{ index . "custom-mood" }}` 桥接，移动端未配通 | 思源侧配置活，非 Echo 代码问题 |
| D5 | **撤销快照经 sy codec 的潜在丢块** | tech-plan §7.1：回读含子集外块文档时结构撤销可能跳过只读节点。当前无外部 .sy 导入链路，风险未触发 | 上导入功能前二选一：快照保原始节点 / 含 skippedTypes 禁结构撤销 |
| D6 | **思源平台限制**（非我方缺陷） | Android 思源不响应 ACTION_SEND（只能 SAF 手动导入 zip）；导入会重生成全部块 ID，重复导入=新建同名笔记本，非合并幂等 | 在使用文档中写明流程；不依赖"容器 ID 幂等"假设 |
| D7 | **真实数据源前刷新无可见反馈** | ↻ 对假常量数据零变化；功能不崩但用户无感 | 接真实 provider 时加「更新于 HH:mm」 |

日记模块的完整里程碑状态见
[diary/flutter-tech-plan.md](diary/flutter-tech-plan.md)。

## B. 通用工程问题

| # | 问题 | 快核现状（2026-10-11） |
|---|---|---|
| G1 | **`SmartNavScreen` 上帝类持续膨胀**：v0.5.0 时 853 行，现 1525 行（机能风组件已抽到 `navigation/widgets/` 9 个文件，但主屏装配本身未拆） | 待重构：抽手势 Resolver / 各页装配；ECP P2 的 NavController 提升是一个切入点 |
| G2 | **`search_capsule.dart` 1124 行装多组件**（旧 P2-02） | 仍存在，行为零变化的纯拆分，排期独立 patch |
| G3 | **分层倒置：services 依赖 navigation** | 仍存在：`search_service.dart` import `navigation/nav_destination.dart`（页面搜索源需要目的地模型；可考虑把可搜索项模型下沉为接口数据） |
| G4 | **页面全部常驻构建**（旧 P2-08） | 仍如此（Row 一次性 build，日记页 State 常驻已被真机验证依赖此特性——自动成稿/防抖 flush 挂在常驻 State）。窗口化懒加载前必须先迁移这些生命周期假设，见 Q3 |
| G5 | **锚点按页序号 int 索引**（旧 P2-10） | `NavBadgeService.levelOf(int)` 未变；脚手架侧写死页序已消除。任何锚点持久化之前必须先改 destinationId 索引 |
| G6 | **无 Semantics 无障碍**（旧 P2-13） | 全库仅一处 `ExcludeSemantics`；TalkBack 不可用。发版前做最小集 |
| G7 | **无 CI**（旧 P2-14 下半） | 测试体系已从 24 个增至 194 个（日记单测/widget 覆盖充分），但仍无 GitHub Actions；门禁全靠本地自觉 |
| G8 | **release 加固缺失**（旧 P2-15） | release 仍用 debug 签名、无独立 keystore/R8；无 FlutterError.onError / runZonedGuarded 崩溃钩子。**release 包人工检查从未执行**（发版前必做） |
| G9 | **搜索仍为同步接口、无防抖、无删除入口**（旧 P2-12） | 未变；接真实异步数据源时一并演进 |
| G10 | **墙钟 Timer 散落**（旧 P2-06） | current_state「时间源」有完整清单；帧/墙双轨并存是已知取舍 |
| G11 | **多指触控竞态**（旧 P1-02，待复核） | 第二指劫持/穿越手势的风险自 v0.5.0 后未复核，导航手势代码区域未大改，假定仍在 |
| G12 | **涟漪节点无 Key**（旧 P1-04，待复核） | 连发两次继承错误动画状态；未复核 |
| G13 | **触感 invokeMethod 无 catchError**（旧 P1-06，待复核） | `Haptics.tick/confirm` 仍直接 return channel Future；通道异常时为未捕获异步错误，严重度低 |

旧报告中的 P1-05（单页 NaN，当前固定 4 页且短期不变）、P2-03/05/07/09/11
（控制器私有化/几何常量/速度采样/注入/散落色）为低优先卫生项，
论证见归档报告，触碰相关文件时顺手处理，不在此单列。

## C. 待负责人决策（agent 不得自行决定）

- **Q2 目标设备形态**：只承诺手机竖屏？平板/折叠/横屏是否锁向或居中布局。
- **Q3 懒加载策略**：是否接受"当前页±1"窗口化（离屏页 State 销毁重建）；
  注意 G4——日记页的自动成稿与防抖 flush 现依赖常驻，改造需先迁移。
- **Q4 搜索历史/锚点持久化时点**：锚点改 id 索引（G5）必须先于其持久化。
- **Q5 锚点是否要未读计数**：影响 `NavBadgeService` 接口是否尽早演进。
- **Q6 语言**：是否只有中文（决定 l10n 投入）。
- **Q8 后台返回后搜索 fuse 计时语义**；是否把短延时统一到帧时钟。

已决：Q1 按压色（v0.4.9/10 拍板）、Q7 快捷弧数量（v0.5.4 起数量驱动，
不再写死 3）、Q9 发布节奏（已走功能优先路线至 v0.9）。

## D. 保护项（无新证据不得改动，迁移自旧报告 §6）

1. 物理参数为 4 页场景真机手调，不做"通用化/可配置化"；
2. 帧时钟不回退 Stopwatch（确定性测试依赖）；
3. 真实导航条与搜索 pill 不重新合并为"万能变形组件"；
4. 不恢复 GlobalKey 实时测量导航几何；
5. 当前规模不引入状态管理框架（ChangeNotifier + InheritedNotifier 够用）；
6. 不为"干净"提前做大改（懒加载/异步搜索/i18n 等业务需求到来再做）；
7. `ideas/smart_line.html` 等原型是手感基准，不删除。

## E. ECP P1 审查交接单（2026-10-12，分支 feat/ecp-p1-core @27ab796）

审查结论：analyze 0 issue / 230 测试绿 / 24 步真机实测通过 / release 包
aapt2 实证无 ECP 组件。下列 5 条为遗留项，**E1–E3 合 main 前必修，
E4–E5 可挂账**（建议同批顺手）。修复在本分支续做，门禁照旧。

| # | 级别 | 问题与位置 | 修复要求 | 验收 |
|---|---|---|---|---|
| E1 | major（必修） | **接收器不校验调用方，第三方 App 可冒充 adb 通道**。[DebugControlReceiver.kt:30](../echo/android/app/src/debug/kotlin/com/everse/echo/DebugControlReceiver.kt#L30) onReceive 只查 action；debug 清单 exported=true 无 permission。Dart 侧通道恒为 adb（起始 2 级）：任意 App 可无 PIN 读 diary.list/get（有序广播 resultData 回传）、nav.goto、sys.clock.set；PIN 未设时还能抢 auth.set-pin 首装后执行 3 级命令 | onReceive 开头取 `Binder.getCallingUid()`，仅放 `ROOT_UID(0)/SHELL_UID(2000)`，其余直接 return（不 setResult、不打日志）。注释说明：信任边界是 shell/root uid，不是 debuggable 标志 | 现有 adb（uid 2000）链路全部命令实测仍通；代码审查确认无其它入口；补一条接收器单测（Robolectric 或抽纯函数 `isCallerTrusted(uid)` 做 Dart/Kotlin 侧纯逻辑测试，二选一并在提交说明写明） |
| E2 | major（必修） | **echo-cmd 无法给布尔传 false，真实 prune 走不通**。[scripts/echo-cmd:195-212](../scripts/echo-cmd#L195-L212) 布尔标志恒编 true，不认 `--name=value`；[diary_commands.dart:196](../echo/lib/src/control/commands/diary_commands.dart#L196) dryRun 缺省 true。实测 `--dry-run false` 直接报参数错 | 支持 `--flag`（true）与 `--flag=true|false`、`--flag true|false` 两形态；同时更新手册 §9.1 示例。注意 `--reset`（clock.set）与 `--confirm` 保持纯开关语义 | 真机：`diary.prune --confirm --dry-run=false` 真实删除并返回 dryRun:false；`--dry-run` 单独仍为预演；其它布尔参数（keep-seeds/wait-snapshot）false 可达 |
| E3 | minor（必修） | **过鉴权后的执行失败不入审计**。[control_bus.dart:144-166](../echo/lib/src/control/control_bus.dart#L144-L166) handler 抛 ControlException/Timeout/其它异常时直接 fail()，仅鉴权拒绝与成功写审计，与设计 §6「≥2 级调用全部入审计」不符 | catch 各分支补 `_auditIfNeeded(..., ok:false, ms:..., error:...)`；timeout 分支同 | control_bus_test 加用例：handler 抛 ControlException 后 audit 末条 ok=false 且 errorCode 正确；≥2 级业务失败、3 级超时两类各一 |
| E4 | minor（可挂账） | **接收器 9s 预算 vs slow 命令 60s 超时**。[DebugControlReceiver.kt:105-113](../echo/android/app/src/debug/kotlin/com/everse/echo/DebugControlReceiver.kt#L105-L113)：导出超 9s 回 TIMEOUT 但 Dart 侧继续、zip 可能已落盘。当前实测导出 80ms 不触发 | P1 仅需在 ecp-design.md §7 或手册写明该限制与判定方法（以落盘文件/审计为准）；根治随 P3 事件流/结果轮询 | 文档一节；清单挂账 |
| E5 | minor（可挂账） | **allowBackup 默认开，pin.json 可随备份导出**。主 [AndroidManifest.xml](../echo/android/app/src/main/AndroidManifest.xml) 未声明；[pin_store.dart:54](../echo/lib/src/control/auth/pin_store.dart#L54) 文件在默认备份范围。PBKDF2 12 万轮加盐使爆破成本高，且 release 永不生成 pin.json，属纵深防御 | Manifest 置 `android:allowBackup="false"`（App 无需要系统备份的用户状态；日记是导出归档模型），或加 dataExtractionRules 排除 echo_control/ | 装机后 `dumpsys package` flags 中无 ALLOW_BACKUP（或规则文件含排除项）；release/debug 各验一次 |

修复完成后请维护者复验 E1–E3 真机项再合 main；E4/E5 若挂账，
在本表标注「随 P3」或解决版本。

### 修复回执（2026-10-12，快通道，待维护者复验）

- **E1 ✅ 已修（实现方式与交接单有偏差，附实测依据，请复验确认）**：
  交接单写的 `onReceive` 内 `Binder.getCallingUid()` 在 manifest
  接收器上**拿不到发送方 uid**——接收器经 ActivityThread 消息派发，
  已离开 binder 事务，实测恒为本 App uid（MIX 2S / Android 10：
  `binder=10378 my=10378`，`getSentFromUid()` 为 API 34+，旧机
  返回 null）。若按原写法，uid 2000 的正常 adb 链路会被全部误杀
  （装机后实测 echo-cmd 全命令静默丢弃，已实证）。故改为等价且
  真正生效的两层门禁：①debug 清单接收器声明
  `android:permission="android.permission.DUMP"`，AMS 派发前用
  发送方真实 uid 校验（普通三方 App 无法获得 DUMP，root/shell
  天然持有，`dumpsys package com.android.shell` 实证 granted），
  未持有者根本不进入 onReceive，等效静默丢弃；②进程内
  `isCallerTrusted(uid)` 0/2000 白名单保留为纯函数（companion，
  ROOT_UID=0/SHELL_UID=2000），API 34+ 经 `getSentFromUid()`
  作二次门禁、身份缺失 fail-closed。JVM 单测
  testDebug/DebugControlReceiverTrustTest 3 条（0/2000 放行，
  1000/10001/99999/-1 拒绝）。真机：uid 2000 冷启动→ping/audit
  全链路通过；release 合并清单无接收器（grep 计数 0）。
- **E2 ✅ 已修并真机复验通过**：echo-cmd 布尔三形态 `--flag` /
  `--flag=v` / `--flag v`（v 仅 true/false，第二形态只在**下一
  token 恰为 true/false** 时吃值，绝不误吃后续 `--xxx`）；
  `--confirm`/`--reset` 保持纯开关且拒绝 `--confirm=x`；Python
  侧补 `"false"→False`；手册 §9.1 已更新。解析探针 8 case 全对。
  MIX 2S 真机（2026-10-12）：`diary.ensure --date 2026-10-10
  --wait-snapshot=false`（false 实达 handler，审计可查）→
  `diary.prune --confirm`（单独仍预演 dryRun:true，deleted
  仅 [2026-10-10]，09-12 有字稿 kept:non-empty）→
  `--confirm --dry-run=false` **真实删除** dryRun:false/
  deleted:[2026-10-10] → 空格形态 `--dry-run false` 幂等
  dryRun:false/deleted:[]；list 复核 10-10 已消失、3 篇既有
  日记完好。`--keep-seeds=false` 形态经解析探针覆盖，未真机
  执行 diary.reset（会清空日记域，无安全实测对象）。
- **E3 ✅ 已修**：control_bus.dart 鉴权后 5 个 catch 分支统一走
  `failAudited`（stopwatch 停表 + `_auditIfNeeded(ok:false)` +
  fail 信封）。新增 2 条 control_bus_test：user 级 handler 抛
  CONFLICT → audit ok:false/errorCode=CONFLICT；admin 级 slow
  命令超时（CommandSpec 新增仅供测试的 `timeoutOverride` 缝把
  60s 压到 50ms）→ ok:false/TIMEOUT。
- **E4 ✅ 文档化**：ecp-design.md §3.2 增补已知限制段（9s vs 60s、
  TIMEOUT 不取消 Dart 执行、以落盘文件+sys.audit 为准），根治随 P3。
- **E5 ✅ 已修**：主清单 `android:allowBackup="false"`（附注释：
  日记导出归档模型 + pin.json 不外泄）。debug 装机 dumpsys flags
  无 ALLOW_BACKUP；release APK aapt2 xmltree 实证 allowBackup=false。

门禁：flutter analyze 0 issue；flutter test **232** 全绿（基线 230
+E3 两条）；`./gradlew testDebugUnitTest` BUILD SUCCESSFUL（3/3）。

### 维护者复验结论（2026-10-12）

**E1–E5 全部通过，同意合 main。** 复验方式（MIX 2S，全新 debug/release
包，非沿用 agent 自证）：

- **E1 偏差裁定：接受，且原交接单修法确属错误。** manifest 接收器
  onReceive 离开 binder 事务、`Binder.getCallingUid()` 恒为自身 uid
  一点属实（agent 装机实证）；DUMP 方案是对该场景的正确门禁。
  复验：合并后 debug 清单 aapt2 确认 receiver 带
  `android:permission="android.permission.DUMP"`；shell uid 2000
  冷启动→ping 全链路通；JVM 3 测随 gradle BUILD SUCCESSFUL 通过；
  API34+ 二次门禁代码 fail-closed 正确。
  **未完成的一项实证（非阻塞）**：run-as 以 App uid 发广播模拟三方
  App 时，被 MIUI 自家 `am` 包装的 INTERACT_ACROSS_USERS 检查提前
  拦截，未走到 AMS 的 DUMP 校验，故"无 DUMP 三方 App 被拒"在本机
  无法用 am 直证；该项以合并清单 + AMS 派发前 permission 强制
  （平台保证）为据，P2 有条件时用 instrumentation 补一条真负向用例。
- **E2 通过**：真机三形态实测——`--dry-run` 与 `--dry-run true`
  预演不删，`--dry-run=false` 与 `--dry-run false` 真实删除
  （meta+.sy 同删，列表即时变化），`--dry-run=maybe` 退出码 2。
- **E3 通过**：232 测试含新增两条（CONFLICT/超时入审计）；真机补证
  已解锁会话内 auth.set-pin 旧 PIN 错误 → 审计出现 ok=false 记录。
- **E4 通过**：设计 §3.2 限制段准确（9s vs 60s、TIMEOUT 不取消
  Dart 执行、以落盘+审计为准），根治挂 P3。
- **E5 通过**：release 合并清单 allowBackup=false；装机 dumpsys
  flags 已无 ALLOW_BACKUP。
- release 隔离复验：release dex 无 CTRL 字符串，清单仅 androidx
  自带 receiver（同 P1 初审）。

## 维护规则

- 修复即更新本文件（快通道，governance §4.2）；
- 新条目给：位置、现状证据、建议；不写无法复现的问题；
- 每 MINOR 版本发布时由维护者顺带复审一次。
