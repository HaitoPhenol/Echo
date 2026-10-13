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
不再写死 3）、Q9 发布节奏（已走功能优先路线至 v0.9）、
**Q10 权限模型威胁对象（2026-10-13 拍板）**：不防"临时持机者"，
防 MCP/内置 agent 自动化通道；本地用户最高权限；chat.send 升 3 级、
diary.export 降 2 级、本地通道放开 PIN 首装；终端页为未来愿景
（详见 ecp-design.md §5/§7，P3 交接单 §G）。

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

## F. ECP P2 施工挂账（2026-10-12，分支 feat/ecp-p2-controllers）

### F1（已裁定：A，已落地）Dart SDK 3.13 formatter 与 main 基线风格不兼容，main 基线 61/103 文件存在格式 churn

**现象与复现**（任一工作树均可复现，与 P2 改动无关）：

```
$ cd echo && dart --version
Dart SDK version: 3.13.5 (stable) (Tue Sep 29 ... 2026) on "linux_x64"
$ dart format --output=none --set-exit-if-changed lib test
Formatted 114 files (48 changed)
```

main 基线（0df9120，v0.10.0+35）上**从未被 P2 触碰的文件**也被判为
需重排（如 test/diary/ui/diary_m5_test.dart）。即当前 SDK 自带
formatter 的输出风格（参数拆行、三元/短构造函数合并、集合字面量
展开等）与入库时代码所用风格整体不兼容；项目无 CI 格式门禁（见
G7），差异此前未暴露。

**发现经过**：P2 步骤 1–10 完成后做提交前 diff 审查，发现 11 个 P1
文件出现大量增删行。逐文件做「`dart format`(main 版) 与工作区」
对比，确认这 11 个文件与 formatter 处理后的 main 版**逐字节相同，
零逻辑变化**（control_bus 的 ArgumentError→USAGE / StateError→
CONFLICT 映射经核 main 已有，非 P2 新增）：

```
echo/lib/src/control/auth/audit_log.dart
echo/lib/src/control/auth/auth_session.dart
echo/lib/src/control/auth/pin_store.dart
echo/lib/src/control/channels/adb_control_channel.dart
echo/lib/src/control/commands/auth_commands.dart
echo/lib/src/control/commands/diary_commands.dart
echo/lib/src/control/commands/sys_commands.dart
echo/lib/src/control/control_app_state.dart
echo/lib/src/control/control_bus.dart
echo/lib/src/control/protocol/control_envelope.dart
echo/lib/src/control/protocol/control_error.dart
```

另 10 个文件为「P2 语义改动 + 同批 formatter churn」混合
（括号内为剔除格式后的语义差异行数）：bootstrap.dart(37)、
commands/control_json.dart(30)、commands/nav_commands.dart(23)、
protocol/command_spec.dart(4)、navigation/nav_destination_specs.dart(20)、
navigation/smart_nav_screen.dart(53)、
navigation/widgets/mechanical_coords_bar.dart(90)、
pages/chat_page.dart(27)、services/chat_store.dart(186)、
test/control/control_test_harness.dart(63)。P2 新增的 6 个 lib 文件
与 4 个测试文件自然也是 3.13 风格。

**影响**：

1. 若直接提交，P2 评审 diff 会混入约 600 行与 P2 无关的换行噪声，
   且跨越 auth/审计等安全敏感文件，增加评审负担与误读风险；
2. 此后任何开发者/agent 运行 `dart format .` 都会产生跨全库的
   大面积噪声 diff，且新代码与旧代码风格持续混杂。

**待维护者选择的处置方案**：

- **A（建议）**：P2 分支只保留语义改动——11 个纯 churn 文件还原
  main；10 个混合文件在 main 旧格式上重施语义（重跑 analyze +
  270 测试）；全库升格式另开独立 `chore: dart format (SDK 3.13)`
  提交，一次性吃掉 48 文件 churn，评审与回滚边界清晰。
- **B**：全项目固定 formatter 版本/风格（如统一到旧版 SDK 输出，
  或 FVM 钉版本），P2 新文件回改旧风格；长期维持单一风格但需
  维护工具链约定。
- **C**：接受 3.13 风格为新基线，P2 连同 churn 一起提交，后续不做
  独立格式提交（P2 diff 噪声不可避免）。

**当前处置（已暂停）**：工作区保持发现时原样，**未做任何还原/
重格式化，未提交**；P2 语义工作（步骤 1–10）已全部完成，门禁
`flutter analyze` 0 issue、`flutter test` 270 全绿（232 基线 + P2
新增 38）。维护者裁定后再完成格式收敛、gradle 门禁与提交；
真机实测（MIX 2S）在提交后另行安排。

**维护者裁定（2026-10-12）：采 A，且 chore 先行，省去"旧格式上
重施语义"的返工。** 独立复核（main 0df9120 临时 worktree，不碰
P2 工作区）：

- 干净 main 上 `dart format lib test` 实测 **103 文件中 61 个需
  重排**（P2 树里的 114/48 是同一事实的剩余视角：多出的 11 个
  是 P2 新增文件，已排好的 21 个触碰文件不在 48 之列）；未触碰
  文件（diary_m5_test 等）同样中招，与 P2 无关，属基线漂移；
- 11 个"纯 churn"文件逐一比对 `dart format(main 版)` 与 P2
  工作区版，**11/11 sha256 相同**，零逻辑变化属实；
- 混合文件剔除格式后语义行数抽查与报告一致（chat_store 186、
  command_spec 4、chat_page 27）；
- 全库 Dart 源码仅在 echo/lib、echo/test（无 integration_test/
  顶层脚本），chore 范围就这两个目录，不扫 build/.dart_tool。

**为什么不是 B/C**：B 钉旧版 formatter 是逆工具链而行（tall 风格
是 3.7+ 事实标准），单人项目无收益；C 让安全敏感文件（auth/审计）
的评审 diff 永久混入换行噪声，不可接受。A 的格式提交零逻辑、
可独立 review/回滚，是标准做法。

**执行顺序（关键：chore 落在 P2 提交之前）**：

1. 从 main 切 `chore/dart-format-313`，在 echo/ 执行
   `dart format lib test`（61 文件），单提交
   `chore: dart format 全库至 SDK 3.13 风格`，提交信息注明：
   formatter 机械输出、零逻辑变化、动机（P2 首提新风格暴露基线
   漂移）；快进合 main。
2. P2 分支整体平移到新 main。由于 P2 触碰文件在工作区里**已是
   3.13 风格**，平移后：11 个纯 churn 文件自动无 diff（已逐字节
   证明）；10 个混合文件自动只剩语义 diff；新文件照旧。无需手工
   在旧格式上重施语义。操作路径：P2 工作先整体落一个 WIP 提交
   保全 → `git rebase --onto <新main> 0df9120`，冲突文件一律取
   P2 侧内容（P2 版即规范终态）→ rebase 后跑 `dart format
   --set-exit-if-changed lib test`（必须 exit 0）。
3. 重开门禁：flutter analyze 0、flutter test 270 全绿、
   testDebugUnitTest 通过；再交维护者做提交前 diff 审查
   （语义 diff 预期：10 混合文件 + 新增 11 文件 + pubspec.yaml
   的 fake_async + pubspec.lock 对应 1 行（见勘误①）+ docs/scripts，
   无 auth 格式噪声），过审后真机 MIX 2S 实测。

**附带裁定（随 P2 处理，不单开）**：

- ~~`echo/pubspec.lock` 当前 diff 是本机 pub 镜像（pub.flutter-io.cn）
  重写 URL 的环境噪声、无版本变化，**不得进 P2 提交**，平移后还原~~
  ——**执行前勘误①（2026-10-12，已核查工作区）：本条与事实不符，
  按下述修正执行。** 实际 `git diff --numstat` 为 1 增 1 删，唯一
  差异是 `fake_async: dependency: transitive → "direct dev"`，无任何
  URL 行变化；这是 P2 把 fake_async 提为显式 dev_dependency 后锁文件
  的**合法同步，应随 P2 提交**。若还原它，锁文件与 pubspec.yaml 矛盾，
  下次 `flutter pub get` 必自动改回。镜像 URL 重写当前不存在；执行中
  若 pub get 触发 `pub.dev → pub.flutter-io.cn` 重写，仅还原 URL 行。
- ~~`.trae/`（agent 工作目录，含本次 plan 文档）加入仓库根
  .gitignore，不入库~~ ——**执行前勘误②（2026-10-12）：`.trae/`
  并非未跟踪目录，直接 ignore 会造成半进半出，需维护者二选一后
  再执行。** 现状：该目录已有 10+ 个跟踪文件（历史 plan：
  diary_m2_editor_plan / m4_templates_plan / m5_persistence_export_plan；
  `.trae/skills/*/SKILL.md`），既有约定是「plan/skill 入库」；
  .gitignore 对已跟踪文件不生效。选项：**a)** 确要改约定——加 ignore
  并 `git rm -r --cached .trae`（工作区文件保留、历史可溯），作为
  独立小提交，不混进 P2；**b)（建议）** 维持约定——本次
  `.trae/documents/ecp-p2-controllers_plan.md` 照常随 P2 入库，
  不做 ignore（与三个历史 plan 一致，零额外动作）。
- G7（无格式 CI 门禁）维持挂账：本次先靠"提交前 format-exit-0"
  人工纪律，是否把 format 检查接进 scripts/nightly 随 P3 决定，
  不在 P2 扩面。

**执行结果（2026-10-12，维护者按本裁定操作）**：

- 两条勘误经核查均属实并采纳：lock 仅 fake_async 一行合法同步；
  `.trae/` 按选项 b 维持入库约定，P2 plan 照常随 P2。
- `chore/dart-format-313`（main 上 **9c452a1**）：61 文件
  dart format 机械重排，二次 format 幂等；该提交上 analyze 0、
  **flutter test 232 全绿**，零行为变化。已快进合本地 main
  （**未 push**，与 origin/main 领先 1 个提交，待用户发话）。
- P2 整体 rebase 平移到 9c452a1：4 个文件冲突
  （control_json/nav_commands/mechanical_coords_bar/
  control_test_harness，均在预期 10 个混合文件内），全部取 P2 侧；
  11 个纯 churn 文件平移后自动归零、不出现在 diff 中。
- **exit-0 闸门抓出 5 个漏网文件**：mechanical_coords_bar.dart
  与 4 个 P2 新文件（console_stats_service + 3 个 commands 测试）
  在原工作区里并未达到 3.13 规范（"新文件自然合规"的判断不成立），
  已统一 format，全树 `dart format --set-exit-if-changed` exit 0。
- 平移后 P2 最终 diff：28 文件 = 10 混合文件（只剩语义）+
  11 新增代码文件 + pubspec.yaml + pubspec.lock（各 1 行合法同步）
  + 3 个 docs + scripts/echo-cmd + P2 plan，无 auth/审计格式噪声。
- 重开门禁：flutter analyze **0 issue**、flutter test **270 全绿**。
- **JVM 单测已闭环（2026-10-12 22:57）**：用户在系统终端
  `./gradlew testDebugUnitTest` → BUILD SUCCESSFUL（测试任务当时
  内容指纹 up-to-date，git 证据：android/ 自 27c0c30 零改动）。
  维护者随后借助该外部 daemon 执行
  `cleanTestDebugUnitTest testDebugUnitTest --no-build-cache`
  强制真实重跑（非 UP-TO-DATE / 非 FROM-CACHE）：**3 tests，
  0 skipped / 0 failures / 0 errors**，报告时间戳 2026-10-12
  13:57:23Z（即当时）。沙箱内自启 daemon 仍不可用（snap flutter
  路径不可写），但连接沙箱外 daemon 可正常工作。
- 工作区已 mixed reset 为「相对 9c452a1 的纯语义改动」交回 P2
  agent 组织正式提交（16 改 + 12 新增未跟踪），WIP 保全提交已消解。

### F2（已修复，待维护者复验，2026-10-12）chat.send 正文进入审计，违反设计 §6「正文仅记长度」

**提交**：8b6679f（feat/ecp-p2-controllers）。维护者逐文件语义审查 +
两名独立子代理交叉验证（2/2 确认）。

**现状证据**：

- [control_bus.dart:39-43](../echo/lib/src/control/control_bus.dart#L39-L43)
  `auditRedactedParams = {pin, oldPin, newPin}`，只脱敏 PIN 类键；
- [control_bus.dart:214-231](../echo/lib/src/control/control_bus.dart#L214-L231)
  `_sanitizeForAudit` 对普通 String：**≤80 字原样保留**、>80 字截
  前 80 字 + `…(+n)`；
- [chat_commands.dart:104-130](../echo/lib/src/control/commands/chat_commands.dart#L104-L130)
  chat.send 为 user(2) 级（≥2 级必入审计，见
  control_bus.dart:196-197），必填 `text` 即消息正文；
- 后果：一条「你好」经 adb chat.send 后，`sys.audit` 回读的条目
  paramSummary.text 为原文全文；长消息留前 80 字。
- 设计 [ecp-design.md §6](ecp-design.md) 原文：参数摘要「长文本截断、
  **绝不记录 PIN/正文全文，仅记长度与目标 id**」。PIN 已按长度
  脱敏，正文没有——P2 是首个携带自由正文的命令，缺口在本批首次
  实体化。

**定级**：minor（debug-only、内存 200 条环形缓冲、adb/2000 可达），
但属安全契约缺口，**合 main 前必修**。

**修复要求**：

1. 审计对正文类参数采用与 PIN 同构的「仅长度」策略：为参数增加
   正文标记（如 `ParamSpec(auditRedact: true)`，在 chat.send 的
   `text` 上声明；不要只在总线硬编码键名 `text`，未来 P4 播种等
   可能有别的正文键）；`_sanitizeForAudit` 对标记参数输出
   `<redacted:N>`（N=trim 前或 trim 后长度需在提交说明写明并与
   测试一致——建议 trim 后实际落库长度）；
2. 会话 id 等其他参数照常记录（满足"长度与目标 id"）；
3. 补测试（control_bus_test 或 chat_commands_test）：chat.send
   成功/失败两条审计中 paramSummary 不含任何正文字面、仅
   `<redacted:N>`，N 正确；
4. 门禁照旧：analyze 0、flutter test 全绿（应 271）、format exit 0；
   完成后回执本条，维护者复验 → MIX 2S 真机（含多行
   `--text-stdin`、badge 状态机、console.refresh 与读数条同步、
   release 无 CTRL 复核）。

**备案（不阻塞）**：8b6679f 提交说明「11 条全部 owner 级」措辞
有误（实际读 owner1/写 user2，代码与手册 §6–§8 一致），无需改码。

**修复回执（2026-10-12，快通道，待维护者复验）**：

1. `ParamSpec` 新增 `auditRedact: bool = false`（command_spec.dart）：
   清单驱动脱敏，总线不再硬编码任何键名——原
   `ControlBus.auditRedactedParams` 静态集合已删除；P4 新正文键只需
   在清单标注。toHelp 在标记时输出 `auditRedact:true`（附加字段，
   不影响既有消费方）。
2. `_sanitizeForAudit(spec, args)` 从 spec.params 派生脱敏集合；
   标记参数输出 `<redacted:N>`，**N 取 trim 后落库长度**（空白文本
   N=0，与 store.send 的 trim 语义一致）；成功/失败共用同一方法。
   chat.send 的 `text` 与 auth 的四个 PIN 参数（pin/newPin/
   newPinConfirm/oldPin）全部挂标记，PIN 脱敏行为零回退。
3. 测试：chat_commands_test 新增 1 用例（+1=**271**），单测内覆盖
   三条审计——发送成功（N=12、ok=true）、未知会话 NOT_FOUND
   （N=12、ok=false）、空白文本 USAGE（N=0）：id 照常可见，
   paramSummary 序列化结果不含正文字面；control_bus_test 原 PIN
   脱敏用例改为清单驱动写法并加「未标记者落字面」对照，另证
   trim 长度语义（`'  123456  '` → 6 而非 10）。
4. 门禁：flutter analyze 0；flutter test **271 全绿**；
   `dart format --set-exit-if-changed lib test` exit 0。
5. 备案项确认：本修复提交说明按实际级别措辞（读 owner1 / 写 user2）。

**MIX 2S 真机盲跑回执（2026-10-13 00:00–00:10，debug 包全新安装
+ pm clear 首装，echo1 PIN；证据 artifacts/device/f2-*.png，未入库）**：

- 装机：`app-debug.apk`（9bc8053 代码）冷启正常；首装 auth.set-pin
  经 stdin 文件喂入成功；auth.unlock 至 3 级。
- console：snapshot/refresh 回真机读数（model "MIX 2S"，tempC
  32.0→33.0 随时间变化，powerW 真实波动 0.0→0.7W）；refresh 返回
  新快照；sys.info 同源（0.10.0+35）。refresh 后立即截图，读数条
  T/P 与快照同帧一致（同一 ConsoleStatsService 驱动，f2-10）。
- badge 命令矩阵全通：notify→notification；exception→exception；
  view 清通知但不清异常；resolve 清零；非法 `--page ghost` →
  USAGE/exit 2。导航胶囊绿/红刻度在 f2-05/f2-03 可见；面板
  「处理异常」按钮闭环（f2-09）。观察（非缺陷）：console 调试面板
  的第三按钮由面板本地「待处理」态驱动，命令直写 NavBadgeService
  的异常只体现在导航刻度——调试夹具与服务的既有分工，契约未承诺同步。
- chat：模拟 3 会话；list/get（游标=msg-3、hasMore）/mark-read/
  open 回读全对；多行预览取首行；点按未读行走同一
  ChatSessionController.open 路径，截图实证绿点消失（f2-05→f2-06）。
  P2 无会话详情 UI（点按契约即触发已读，与手册 §6 一致）。
- **F2 真机实证**：`--text` 短消息（N=16）、`--text-stdin` 三行
  多行（N=22，内部换行完整保留）、未知会话失败（N=17，NOT_FOUND
  exit 5）；`sys.audit` 三条 paramSummary 均为 `<redacted:N>`、
  id 照常可见，对整份审计 JSON 扫 `F2SECRET/F2-PLAIN/FAIL-LITERAL`
  零命中。`--text`/`--text-stdin` 同传 → exit 2 互斥。
- release 复核（app-release.apk 52.2MB）：dex 对
  DebugControlReceiver/echo/control/AUTH_REQUIRED/chat.send/
  badge.notify/console.refresh 六特征串命中全 0；合并清单仅 2 个
  androidx 自带 receiver，无 ECP 组件。
- 结论：P2 + F2 真机无阻塞项，待维护者复验 F2 代码后可合 main。

**维护者复验结论（2026-10-13）：F2 通过，P2 同意合 main。**

- 代码复核：`ParamSpec.auditRedact` 清单驱动实现与交接要求一致；
  脱敏集合从 spec.params 派生，PIN 四参数（pin/newPin/newPinConfirm/
  oldPin）全部挂标，原硬编码集合删除后 PIN 脱敏零回退；N 取 trim
  后长度、成功/失败共用 `_sanitizeForAudit`；拒绝路径（裁决前 args
  已解析）同样脱敏。未标记参数（如 id）落字面满足「长度+目标 id」。
- 测试复核：新增用例覆盖成功/USAGE(N=0)/NOT_FOUND 三审计路径 +
  未标记对照；维护者独立复跑 format exit 0、analyze 0、
  **flutter test 271 全绿**；F2 零 android/ 改动，JVM 3/3 延续。
- 真机独立抽检（MIX 2S，非沿用盲跑自证）：发送
  `"  MAINTAINER-PROBE-7731  "`（trim 后 21）成功、
  `"FAIL-PROBE-9988-LITERAL"`（23）NOT_FOUND 失败；sys.audit
  两条分别 `<redacted:21>` / `<redacted:23>`、id 可见，整份审计
  JSON 对两特征串 grep 命中 **0**；盲跑历史条目 N=16/22/17 与回执
  吻合。命令结果信封仍含正文属正常（设计 §6 只约束审计）。
- 盲跑截图证据核验：f2-01~10 时间戳（23:51–00:01）与回执吻合，
  读数条真机值（MIX 2S / 33.0°C / 0.1W）、多行首行预览
  （「多行第一行」）属实；两条观察记录（调试面板本地待处理态、
  无会话详情 UI）与手册契约一致，不挂账。
- 验毕测试机已 pm clear（PIN/文件会话/模拟会话清空），ALLOW_BACKUP 仍为 0。

## G. ECP P3 施工交接单（2026-10-13，分支 feat/ecp-p3-slash-console）

> 设计依据：ecp-design.md §5（2026-10-13 用户裁定修订版）、§7
> （含终端页愿景）、§10；手册 ecp-commands.md 已同步修订并作为本单
> 一部分提交。**先读修订后的 §5 再动手。** 本期验收主线：MIX 2S
> debug+release 双包走查；日常用机 M6 钉 0.10.0，不装机，双真机
> 第二台走查排 M6 收官后补，不阻塞合 main。

### G0｜权限模型修订（先做，独立提交，先于 UI）

级别语义重定义见设计 §5.1（威胁模型＝自动化通道，本地用户最高
权限）。代码改动：

1. **`chat.send` 2→3 级**：[chat_commands.dart](../echo/lib/src/control/commands/chat_commands.dart)
   `level: ControlLevel.user→admin`；**保持非 destructive**（不弹
   确认卡、不要 --confirm）；summary/手册措辞已改，代码 summary 同步。
2. **`diary.export` 3→2 级**：[diary_commands.dart:282-289](../echo/lib/src/control/commands/diary_commands.dart#L282)
   `level: admin→user`、**删除 `destructive: true`**（不再要求
   --confirm；注意总线 confirm 推导与 help 输出随之变化）；`slow` 保留。
3. **PIN 首装门禁放开到本地通道**：[auth_commands.dart:112-122](../echo/lib/src/control/commands/auth_commands.dart#L112)
   删 `buildMode==debug && channel==adb` 条件，改为通道本地性判定——
   在 `ControlChannel`（[command_spec.dart:42](../echo/lib/src/control/protocol/command_spec.dart#L42)）
   加 `bool get isLocal`（adb/slash=true，mcp=false；未来新增通道默认
   false，注释写明），首装条件改为 `ctx.channel.isLocal`；拒绝文案
   更新（不再提 debug/adb）；`pin-init` 审计条目保留不变。
4. **测试**（基线 271，只增不减）：
   - slash/adb 未解锁：`chat.send` → AUTH_REQUIRED(need 3)；解锁会话内
     连续两次成功（不要求 confirm）；MCP 假通道（start0/max1）任何级别
     发送均 AUTH_REQUIRED；
   - `diary.export`：slash/adb 无解锁直接成功且无需 confirm；MCP 拒绝；
   - pin-init：slash 在 buildMode=release 且未设 PIN 时初始化成功；
     adb/debug 原路径保持；mcp 拒绝；已设 PIN 后首装路径不可达
     （走改 PIN 流程）；
   - 清单一致性测试中 export/chat.send 级别断言同步；3 级命令均标
     destructive 的既有断言若存在需改为"destructive 子集需 confirm"。
5. G0 收口：analyze 0 / flutter test 全绿 / format exit 0，**独立
   一个提交**（`feat(ecp): P3-G0 权限模型修订…`），便于单独复审。

**维护者复审结论（2026-10-13，提交 8df045b）：G0 通过，可进 G1。**

- 生产代码 6 文件与本单 G0.1–G0.3 逐条对应，无夹带；文档/注释四处
  过时表述（含 pin_store、ControlBusHandle.buildMode）同步干净。
- **确认门语义亲核**：[command_spec.dart:167](../echo/lib/src/control/protocol/command_spec.dart#L167)
  构造期推导 `requiresConfirm = confirmRequired ?? level==admin`，
  总线 [auth_session.dart:82](../echo/lib/src/control/auth/auth_session.dart#L82)
  裁决只认该字段，`destructive` 是 help/UI 元数据不参与裁决。故：
  chat.send 升 admin 后**必须**显式 `confirmRequired:false`（否则默认
  要 --confirm），agent 加得正确；export 降 user 后默认免确认；
  set-pin 总线特判（二次输入 PIN 即确认）保留。
- **清单双向断言亲核**（manifest_consistency_test.dart:59-77）：
  destructive→requiresConfirm 与 admin+requiresConfirm→destructive，
  本就是「子集」语义，chat.send（admin/非破坏/免确认）合法落入，
  无需改测试；提交说明属实。合法三组合：prune/reset/seed
  （admin+破坏+确认）、chat.send（admin+非破坏+仅解锁）、
  set-pin（总线特判）。
- 测试矩阵评审：三通道 × chat.send（need=3 / mcp 恒拒 / adb+slash
  解锁后 confirmed:false 连发）、export（未设 PIN 直放落 zip / mcp
  AUTH_REQUIRED）、release+slash 首装成功+pin-init 审计、mcp
  authDenied 且 PIN 未被设、已设后走改 PIN 缺 oldPin 报 USAGE；
  被拒发送零污染有 `hasLength(3)` 兜底。夹具每测试重建，
  group setUp 的 set-pin 每次均走首装路径，生命周期正确。
- echo-cmd 脚本无需改：confirm 为通用透传开关，对 export 无硬编码。
- **门禁独立复跑（非沿用提交说明）**：format exit 0 / analyze 0 /
  **flutter test 275 全绿**；零 android/ 改动，JVM 不涉及。
- 设计 §11 旧措辞「3 级均 destructive 且需确认」已随签复订正为
  子集语义。**G0 行为变化（export 免确认、send 需解锁、slash 首装）
  的真机实证不单独装机，并入 G4 debug+release 双包走查。**

### G1｜slash 控制台核心（`lib/src/control/slash/`，与入口解耦）

- **`ControlConsoleCore`**（ChangeNotifier 风格，与项目既有状态管理
  一致，不引入框架——保护项 §D.5）：`submitLine(String)` → 行解析 →
  `bus.execute(channel: ControlChannel.slash, …)` → 信封流（结果历史
  列表、进行中态、slow 命令 60s 超时态，复用总线超时不另造）；
  命令历史（↑↓，会话内）。
- **行解析器**（纯 Dart，重点单测）：`ns.verb --flag --k=v --k v`、
  引号、尾随 `?`/`--help` 出 man；未知参数 USAGE 的语义与 adb 侧
  对齐（同一套 CommandSpec，禁止两套校验）。
- **补全引擎**（纯 Dart）：`visibleSpecs` 驱动三段式
  （命名空间→动词→参数），带类型提示与摘要；release 下 debugOnly
  命令注册侧已物理跳过，补全天然不可见，**不要加二次黑白名单**。
- **结果视图模型**：信封 → 结构化渲染模型（列表成表 / 键值 / JSON
  文本），JSON 可长按复制；搜索卡片（G2）与未来终端页（愿景见 §7）
  共用这一个接口。
- 多行进文本：adb 侧靠 `--text-stdin`，slash 面板需自有方案
  （如输入区展开/换行手势），在 plan 文档写明，不改变命令参数契约。
- 测试：解析、补全分段、历史、视图模型、超时态的纯 Dart 单测。

**维护者复审结论（2026-10-13，提交 43ff0c9）：G1 通过，可进 G2。**

五件套（line_parser/completion/result_view/console_core + barrel）
逐文件通读，关键安全/契约点亲核：

- **校验不双轨**：解析器只管词法/形状，值一律 String 入 Map，类型/
  必填/未知参数/鉴权仍只由总线裁决（合成 USAGE 仅限引号未闭合、
  裸位置参数等词法错），与交接单一致；布尔名单从 spec.params 派生
  +confirm/stay/help 三个全局开关，无硬编码业务名单。
- **help 改道正确**：`?`/`--help` 统一改走 `sys.help --command`，
  entry.cmd 保留被查命令；0 级在 slash 起始 2 级内直放；release 下
  查 debug-only 命令自然"不存在"，无风味泄漏。
- **历史脱敏截断**：遇 auditRedact 参数即停止重建（不留占位符防
  召回重发），且历史在执行前写入——鉴权被拒的行同样安全，有测试
  钉死（secret-alpha / text 在 id 前两 case）。
- **超时不自造**：慢命令经真 bus + timeoutOverride 验证 TIMEOUT
  视图，Core 无 Timer；dispose 后在飞调用静默不通知。
- **G3 接缝双保险**：源码正则禁 Widget import + 假第二消费者纯
  Dart 挂载（notifies≥2、KeyValueView 回填）均有测试，核心确实
  可被未来终端页独立复用。
- **补全 release 裁剪**：引擎只吃 visibleSpecs，debug-only 物理
  不可见有 release 风味测试；--confirm 仅 requiresConfirm 命令出现
  （chat.send 不出现）有断言。
- 多行 submitMultiline 互斥/string 类型/未知命令/换行保留四 case
  齐全；手册 §1.1 行语法契约与实现逐条一致。
- **门禁独立复跑**：format exit 0 / analyze 0 / **flutter test 336
  全绿**（275+61）；零 android/、零 UI 装配，范围与交接单相符。

**Nit（不阻塞，建议 G2 顺手清，不单开提交）**：
① [completion.dart:227](../echo/lib/src/control/slash/completion.dart#L227)
布尔三元两分支完全相同，是死表达式，直接用 `'--${cli(p)} '`；
② [console_core.dart](../echo/lib/src/control/slash/console_core.dart)
`_historyLine(displayLine, inv)` 的 displayLine 形参函数体从未使用
（submitMultiline 传的 `… <多行>` 是无效参数），删形参；
③ entries 结果流无上限（history 有 100、audit 有 200），搜索栏
会话期量级有限不致问题，终端页正式立项时定裁剪/分页策略，此处挂账。

真机不涉及（零 UI 装配），G1 无实证项；行为全部在 G4 随 UI 走查。

### G2｜搜索栏指令态 UI（最薄注入，禁止顺手重构上帝类）

- 搜索栏首字符 `/` 进指令态（提示符 ⌘/变色、Esc 退回搜索语义）；
  SmartNavScreen（G1 挂账 1525 行）/search_capsule（G2 挂账 1124 行）
  **只做注入与浮层承载，不做结构拆分**；
- 3 级 UX 闭环：AUTH_REQUIRED 信封 → PIN 面板；**从未设 PIN 时引导
  首装**（两输一致 → set-pin pin-init → 自动 unlock → 原命令自动
  重放），release 必须走通；已设 PIN → unlock → 重放；
- destructive 命令（prune/reset/seed）执行前确认卡（回显全名+影响
  范围）；chat.send 等非破坏性 3 级不弹卡；
- `nav.goto` 后默认收起指令台，`--stay` 保留；
- 回前台锁态即时刷新（会话即焚由 AuthManager.attach 兜底，UI 只
  消费 auth.status，不另造生命周期监听）；
- widget 测试：指令态进出、补全选择、PIN 首装→重放全链路（假
  bus/假 AuthManager）、确认卡、↑↓ 历史；release 风味用
  ControlBuildMode.release 构造补全/注册断言。

**维护者复审结论（2026-10-13，提交 ca1cfdd）：G2 代码质量通过；
1 个一行安全 UX 项须在 G3 前修掉，其余挂账。门禁独立复跑 format
exit 0 / analyze 0 / flutter test 353 全绿（336+17）。**

注入纪律亲核（本轮审查头号约束）：
- smart_nav_screen 仅 +40 行：字段/装配/dispose/onChanged 与
  onSubmitted 分流/reset 调 hostClosed/一层 Positioned 浮层，
  1500+ 行上帝类零重构；未走 ControlBootstrap 的路径 `_slash==null`
  自动降级纯搜索（widget 测试与既有页面测试因此零改动）；
- search_capsule 仅 +74 行：两个新字段（默认关）、建议区
  `if (!slashMode)` 让位、终端符/提示语/回车键，键事件只在
  slash 态包一层——搜索态路径字节级等价；
- slash_ui/ 与 slash/ 分层正确：核心零 Widget 红线由 G1
  slash_seam_test 继续钉（本轮未松动），G3 无新代码面。

3 级闭环逐跳亲核（真 bus + release 风味测试佐证，非自报）：
- chat.send spec = admin + 显式 `confirmRequired: false`
  （[chat_commands.dart:114-117](../echo/lib/src/control/commands/chat_commands.dart#L114-L117)），
  预判不挂卡、解锁即连发，与 Q10 裁定一致；slash 通道 start=user(2)
  /max=admin(3)，mcp guest(1)/owner(2) 物理挡死写级别；
- set-pin 首装不死锁：总线 check 对 `auth.set-pin` 显式特判放行
  （[auth_session.dart:82](../echo/lib/src/control/auth/auth_session.dart#L82)），
  handler 内双路径自裁——未设 PIN 要求 `channel.isLocal`
  （=adb||slash，注释钉死未来网络通道必须 false），改 PIN 要求
  解锁会话 + oldPin；release slash 首装全链路有测试（两输/不一致
  回退/落盘 verifyPin/slash 会话颁发）；
- 重放行严谨：确认卡路径追加 ` --confirm` 词法重投，解锁后重放
  不再撞 CONFIRM；CONFIRM_REQUIRED 信封有兜底补卡；错 PIN 原地
  重试、冷却剩余秒在结果卡呈现；cancelPin 不留重放；
- nav.goto 收起四分支齐（成功收/--stay 不收/失败不收/`?` 帮助
  不收），helpIntent 判断正确（改道后 entry.cmd 保留被查名）；
- 焚会话联动正确：expire 有会话才写审计+通知，paused 无会话补
  一次纯 UI 通知（不写审计）→ 首装第一遍暂存随切后台清空，有
  测试；unlock/lock 通知点对称；busy 期间不被通知打断。
- G1 三 nit 已清（死三元/无用形参/entries 挂账注释落在 core）。

**须修（G3 前，一行级）：确认卡回显丢原参数。**
[slash_sheets.dart:317](../echo/lib/src/control/slash_ui/slash_sheets.dart#L317)
显示 `'${pending.cmd} --confirm'`，而 PendingConfirm.line 带着用户
完整原行——`diary.prune --before 2026-10-01` 在卡上只剩
`diary.prune --confirm`，**用户核对不到删除范围**（summary 只是
一句话描述）。破坏性命令的影响范围恰恰全在参数里。改为回显
`'${pending.line} --confirm'`（长行允许换行/省略号均可），controller
测试可顺手加一条带参 pending 的断言。

> **已闭合（2026-10-13，提交 71445b0）**：回显改为
> `${pending.line} --confirm` + softWrap 自然换行；新增 3 条断言
> （模型层：带参 pending 保真、解锁后带参原行+--confirm 重投；
> widget 层：卡面与结果回显均含 `--before 2026-10-01`），测试
> 353→356。维护者独立复跑 format 0 / analyze 0 / flutter test 356
> 全绿，工作区零污染。G2 复审全部事项关闭。

挂账（不阻塞，终端页立项/后续硬化再议）：
① controller `_onCoreChanged` 只认 entries.last：多条 3 级命令快速
连提且完成乱序时，非最新条的 AUTH/确认不弹面板（错误仍留结果流，
可 ↑ 召回重试；AUTH 为总线同步裁决，实际难触发）；
② paused 与在飞 unlock 的微秒级竞态理论上可在后台颁发短命会话，
需要 resume 复核或在飞取消，本期窗口极小且 G4 不可稳定复现；
③ 纯触屏无 Esc/↑↓：Esc 有清空首字符与点 scrim 兜底，命令历史无
触屏入口（手册已诚实写明"物理键盘 ↑↓"），G4 真机记录触屏体验，
随终端页正式立项解决；
④ 指令态仍照跑 searchAll 一次（结果区不挂载、无泄漏，注释自承，
可忽略）。多行正文撞 AUTH 不重放（需重新展开提交）是**有意设计
且测试钉死**——避免敏感正文二次发送，符合安全优先，不是缺陷。

### G3｜终端页接缝（留饼，不建页面）

- 不新增页面、不占导航位（现有「终端」页 id=console 不动）；
- 验收接缝：`ControlConsoleCore` + 渲染接口不 import 任何搜索栏
  Widget（可写一条静态约束测试或 debug 最小挂载证明第二消费者
  可挂即可）；正式终端页（裸命令输入/JSON 美化/滚动回溯）另立项。

**维护者验收结论（2026-10-13，随 71445b0 复核）：G3 通过，
P3 代码侧全部完成，进入 G4 真机。**

G3 三条验收项逐条取证：
1. **不建页面、不占导航位**：G1/G2 文件清单中 nav_destination_specs
   零改动；现有「终端」页 id=console 未动；G2 仅在既有搜索屏内
   叠一层 Positioned 浮层，无新路由/导航目的地；
2. **核心不绑搜索栏**：`lib/src/control/slash/` 全目录唯一 flutter
   import 是 console_core 的 `package:flutter/foundation.dart`
   （ChangeNotifier），对 widgets/material/cupertino 与
   navigation/slash_ui 零依赖；G1 的 slash_seam_test 静态约束
   （禁 Widget import 正则）在 G2 后仍绿；
3. **第二消费者可挂**：slash_seam_test 的假终端消费者（纯 Dart
   类订阅 ChangeNotifier + 独立使用 parser/completion/view 三件套）
   在 356 全套测试中通过，未来终端页换皮复用路径成立。

无新增代码、无新测试，G3 为纯验收阶段。

### G4｜真机（MIX 2S，debug+release 双包）

release 全新安装走完整链路：`/` 指令态 → 3 级命令触发 PIN 引导首装
→ chat.send 会话内连续发送不重复弹 PIN → 切后台再回来会话已焚、
需重解 → diary.export 无 PIN 直接成功 → diary.prune 确认卡预演/
真删 → diary.reset/clock.set 在补全中不出现（debugOnly）。
release 包 dex/清单无 adb 入口复核（同 P1/P2 六特征串）。验毕
pm clear。

#### G4 首轮结果（2026-10-13，release 全新装 + MIX 2S 真机）：**不通过，2 个阻断缺陷回派修复**

已通过项（证据 artifacts/g4-r1-*.png）：

- **release 冷启动/指令态/几何**：长按灰色导航胶囊呼出搜索，
  tap(300,2078) 聚焦，输 `/` 出终端符与候选；命名空间计数
  sys 5 / auth 4 / nav 2 / diary 5 / chat 5 / console 2 / badge 5。
- **debugOnly 补全裁剪（真机实证）**：`/diary.` 动词恰 5 个
  list/get/ensure/prune/export，**无 reset**；`/sys.` 恰 5 个
  ping/help/info/status/audit，**无 clock.set**；级别标注正确。
- **dex/清单无 adb 入口**：app-release.apk classes.dex（567KB）
  对 DebugControlReceiver/echo/control/AUTH_REQUIRED/chat.send/
  badge.notify/console.refresh 六串命中全 **0**；清单仅
  MainActivity + ShareFileProvider + 两个 androidx receiver，
  无 DebugControlReceiver。
- 轻微（不阻断，挂账）：libapp.so 中 `clock.set` 字面量残留 1 次
  ——来源 [command_spec.dart:239](../echo/lib/src/control/protocol/command_spec.dart#L239)
  协议层 `controlledVerbs` 白名单（parser 用，无 debug 守卫）；
  命令注册侧已物理跳过（真机补全不可见、不可达），无功能风险，
  仅为字符串残留。`diary.reset` 0 命中。

**G4-BUG-1（阻断，触屏路径全灭）：IME"完成"提交即失焦，指令台 150ms 后自毁**

- 位置：[smart_nav_screen.dart:357-371](../echo/lib/src/navigation/smart_nav_screen.dart#L357-L371)
  `_handleFocusChange` + [slash_console_controller.dart:229-239](../echo/lib/src/control/slash_ui/slash_console_controller.dart#L229-L239)
  `hostClosed()`。
- 机理：MIUI 豆包/搜狗 IME 点蓝色"完成"键（触屏用户唯一提交动作，
  imeAction done/search）触发 onSubmitted 后**主动 hide 键盘 →
  搜索 TextField 失焦**；失焦 150ms 定时器判定后执行
  closeSearch()+_resetSearchPanel()→hostClosed()，同步清空
  `_confirm`/multiline/`_pin`/`_pendingReplay` 并 bind('')。
- 实测（artifacts/g4-s0/s1/s2.png，0.2/0.7/2.2s 三时序；
  g4-r1-confirm-card.png、g4-r1-reopen.png）：输全 `/diary.prune`
  点完成，0.2s 面板开始关闭，确认卡从未可交互，重开后面板纯搜索态、
  挂起态全失。`/sys.ping` 同样提交后即关，结果流不可见。
- 后果：纯触屏下确认卡不可点、PIN 首装/解锁面板不出现、AUTH 后
  重放命令丢失、结果不可见——G4 清单全部交互链路（3 级命令、
  chat.send 连发、prune 预演/真删）在第一步提交即断。
- 测试缺口：Widget 测试模拟 onSubmitted 不经过真实 IME hide，
  焦点链不触发，故 G2 测试 356 全绿未暴露。
- 修复约束（交业务 agent）：slash 指令态（active）或存在挂起交互
  （confirmPending / pin.visible / multiline / 有结果 entries）时，
  失焦定时器不得 closeSearch/reset；显式退出路径（BACK、scrim、
  ESC、nav.goto 成功收起）行为不变；普通搜索态行为不变。补 Widget
  测试：提交后焦点丢失，确认卡/PIN 面板仍在且可交互。

**G4-BUG-2（阻断，点号形态补全损坏 + 精确命令无法回车提交）**

- 位置：[completion.dart:189-211](../echo/lib/src/control/slash/completion.dart#L189-L211)
  `_verbs`（点号形态 insert 为 `verb ` 而 replaceStart=body 首字符）
  与 [slash_console_controller.dart:186-200](../echo/lib/src/control/slash_ui/slash_console_controller.dart#L186-L200)
  applySelected/applyCandidate；连带 handleEnter 判定（550-551 行）。
- 机理：`/sys.pi` 动词段候选 insert=`ping `、replaceStart=1，
  应用后文本 = `/ping `——**namespace 被吞**（空格形态
  `/sys pi` replaceStart 正确，不受影响）。另：命令敲全
  `/sys.ping` 时动词段仍返回唯一高亮候选，hasCandidates=true，
  物理回车走补全把文本改坏（实测 artifacts/g4-ping-enter.png：
  `/sys.ping` 回车 → `/ping `）而非提交。
- 后果：点号形态（主推用法）点候选或物理回车必损坏命令；触屏点
  `/diary.` 候选（g4-r1-diary2 主交互）同样必现。
- 测试缺口：[completion_test.dart:42-51](../echo/test/control/slash/completion_test.dart#L42-L51)
  段二只断言候选 label/replaceStart，从无"应用后完整文本"断言；
  controller 测试未覆盖点号形态 applySelected 与"精确命令回车提交"。
- 修复约束：点号形态应用候选后须保留 ns（如 `/sys.ping `）；
  当前尾串已精确等于某命令（或应用候选后文本无变化）时 Enter
  必须放行给 onSubmitted 提交。补纯 Dart 测试钉死两类场景。

**G4-BUG-3（阻断，修复后复验新发现：确认卡/PIN 卡底部按钮在 MIUI 键盘收起后可见不可点，触屏确认路径全灭）**

- 复现：MIX 2S（豆包 IME）输 `/diary.prune` 后点蓝色"完成"或物理
  ENTER 提交 → 破坏性命令确认卡出现 →「确认执行」「取消」点按无任何
  反应（右上角 X 同样点不中）。release/debug 双包均现；HOME 切后台再
  回前台不恢复。证据：artifacts/g4-bug3.mp4（10s 内 4 次点按三按钮
  画面零变化）、g4-dbg-tapx2.png（debug 条纹
  `BOTTOM OVERFLOWED BY 33 PIXELS`）。
- 机理（两层叠加，均已用证据闭合）：
  1. **IME hide 后窗口 metrics 卡滞，视觉/触摸坐标缩放错位**：键盘收起
     后系统侧 mImeHeight=0、窗口 frame 恢复 [0,0][1080,2160]，但 Flutter
     逻辑画布高度卡在键盘压缩值（实测约 1751，缩放比 ≈0.81）。引擎仍按
     1751/2160 归一化触摸点：物理 y>1751 的点击全部落在逻辑底边，按钮
     （物理 y≈1788）与输入胶囊永不可点；物理 (905,1385) 被映射到逻辑
     ≈1123，实际命中参数列表 `--stay` 行并把 token 插入命令行
     （g4-bug3-tile.png 第 6 帧起命令变 `/diary.prune --stay`）。重新
     长按呼出搜索可恢复一次，提交后再次卡滞。
  2. **SlashCommandLayer 高度约束导致 Sheet 底部溢出**：
     [slash_command_layer.dart:47-64](../echo/lib/src/control/slash_ui/slash_command_layer.dart#L47-L64)
     以 `mq.size.height * 0.45` 为最大高（压缩态仅约 788），Column 中
     CompletionBar/ResultsList 与固有高度的 SlashSheetHost 争高，确认卡
     [slash_sheets.dart:343-368](../echo/lib/src/control/slash_ui/slash_sheets.dart#L343-L368)
     按钮行被挤出 RenderBox 边界 33px——Flutter 对 size 外的点不做
     hitTest，即使坐标映射正确按钮仍不可点。PIN 面板同理在风险中。
- 影响：纯触屏用户（无物理键盘）**无法确认任何 3 级破坏性命令**，
  R1 的 PIN 首装/重放链路也无法通过触屏走完；BUG-1 修复保住的卡片
  变成看得见点不动的死卡。
- 修复方向（业务侧择一或组合，需真机实测）：
  - 根因 1：排查/消除对 adjustResize 压缩窗口高度的依赖（如
    Scaffold resizeToAvoidBottomInset:false + 自行消费 viewInsets，
    使窗口逻辑高度不随 IME 改变，坐标永不缩放）；或提交后主动触发一次
    metrics 恢复。须在 MIX 2S 豆包 IME 真机验证触摸坐标准确。
  - 根因 2：Layer 在高度不足时优先压缩 ResultsList（Expanded/最小 0）并
    保证 Sheet 按固有高度完整布局、永不 overflow；或确认/PIN 卡改走
    showModalBottomSheet 等独立路由挂载，脱离 Layer 高度约束。
- 测试缺口：现有 widget 测试给 Layer 的高度约束恒充足，未模拟键盘压缩
  与确认卡同屏。须补：小 MediaQuery 高度（如 780/2160）下挂确认卡，
  断言无 overflow 且「确认执行」「取消」的 hitTest 点位于其 RenderBox
  内并可 tap 生效；PIN 面板同测。

**一修复审（2026-10-13 晚，MIX 2S debug 真机）：方案部分被否，回派二修**

- 一修内容：Manifest `adjustResize`→`adjustNothing` + Scaffold
  `resizeToAvoidBottomInset:false` + 浮层以 `max(padding,viewInsets)`
  手动避让 + Layer 内 SheetHost 移出 Flexible、压缩区改可滚动
  （analyze 0 / 377 测试全绿 / format 0）。
- 真机结果：根因 2 的 Layer 改造成立（压缩高度测试通过）；但根因 1
  规避失败并引入新阻断——**adjustNothing 下豆包 IME 键盘弹起时
  Flutter 收不到 viewInsets.bottom（上报恒 0），浮层不抬升，搜索胶囊
  被键盘整体盖住、无法看到输入内容与候选**（证据
  artifacts/g4-fix-ime2.png：键盘顶缘 y≈1295，其上方无胶囊/面板）。
  「API29 启发式仍派发 systemWindowInsetBottom」的假设在该
  MIUI+豆包组合不成立。无键盘态几何正常（g4-fix-type.png）。
- 二修方向：① 回退 Manifest/Scaffold/DiaryShell/smart_nav 的
  adjustNothing 链路到 adjustResize 原状（键盘弹起态旧几何真机本来
  正确），**保留** SlashCommandLayer 的 Sheet 不溢出改造与几何测试；
  ② 根因 1 改走原生侧强制 relayout：MainActivity 加薄 MethodChannel
  （如 echo/window_insets），提供 refreshInsets（先
  `decorView.requestApplyInsets()`；若不足则
  setSoftInputMode 在 ADJUST_NOTHING/ADJUST_RESIZE 间 post 切换一次
  强制 WindowManager 重新布局），Flutter 侧在指令 onSubmitted 后
  （IME hide 动画后约 200-300ms）调用一次；③ 本期因此产生 Kotlin
  改动，门禁加跑 testDebugUnitTest；④ widget 测试调整为 adjustResize
  语义（body 随 inset 压缩），并对通道调用补 mock 断言。

修复后重建双包，从 release pm clear 全新装重跑全部 R1-R3 链路。

**二修复审（2026-10-13 深夜，MIX 2S debug 真机）：真机证伪，回派三修**

- 二修内容：Manifest/Scaffold 回退 adjustResize；新增原生
  `echo/window_insets#refreshInsets` 通道（requestApplyInsets +
  softInputMode ADJUST_NOTHING→RESIZE 两层 post toggle），Dart 侧
  提交后 280ms 调用（Kotlin 单测 4 绿、Dart 377 绿）。
- 真机结果：按钮仍不可点。View/窗口尺寸本就正确，没有真实几何变化
  的 relayout 不会让引擎重发 metrics，机理上无效。关键旁证：卡滞态
  BACK 退出搜索态后 metrics 立即自愈、重开面板一切正常。

**三修复审（2026-10-14 凌晨）：真机证伪，且坐标探针推翻旧根因模型**

- 三修内容：提交后 250ms 先
  `focusManager.primaryFocus?.unfocus()` 再调原生通道，试图程序化
  复刻 BACK 的失焦路径。门禁 analyze 0 / 377 绿 / format 0。
- 真机结果（验收方独立复验）：确认卡三按钮仍不可点。Dart unfocus
  不 dispose FocusNode、不清 TextInput 客户端，走不到 BACK 的
  IMM 断链；且后续证据表明缺陷与焦点无关。
- **根因重定性（坐标对照实锤）**：临时在 runApp 根挂指针探针
  （[PTRMAP]，验毕已删），测得卡滞态引擎
  `physicalSize=1080x2160、dpr=2.75` 全程正确，adb 注入与真人手指
  两类触摸源的物理→逻辑映射完全一致，**不存在 metrics 卡滞**：
  - adb tap 按钮视觉中心物理 (887,1595) → logical(322.5,580.0)
    → 无响应；
  - adb tap 视觉空白处物理 (887,1893) → logical(322.5,688.4)
    → 【确认执行】被命中（AUTH_REQUIRED + PIN 卡弹出）；
  - 真人手指点按物理 (907,1893) 同样命中。
- 真根因：豆包 IME hide 且 SurfaceView resize 回全屏期间，Flutter
  **布局/hit-test 已随最终 metrics 到达贴底位置（真实命中盒
  y≈1893），但引擎把最终布局帧丢失/未提交，屏幕最后一帧停在键盘
  动画中途（按钮画在 y≈1595）**；此后 app 静止无脏区不再产帧，
  形成「视觉残影 vs 触摸已正确」。任何后续产帧（BACK、命中后的状态
  变更）画面立刻对齐，反证只差一帧。旁证：`wm density` 真实
  configuration 改变（界面确有重排）仍不治——新帧仍可能被 resize
  时序吞掉；`wm overscan` 对 MIUI SurfaceView 仅输出裁切。
  先前"点 (905,1385) 误命中 --stay"等现象即点在视觉旧帧、命中在
  新布局的同一错位，原"0.81 归一化"推断作废。根因 2 的 Layer
  不溢出改造（一修第 4 项）独立有效，继续保留。

**四修（最终修复）+ 终审通过（2026-10-14，MIX 2S debug 真机）**

- 修复（纯 Dart）：[window_inset_refresher.dart](../echo/lib/src/services/window_inset_refresher.dart)
  `MetricsFramePacer`——app 级 WidgetsBindingObserver，
  `scheduleAfterSlashSubmit()`（仅 slash 提交分支）打开 1.2s 补帧
  窗口；窗口内收到「viewInsets.bottom==0 且物理高恢复全屏基线」的
  终态 metrics 时对全部根 RenderView `markNeedsLayout()` 强制重提
  一帧 scene，并 addPostFrameCallback 次帧再补一次（覆盖 surface
  resize 晚于首个全屏 metrics 的 ROM）；另设 200ms fallback Timer
  兜住 metrics 回调缺失。窗口外零开销，非 Android 静默。
- 无效路径全部清除：三修 unfocus、二修原生通道
  （MainActivity.kt 回退 HEAD、删除 WindowInsetRelayout.kt 及其
  单测）、main.dart PTRMAP 临时探针，均不在最终代码中。
- 门禁（验收方独立复跑）：flutter analyze **0 issue**；
  flutter test **379 全绿**；dart format --set-exit-if-changed
  **exit 0**；Kotlin 净零改动，免 Gradle。
- 真机验收（验收方独立操作，证据 artifacts/verify-r1~r3-*.png、
  verify-enter.png）：豆包 IME 点「完成」后确认卡**直接贴底渲染**，
  【确认执行】(887,1886) 一点即中 → PIN 解锁卡；输 1234 点视觉
  【确定】→ 解锁、prune 自动重放成功（cutoff 2026-10-13、
  dryRun true）；【取消】(670,1886) 关卡零新增；【X】(979,1545)
  关卡零执行；物理 ENTER 提交确认卡同样贴底正常。三轮重复稳定。
  业务 agent 另回归：普通搜索不触发补帧、键盘弹起连点/快提无闪烁
  报错（logcat 干净）、窗口关闭后 3.5s 再点仍精确命中（画面持久
  对齐）、退出 slash 重开输入正常。
- 备注：真机观察 PIN【确定】首次触摸偶有数秒系统派发延迟（迟到后
  正确执行、零误触），物理 ENTER 即时，判定为 MIUI/豆包 IME 注入
  时序现象，非本缺陷，挂账观察。
- **G4-BUG-3 终审：通过。** release 包 R3 全链路（含本修复）待
  全新装复验后补结论。

### 验收总门

analyze 0 / flutter test 全绿 / format exit 0；动了 android/ 才跑
testDebugUnitTest（本期预期零 android 改动）；语义 diff 交维护者
终审 → G4 真机 → 合 main 排 **0.12.0+37**。D3 挂账中"Slash 命令
面板"随本期关闭，日记编辑器 ↑↓ 逐行跳焦留独立小 patch。

## 维护规则

- 修复即更新本文件（快通道，governance §4.2）；
- 新条目给：位置、现状证据、建议；不写无法复现的问题；
- 每 MINOR 版本发布时由维护者顺带复审一次。
