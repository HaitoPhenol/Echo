# ECP（Echo Control Protocol）改造开发方案

状态：待开发 · 基底：main（≥ 0.9.0+34，M5 持久仓储已合入）
最后更新：2026-10-11
配套手册：[ecp-commands.md](./ecp-commands.md)

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

> **已知限制（E4，随 P3 事件流/结果轮询根治）**：接收器 `goAsync()`
> 的系统广播预算约 10s，`DebugControlReceiver` 保守取 **9s**；而总线
> 侧 slow 命令预算是 **60s**。命令执行超过 9s 时，接收器先回
> `TIMEOUT`，但 Dart 侧调用**不会被取消**——命令继续执行，产物
> （如导出 zip）仍可能正常落盘。因此收到 `TIMEOUT` 不代表失败，
> 判定以**落盘文件/审计流水为准**：`sys.audit` 中该命令的最终
> `ok/error` 与落盘结果才是结论（P1 实测导出约 80ms，不触发；
> 日志与审计时间戳可与接收器回包的 nonce 对应）。

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
  `prune/delete/reset`（生命周期）；
- 首批命名空间：`sys` `auth` `nav` `diary` `chat` `console` `badge`；
- 仅 debug 构建注册：`sys.clock.set`、`diary.seed`、`diary.reset`
  （release manifest 中不存在，而非"存在但拒绝"）。

首批完整命令、参数、示例见 [ecp-commands.md](./ecp-commands.md)。

## 5. 权限模型

### 5.1 四级权限

| 级 | 名称 | 含义 | 代表命令 |
|---|---|---|---|
| 0 | `guest` | 公开只读 | `sys.ping` `sys.help` `sys.info` |
| 1 | `owner` | 所有者私人数据读取 | `diary.get` `diary.list` `chat.get` `console.snapshot` `badge.status` |
| 2 | `user` | 可逆的常规业务写 | `nav.goto` `chat.send` `diary.ensure` `console.refresh` `badge.*` |
| 3 | `admin` | 批量删除/清空/数据外带/测试灌数/鉴权变更 | `diary.export`、`diary.prune`、`diary.reset`、`diary.seed`、`auth.set-pin` |

定级按**最坏通道**评估：导出在用户手里是正常功能，经网络通道即为
数据外带，故 `diary.export` 定 **3 级**（单篇/批量同价，暂定）。

### 5.2 通道信任上限

| 通道 | 起始级别 | 解锁后上限 | 说明 |
|---|---|---|---|
| slash 指令台 | 2 | 3 | 用户本人持机；UI 常规写操作本就不需要 PIN |
| adb（仅 debug 包） | 2 | 3 | 物理控制台类比；包装脚本经 stdin 收 PIN，不入 shell 历史 |
| MCP / 未来网络通道 | 0 | **1（只读上限，长期铁律）** | 写能力永不随 debug 包放开；未来如需写，按命令逐个显式授权 scope，另立协议版本 |

读命令（≤1）在本地通道随时可用；2 级写在本地通道直接放行；
**3 级一律先解锁**；3 级命令额外需要一次显式确认（slash 弹确认卡，
adb 传 `--confirm`，参数回显命令全名与影响范围）。

### 5.3 PIN 与会话（用户裁定）

- **PIN 形态**：用户自定义**字母数字 PIN**（规则：4–32 位，字母+数字
  字符集 `[A-Za-z0-9]`，不允许纯符号；设置时二次确认）。
- **无默认密码**：任何构建都不内置默认 PIN。首次执行 3 级命令时引导设置；
  adb 侧在"从未设置 PIN"的 debug 包上允许 `auth.set-pin` 一次性初始化
  （仅此一种免旧 PIN 情形，audit 标记 `pin-init`）。
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

## 9. 前置重构（同路原则要求）

下列能力当前埋在 Widget State 内，P1/P2 需先提升为正式控制器，
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

## 10. 分期实施

| 阶段 | 内容 | 验收 |
|---|---|---|
| **P1** | 协议核心（spec/envelope/bus/错误码）+ PIN/会话/审计 + adb 通道（receiver+MethodChannel）+ `scripts/echo-cmd` + `sys`/`auth`/`nav`/`diary` 命名空间（含 `sys.clock.set`，04:00 边界真机直测；`diary.prune` 立即触发） | 总线/鉴权/参数校验单测；真机广播逐命令实测；analyze 0、全测试绿 |
| **P2** | §9 控制器提升重构 + `chat`/`console`/`badge` 命名空间 | 重构后既有 widget 测试全绿；新域命令逐真机实测 |
| **P3** | slash 指令台 UI（指令态、补全、卡片、PIN 面板、确认卡、历史） | widget 测试 + 双真机走查；release 包确认无 debug 入口残留 |
| **P4** | 事件流（结构化订阅：状态变更/导出完成/审计事件）、播种增强；MCP 通道接入（只读，§5.2 铁律）另立专项评审 | 事件流单测；MCP 只读边界有负向测试 |

每阶段独立分支 `feat/ecp-pN-*`，从 main 拉出，完成后按项目版本规则
排 MINOR；P1 是基础设施，建议优先于 M6（7 天连写）——连写期间产生的
现场核查需求直接用命令完成。

## 11. 测试策略

- **协议层纯 Dart 单测**：注册/重名冲突/参数类型与必填校验/默认值、
  权限裁决矩阵（4 级 × 3 通道）、会话前后台失效、PIN 错误退避、
  错误码映射、幂等性元数据完整；
- **清单一致性测试**：反射收集全部注册命令，断言每条都有手册小节
  （CI 守手册漂移）、3 级命令均标 `destructive` 且需确认、
  release 测试环境下 debug-only 命令不注册；
- **适配器测试**：命令对内存仓储/假 store 的行为断言（结果 JSON 形状 +
  底层状态变化），复用现有 194 测试的 fixture；
- **Android 通道**：真机 `am broadcast` 实测（纳入 echo-device-verify
  技能流程），含 receiver 在 release 包不存在的检查；
- **门禁**：`flutter analyze` 零 issue、`flutter test` 全绿，与既有
  里程碑一致。

## 12. 安全边界备忘

- adb 通道仅存在于 debug 包，不作为面向用户的能力承诺；
- MCP 默认只读是长期铁律，任何放开写权限的提案须独立评审+用户显式授权；
- 命令不得输出凭据、PIN、其他应用数据；导出文件路径返回沙盒路径，
  不外带内容；
- 未来账号体系落地时，PIN 模型可替换为账号鉴权，命令清单与级别不变。
