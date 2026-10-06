---
name: echo-maintainer-review
description: Echo 项目的代码审查与文档定期维护流程。用户要求审查/检查代码、升版或发版前例行检查、复核问题清单、维护 docs 时使用；不适用于直接写新功能或修复单个已确认 bug。
---

# Echo 维护者审查流程

职责与边界见 `docs/maintainer-charter.md`；本技能只固化执行步骤。
规则要改走 `docs/governance.md` 的 RCR，不在审查中顺手改规则。

## 1. 定类型、冻基线

- 例行（升版/打tag）｜深度（MINOR 跨 5 或用户要全库评估）｜按需
  （用户点名）｜局部（刚改完高风险区：物理/手势/几何/开合动画/接口契约/
  生命周期）｜纯文档（跳到第 4 步）。
- 用户说"这次不用审查"则停，在章程第 6 节日志记一行。
- 记录 `git rev-parse --short HEAD`、pubspec 版本号、`git status --short`。
- 例行范围取 diff：基线查 code_review_report 头部"复核基线"与章程日志，
  跑 `git log --oneline <基线>..HEAD` 与 `git diff <基线>..HEAD --stat`。
- 深度/按需：先 `wc -l` 看规模，按 lib/src 分层逐文件通读。

## 2. 取证（先工具后结论）

1. `cd echo && flutter analyze`（零问题）、`flutter test`（记通过数，
   失败先区分回归还是测试过期）。
2. 逐维度核对，每条问题必须有**文件+行号+机理**：
   边界条件（空集/除零/极值/多指快操作）｜分层依赖（services 不得 import
   UI）｜单一事实来源（重复常量/魔数/视觉命中同源）｜生命周期
   （Timer/监听/Controller 释放、mounted）｜动画（Key、逐帧重布局、
   描边位置、圆角夹取、光效订阅）｜可测性（纯逻辑单测、pump 推进）｜
   发布安全（kDebugMode、PopScope、崩溃兜底）｜无障碍/适配（按阶段记 P2/P3）。
3. 铁律逐条过（违反≥P1），约定偏离看有无理由注释。
4. 复核报告未决条目在新代码下是否仍成立——已修要找代码证据，
   不看提交信息下结论。

## 3. 更新问题清单（唯一登记处 code_review_report.md，不新建文件）

- 新问题带位置链接/证据/影响/改法/验收，分级 P0 阻断、P1 缺陷、
  P2 债务、P3 卫生；产品取舍进第 4 节 Q 列表，不替用户决定。
- 已修：划线标 ✅ + 解决版本方式；基线推进：更新头部复核说明。
- 无实际后果的偏好不上报，不凑数、不抬级。

## 4. 文档对照（快通道，发现即修，proposals/README.md 留一行）

- current_state：版本/hash/选型/服务实现/时间源/平台测试现状；
- architecture：目录树、接口签名、几何时长数值、"几个"、文件函数名；
- glossary：代码位置与视觉描述；交叉链接与 file:// 行号有效性；
- 新事故按"症状→根因→原则编号"补进 engineering_standards 第 3 节。
- 是规则本身过时而非文档失真时：不改正文，复制
  templates/rule-proposal.md 起 RCR 草案。

## 5. 收尾

- 简明摘要：类型与基线、analyze/test 结果、新发现（P0→P3）、
  已解决/仍有效条目、已修文档、待用户决策项。
- 审查与修复分离：用户选定条目后才改业务代码，改时走全部门禁含真机回归。
- 章程第 6 节 append 日志一行；误判被指出即更正并留痕。
- 不 commit、不打 tag，除非用户明确要求。
