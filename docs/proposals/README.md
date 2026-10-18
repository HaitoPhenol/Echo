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

- 2026-10-19 · docs/diary/flutter-tech-plan.md、sy-format-golden-3.8.6.md、current_state.md、glossary.md、usage-guide.md、architecture.md · 日记时间戳「空段不落盘 + 首字符重打点」与导出段前空行（落盘清洗 `prunedForPersist` 剔掉「最后一个段内无内容的时间戳」、编辑器 `pendingStamp` 首字符重打点为动笔时刻后冻结、前端时间戳胶囊上方 `top:12` 间距、导出每个 `row` 段超级块前插顶层空 `NodeParagraph`）致文档过时，按快通道直接修并在本册登记；系用户当场裁定，非铁律 / 美术 token 变更，不走 RCR · 随本次 feat(diary) 提交入库
- 2026-10-18 · docs/diary/sy-format-golden-3.8.6.md、flutter-tech-plan.md、current_state.md、glossary.md、usage-guide.md、architecture.md · 日记时间戳段与超级块机制（进编辑页生成/复用时间戳胶囊，30 分钟窗口；导出叠加首行 col 超级块 + 每段 row 超级块 + code 标记，落盘/撤销仍扁平；新增块级 custom-echo-stamp 标志与 sy/diary_capsule_items.dart、editor/diary_capsule_chip.dart）致文档过时，按快通道直接修并在本册登记；块级 custom-* 标志属用户当场裁定，非铁律/美术 token 变更，不走 RCR；追加新增模板首块「一句话概述今日」段（12 号底色）与 `background` schema 支持 · 待随本次 docs 提交入库
- 2026-10-18 · docs/diary/flutter-tech-plan.md、current_state.md、architecture.md、glossary.md、usage-guide.md、code_review_report.md、ecp/ecp-commands.md · 日模板重设（单空段骨架 + 胶囊行，data 只读块 / `readonly` 整体退役，自动数据与心情改走文档根 `custom-*`）致文档过时，按快通道直接修并在本册登记；同步收口两处连带的协议面：`diary.get` 块线格式删 `readonly` 字段、`diary.ensure` 删除已成死参的 `--wait-snapshot`（含 echo-cmd BOOL_FLAGS）；系用户当场裁定，非铁律 / 美术 token 变更，不走 RCR · 待随本次 docs 提交入库
- 2026-10-12 · docs/ecp/ecp-commands.md · ECP P2 施工裁定快通道：chat.list 回包由裸数组细化为 `items:[...]` 包裹（信封 result 类型为对象，同 diary.list）；§6 chat/§7 console/§8 badge 全小节统一补「起始 P2」标注与错误码/回包形状；§9.1 补 console.refresh/badge.*/chat.* 与 --text-stdin 示例 · 随本提交入库
- 2026-10-13 · docs/ecp/ecp-commands.md · ECP P1 施工裁定快通道：nav 页名由显示文案 terminal/chat/template/diary 改为与 UI 解耦的稳定 id console/chat/notes/me（nav.page/nav.goto、§8 badge、§9 示例同步）；diary.export 的 --notebook 由必填改可选、缺省「日记」；manifest 一致性测试（test/control/manifest_consistency_test.dart）把手册小节作为冻结契约双向校验 · 随本提交入库
- 2026-10-12 · §E E1–E5 修复回执（code_review_report/ecp-design） · E1 接收器门禁实测改道：onReceive 内 Binder.getCallingUid() 恒本 App uid（消息派发已离 binder 事务），改用清单 android:permission=DUMP 在 AMS 层按真实发送 uid 拦截 + isCallerTrusted 纯函数 0/2000（API34+ 进程内二次门禁，3 条 JVM 单测）；E3 失败审计 2 测试；E4 9s/60s 文档化随 P3；E5 allowBackup=false 双构建实证；测试 230→232 · 随本提交入库
- 2026-10-12 · code_review_report 新增 §E · ECP P1（27ab796）验收交接单 E1–E5：接收器调用方 uid 校验、echo-cmd 布尔 false、失败审计三条必修；9s/60s 超时差、allowBackup 两条可挂账；含位置/修法/验收标准，ECP agent 分支续做 · 随本提交入库
- 2026-10-11 · engineering_standards 事故 15 / usage-guide §8.6 · 思源 AV 模板列语法误判沉淀为事故（外部工具行为须真实闭环验证才能写结论；裸 `.action{}` 不包 `{{}}`、模板列不能分组、聚合须 select+kanban、导入重生成 ID 不幂等），usage-guide 补思源 MCP 测试纪律（仅用 siyuan-repo/、禁 curl 带 token、strict 两阶段写、不重启不改盘）· 随本提交入库
- 2026-10-11 · docs 全量清点（v0.9.0+34）· 旧评审报告（v0.5.0 基线）归档到 component-reports/codebase-review-v0.5.0-2026-10-06.md（加只读头），code_review_report.md 重写为当前问题清单（D/G/Q 编号）；current_state 重写为 v0.9 快照（补日记模块/194 测试/真依赖，删 v0.6.x patch 叙述）；architecture 补目录树与 3.12 日记模块契约；usage-guide 补 4.10 日记操作；glossary 加第十节；AGENT.md 文档地图补 diary/ecp · 随本提交入库
- 2026-10-09 · 新增 .trae/skills/echo-remote-report 技能 · 用户远程/夜间盲跑时移动端 Trae 收不到图片，固化飞书汇报流程：持设备锁截图→img_key→富文本 post 发「Echo 夜间报告」群，录屏/APK 归档云盘 Echo 文件夹附链接，含固定 chat_id/folder_token、幂等键与私聊回退 · 随本提交入库
- 2026-10-09 · engineering_standards 1.15 · 合并 docs/device-testing-playbook：新增真机取证工具链（设备参数、exec-out 截图、screenrecord 360s 分段、ffmpeg 抽帧故事板、手势注入坑、临时探针纪律），1.12 与交付门禁第 3 条加引用 · 随合并提交入库
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
