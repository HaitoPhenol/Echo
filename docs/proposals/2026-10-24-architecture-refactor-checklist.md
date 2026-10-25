# 架构改造清单（临时分析稿）

> **状态：临时文档，非生效规则。**
> 用于对照《架构设想》（外部文档）评估差距并排期，讨论结束后可整份删除。
> 不触发 RCR；若其中某项要固化为约定，另走 RCR 提案。
> 盘点基线：`main` @ 06b5569，`lib/src` 共 113 个 Dart 文件。

---

## 1. 差距摘要

| 目标层 | 现状 | 结论 |
|---|---|---|
| 接口层 | GUI ✅；adb broadcast + App 内 slash 指令台（替代 CLI）；MCP 仅预留枚举与假通道测试 | 完成约 1/3 |
| 统一指令路由 | `ControlBus`：37 条命令 / 7 域，含校验、权限、审计、慢命令作业化 | 已达标 |
| 事件总线 | `ControlEventBus`：环形 256 + 长轮询 + 广播；但只做单向遥测 | 半达标 |
| 领域层 | diary、chat 独立；IoT 缺失；无 agent | 缺 2 个领域 |
| 数据层 | 日记有 Repository 双实现；搜索历史有接口；聊天仅内存实现、无抽象 | 局部缺 |
| 横切 | auth / audit / jobs 已具备 | 达标 |

文件级合规：约 92% 已在分层内；明确违反「UI 不碰存储」1 处，灰色跨域 3 处。

---

## 2. 改造项

### R1 拆出日记模块装配（优先级 P0，修底线一）

**状态（2026-10-25）**：已实现，未提交。新增 `diary/diary_module.dart`；`diary/ui/` 已无
`dart:io` / `path_provider` / 持久仓储引用。装配点仍在 `DiaryPage._bootstrap` 调用模块，
「上移到 composition root」并入 R3 一并处理。

**问题**：`echo/lib/src/diary/ui/diary_page.dart` L153-L220 在 UI 内获取应用文档目录、打开
`PersistentDiaryRepository`、构造 `DiaryExportService`，并向子树注入 Scope。

**做法**
- 新增 `diary/diary_module.dart`：持有 repository / composer / exportService / clock，负责
  `open()`、`dispose()`、路径获取，以及向 `ControlRegistry` 注册同源实例。
- 装配点上移到 top-level（`echo_app.dart` 或 `main.dart` 之后的统一 composition root）。
- `diary_page.dart` 只消费已注入的 scope，`dart:io` / `path_provider` 从 UI 层移除。
- `ControlPaths.diaryRoot` 改由 module 回填，不再由 DiaryPage 回填。

**验收**
- `grep 'getApplicationDocumentsDirectory' lib/src/*/ui` 为空。
- 日记页冷启动、切页、导出、命令 `diary.*` 行为不变；现有测试零改动通过。

---

### R2 聊天数据抽象与持久化（P1）

**问题**：`echo/lib/src/services/chat_store.dart` 直接是内存实现，无接口、无持久化，
不符合「Repository 隐藏存储差异」。

**做法**
- 抽 `ChatRepository` 接口（会话列表、未读、消息追加、按 id 查询）。
- 保留 `ChatStore` 作为 `ChangeNotifier` 视图层缓存，内部改调 `ChatRepository`。
- 先提供 `InMemoryChatRepository`（零行为变化），持久化实现另立一项。
- `control/commands/chat_commands.dart` 改为依赖接口而非具体类。

**验收**
- 现有 chat 命令与 UI 行为不变；新增接口的单测；`chat.*` 命令测试全绿。

---

### R3 收紧跨域依赖（P1）

状态（2026-10-25）：已实现，待审查/提交。

**问题**
- `navigation/smart_nav_screen.dart` L7-L11 直接 import diary 仓储/页面与 control 内部。
- `navigation/nav_destination.dart` 同时 import 三个页面模块。
- `diary/ui/diary_export_flow.dart` 反向 import `navigation/dock_geometry.dart`。
- `control/commands/*` 直接 import 具体领域类型（`control_json.dart` 同时依赖 diary、chat、console）。

**判断**：顶层 composition root 的跨域 import 属于架构允许的「顶层互相调用」；真正要收的是
**越大越多的直接内部依赖**，避免装配知识散落在 widget 里。

**做法**
- 抽出 `app/app_services.dart`（或 `composition_root.dart`）集中所有领域实例装配，导航页只拿接口。
- `nav_destination.dart` 只依赖「页面构造器」抽象，不 import 具体页面实现。
- 导出流程需要的底部几何改为 `theme/` 或独立 `geometry/` 的共享常量，UI 不再跨模块取。
- `control/commands` 的 JSON 序列化下沉到各领域（`diary/` 提供 `toJson`），`control_json.dart` 只做转发。
- 随装配上移一并处理（R1 审查遗留）：`DiaryModule` 增 `dispose`/注册表 `unset`
  （含 `repository.close()`）；`dataProvider` 字段收敛到模块唯一来源，避免页面与模块分叉。

**验收**
- 新增一条源码断言测试：`lib/src/services/**` 不得 import `control|diary|navigation`（已有约定，保留）。
- `lib/src/navigation/pages/**` 不直接 import 具体领域数据层。
- 导航/日记/聊天全部回归测试通过。

---

### R4 MCP Server 适配（P2，接口层补齐）

**做法**
- 新增 `control/mcp/`：一个 JSON-RPC 2.0 适配器，Tools 由 `ControlBus.visibleSpecs`
  自动派生 JSON Schema（`CommandSpec` 已含参数、读写、权限级别）。
- Resources 映射 owner 级只读命令（`diary.get/list`、`chat.get/list`、`sys.status` 等）。
- 通道身份使用已预留的 `ControlChannel.mcp`：起始 guest、上限 owner 只读，写命令物理不可达。
- 传输：先做 stdin/stdout（桌面/调试宿主），移动端外接方式后续再定。

**验收**
- 新增 MCP 一致性测试：工具数 == 可见命令数（只读子集）、Schema 与手册双向一致。
- 复用现有假通道边界测试，替换为真实适配器测试。
- release 构建默认不挂载。

**风险**：对外暴露只读数据需再次确认权限上限；默认关闭，需显式启动参数。

---

### R5 跨域事件化（P2）

**问题**：事件总线目前只做「UI → 事件」单向翻译，域间仍是直接调用，未达成文档的 EDA 解耦。

**做法**
- 定义领域事件契约（`diary.committed`、`chat.incoming`、`nav.changed` 已有先例）。
- 至少落地一条真实跨域订阅（例如日记提交后由订阅者刷新统计/徽标），证明「发布者不认识订阅者」。
- 保留现有 `UiEventBridge` 方向约束：services/navigation 不得反向 import control。

**验收**
- 新增订阅链路单测；断开订阅者时发布者行为不变；无循环依赖。

---

### R6 真 CLI（P3，可选）

- 形态一（推荐先做）：App 内终端页，复用 `ControlConsoleCore`，零新内核。
- 形态二（成本高）：PC 宿主进程，通过 adb/本地 socket 连总线；属于新工程，不并入本次改造。

**待决策**：是否需要形态二。

---

### R7 IoT 领域（P3，需产品决策）

- 当前无任何依赖，新增 `iot/`（仓储 + 服务）与 `control/commands/iot_commands.dart` 即可挂载。
- **不自行开工**：设备协议（MQTT/HTTP）、状态模型、隐私边界都需用户先定。

---

## 3. 明确不做

- 不引微服务、消息队列、内部 HTTP：单进程内存总线已满足文档的「零网络开销」。
- 不采用文档建议的 Electron/Tauri + Node 技术栈：Flutter 单进程更贴合该蓝图。
- 不为「以后可能用到」提前抽象；每项只在触发实际需求时实施。

---

## 4. 每项的交付门禁

- `flutter analyze` 零问题；`flutter test` 全绿（当前基线 591 项）。
- 涉及 UI 装配的改动必须真机回归：冷启动、切页、日记读写、导出、聊天未读。
- 一项一分支（`feat/xxx`），不改动其他项；合并前不混提交。
- 文档同步：`docs/architecture.md`、`docs/current_state.md`。

---

## 5. 待用户决策

1. R4 MCP 是否允许暴露只读日记/聊天数据（owner 级）。
2. R6 是否需要 PC 侧真 CLI。
3. R7 IoT 是否进入路线图；若进入，协议先定哪一种。
4. R1/R3 的装配层落点：`app/` 还是新增 `composition/`。
