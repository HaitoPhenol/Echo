# ECP P3-G2｜搜索栏指令态 UI（最薄注入）实施 plan

日期：2026-10-13。上游：G1 `43ff0c9`（slash 核心纯 Dart 库，复审通过；
3 条 nit 已在本批顺手清：①completion 布尔死三元 ②_historyLine 删
无用形参 ③entries 无上限代码内挂账）。

## 1. 范围（交接单 §G2）

- 搜索栏首字符 `/` 进指令态：提示符（⌘/终端符）、变色、Esc/清除
  退回搜索语义；搜索建议区（历史 chips/结果）在指令态让位。
- 补全候选浮层：点选/键盘上下+回车插入；↑↓ 在无候选展开时召回
  G1 命令历史（脱敏后的）。
- 结果卡片：G1 ResultView 四态渲染；JSON 长按复制（Clipboard）。
- 3 级 UX 闭环：
  - 未设 PIN：面板引导首装（两输一致 → `auth.set-pin` → `auth.unlock`
    → 原命令自动重放），release 必须走通（本地通道 G0 已放行）；
  - 已设 PIN：`auth.unlock` → 重放；PIN 错面板留错可重试；
  - destructive（`requiresConfirm` 且行内无 `--confirm`）执行前确认卡，
    回显命令全名 + spec.summary（影响范围描述不另造数据源）；
    chat.send / auth.set-pin（confirmRequired:false）不弹卡。
- `nav.goto` 成功且无 `--stay` → 收起指令台（退出搜索）；`--stay`、
  失败、helpIntent 均不收起。
- 回前台锁态即时刷新：会话即焚仍由 AuthManager.attach 兜底；
  **AuthManager 混 ChangeNotifier**（unlock/lock/expire 时通知），
  UI 只 AnimatedBuilder 消费，不另造生命周期监听。面板打开期间被焚：
  清空首装暂存的第一遍 PIN，回到解锁/首装初始态。
- 多行进文本：当前命令存在 auditRedact 的 string 参数（chat.send
  `--text`）时显示多行展开按钮；展开后 head + 全文走 G1
  `submitMultiline`，参数契约不变。

## 2. 非范围

- 不拆分/重构 SmartNavScreen、search_capsule（只做注入点与外观
  开关）；nav 以外页面无改动。
- 无新命令、无契约字段变化；adb/MCP 零改动。
- 终端页（G3）不做；entries 裁剪策略挂账不动。
- 真机走查在 G4（本批含 widget 测试，不装机）。

## 3. 文件清单

新增 `echo/lib/src/control/slash_ui/`（**允许 import widgets/material**；
G1 的 `slash/` 零 Widget 红线不变，UI 只依赖其公开 API）：

| 文件 | 职责 |
|---|---|
| `slash_console_controller.dart` | 纯 Dart（仅 foundation）交互编排：active 推导、补全文本、确认卡/PIN 状态机、重放、收起回调、键盘动作；TextEditingValue 经回调写回，可脱离 widget 单测 |
| `slash_command_layer.dart` | StatefulWidget 浮层骨架：监听输入框/焦点、Esc 与 ↑↓ 回车键绑定、补全候选条、busy 指示、组合各 sheet/卡片 |
| `slash_sheets.dart` | PIN 面板（首装两态/解锁/错误重试）、destructive 确认卡、多行输入展开 |
| `slash_result_card.dart` | ResultView → Widget：ErrorView（码/need/elevate/retryAfterMs 人话）、Table、KeyValue、Json（长按复制） |
| `slash_ui.dart` | barrel |

薄改：

- `control/auth/auth_session.dart`：`with ChangeNotifier`，
  requestUnlock 成功 / lock 实际移除 / expireAllSessions 后 notify。
- `navigation/widgets/search_capsule.dart`：加 `bool slashMode = false`
  （图标换终端符 + accentBlue、hint 换「输入命令 · 尾随 ? 看帮助」；
  slashMode 时不挂历史/结果建议区）。改动控制在外观层。
- `navigation/smart_nav_screen.dart`：
  - initState 中 `ControlBootstrap.instance` 非空时创建 controller
    （bus/auth 同源，onRequestClose: _exitSearch），dispose 释放；
  - _handleQueryChanged 先 `_slash.bind(value)` 再 setState；
  - _handleSubmitted 指令态改走 `_slash.submit(value)`，不入搜索历史；
  - Stack 在 capsule 之后叠一层 SlashCommandLayer；
  - 给 SearchCapsule 传 slashMode；其余结构不动。

## 4. 交互状态机（controller）

```
bind(text): active = text.startsWith('/')（trim 非空）
          completion = engine.complete(text)（带光标时以 caret 切尾）
          active=false 时复位候选/选中/recall
submit(text):
  parseLine 预判（lookup=bus.specOf；词法错直接交 core.submitLine
    合成 USAGE，不拦）:
  spec.requiresConfirm && !inv.confirmed && !helpIntent
    → confirm 卡挂起 {line, cmd, summary}，不执行
  否则 _run(line)
confirmYes(): _run('$line --confirm')（词法正规路径，历史只一条）
_run(line): await core.submitLine(line)
  完成后（core listener 统一处理，重放同路径）:
    ErrorView AUTH_REQUIRED → 开 PIN 面板：
      await pins.isPinSet() → firstInstall / unlock 态，记 _pending=line
    ErrorView CONFIRM_REQUIRED → 兜底转确认卡（正常预判拦不到时）
    done && cmd=='nav.goto' && ok && !stay && !helpIntent
      → onRequestClose()
submitPin(pin):
  firstInstall:
    第一遍暂存内存（切「再输一遍」态；切后台焚会话时清空）
    第二遍不一致 → 本地报错，回第一遍；一致 →
      bus.execute(auth.set-pin, {newPin,newPinConfirm}) →
      bus.execute(auth.unlock,{pin}) → 成功关面板 _run(_pending)
  unlock: bus.execute(auth.unlock,{pin}) → 成功关面板 _run(_pending)
  失败：面板留错（USAGE 显示消息/AUTH_DENIED 显示剩余重试与冷却）
cancelPin/confirmNo(): 关闭，不重放（原行已在结果流留 AUTH/无记录）
```

- PIN/set-pin 编排调用直接走 bus.execute（不进 core entries，
  结果流只呈现用户命令；审计环照记，PIN 参数 auditRedact 不字面化）。
- pending 重放行含确认卡追加的 `--confirm`：解锁后不再撞
  CONFIRM_REQUIRED，无二次弹窗。
- 键盘：Esc → 清输入退指令态；候选展开时 ↑↓ 移动候选高亮、
  Enter/Tab 应用高亮候选（不提交）；无候选时 ↑↓ 召回历史
  （写回 TextEditingValue+复位光标）；手机端点候选/按钮闭环。
- 多行：面板内 TextField（最少 3 行、最大 ~120 字符高滚动），
  提交按钮 → core.submitMultiline(head, param, text)；Esc/取消收起。

## 5. 视觉

深色 token 全取 AppColors：浮层 overlaySurface、文字 textPrimary/
textMuted、强调 accentBlue、危险操作 anchorRed、成功 anchorGreen；
卡片圆角 12、1px tone1 边；紧凑内边距（12/10），与搜索胶囊同宽
（左右 14），浮层贴胶囊上沿 8dp，结果列表限高（屏高 45%）内部滚动。

## 6. 测试

`test/control/slash_ui/`：

- `slash_console_controller_test.dart`（ControlHarness 真 bus/auth）：
  active 进出；补全 bind/apply（写回值与 caret）；确认卡拦截/确认/
  chat.send 不拦；PIN 已设解锁→重放（diary.prune --confirm）、
  错 PIN 留错；**release 风味首装→重放全链路**
  （harness create(buildMode: release)，set-pin→unlock→prune 三封
  全 ok；debug-only diary.reset 不可见/拒绝补一条风味断言）；
  nav.goto(同页 index0) ok 触发 onRequestClose、--stay 不触发、
  失败不触发；helpIntent 不触发；↑↓ 召回写回且脱敏行无正文；
  焚会话（auth.expireAllSessions）清首装暂存。
- `slash_layer_widget_test.dart`（最小宿主：TextField+Layer+harness）：
  输 `/` 出现提示符与候选；点候选插入；确认卡按钮执行；PIN 首装
  两输→结果卡出现；结果 JSON 长按写 Clipboard（mock 通道断言）；
  Esc 硬件键退指令态；搜索胶囊 slashMode 外观一条（终端图标/hint）。
- SmartNavScreen 上帝类不整树挂载测（装配成本与价值不匹配），
  薄注入由 analyze + 上述宿主测试 + G4 真机兜底。

## 7. 门禁

flutter analyze 0；flutter test 全绿（336 + 新增只增不减）；
dart format exit 0。手册 §1.1 后补一小节「slash 面板交互」（状态机
的用户面描述，无契约变化）。独立提交，不 push。
