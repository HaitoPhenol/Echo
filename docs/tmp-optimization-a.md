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
| 1 | D2 空稿预览标注丢失 | 227f75e | 确认回归成立（M4 `4235d06` 对空预览显「周X（空稿）」，M5 `66a3c24` 一律退化星期小字、注释理由只覆盖 exported）；`day_list_page.dart` 按 state 区分：draft 空稿恢复「周X（空稿）」，exported/archived 维持退化；修正注释；`diary_m5_test.dart` 补回归用例（441→442） | analyze 0 / test 442 全绿 | 待审 |
| 2 | G13 触感 invokeMethod 无 catchError | 20c0ed4 | `Haptics` 收口 `_invoke()`，Android 通道统一 catchError 静默降级（规范 1.11）；新建 `test/services/haptics_test.dart`（首个 services 测试目录），mock 通道抛 PlatformException 验证不逃逸（442→443） | analyze 0 / test 443 全绿 | 待审 |
| 3 | G12 涟漪节点无 Key | 3881f55 | 确认回归成立：涟漪可同屏并存，无 key 时框架按位置配对，先结束者被移除后存留项继承其已完成的动画 State（冻结在透明、onEnded 不再触发、永不移除）。给 `RippleSpec` 加自增稳定 id，挂载节点 `key: ValueKey<int>(spec.id)`；`widget_test.dart` 补并发双涟漪回归用例（443→444） | analyze 0 / test 444 全绿 | 待审 |
| 4 | G11 多指触控竞态 | 9c6654f | 复核成立：`_handleRootPointerDown` 收到新 PointerDown 时不检查已有手势在途——第二指按下会覆盖 `_gesture`（劫持孤立前指），或把手 `_handleGesture` 与导航条 `_gesture` 两套记录同帧并驱（穿越手势，抽屉/翻页并发）。改法：按下入口最前面加单指独占守卫（`_gesture`/`_handleGesture`/`_aiHold` 任一非空即忽略新指针）；`widget_test.dart` 补多指回归用例（第二指按下不改变页面位置、第一指仍持续驱动）；已核验该用例在未加守卫时失败（444→445） | analyze 0 / test 445 全绿 | 待审 |
| 5 | Q2 锁竖屏落地 | f0e8382 | 按评审 §C 指定方式：Manifest 无法按设备区分，改在 `MainActivity.onCreate` 按 `resources.configuration.smallestScreenWidthDp >= 600` 判定——手机 `requestedOrientation = SCREEN_ORIENTATION_PORTRAIT`、平板 `SCREEN_ORIENTATION_UNSPECIFIED`；纯 Kotlin 14 行，不涉及 Dart/布局；**无 Dart 单测**（原生系统行为），以真机冒烟核验 | analyze 0 / test 445 不变 | 待审 |
| 6 | G6 Semantics 无障碍最小集 | 2a1a888 | 10 文件，只加语义不改视觉/布局/手势：导航条本体 `label/value` + `onIncrease/onDecrease`（复用 `NavPhysicsController.stepPage`，等价两端圆点翻页）；两端圆点、把手条、AI 条、快捷弧操作项、会话行（未读追加「未读」）及左滑两按钮各加按钮语义；机能风 `background/coords_bar/page_drum/page_name_plate/page_number` 五个纯装饰层包 `ExcludeSemantics`。**挂账**：圆点/快捷弧/把手/AI 目前仅只读 label，未挂激活动作，TalkBack 可读但双击不直接触发——页面导航已可由导航条 adjustable 动作完成，其余触发留待后续按需接线 | analyze 0 / test 445 不变 | 待审 |

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
  暴露只读 label，未挂 TalkBack 激活动作（双击不直接触发）；页面导航已可
  由导航条 adjustable 动作完成。若要求"完全可操作"，需把 State 内的开竖单 /
  开 AI / 触发快捷弧回调下沉进各 widget（会引入耦合），建议单独安排。
- **Q2 无自动化验证**：锁竖屏为原生系统行为，只能真机走查，见文末真机记录。
- **G8 release 加固**：keystore 涉及密钥/口令（用户决策项），R8 开启需
  proguard 规则并真机回归；见后续施工行与收尾汇报。
