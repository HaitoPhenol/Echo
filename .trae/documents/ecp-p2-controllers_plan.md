# ECP P2：控制器提升 + chat/console/badge 命名空间 实施计划

> 分支：`feat/ecp-p2-controllers`（从 main `0df9120` 拉出，P1+§E 已合入）
> 依据：docs/ecp/ecp-design.md §9（前置重构）、§10 P2 行；docs/ecp/ecp-commands.md §6/§7/§8（冻结契约）

## Repository Research

- **P1 装配**：[bootstrap.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/control/bootstrap.dart) `init()` 在 runApp 前建好 bus/registry，命令构造器 `buildSys/Auth/Nav/DiaryCommands()` 已注册；UI 侧服务由各页 bootstrap 后自行 `registry.set(...)`（现仅 [smart_nav_screen.dart:261](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/smart_nav_screen.dart#L261) 注册 NavPhysicsController，diary_page.dart 注册日记域）。
- **聊天**：[chat_store.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/chat_store.dart) 是内存脚手架：仅 `ChatConversation{id,nickname,preview,unread}` + `addIncoming/remove/markRead/markUnread/hasUnread`，**无消息模型、无 send/get、无会话详情页**。[chat_page.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/pages/chat_page.dart) 的 `_openRowId` 只是左滑操作区展开态（纯 UI 手势态，留在 widget），点按未读行直接调 `store.markRead`。装配在 smart_nav_screen initState（L213-219），并有 `_syncChatBadge` 未读→锚点联动。
- **读数条**：[mechanical_coords_bar.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/navigation/widgets/mechanical_coords_bar.dart) 在 Widget State 内持 `echo/device_stats` channel + 5s Timer + 格式化；bootstrap.dart L125-135 另有一份 `_readDeviceSnapshot`（sys.info 用）。提升后三处（UI/定时器/命令/sys.info）同源同一服务。
- **锚点**：[nav_badge_service.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/services/nav_badge_service.dart) 接口已齐备（levelOf/postNotification/reportException/markViewed/resolveException，页下标），实例 `_badges` 在 SmartNavScreen。badge 命令只缺包装，页名解析可复用 nav 域 `_resolvePage` 同源逻辑。
- **协议**：controlledVerbs（command_spec.dart:215）**缺 `mark-read`**（手册 §6 冻结名），需补；`open/send/refresh/notify/exception/view/resolve/status/get/list` 均已在表。
- **脚本**：echo-cmd 的 PAIRS 按行喂给 Python 拼 JSON，**多行文本会破坏行协议**；`--text-stdin` 必须走独立环境变量注入（仿 PIN 的 inject 思路但不脱敏），在 Python 侧合并为 `text` 键。
- **测试**：test/pages/chat_page_test.dart 依赖 ChatStore/行交互，重构必须保持其绿；manifest_consistency_test.dart 自动要求每条注册命令在手册有小节（§6/§7/§8 已存在，无需改手册结构，仅补 echo-cmd 示例如有缺口）。

## Files and Modules

**新增（lib）**
- `echo/lib/src/services/chat_messages.dart`（或并入 chat_store.dart，二选一，倾向同文件扩展）：`ChatMessage` 值对象 + ChatStore 消息层（每会话消息列表、send/get 分页）。
- `echo/lib/src/services/chat_session_controller.dart`：`ChatSessionController extends ChangeNotifier`（openSessionId/open/close，open 走与点按同路径并触发 markRead）。
- `echo/lib/src/services/console_stats_service.dart`：`ConsoleStatsService extends ChangeNotifier`（channel 读数、5s 定时、snapshot/refresh、异常降级）。
- `echo/lib/src/control/commands/chat_commands.dart`、`console_commands.dart`、`badge_commands.dart`。

**新增（test）**
- `echo/test/control/chat_commands_test.dart`、`console_commands_test.dart`（假 channel/时钟）、`badge_commands_test.dart`；
- `echo/test/services/chat_session_controller_test.dart`、`chat_messages_test.dart`、`console_stats_service_test.dart`（视拆分情况合并）。

**修改**
- `chat_store.dart`：消息层 + `send`/`get`，preview 随发送更新；
- `chat_page.dart`：点按行改调 ChatSessionController.open（同路原则），左滑展开态 `_openRowId` 不动；
- `mechanical_coords_bar.dart`：改为消费 ConsoleStatsService（Scope/构造注入），删除自持 channel/Timer；
- `smart_nav_screen.dart`：建 ConsoleStatsService/ChatSessionController，注册 ChatStore/Controller/Badges/ConsoleStats 进 ControlRegistry；读数条传入服务；dispose 收口；
- `bootstrap.dart`：`_readDeviceSnapshot` 改为消费 ConsoleStatsService（服务在 UI 装配前可能缺失——保留 channel 直读兜底或允许 sys.info 降级，实施时按装配顺序定：服务由 SmartNavScreen 注册，晚于 bootstrap；故 ConsoleStatsService 改为在 bootstrap.init 中创建并注册、UI 从 registry 取同源实例——**采用此顺序**）；
- `command_spec.dart`：controlledVerbs 加 `mark-read`；
- `scripts/echo-cmd`：`--text-stdin` 支持（独立 env 注入 Python → text 键）；
- `docs/ecp/ecp-commands.md` §9.1：补 chat.send --text-stdin、console.refresh、badge.* 示例（契约表本身不改）。

## Implementation Steps（依赖序）

1. **协议微调**：controlledVerbs 补 `mark-read`；跑 manifest 测试确认不影响既有。
2. **ConsoleStatsService 提升（最独立，先做）**：channel+Timer+snapshot 从 widget 与 bootstrap 两处收口为一个 ChangeNotifier；在 ControlBootstrap.init 创建并 registry.set；MechanicalCoordsBar 改消费它；sys.info 改取服务快照。补纯 Dart 测试（注入假 MethodChannel？channel 调用包一层可注入函数 + 假时钟 Timer 用 fakeAsync）。既有 widget 测试全绿。
3. **ChatStore 消息层**：ChatMessage{id,conversationId,text,direction(in/out),createdAt}；每会话消息内存列表；`send(id,text)`（空文本 USAGE/不存在会话 NOT_FOUND，写消息+更新 preview+notify）、`messagesOf(id,{limit,cursor})` 倒序分页（cursor=消息 id 或时间戳，定：用消息 id 游标，返回 nextCursor）；`get` 读会话不存在 → NOT_FOUND。
4. **ChatSessionController**：持 openSessionId，open(id) 校验存在→markRead（经 ChatStore 同一路径）→notify；close()。chat_page 点按行（含已读行点按？现仅未读行点按 markRead——统一为点按即 controller.open）。
5. **chat 命令**：list(1)/get(1,id+limit+cursor)/open(2,id,--stay 接受无动作)/send(2,非幂等 idempotent:false,id+text)/mark-read(2,id)。返回形状严格按手册 §6。
6. **badge 命令**：status(1, 各页 level 一览）/notify/exception/view/resolve(2, --page)；页名↔下标解析与 nav 同源（抽公共 resolvePage 工具，nav 命令一并改用，避免两份）。
7. **console 命令**：snapshot(1)/refresh(2)，返回 {model,tempC,powerW}（refresh 返回刷新后快照）。
8. **装配**：SmartNavScreen 把 ChatStore/ChatSessionController/_badges/ConsoleStats（已在 bootstrap）注册进 registry；bus.registerAll 加三组命令（bootstrap.init）。
9. **echo-cmd**：--text-stdin（读 stdin 全文，经 ECP_TEXT_STDIN env 注入 Python 合并 text；与 --text 互斥校验）；长文本不进 PAIRS 行协议。
10. **手册 §9.1 示例**补齐。

## Dependencies and Considerations

- **同路原则（§9.4）**：chat.open 与行点按必须同一 controller 方法；badge 命令直接调 NavBadgeService 公共接口；console.refresh 与 5s 定时器同一 refresh()。
- **幂等元数据**：chat.send 标 `idempotent:false`，其余写命令幂等；审计已在总线自动覆盖。
- **注册时机**：服务未就绪时命令 requireService 抛错会被总线映射——UI 装配前命令到达返回明确错误（diary 域已有此模式，保持一致）。ConsoleStats 因 sys.info 冷启动需要，放 bootstrap.init 创建。
- **空数据安全**：真机现有会话由「模拟：聊天新消息」按钮产生；真机实测只新增/读取/标记，不执行删除（无 chat.delete 命令），不碰用户数据。
- **--stay**：slash 专用开关（手册 §1.1），adb 接受入参但 handler 不使用；bool 解析已支持。
- **release 边界**：新命令注册在 bus（全构建），但 release 无 adb 通道，物理不可达；与 P1 一致，manifest 一致性测试守 debug-only 规则（新命令均非 debugOnly）。

## Validation

- `cd echo && flutter analyze` 零 issue；
- `flutter test` 全绿（基线 232，预期 +新用例；chat_page_test 等既有 widget 测试不回归）；
- manifest_consistency_test 自动校验 11 条新命令手册小节齐全、3 级/非幂等标注正确；
- `cd echo/android && ./gradlew testDebugUnitTest`（不涉及 Kotlin 改动，确认无回归即可）；
- **MIX 2S 真机逐命令实测**（debug 包，用户在场时解锁 2 级）：
  - console.snapshot/refresh（refresh 后数值变化或同值均记录）；
  - badge.status → notify chat → status 红/绿 → view/resolve → status 复原；
  - 模拟按钮造会话 → chat.list → get（limit/cursor 分页）→ mark-read → list unread 变化 → open；
  - chat.send --text 与 --text-stdin 各一条（发到测试会话），get 验证消息体/preview 更新；
  - 负向：get 不存在 id → NOT_FOUND；send 空文本 → USAGE；
  - E1 门禁回归：上述全程走 echo-cmd（uid2000）无误伤。

## Risks

- **假 MethodChannel 测试**：ConsoleStats 的 channel 依赖难纯测 → 把「取快照」抽成可注入函数（生产绑 MethodChannel，测试给假函数），Timer 用 fakeAsync；不为可测性改生产结构。
- **chat_page 重构回归**：点按语义变化（已读行点按也 open）可能影响既有 widget 测试 → 先跑测试读断言，必要时让 controller.open 对已读行只设 openSessionId 不重复 markRead（store 本就幂等），保持外部可观察行为不变。
- **消息 id 游标**：内存自增 id 与既有 `incoming-N` id 共存 → id 生成统一走 store 内序列器，cursor 按列表位置比较，不假设 id 可排序。
- **装配顺序循环依赖**：ConsoleStats 在 bootstrap 创建、UI 从 registry 取；若 widget 树测试不经 bootstrap.init，MechanicalCoordsBar 需接受可空服务并自建降级实例（与现在「—」降级一致）。
