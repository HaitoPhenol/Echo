# 优化轮 A 项临时记录（审阅后删除，内容保留于 tag）

> 本文件是 2026-10-16 优化轮（分支 `feat/optimization-a`）的施工流水与
> 处理方法记录，供负责人复盘与审阅；轮次完成、审阅通过后整体删除
> （历史经 tag 保留）。权威问题清单仍在
> [code_review_report.md](code_review_report.md)。

## 任务范围（负责人 2026-10-16 指定）

逐个解决问题清单中 6 项（G7 CI、G4 懒加载本轮挂起）：

1. D2 空稿预览标注丢失（修复）
2. G13 触感 invokeMethod 无 catchError（修复）
3. G12 涟漪节点无 Key（修复）
4. G11 多指触控竞态（复核，视情况修复）
5. Q2 锁竖屏落地（已拍板待实施）
6. G6 Semantics 无障碍最小集
7. G8 release 加固（keystore / R8 / 崩溃钩子）

> 上表 7 行对应清单中 6 个问题条目（G11/G12 同属"待复核"一组的两半）。

## 执行模式

- 分支 `feat/optimization-a`（自 main `66b3b4a` 切出）；
- 双子智能体流水：执行者施工、审查者独立复审，调度者汇总决策；
- 一个问题一个原子提交（Conventional Commits，正文说明原因）；
- 任务分支不预占版本号（pubspec 保持 0.13.1+39）；
- 每个提交过门禁：`flutter analyze` 零问题 + `flutter test` 全绿；
- 真机：MIX 2S（3f6cc09b）可装机冒烟；六手势人工回归留待合并后。

## 施工流水

（随执行逐条追加）

| # | 问题 | 提交 | 处理方法 | 门禁 | 审查结论 |
|---|---|---|---|---|---|
| 1 | D2 空稿预览标注丢失 | 227f75e | 确认回归成立（M4 `4235d06` 对空预览显「周X（空稿）」，M5 `66a3c24` 一律退化星期小字、注释理由只覆盖 exported）；`day_list_page.dart` 按 state 区分：draft 空稿恢复「周X（空稿）」，exported/archived 维持退化；修正注释；`diary_m5_test.dart` 补回归用例（441→442） | analyze 0 / test 442 全绿 | 通过 |
| 2 | G13 触感 invokeMethod 无 catchError | 20c0ed4 | `Haptics` 收口 `_invoke()`，Android 通道统一 catchError 静默降级（规范 1.11）；新建 `test/services/haptics_test.dart`（首个 services 测试目录），mock 通道抛 PlatformException 验证不逃逸（442→443） | analyze 0 / test 443 全绿 | 通过 |
| 3 | G12 涟漪节点无 Key | 3881f55 | 确认回归成立：涟漪可同屏并存，无 key 时框架按位置配对，先结束者被移除后存留项继承其已完成的动画 State（冻结在透明、onEnded 不再触发、永不移除）。给 `RippleSpec` 加自增稳定 id，挂载节点 `key: ValueKey<int>(spec.id)`；`widget_test.dart` 补并发双涟漪回归用例（443→444） | analyze 0 / test 444 全绿 | 通过 |
| 4 | G11 多指触控竞态 | 9c6654f | 复核成立：`_handleRootPointerDown` 收到新 PointerDown 时不检查已有手势在途——第二指按下会覆盖 `_gesture`（劫持孤立前指），或把手 `_handleGesture` 与导航条 `_gesture` 两套记录同帧并驱（穿越手势，抽屉/翻页并发）。改法：按下入口最前面加单指独占守卫（`_gesture`/`_handleGesture`/`_aiHold` 任一非空即忽略新指针）；`widget_test.dart` 补多指回归用例（第二指按下不改变页面位置、第一指仍持续驱动）；已核验该用例在未加守卫时失败（444→445） | analyze 0 / test 445 全绿 | 通过 |
| 5 | Q2 锁竖屏落地 | f0e8382 | 按评审 §C 指定方式：Manifest 无法按设备区分，改在 `MainActivity.onCreate` 按 `resources.configuration.smallestScreenWidthDp >= 600` 判定——手机 `requestedOrientation = SCREEN_ORIENTATION_PORTRAIT`、平板 `SCREEN_ORIENTATION_UNSPECIFIED`；纯 Kotlin 14 行，不涉及 Dart/布局；**无 Dart 单测**（原生系统行为），以真机冒烟核验 | analyze 0 / test 445 不变 | 通过 |
| 6 | G6 Semantics 无障碍最小集 | 2a1a888 | 10 文件，只加语义不改视觉/布局/手势：导航条本体 `label/value` + `onIncrease/onDecrease`（复用 `NavPhysicsController.stepPage`，等价两端圆点翻页）；两端圆点、把手条、AI 条、快捷弧操作项、会话行（未读追加「未读」）及左滑两按钮各加按钮语义；机能风 `background/coords_bar/page_drum/page_name_plate/page_number` 五个纯装饰层包 `ExcludeSemantics`。**挂账**：圆点/快捷弧/把手/AI 目前仅只读 label，未挂激活动作，TalkBack 可读但双击不直接触发——页面导航已可由导航条 adjustable 动作完成，其余触发留待后续按需接线 | analyze 0 / test 445 不变 | 通过 |
| 7 | G8 release 加固 | d780650 / 4460fa8 | 负责人裁定范围＝**崩溃钩子 + R8**，keystore 挂起。① 崩溃钩子：`main.dart` 启动包进 `runZonedGuarded` 并接管 `FlutterError.onError`（保留 `previousOnError`，zone 内未捕获异步错误统一 `debugPrint`）；启动顺序 `ensureInitialized → 钩子 → ControlBootstrap.init → runApp` 不变，无远端上报后端（留注入口）。② R8：`build.gradle.kts` 的 release 段加 `isMinifyEnabled/isShrinkResources` 与默认优化规则 + `proguard-rules.pro`，**签名配置未动**；新建 `proguard-rules.pro` 仅保底 `-keep class com.everse.echo.**`（Flutter embedding keep 随 AAR 提供）；已核实 Kotlin 反射仅存在 debug 源集，release 无裁剪风险 | analyze 0 / test 445 全绿 / `build apk --release` 成功（53.3MB，无 R8 missing class、无新增 dontwarn） | 通过 |

## 执行模式偏差记录

- 调度者按指示尝试派「执行者+独立审查者」双子智能体流水，但
  general-purpose 智能体通道被平台拦截（连续多次返回 unusual
  activity，含最小调用）。Explore 类型可用。调整后模式：
  **调度者本人承担执行施工，每个问题完成后派独立 Explore 智能体
  复审**（可读代码、跑门禁、给结论），保持"执行与审查分离"。
- 2026-10-16 追加：D2/G13 两个后台复审智能体先后因**平台配额耗尽**
  （exceed quota limit）失败，审查未完成。处置：流水表两行审查结论
  维持「待审」，轮次收尾时统一重试派发独立复审；若配额仍不可用，
  由调度者做一轮自审并在汇报中明确标注「独立审查未跑成」。
- 2026-10-16 追加：原调度者（GLM）配额耗尽，本分支现场由**新调度者
  接手续作**。G12 的在途未提交改动经核对（意图自洽、门禁 444 全绿）
  后提交为 `3881f55`；流程保持不变。

## 挂账 / 待负责人知晓

- **G6 无障碍最小集是"可读优先"**：底栏圆点 / 快捷弧 / 把手 / AI 条目前只
  暴露只读 label + `button:true`、未挂 TalkBack 激活动作（双击不直接触发，
  独立复审亦指出「播报为按钮却不可点」的角色误导）；页面导航已可
  由导航条 adjustable 动作完成。若要求"完全可操作"，需把 State 内的开竖单 /
  开 AI / 触发快捷弧回调下沉进各 widget（会引入耦合），建议单独安排。
- **Q2 无自动化验证**：锁竖屏为原生系统行为，只能真机走查，见文末真机记录。
- **G8 release 加固**：keystore 涉及密钥/口令（用户决策项，本轮挂起）；R8 已开
  并过真机冒烟，见文末真机记录。

## 轮次收尾独立复审（2026-10-16，独立子智能体）

对全分支 diff（`66b3b4a..c2f8d2a`）做只读独立复核，结论：

- **七项全部判定「正确」**，无 P0/P1。逐项要点：D2 按 `state` 分流且仅改 sub；
  G13 收口 `_invoke().catchError` 且测试确会走到 android 分支；G12 key 落在
  Stack 子列表、身份真稳；G11 守卫在函数最顶部、覆盖 `_gesture/_handleGesture/
  _aiHold`，被忽略的第二指在 `_releaseGesture` 因 pointer 不匹配直接 return；
  Q2 仅 `onCreate` 新增、无 Manifest 冲突；G6 聊天行 `excludeSemantics` 只排子
  节点、真正的 tap 在祖先 `_SwipeToReveal`、左滑按钮为兄弟未被吞，导航条
  value/increasedValue/decreasedValue 配套完整；G8 启动顺序完好、仅动 release
  块、签名未变、keep 规则最小。
- **门禁复跑**：`flutter analyze` No issues found；`flutter test` **+445 全绿**。
- **P2（保留为挂账）**：G6 端点圆点/把手/AI/快捷弧仅「button:true + label」但无
  激活动作，读屏会播报为「按钮」却双击无效，角色具误导性；与「最小集」意图相符，
  已并入下方挂账，不本轮扩大改动。
- **P3（不改）**：G8a 崩溃钩子保留默认转储后又 `debugPrint` 一遍（有意保留标记行）；
  G6 若页名为空 value 尾巴会留「：」（当前 4 页 id 齐全，不触发）；
  `haptics_test.dart` 的 `ensureInitialized()` 可省。
- **残余不确定性**：G8b 的 R8 出包由施工阶段的 `build apk --release` 成功（53.3MB、
  无 missing class）覆盖；Q2 为原生行为，无 Kotlin 单测，靠真机冒烟核验（见下）。

## 真机记录（MIX 2S / `3f6cc09b` / 1080×2160 / 440dpi，2026-10-16）

### Q2 锁竖屏（决定性证据）
- 基线：`settings get system user_rotation`=0，display rotation 0。
- 请求横屏：置 `accelerometer_rotation 0` + `user_rotation 1`，回读 `user_rotation`=1
  （请求已被系统接受）。
- Echo 前台时 `dumpsys window displays` 仍为 **rotation 0**，且
  `mCurrentAppOrientation=SCREEN_ORIENTATION_PORTRAIT`；截图仍为 1080×2160 竖版。
- Manifest 无 `screenOrientation`（已核），故该 PORTRAIT 只可能来自 MainActivity
  新代码 → Q2 落地生效。debug 与 release 两包前台均报 PORTRAIT。
- 局限：MIUI 启动器自身亦锁竖屏，HOME 后 `mCurrentAppOrientation` 仍为 PORTRAIT，
  「切到桌面应恢复横屏」的对照无法在本机取得（MIUI 行为，非我方缺陷）。
- 事后已还原 `accelerometer_rotation`=1、`user_rotation`=0。

### 装机冒烟
- debug：`build apk --debug` 成功；装机冷启动正常，主屏（终端页 + 底栏三件套）
  竖版渲染无误。
- release（R8 开启）：`build apk --release` 成功（53.3MB，无 R8 missing class、
  无新增 dontwarn）；`am start -W` 冷启动 **1410ms**；`versionName=0.13.1` /
  `versionCode=39`；主屏渲染正常，左滑翻页到 02 聊天页（「暂无消息」）成功
  → R8 未破坏运行与手势。
- release 下终端页两个「模拟 / 处理异常」按钮按设计缺席
  （`nav_destination.dart:125` 的 `kDebugMode && id=='console'` 守卫），非 R8 裁剪。
- 崩溃钩子未做主动触发（无上报后端，仅 `debugPrint`）；启动链路正常即视为接入
  无副作用。
- 截图存于 `artifacts/opt-a-*.png`（gitignore，未入库）。
