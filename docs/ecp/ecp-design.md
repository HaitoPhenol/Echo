# ECP（Echo Control Protocol）设计说明

状态：**P1–P4 已全部交付**（v0.13.0+38，tag `v0.13.0`，2026-10-15）。
本文档保留为**现行协议架构说明**——原则、权限矩阵、审计、安全边界
仍是生效规则；标注「未来/另立专项」的部分（MCP 远端传输/提权、内置
agent 通道、终端页 UI）尚未立项——MCP stdio **只读适配器**已随架构改造
R4 落地（默认关闭）。四期施工与复审的历史流水见
[../archive/ecp-p1-p4-review-log.md](../archive/ecp-p1-p4-review-log.md)。
最后更新：2026-10-25（补 R4 MCP 只读适配器状态）
配套手册（冻结契约，与 manifest 双向测试一致）：[ecp-commands.md](./ecp-commands.md)

---

## 1. 背景与目标

真机验收中长期存在一个效率瓶颈：验证非交互类功能（成稿、清理、导出、数据
注入、时钟边界）只能靠 `adb shell input tap/swipe` 模拟点击，再截图/OCR 猜
结果。一次 prune 或 04:00 日界验证的 UI 操作成本远高于功能本身。

ECP 在 App 内部建一条**控制面（control plane）**：

- agent 可脱离 UI，用一条命令直接驱动业务并取回结构化 JSON；
- 高级用户可在全局搜索栏以 `/` 进入「指令台」直接操作系统；
- 同一份命令清单未来直接派生为 App 内 agent 与 MCP server 的工具表，
  协议设计一次到位、分通道接入。

**非目标**：ECP 不重写任何业务逻辑，不做第二套"测试专用实现"。所有命令
必须走用户界面正在使用的同一批公开 API。

## 2. 设计原则

1. **同路原则**：命令调用的代码路径与用户操作完全一致（同一个 repository、
   同一个 controller）。命令只是另一个调用方；凡命令需要而 UI 没暴露的
   能力，先做正式的控制器提升重构，不开测试后门。
2. **清单即真相（manifest-first）**：每条命令声明式定义一次，自动派生
   slash 补全/帮助、adb 参数校验、未来 MCP JSON Schema 与 `sys.help`。
3. **读写分治**：读命令保证零副作用、可并发、可缓存；写命令标注幂等性。
4. **默认安全**：release 包不含调试通道；敏感命令需要 PIN；网络通道默认
   只读。
5. **名称冻结**：命令一经发布即契约，改名只加别名不删原名，由测试保证
   manifest 与手册一致。
6. **机读优先、人读兼容**：一切输出首先是结构化 JSON，再由各通道渲染。

## 3. 总体架构

```
 ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐
 │ adb broadcast│  │ slash 指令台  │  │ MCP / app agent(未来)│
 │  (debug 包)  │  │ (全用户, 包内)│  │  (网络, 默认只读)    │
 └──────┬───────┘  └──────┬───────┘  └─────────┬──────────┘
        │ 通道适配         │                    │
        ▼                 ▼                    ▼
 ┌──────────────────────────────────────────────────────┐
 │                    ControlBus（命令总线）              │
 │  注册清单 · 参数校验 · 权限裁决 · 审计 · 统一错误信封    │
 └───────────────────────────┬──────────────────────────┘
                             ▼
 ┌────────────┬────────────┬────────────┬────────────────┐
 │ SysCommands│ NavCommands│DiaryCommands│ Chat/Console/… │  ← 各域适配器
 └─────┬──────┴─────┬──────┴──────┬─────┴────────┬───────┘
       ▼            ▼             ▼              ▼
  系统服务      NavController  DiaryRepository  ChatStore /
  (时钟/会话)   (提升自 UI)     /Exporter/…     NavBadgeService…
```

### 3.1 核心组件

| 组件 | 职责 |
|---|---|
| `CommandSpec` | 单条命令的不可变清单：名称/摘要/参数表/读或写/权限级/幂等/返回形状/起始版本/是否仅 debug |
| `ControlBus` | 注册、发现、执行；统一参数类型转换、异常到错误信封的收口 |
| `CommandHandler` | 各域适配器，一个文件一个命名空间，只做参数解包→调公开 API→结果 JSON 化 |
| `AuthSession` | 当前通道的有效级别与 PIN 解锁会话（§5） |
| `AuditLog` | ≥2 级调用与解锁事件的审计流水（§6） |
| 通道适配 | adb MethodChannel、slash UI、未来 MCP；各自决定信任上限与渲染方式 |

### 3.2 调用链（adb 通道）

```
am broadcast -a com.everse.echo.CTRL --es cmd 'diary.prune' --es args '{...}'
   → DebugControlReceiver（仅 debug 源集）
   → goAsync() 占住 PendingResult
   → MethodChannel("echo/control") invokeMethod("exec", …)
   → ControlBus.execute(channel=adb, …)
   → 结果 JSON 回填 resultData + logcat 一行
```

- 广播 Action 固定 `com.everse.echo.CTRL`；
- 接收器声明 `android:permission="android.permission.DUMP"`：AMS 在派发前
  用**发送方真实 uid** 校验，普通三方 App 无法获得该权限，root(0)/shell(2000)
  天然持有——信任边界是调用方 uid，不是 debuggable 标志。不能在 onReceive
  里查 `Binder.getCallingUid()`：manifest 接收器经 ActivityThread 消息派发，
  已离开 binder 事务，取到的恒为本 App 自身 uid（MIX 2S/Android 10 实测
  10378）。进程内 0/2000 白名单（`isCallerTrusted`，API 34+ 的
  `getSentFromUid()`）作为二次门禁，单测覆盖白名单判定；
- `cmd` 为点号全名，`args` 为 JSON 字符串（也接受逐个 `--es` 标量，
  由包装脚本统一转 JSON，人类手工调试更方便）；
- 执行超时 10s（导出等长命令单独标注 `slow`，上限 60s）；
- 结果同时回 `resultData`（JSON 信封）与 logcat tag `EchoCtrl`，
  `am broadcast` 部分 ROM 不回显 resultData 时用 logcat 兜底。

> **E4（P4 已根治：作业化执行 + 结果轮询，Kotlin 零改动）**：
> 接收器 `goAsync()` 的系统广播预算约 10s，`DebugControlReceiver`
> 保守取 **9s**；总线侧 slow 命令预算是 **60s**。P4 起 adb 通道对
> slow 命令（`diary.export`、debug 验证命令 `sys.delay`）立即回
> `async:true` 的 running 信封（远小于 9s），真正执行在后台继续，
> 工作站用普通广播 `sys.job.get --id <jobId>`（jobId＝原调用
> nonce）轮询终态；`scripts/echo-cmd` 默认每 0.5s 自动轮询至 done
> （最长 65s），`--no-wait` 只取 running 信封。即便旧路径上接收器
> 已先回 `TIMEOUT`，Dart 侧调用也不取消，仍可用同一 nonce 轮询到
> 最终信封——`TIMEOUT` 不代表失败的旧判定（落盘文件/审计流水）
> 被轮询终态取代。slash 通道是进程内调用，无 9s 预算，行为不变
> （始终直接等待终态，不异步化）。

### 3.3 代码布局

```
lib/src/control/
  protocol/
    command_spec.dart        # 清单模型、受控动词表、参数类型
    envelope.dart            # 统一返回信封
    error_code.dart          # 错误码与退出码
  control_bus.dart
  auth/
    pin_store.dart           # 加盐哈希、校验、改 PIN
    auth_session.dart        # 前台会话（生命周期联动）
    audit_log.dart           # 审计流水存储
  commands/
    sys_commands.dart
    auth_commands.dart
    nav_commands.dart
    diary_commands.dart
    chat_commands.dart
    console_commands.dart
    badge_commands.dart
  events/
    event.dart               # 不可变事件值对象（seq/time/type/level/data）
    event_bus.dart           # 内存环形事件流（poll 长轮询 + 广播流）
    event_types.dart         # P4 冻结事件类型与敏感度登记表
  jobs/
    job_store.dart           # slow 命令后台作业表（环 32，跨通道隔离）
  control_event_bridge.dart  # 装配层适配器：services/navigation → 事件
  channels/
    adb_control_channel.dart # MethodChannel 绑定
  bootstrap.dart             # debug 引导：注册各域 + 挂通道（release 空实现）

android/app/src/debug/kotlin/com/everse/echo/DebugControlReceiver.kt
android/app/src/debug/AndroidManifest.xml          # 仅注册 receiver
scripts/echo-cmd                                    # adb 包装（工作站侧）
```

release 构建不包含 `src/debug/` 源集，物理无 receiver；Dart 侧通道挂载
也在 debug 引导内，双保险。

## 4. 命令体系（摘要，详见命令手册）

- 规范名：`<命名空间>.<动词>`，如 `diary.list`；
- slash 等价写法：`/diary list`，支持短别名（如 `/d ls`）；
- 受控动词表：`list/get/status`（读）、
  `goto/open/create/set/send/refresh/ensure`（写）、
  `notify/exception/view/resolve`（信号）、
  `prune/delete/reset/seed`（生命周期；`seed` 为 P4 debug 灌数）、
  `job.get`（P4：异步作业轮询）、`events`（P4：事件游标/长轮询）、
  `delay`（P4：仅 debug 验证用）、
  `block.set`/`document.set`/`custom.set`/`state.set`（P5：日记内容/自定义
  属性/状态迁移的显式写入）；
  带点复合动词 `clock.set` 等与清单逐字一致；
- 首批命名空间：`sys` `auth` `nav` `diary` `chat` `console` `badge`；
- 仅 debug 构建注册：`sys.clock.set`、`diary.seed`、`diary.reset`、
  `chat.seed`、`sys.delay`
  （release manifest 中不存在，而非"存在但拒绝"）。

首批完整命令、参数、示例见 [ecp-commands.md](./ecp-commands.md)。

## 5. 权限模型

### 5.1 四级权限

| 级 | 名称 | 含义 | 代表命令 |
|---|---|---|---|
| 0 | `guest` | 公开只读 | `sys.ping` `sys.help` `sys.info` |
| 1 | `owner` | 所有者私人数据读取；**用户接入 Agent/MCP 即视为同意此级读取**，不做逐条读同意 | `diary.get` `diary.list` `chat.get` `chat.list` `console.snapshot` `badge.status` `sys.status` `sys.audit` |
| 2 | `user` | 本地可逆常规写 + **数据导出**（本地通道直放；MCP 上限 1 物理不可达） | `nav.goto` `diary.ensure` `console.refresh` `badge.*` `chat.open` `chat.mark-read` `diary.export` `diary.goto` `diary.state.set` `diary.block.set` `diary.document.set` `diary.custom.set` |
| 3 | `admin` | **外部可见副作用 / 不可逆删除 / 鉴权凭据变更**：须显式授权（当次前台解锁会话） | `chat.send`、`diary.prune`、`diary.reset`、`diary.seed`、`auth.set-pin` |

**定级原则（2026-10-13 用户裁定修订，替代原"按最坏通道评估"）**：

- **威胁模型不是"临时拿到未锁屏手机的人"**（该场景明确不考虑），
  而是 **MCP / 内置 agent 等自动化通道**；本地持机用户拥有最高权限；
- 按**操作对用户利益的影响面**定级：消息真实发出（外部可见、不可
  撤回）、批量删除/清空（不可逆）、鉴权凭据变更 → 3 级；
- **数据导出是"需要工具辅助的正常操作"，不是攻击面** → 2 级；MCP
  通道上限 1 仍然物理挡住 agent 导出，不需要靠 3 级来防；
- 读取是用户使用 Agent/MCP 的前提（否则 agent 退化为聊天机器人）：
  连接/接入环节取得用户同意后，1 级读取对其开放；
- **授权与逐条确认分离**：3 级命令要求解锁会话（当次前台有效），
  其中仅 `destructive` 命令（prune/reset/seed）另需一次显式确认；
  高频外部副作用命令（`chat.send`）会话内不逐条弹确认。

### 5.2 通道信任上限

| 通道 | 起始级别 | 解锁后上限 | 说明 |
|---|---|---|---|
| slash 指令台 | 2 | 3 | 用户本人持机；UI 常规写操作本就不需要 PIN |
| adb（仅 debug 包） | 2 | 3 | 物理控制台类比；包装脚本经 stdin 收 PIN，不入 shell 历史 |
| MCP / 未来网络通道 | 0 | **1（只读上限，长期铁律）** | 写能力永不随 debug 包放开；未来如需写，按命令逐个显式授权 scope，另立协议版本 |

读命令（≤1）在本地通道随时可用；2 级写在本地通道直接放行；
**3 级一律先解锁**；3 级命令中的 `destructive` 子集需要一次显式确认
（slash 弹确认卡，adb 传 `--confirm`，参数回显命令全名与影响范围）。

> **未来内置 agent 通道**：另立一行，拟定起始 0/上限 1 与 MCP 同；
> 2/3 级写操作不发会话令牌，而是走与 slash 同源的**逐次用户授权面板**
> （用户在场点按），不复用 slash 的当次前台会话。P4 之后另立专项。

### 5.3 PIN 与会话（用户裁定）

- **PIN 形态**：用户自定义**字母数字 PIN**（规则：4–32 位，字母+数字
  字符集 `[A-Za-z0-9]`，不允许纯符号；设置时二次确认）。
- **无默认密码**：任何构建都不内置默认 PIN。首次执行 3 级命令时引导
  设置。**本地通道（adb/slash）均可在从未设 PIN 时一次性初始化**
  （2026-10-13 修订：release 包的 slash 面板同样允许——本地持机用户
  拥有最高权限，"防临时持机者"不在威胁模型内），audit 标记
  `pin-init`；非本地通道（MCP 等）上限 1，对 3 级命令物理不可达，
  无需额外禁令。
- **存储**：仅存加盐哈希（随机 salt + 慢速哈希），不落明文、不进日志、
  不进审计；后续可升级到 Android Keystore 封装。
- **会话有效期＝当次前台运行**：
  - `auth.unlock` 成功后颁发内存会话令牌；
  - App 一旦进入后台（`AppLifecycleState.paused`，含息屏/切应用/锁屏）
    **立即销毁全部会话**；回到前台需重新解锁；
  - `auth.lock` 可主动立即降权；
  - 连续 5 次 PIN 错误，该通道冷却 30s（指数退避到 5min），事件入审计。
- 生物识别**不引入**（与"字母数字 PIN"裁定一致，保持模型简单）。

## 6. 审计

- 记录范围：所有 ≥2 级命令调用、解锁成功/失败、会话失效、PIN 初始化；
- 字段：时间、通道、命令全名、参数摘要（长文本截断、绝不记录 PIN/正文
  全文，仅记长度与目标 id）、结果 ok/错误码、耗时；
- 存储：debug 期落内存环形缓冲（≥200 条）+ 可选落盘；M5 持久化之后
  接入 sqflite 独立表；
- 查询：`sys.audit`（1 级），支持 `--limit`。

## 7. Slash 指令台（人机通道）

- 全局搜索栏输入 `/` 即进入指令态：搜索语义挂起、输入框视觉切换
  （提示符 `⌘`/变色），`Esc` 退回搜索；
- 三段式补全：命名空间 → 动词 → 参数，逐段说明与类型提示；
  `命令 --help` 或尾随 `?` 出单条 man 风格文档；
- 结果以结构化卡片渲染（列表成表、状态成键值、JSON 可长按复制），
  ↑↓ 翻命令历史；
- 3 级命令就地弹 PIN 面板与确认卡，成功后结果回填，不跳页；
- `nav.goto` 类可视命令执行后正常跳转，默认收起指令台（`--stay` 保留）。

**终端页（未来愿景，P3 只留接缝、不建页面）**：现有「终端」页
（稳定 id `console`，当前承载机能风读数条）未来演进为正式终端——
行输入**不带 `/` 前缀**、返回信封做格式化 JSON 渲染（折叠/高亮/
长按复制）、完整滚动历史。P3 必须把控制台抽成与入口无关的核心：
`ControlConsoleCore`（行提交 → slash 通道执行 → 信封/进行中状态流 +
命令历史）与结果渲染接口（信封 → 结构化视图模型）。搜索栏指令态是
第一个消费者，终端页是未来的第二个消费者；P3 不新增页面、不占
导航位，接缝以"核心不依赖搜索栏 Widget"为验收（测试或 debug 最小
挂载证明即可）。slash 是 App 的核心玩法，终端形态的正式实现单独立项。

## 8. 返回信封与错误码

所有通道统一：

```json
{ "ok": true, "cmd": "diary.list", "ms": 4,
  "result": { "items": [ … ], "cursor": null } }
```
```json
{ "ok": false, "cmd": "diary.prune", "ms": 1,
  "error": { "code": "AUTH_REQUIRED", "message": "需要 3 级解锁",
             "need": 3, "elevate": "auth.unlock" } }
```

进程退出码（脚本用）：

| 码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 命令执行失败（业务异常） |
| 2 | 用法错误（参数缺失/类型不符） |
| 3 | 未认证/认证失败 |
| 4 | 状态冲突（如重复导出冲突） |
| 5 | 目标不存在 |
| 124 | 超时 |
| 127 | 未知命令 |

## 9. 前置重构（同路原则要求，P1/P2 已完成）

下列能力原埋在 Widget State 内，已在 P1/P2 提升为正式控制器，
UI 改为消费控制器：

1. **NavController**：从 `SmartNavScreen` 抽出 PageController 的
   `goto/page` 能力与当前页状态（ChangeNotifier），`nav.*` 与横滑手势
   共用同一实例；
2. **ChatSessionController**：聊天页当前会话选择/打开状态从
   `chat_page.dart` State 提升，`chat.open` 与用户点按走同一入口；
3. **ConsoleRefreshTrigger**：机能风读数条的"snapshot + 定时刷新"
   收口为可手动 `refresh` 的服务，通道与定时器都只调它；
4. 写命令统一经控制器/仓储入口，禁止命令适配器直接碰私有字段
   （code review 检查项）。

## 10. 分期实施（P1–P4 已全部交付）

| 阶段 | 内容 | 验收 | 交付 |
|---|---|---|---|
| **P1** | 协议核心（spec/envelope/bus/错误码）+ PIN/会话/审计 + adb 通道（receiver+MethodChannel）+ `scripts/echo-cmd` + `sys`/`auth`/`nav`/`diary` 命名空间（含 `sys.clock.set`，04:00 边界真机直测；`diary.prune` 立即触发） | 总线/鉴权/参数校验单测；真机广播逐命令实测；analyze 0、全测试绿 | ✅ v0.10.0 |
| **P2** | §9 控制器提升重构 + `chat`/`console`/`badge` 命名空间 | 重构后既有 widget 测试全绿；新域命令逐真机实测 | ✅ v0.11.0 |
| **P3** | §5 权限模型 2026-10-13 修订（`chat.send`→3 级、`diary.export`→2 级、本地通道放开 PIN 首装）+ slash 指令台 UI（指令态、三段补全、卡片、PIN 引导/解锁面板、确认卡、历史）+ `ControlConsoleCore` 终端页接缝（不建页面） | 权限矩阵/解析/补全单测 + widget 测试；MIX 2S debug+release 双包真机走查（release 首装 PIN→发消息/导出/删除全链路）；release 包无 adb 入口残留 | ✅ v0.12.0 |
| **P4** | 事件流（结构化订阅：五种冻结事件 `audit.entry`/`command.finished`/`diary.export.completed`/`chat.incoming`/`nav.changed`，详见命令手册 §1.5；敏感度分级 + `sys.events` 游标/长轮询；装配层适配器转发，services 层禁反向 import control）、**E4 的 adb 9s 预算根治——作业化结果轮询**、播种增强；MCP 通道接入（只读，§5.2 铁律）另立专项评审；内置 agent 通道（§5.2 愿景）更后 | 事件流单测；MCP 只读边界有负向测试；services→control 零反向依赖源码断言 | ✅ v0.13.0 |
| **R4** | MCP stdio 只读适配器（2026-10-25，架构改造 R4）：JSON-RPC 2.0 + `ControlBus` 只读工具/资源派生，通道上限 owner(1)，仅 debug 且 `--mcp` 挂载；工具表另含唯一写例外 `auth.unlock`（否则 owner 只读正文不可达；PIN 错误沿用冷却，解锁后仍只读上限） | 工具/资源/权限/默认不挂载测试；analyze 0、全测试绿 | ✅ 待审查/提交 |

P4 之后原计划到此为止。**尚未立项的后续专项**（原设计点名）：
MCP 远端传输/提权（真实通道的 stdio 只读适配器已在 R4 落地，
默认关闭）、内置 agent 通道（§5.2）、终端页完整 UI（§7，接缝已备）、
审计 sqflite 落盘（§6）。立项时另起文档与分支，不沿用 P 编号。

每阶段独立分支 `feat/ecp-pN-*`，从 main 拉出，完成后按项目版本规则
排 MINOR；各期交接/复审/真机验收原文归档于
[../archive/ecp-p1-p4-review-log.md](../archive/ecp-p1-p4-review-log.md)。

## 11. 测试策略

- **协议层纯 Dart 单测**：注册/重名冲突/参数类型与必填校验/默认值、
  权限裁决矩阵（4 级 × 3 通道）、会话前后台失效、PIN 错误退避、
  错误码映射、幂等性元数据完整；
- **清单一致性测试**：反射收集全部注册命令，断言每条都有手册小节
  （CI 守手册漂移）、`destructive` 子集（prune/reset/seed）必同时
  要求确认，双向断言（destructive⇄3 级需确认）；非破坏 3 级
  （chat.send、set-pin）只需解锁、不要求确认；
  release 测试环境下 debug-only 命令不注册；
- **适配器测试**：命令对内存仓储/假 store 的行为断言（结果 JSON 形状 +
  底层状态变化），复用现有 194 测试的 fixture；
- **Android 通道**：真机 `am broadcast` 实测（纳入 echo-device-verify
  技能流程），含 receiver 在 release 包不存在的检查；
- **门禁**：`flutter analyze` 零 issue、`flutter test` 全绿，与既有
  里程碑一致。

## 12. 安全边界备忘

- **威胁模型（2026-10-13 用户裁定）**：不包含"临时取得未锁屏设备的人"；
  防护对象是 MCP / 内置 agent 等自动化通道。本地持机用户拥有最高权限，
  PIN/授权的意义是自动化边界 + 高危操作的显式摩擦；日记 UI 既有导出
  入口不设锁，与命令通道 `diary.export` 2 级一致；
- adb 通道仅存在于 debug 包，不作为面向用户的能力承诺；
- MCP 默认只读是长期铁律，任何放开写权限的提案须独立评审+用户显式授权；
  当前唯一例外是 `auth.unlock`（2026-10-25 用户授权）：只授予 owner
  只读会话，不获得任何写能力，其余写命令仍在适配器层物理不可达；
- 命令不得输出凭据、PIN、其他应用数据；导出文件路径返回沙盒路径，
  不外带内容；
- 未来账号体系落地时，PIN 模型可替换为账号鉴权，命令清单与级别不变。
