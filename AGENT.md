# AGENT.md — Echo 工作提示

你是接手 **Echo** 的开发 agent。本文件只有项目梗概与工作要求；
动手前按下表读完 `docs/` 中的对应文档。

## 项目梗概

- Echo 是单人开发、处于 **0.x 实验期**的 Flutter App，核心是一套自研底部手势导航：
  导航条 + 两端翻页圆点、横滑翻页（自研物理）、上甩快捷操作弧（可反悔）、
  长按展开搜索、导航锚点（通知绿呼吸 / 异常红急闪）。
- Flutter 工程在 `echo/`（代码在 `echo/lib/src/`：theme / app / pages /
  services / navigation）；设计手感基准是 `ideas/smart_line.html`，**不要删除**，
  代码注释中"与原型一致"均指它。
- 版本节奏快、重视每次发版的仪式感；详细架构与接口见
  [docs/architecture.md](docs/architecture.md)，组件称呼见
  [docs/glossary.md](docs/glossary.md)。

## 文档地图

| 文档 | 什么时候读 |
|---|---|
| [docs/architecture.md](docs/architecture.md) | 了解目录结构、核心接口、扩展操作（加页面/快捷操作/搜索源等） |
| [docs/engineering_standards.md](docs/engineering_standards.md) | **改动前必读**：工程原则、交付门禁、测试约定、历史事故档案 |
| [docs/current_state.md](docs/current_state.md) | 了解当前实现手段（会变化，勿当教条）与已知债务 |
| [docs/code_review_report.md](docs/code_review_report.md) | 已知问题的权威清单（含行号、改法、验收、路线图）与待用户决策的问题 |
| [docs/glossary.md](docs/glossary.md) | 讨论界面、写注释、写提交信息时统一称呼 |
| [docs/governance.md](docs/governance.md) | **觉得规则碍事/过时/缺失时读**：规则如何变更（快通道 vs 提案）、谁有权改、多久复审 |
| [docs/maintainer-charter.md](docs/maintainer-charter.md) | **主助手常设职责**：何时主动审查代码、如何登记问题、如何定期维护 docs（版本节点触发） |
| docs/component-reports/ | 各组件的阶段开发总结归档（如智能导航线 v0.4.10 总结）；了解模块演进史时查阅，归档内容只增不改 |
| docs/proposals/ + docs/templates/ | 规则变更提案（RCR）的登记册与模板 |

## 工作要求

1. **先读文档再动手**：规范在 [engineering_standards.md](docs/engineering_standards.md)，
   现状与已知问题在 [current_state.md](docs/current_state.md) 和
   [code_review_report.md](docs/code_review_report.md)。问题清单以审查报告为准，
   修完即更新，不要凭过期记忆改代码。
2. **规范与手段分开看**：原则（分层、单一事实来源、稳定 Key、形态解耦、
   时间可测、动画不重布局、真机验收等）必须遵守；当前用什么工具/实现只是现状，
   可以换，但要满足原则、说明理由并同步更新文档。
3. **交付门禁**：`cd echo && flutter analyze` 零问题、`flutter test` 全绿；
   手感改动必须真机回归六种基础手势（横滑、点圆点、上甩及反悔、双击直达、
   长按搜索、多指边界）；新行为补测试，修 bug 先补回归测试。
4. **功能改动后做文档对照审计**：architecture.md / glossary.md 与源码逐句核对
   （术语、文件位置、数值、数量），并同步更新受影响的现状文档。
5. **版本与提交**：`0.MINOR.PATCH+N`，MINOR 功能 +1、PATCH 修复 +1
   （MINOR 增加时清零），`+N` 只增不减；每版打 tag。提交用
   `feat/fix/refactor/docs/chore:` 前缀。**不主动 commit、push、打 tag，
   除非用户明确要求。**
6. **产品决策问用户**：目标设备形态、页面懒加载策略、持久化时点、
   快捷弧数量、语言等开放问题见审查报告 Q2~Q9（Q1 按压色已决：圆点按下
   tone2、滑块按下无变化），禁止替用户做产品决定。
7. **文件卫生**：按职责分层归位（services 不得依赖 UI 层），不把文件放得到处都是；
   优先编辑已有文件；同一常量只定义一次；不在组件里散落裸色值 / 魔数。
8. **发布相关改动**：调试脚手架不得进入 release 包；搜索/快捷弧打开时系统返回键
   必须关闭浮层而非退出 App（修复前属于已知 P0 问题，改动相关模块时优先处理）。
9. **规则可改，但走流程**：发现规则碍事、过时或缺失是正常现象——
   你有义务提出，但不得自行偷改【铁律】或美术 token。小事（文档纠错、
   现状同步）走快通道直接改并在提案登记册留一行；规则实质变更先按
   [governance.md](docs/governance.md) 写 RCR 提案、经负责人批准后执行；
   紧急情况下按"临时例外"流程标注并补提案。
