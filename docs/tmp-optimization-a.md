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
| 2 | G13 触感 invokeMethod 无 catchError | （本行随提交回填） | `Haptics` 收口 `_invoke()`，Android 通道统一 catchError 静默降级（规范 1.11）；新建 `test/services/haptics_test.dart`（首个 services 测试目录），mock 通道抛 PlatformException 验证不逃逸（442→443） | analyze 0 / test 443 全绿 | 待审 |

## 执行模式偏差记录

- 调度者按指示尝试派「执行者+独立审查者」双子智能体流水，但
  general-purpose 智能体通道被平台拦截（连续多次返回 unusual
  activity，含最小调用）。Explore 类型可用。调整后模式：
  **调度者本人承担执行施工，每个问题完成后派独立 Explore 智能体
  复审**（可读代码、跑门禁、给结论），保持"执行与审查分离"。

## 挂账 / 待负责人知晓

（随执行追加）
