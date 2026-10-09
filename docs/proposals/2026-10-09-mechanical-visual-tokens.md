# RCR-2026-001：机能风视觉层色值收编进 AppColors（mech 色组）

| 项 | 内容 |
|---|---|
| 提案编号 | RCR-2026-001 |
| 状态 | 已采纳-待应用（分支 `feat/page-background-art` 已落地，**未合并 main、未升版**） |
| 提案人 | 开发 agent（echo-maintainer-review 流程） |
| 日期 | 2026-10-09 |
| 管辖域 | 前端美术 |
| 稳定级别 | 约定 |
| 目标版本 | 合并 main 时按版本纪律取下一号（当前 main 为 v0.5.4+27） |

---

## 1. 动机（为什么现在要改）

- 机能风页面背景实验（原型 `ideas/mechanical_style_page.html`）在
  `feat/page-background-art` 分支经 A/B/C/D 四阶段真机迭代（测试机
  MIUI MIX 2S，1080×2160/440dpi），2026-10-09 负责人裁决采纳。
- 实验期 18 个颜色常量就地定义在 `theme/mechanical_style.dart`，
  与规范 1.5「颜色集中在调色板、禁止散落裸值」相冲突；其中存在 3 组
  同值重复（#D8D8D8、#646464、#262626 各被两个名字引用）。
- 证据：commit `0fee84d` 迁移前后截图 29.png → 32.png 像素对比，App
  内容区零差异（唯一差异为 MIUI 功耗悬浮球数值区域，与本应用无关）。
  实验取证截图 1-32.png 曾随分支提交入库，2026-10-09 应用户要求从
  工作树移除（改由更轻便的取证手段），需要时可在本分支历史提交中查阅。
- 若不改的后果：实验皮肤转正后形成「调色板外第二套色值来源」，后续
  机能风元素继续在组件里造裸值，规范 1.5 事实失效。

## 2. 现状规则（改之前）

- 出处：[engineering_standards.md](../engineering_standards.md) 1.5 视觉规范
  （颜色集中 `theme/app_colors.dart`、禁止裸十六进制值与临时透明度）。
- 实验期豁免理由：机能风为可放弃实验，颜色与几何/排印/时长共同隔离在
  `MechanicalStyle`，约定「放弃实验时整组删除，不污染调色板」。
- 采纳后豁免理由消失：色值须迁入调色板，但**不向 tone1～tone4 亮度阶
  归并**——机能风色值多为带冷感的不透明灰（#0F0F0F/#262626/#3D3D3D/
  #E1E1E1）与独立的纹理透明度序列，语义上是一套皮肤而非第五亮度阶。

## 3. 提议变更（改之后的完整条文）

新条文：

1. `AppColors` 新增「机能风视觉层」色组（`mech*` 前缀，共 15 个
   token），与 tone1～tone4 **并列、互不归并、互不混用**：
   导航/浮层体系取 tone 阶；固定背景、读数条、大页码、kicker、转鼓
   等机能风元素取 mech 色组。
2. `MechanicalStyle` 只保留几何 / 排印 / 时长常量，**不得再放颜色**。
3. 迁移时同值收敛（不保留别名）：三组重复值各取一个新名。

### 全量迁移表（18 → 15）

| # | 旧常量（MechanicalStyle） | 旧值 | 新 token（AppColors） |
|---|---|---|---|
| 1 | baseBackground | #0C0C0C | `mechBackground` |
| 2 | fineGridColor | 白 α.05 (#0DFFFFFF) | `mechFineGrid` |
| 3 | coarseGridColor | 白 α.10 (#1AFFFFFF) | `mechCoarseGrid` |
| 4 | dotColor | 白 α.22 (#38FFFFFF) | `mechGridDot` |
| 5 | coordsDimColor | 白 α.30 (#4DFFFFFF) | `mechCoordsDim` |
| 6 | coordsHiColor | 白 α.55 (#8CFFFFFF) | `mechCoordsHi` |
| 7 | pageNumberStrokeColor | 白 α.10 (#1AFFFFFF) | `mechPageNumberStroke` |
| 8 | kickerHiColor | #D8D8D8 | `mechInk`（与 12 收敛） |
| 9 | kickerDimColor | #646464 | `mechInkDim`（与 13 收敛） |
| 10 | drumPanelColor | #0F0F0F | `mechDrumPanel` |
| 11 | drumBorderColor | #262626 | `mechDrumLine`（与 15 收敛） |
| 12 | drumHiColor | #D8D8D8 | `mechInk` |
| 13 | drumTagColor | #646464 | `mechInkDim` |
| 14 | drumUnitColor | #3D3D3D | `mechDrumUnit` |
| 15 | drumViewEdgeColor | #262626 | `mechDrumLine` |
| 16 | drumNumberColor | #E1E1E1 | `mechDrumNumber` |
| 17 | drumTickOffColor | #272727 | `mechDrumTickOff` |
| 18 | drumProgressTrackColor | 白 α.05 (#0DFFFFFF) | `mechDrumProgressTrack` |

注意 `mechCoarseGrid` 与 `mechPageNumberStroke` 同为白 α.10、
`mechFineGrid` 与 `mechDrumProgressTrack` 同为白 α.05，但**不收敛**：
语义不同（背景纹理 vs 页码描边 vs 转鼓轨道），未来可能分别调参。

涉及修改的文件清单：

- [x] `echo/lib/src/theme/app_colors.dart`（新增 15 token 色组段）
- [x] `echo/lib/src/theme/mechanical_style.dart`（删除全部颜色）
- [x] 5 个引用文件改 import/取色：`mechanical_background.dart`、
      `mechanical_coords_bar.dart`、`mechanical_page_drum.dart`、
      `mechanical_page_number.dart`、`pages/template_page.dart`
      （聊天页透明化在更早提交完成，不涉色值迁移）
- [x] `docs/architecture.md`（3.8 色板 mech 段、3.9 Stack 分层、3.11
      机能风视觉层全节、目录树）
- [x] `docs/engineering_standards.md`（1.5 增补 mech 色组条款）
- [x] `docs/glossary.md`（色板节 mech 段、第九节 7 术语、转鼓改名）
- [x] `docs/current_state.md`（分支态现状、测试 22→24、D1 回归）
- [x] `docs/proposals/README.md`（本登记）

## 4. 影响面与兼容性

- 受影响模块：4 个 `mechanical_*.dart` 组件、模板页、聊天页；纯取色
  常量搬家，无几何/时长/手势/接口变化。
- 非破坏性变更：18 个旧名为实验期内部 API，未跨包暴露；迁移后像素级
  视觉零变化（29→32.png PIL 对比 App 内容区 0 差异像素）。
- 与其他规则的交互：构成规范 1.5 的首个「并列色组」先例；AI 条虹彩
  六色、功能色（accentBlue/anchorGreen/anchorRed）仍就地/按原语义
  定义，不适用本提案。
- 保留项（验收时明确不动，不属于本提案范围）：粗网格 α 维持 .10；
  kicker 不打包真等宽字体（`fontFamily: monospace` 在 Flutter/Android
  不解析，要真等宽需引 Roboto Mono，包体/许可另议）。

## 5. 验收标准

- [x] `flutter analyze` 零问题
- [x] `flutter test` 全绿（24 个：widget 11 + dock_geometry 6 +
      chat_page 7）
- [x] 真机：MIX 2S 六手势回归（横滑转鼓跟手 / 圆点点按 / 上甩快捷弧
      含热区外反悔 / 长按搜索胶囊通过；双击直达与双指边界 user 版
      无 root 无法 adb 注入，以 widget 双击用例 + 代码走查兜底，
      **留人工真机复核**）
- [x] 像素对比：迁移前后截图 App 内容区零差异
- [x] 文档交叉引用同步、无失效链接
- [x] 实验期隔离注释全部清理、被取代的旧 `nav_roller.dart` 删除
      （commit `897df08`）

## 6. 回滚方案

失败信号：合并 main 后出现取色回归（某处误用旧名导致编译错误可被
analyze 拦截；视觉偏差只能靠真机/截图发现）。

回退方式：`git revert 897df08 0fee84d`（逆序）即恢复实验期
`MechanicalStyle` 持色形态；无数据迁移、无接口适配。若 main 已基于
此分支推进更多提交，则仅回滚色组引用（mech* → 就地具名常量），
架构 3.11 等文档随之回退。

## 7. 复审安排

随合并后第一次 MINOR 复审：确认 mech 色组在真实页面接入过程中未被
误用为通用灰阶；若出现第二套皮肤需求，将本提案升级为「皮肤色组」
通用机制而非特例。

---

## 审批记录

| 日期 | 审批人 | 结论 | 意见 |
|---|---|---|---|
| 2026-10-09 | 负责人 | 通过（采纳，暂缓合并） | 「保持当前效果，采纳不删，效果不错。你整理代码和文档，但是先不要合并。」 |

## 应用记录

| 日期 | 版本 | 提交 | 实际落地内容与提案的差异 |
|---|---|---|---|
| 2026-10-09 | 未发版（分支 feat/page-background-art） | `0fee84d`（色值迁移）、`897df08`（删 NavRoller/清注释）、docs 提交 | 与提案一致；合并 main 时补登版本号 |
