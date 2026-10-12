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
- 验毕测试机已 pm clear（PIN/内存会话清空），ALLOW_BACKUP 仍为 0。

## 维护规则

- 修复即更新本文件（快通道，governance §4.2）；
- 新条目给：位置、现状证据、建议；不写无法复现的问题；
- 每 MINOR 版本发布时由维护者顺带复审一次。
