# 规则变更提案登记册

> 本目录存放规则变更请求（RCR）。流程、通道判定与写作要求见
> [../governance.md](../governance.md)，模板见
> [../templates/rule-proposal.md](../templates/rule-proposal.md)。
>
> 提案文件**永不删除**：被否的提案也是决策历史，
> 能防止同类提议被反复提出。

## 状态流转

```
草案 / 草案（紧急） → 评审中 → 已采纳-待应用 → 已采纳-已应用
                     ↘ 需修改（回草案）
                     ↘ 已驳回
任何阶段可 → 已撤回
```

## 登记册

| 编号 | 日期 | 域 | 标题 | 状态 | 落地版本 | 文件 |
|---|---|---|---|---|---|---|
| RCR-2026-001 | 2026-10-09 | 前端美术 | 机能风视觉层色值收编进 AppColors（18 实验色 → 15 个 `mech*` token） | 已采纳-已应用 | v0.6.0 | [2026-10-09-mechanical-visual-tokens.md](2026-10-09-mechanical-visual-tokens.md) |

<!-- 登记示例（复制此行）：
| RCR-2026-001 | 2026-10-08 | 前端美术 | 新增第五亮度阶 tone5 | 已采纳-已应用 | v0.6.0 | [2026-10-08-tone5-surface-level.md](2026-10-08-tone5-surface-level.md) |
-->

## 快通道变更日志

> 不走提案、直接执行的规则文档小改，在此追加一行（最新在上）。
> 格式：日期 · 文件 · 一句话原因 · 提交。

- 2026-10-07 · architecture / current_state / glossary · 左滑操作区改恒为两个等宽按钮（已读行「未读」/未读行「已读」+ 恒在最右的「删除」，总宽 152 恒定）；修复吸附落位后再次拖动瞬间跳回上次松手位的穿帮（拖动起点抓取必须先于拖动标志置位）；聊天用例 6→7（新增再拖动连续性回归），半程阈值随恒宽改 -76/落位 -152 · 随本提交入库
- 2026-10-07 · architecture / current_state / glossary / code_review_report · 聊天列表初始改空态（居中 13px「暂无消息」，ChatStore 去掉 seedCount 播种），行间分隔线改屏宽 80% 水平居中 1px（原 74px 缩进）；聊天页 5 个用例随之重写、widget_test 页面位置标记改由 ChatPage 组件承担 · 随本提交入库
- 2026-10-07 · architecture / current_state / glossary / code_review_report · 会话列表数据化（ChatStore）：左滑删除/置未读、未读呼吸绿点、模拟新消息插入；聊天锚点改数据驱动（全部已读才恢复，停留 700ms 对聊天页失效）。新增 3.10 ChatStore 章节与术语表「聊天页」节，测试 19→22（聊天用例 2→5），更新 P2-10 证据（脚手架移除聊天序号硬编码） · 随本提交入库
- 2026-10-07 · architecture / current_state / code_review_report · 会话行填充头像占位框/昵称/预览：3.1 页面说明、目录树、页面现状与 P2-08 负载描述同步（几何数值 48/72/74 与取色 tone1/tone2/tone4） · 随本提交入库
- 2026-10-07 · architecture / current_state / code_review_report · 聊天页替换占位页（ChatPage 会话列表骨架）：目录树、3.1 页面说明、页面现状、测试数量（19 个/三文件）同步，P2-08 影响更新为「首个真实页面已常建」；顺手补登目录树遗漏的 dock_geometry_test.dart · 已随 a6fbf13 入库
- 2026-10-07 · 新增 docs/usage-guide.md + AGENT.md/glossary 链接 · 新入场 agent 不会使用软件（点错按钮），补齐操作指南：全部 10 种手势的触发条件/死区阈值/反馈/取消路径、坐标公式与 w=360 参考值（快捷弧三钮圆心等）、浮层互斥与返回键顺序、debug 按钮清单、测试 agent 注意；坐标以 DockGeometry 为准并声明不一致时改文档 · 随 docs 提交入库
- 2026-10-07 · engineering_standards 1.1 / AGENT.md · 首次接入 GitHub 远程（HaitoPhenol/Echo）后定规：只推 MINOR tag（vX.Y.0）、patch tag 留本地，禁 --tags/--follow-tags；分支全部同步、远程分支不删；已推送内容不可变；push 本身仍须授权 · 随 docs 提交入库
- 2026-10-07 · engineering_standards 1.1 / AGENT.md · 撞号事故（两分支同占 v0.5.3+26）后定规：版本号主线排号、任务分支不预占 pubspec、合并者按 main 实际状态取下一号、撞号后来者顺延；建分支前同步最新 main、开工/合并前扫其他分支 · 随 v0.5.4 提交入库
- 2026-10-07 · engineering_standards 1.1 / AGENT.md / echo-maintainer-review 技能 · 负责人直接指示：新增分支纪律（开工与提交前检查分支、新任务主动提议建分支、不删分支、可 ff 合并 main、合并后构建装手机）；小 bug/小优化授权自主升 PATCH+N 并提交打本地 tag，MINOR/push/删分支仍须确认；纯文档跟随最新分支提交 · 已入库
- 2026-10-07 · code_review_report / current_state / maintainer-charter · v0.5.0 轻复核：标注 P0-01/02 已解决、P1-02/03/04/05 复核结论，现状快照更新到 1ecec32 · 随本提交入库
- 2026-10-06 · docs 全量 + AGENT.md + .trae/skills · 建立文档体系（工程规范/现状快照/治理机制/维护者章程/登记册/模板）与两个项目技能，同步至 v0.4.10 · 随本提交入库
