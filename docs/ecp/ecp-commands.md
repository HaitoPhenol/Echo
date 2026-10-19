# ECP 命令手册

配套设计文档：[ecp-design.md](./ecp-design.md)
版本基线：P1–P4 已全部交付（v0.13.0）；每条命令的"起始"列标注引入阶段，
历史施工/复审记录见 [../archive/ecp-p1-p4-review-log.md](../archive/ecp-p1-p4-review-log.md)

本手册是命令契约。所有命令在代码 manifest 中声明，测试会校验手册与
注册清单一致；名称一经发布即冻结，改名只加别名。

---

## 1. 约定

### 1.1 命名

- 规范名：`<命名空间>.<动词>`，如 `diary.list`；
- slash 形式：`/命名空间 动词 [参数]`，如 `/diary list --month 2026-10`；
- 参数一律 `--名 值`；布尔开关为 `--flag`（出现即真）；
- 全局标志（所有命令通用）：

| 标志 | 值 | 说明 |
|---|---|---|
| `--format` | `json`（默认/adb）、`text`、`table` | 输出格式；slash 固定卡片渲染 |
| `--confirm` | 开关 | 3 级命令的显式确认，缺省拒绝执行 |
| `--stay` | 开关 | 仅 slash：可视命令执行后不收起指令台 |
| `--timeout` | 秒 | 覆盖默认超时（最长 60s） |

**slash 行语法**（P3-G1 起；adb 仍只收 JSON，本节约束面板输入）：

- 前导 `/` 可有可无；`ns.verb` 与 `/ns verb` 两种形态等价
  （`diary.list --limit 5` = `/diary list --limit 5`）；
- `--k=v` 与 `--k v` 等价；布尔参数是否吃下一个 token 由命令清单
  决定（`--flag` 出现即真，`--flag=true|false` 显式给值），不存在
  独立的布尔名单；
- 单/双引号包裹的值可含空格、`--` 与真实换行（行内粘贴多行）；
  不做 shell 转义与变量展开；未加引号的独立 `?` 永远是「尾随帮助」，
  不是参数值；
- 尾随 `?`（`diary.list?`、`/diary list ?`）或 `--help` 不执行命令，
  出该命令的 man（等价 `sys.help --command`）；
- 参数名 kebab-case 与 camelCase 同源（`--keep-seeds` =
  `--keepSeeds`）；
- 会话内 ↑↓ 召回历史；清单标 auditRedact 的参数（PIN、聊天正文）
  不留在历史字面中——历史行截到该参数之前，召回需重新输入；
- 多行进文本除引号粘贴外，输入区可展开为多行编辑（正文经普通
  string 参数提交，参数契约不变；与 adb `--text-stdin` 同源互斥语义）。

**slash 面板交互**（P3-G2 起，搜索栏首个宿主）：

- 搜索栏输入首字符 `/` 进指令态（终端提示符、候选浮层）；Esc 或
  清空即回搜索语义，点空白区收起全部面板状态；
- 候选分命名空间 → 动词 → 参数三段，点选插入；物理键盘 ↑↓ 选项、
  Tab/Enter 补全；无候选时 ↑↓ 召回本会话命令历史；
- 3 级命令未解锁时自动弹 PIN 面板：未设 PIN 引导首装（两输一致 →
  设置 → 解锁 → 原命令自动重放），已设 PIN 直接解锁；错误可原地
  重试，连续错误按协议冷却并显示剩余秒数；
- 破坏性 3 级命令执行前弹确认卡（回显全名与摘要，按钮等价追加
  `--confirm`）；`chat.send` 等非破坏 3 级只解锁不弹卡；
- `nav.goto` 成功默认收起指令台落到目标页，加 `--stay` 保留；
  失败、`?` 帮助查询不收起；
- 会话仅当次前台有效：切后台/息屏立即焚尽，回前台重新解锁，
  面板里未完成的首装输入一并清空；
- 结果为卡片：列表成表、对象成键值、JSON 兜底且可长按复制。

### 1.2 日期与时间参数

- 日期：`YYYY-MM-DD`（如 `2026-10-11`），按 04:00 日记日语义解释；
- 月：`YYYY-MM`；时间戳：ISO 8601 本地时间 `YYYY-MM-DDTHH:mm[:ss]`；
- 日期参数缺省一律取日记日时钟的"今天"，禁止命令内直取
  `DateTime.now()`。

### 1.3 权限标注

每条命令标注：**类**（读/写）、**级**（0–3）、**幂等**、**构建**
（all / debug）。级别语义见设计文档 §5。

- 1 级及以下：本地通道直接执行；
- 2 级：本地通道（slash、adb-debug）直接执行；MCP 禁止；
- 3 级：必须 `auth.unlock` 在当次前台会话内；其中破坏性命令
  （prune/reset/seed，标注 `destructive`）另需 `--confirm` 二次确认，
  非破坏性 3 级（chat.send、auth.set-pin）只需解锁。

### 1.4 返回

统一信封 `{ok, cmd, ms, result | error}`，错误结构含
`code/message/need/elevate`；脚本退出码：0 成功、1 业务失败、2 用法错、
3 认证、4 冲突、5 不存在、124 超时、127 未知命令。

下文"返回"节只列 `result` 内的业务字段。

**异步作业信封（P4，仅 adb 通道的 slow 命令）**：命令被作业化时，
首包立即（远小于接收器 9s 预算）返回

```json
{"ok": true, "cmd": "diary.export", "ms": 1, "async": true,
 "jobId": "<作业 id，等于本次 nonce>",
 "result": {"status": "running", "jobId": "<id>", "cmd": "diary.export",
            "hint": "sys.job.get --id <id>"}}
```

消费者随后用普通广播轮询 `sys.job.get --id <id>` 取终态；
`scripts/echo-cmd` 默认自动轮询并打印/退出对齐**内层信封**，
`--no-wait` 可只取 running 信封。slash 通道是进程内调用，不异步化，
始终直接等终态。

### 1.5 事件流（P4）

`sys.events` 消费一条内存环形事件流（容量 256，seq 从 1 单调递增、
淘汰不回收，允许出现 seq 空洞）。事件形状：

```json
{"seq": 7, "time": "2026-10-14T10:00:00.000", "type": "audit.entry",
 "level": 1, "data": {"cmd": "diary.export", "ok": true}}
```

**本期冻结五种事件**（新类型＝协议变更，先改本手册再登记）：

| type | level | 发射点 | data 要点 |
|---|---|---|---|
| `audit.entry` | 1 | AuditLog 落一条审计 | 审计条脱敏后 JSON（§6，绝无 PIN/正文全文） |
| `command.finished` | 1 | 总线执行唯一收口（含后台作业终态） | `cmd/ok/error?/ms/nonce?/jobId?`；裁决前失败（USAGE/未知命令/鉴权拒绝）不发 |
| `diary.export.completed` | 2 | diary.export 成功 handler | `path/entries/sizeBytes/notebook`；导出失败不发（看 command.finished） |
| `chat.incoming` | 1 | ChatStore.addIncoming（装配适配器转发） | `id/nickname/preview/text`（首条正文，与 chat.get 同为 owner 可读） |
| `nav.changed` | 0 | 导航页切换（装配适配器页号 diff 后发） | `index/page` |

- **敏感度物理过滤**：事件 level 是订阅所需最低级别；调用通道
  级别不够的事件在结果中**物理消失**（不是打码；seq 空洞允许
  调用方感知"有事件但无权看"）。通道级别＝未解锁取起始级、
  已解锁取会话级（mcp 恒 ≤1）。
- 接线纪律：services/navigation 层**零 control 依赖**，
  ChatStore/导航只暴露自身变化信号（Stream/ChangeNotifier），
  由 control 层的装配适配器订阅并转发为事件。

---

## 2. `sys` —— 系统与协议自身

### `sys.ping`
- 类 读 · 级 0 · 幂等 · 起始 P1 · 构建 all
- 参数：无
- 返回：`{"alive": true, "time": "<iso>", "pid": <int>}`
- 用途：链路自检。

### `sys.help`
- 类 读 · 级 0 · 幂等 · 起始 P1 · 构建 all
- 参数：`--command`（可选，限定单条，输出完整清单描述）
- 返回：全部当前通道**可见**命令的名称/摘要/参数摘要（debug-only 命令
  只在 debug 包出现）。

### `sys.info`
- 类 读 · 级 0 · 幂等 · 起始 P1 · 构建 all
- 返回：`version`、`buildNumber`、`flavor`（debug/release）、
  `channel`、设备型号、OS 版本。不含任何用户数据。

### `sys.status`
- 类 读 · 级 1 · 幂等 · 起始 P1
- 返回：App 前后台状态、当前导航页、仓储打开状态（diary: 库路径/
  篇数）、各服务健康概况。一条命令掌握全 App 现场。

### `sys.audit`
- 类 读 · 级 1 · 幂等 · 起始 P1
- 参数：`--limit`（默认 50，最大 200）
- 返回：审计流水倒序（时间/通道/命令/参数摘要/结果/耗时）；
  绝不含 PIN 与正文全文。

### `sys.clock.set`
- 类 写 · 级 2 · 幂等 · **仅 debug** · 起始 P1
- 参数：`--time <iso>` 或 `--reset`（二选一）
- 作用：覆盖日记日时钟（DiaryClock 注入值），**不触碰系统时间**；
  覆盖只在进程存活期有效，冷启动恢复真实时钟。
- 返回：`{"before": "<iso>", "after": "<iso>", "diaryDate": "YYYY-MM-DD"}`
- 用途：直接真机验证 03:59/04:00 日界、跨月跨年，解决 MIUI 无法
  adb 改系统时间的问题。
- 示例：
  ```bash
  scripts/echo-cmd sys.clock.set --time 2026-10-12T03:59
  scripts/echo-cmd sys.clock.set --reset
  ```

### `sys.events`
- 类 读 · 级 1 · 幂等 · 起始 P4 · 构建 all
- 参数：
  - `--since`（int，缺省＝当前尾 seq，即**不补历史**，只等新事件）；
  - `--wait-ms`（0..8000，缺省 0＝立即返回；>8000 USAGE——必须小于
    接收器 9s 预算）；
  - `--limit`（1..100，缺省 50）；
  - `--types`（逗号分隔的白名单，仅允许冻结五类型，未知类型 USAGE；
    缺省＝全部类型）。
- 作用：游标拉取 + 长轮询事件流（§1.5）。无命中且 `--wait-ms>0`
  时挂起到新事件或等待截止（截止返回空集，退出码仍 0）。
- 返回：`{"events":[…事件…], "nextSeq": <int>}`；`nextSeq` 是
  本批末条 seq（空批等于传入 since），作为下一次 `--since` 游标。
  超级别事件在 `events` 中**物理消失**（seq 可有空洞）。
- 示例：
  ```bash
  # 后台挂起等新事件（另一条 adb 触发命令即提前返回）
  scripts/echo-cmd sys.events --wait-ms 8000
  # 只听两类、从游标续拉
  scripts/echo-cmd sys.events --since 12 --types audit.entry,command.finished
  ```

### `sys.job.get`
- 类 读 · 级 1 · 幂等 · 起始 P4 · 构建 all
- 参数：`--id`（必填，异步首包 `jobId`，adb 侧即原调用 nonce）
- 作用：轮询异步作业（adb 通道 slow 命令）。作业**跨通道隔离**：
  adb 起的作业 slash 查不到（NOT_FOUND）；mcp 起始 guest(0) 且只读
  铁律下永不解锁，owner 级的本命令在 mcp 恒被 AUTH_REQUIRED 拒于
  鉴权门。作业表为内存环 32 个，超容量淘汰最旧。取作业时按作业
  原命令在**当前**通道重新过鉴权：后台执行期间会话被销毁（切后台/
  息屏）后，未重新解锁取不回结果（AUTH_REQUIRED），作业保留，
  重解后可再取。
- 返回（running）：`{"status":"running","jobId":"…","cmd":"…"}`
- 返回（done）：`{"status":"done","envelope":{…原命令最终信封…}}`；
  不存在/已淘汰/他通道作业：NOT_FOUND。
- 用途：根治 E4（接收器 9s 预算 vs slow 60s）；轮询本身是普通
  exec 广播，接收器零改动。手工示例：
  ```bash
  scripts/echo-cmd diary.export --no-wait        # 只取 running 信封
  scripts/echo-cmd sys.job.get --id ecp-123-abcd # 手工轮询
  ```

### `sys.delay`
- 类 读 · 级 0 · 幂等 · **仅 debug** · 起始 P4 · slow（60s 预算）
- 参数：`--ms`（整数 0..30000，缺省 5000）
- 作用：**验证用**——挂起指定毫秒后回 `{"sleptMs":n}`，专走
  slow/异步作业路径，用于真机验证 E4 轮询（接收器 9s 预算边界）
  与 echo-cmd 自动等待，无任何业务副作用。release 包物理不注册。
- 示例：
  ```bash
  scripts/echo-cmd sys.delay --ms 12000 --no-wait  # 立即取 running
  scripts/echo-cmd sys.job.get --id <jobId>        # 手工轮至 done
  scripts/echo-cmd sys.delay --ms 12000            # 包装自动等≈12s
  ```

---

## 3. `auth` —— 身份与提权

### `auth.status`
- 类 读 · 级 0 · 幂等 · 起始 P1
- 返回：`{"pinSet": bool, "unlocked": bool, "level": 0..3,
  "channel": "...", "expiresOnBackground": true}`

### `auth.unlock`
- 类 写 · 级 0（动作本身）· 幂等 · 起始 P1
- 参数：`--pin`（slash 走 PIN 面板不传此参；adb 经 stdin 交互输入，
  包装脚本禁止经命令行传 PIN）
- 成功：当前通道级别升至 3，颁发**仅当次前台运行有效**的会话；
  App 一旦后台/息屏立即失效。
- 失败：错误码 `AUTH_DENIED`；连续 5 次触发冷却（30s 起指数退避）。
- 示例：
  ```bash
  scripts/echo-cmd auth.unlock        # 提示 stdin 输入 PIN，不回显
  ```

### `auth.lock`
- 类 写 · 级 0 · 幂等 · 起始 P1
- 立即销毁当前通道会话，级别回到通道起始值。

### `auth.set-pin`
- 类 写 · 级 **3** · 幂等 · 起始 P1（首装规则 2026-10-13 修订）
- 两种形态：
  1. **首次初始化**（设备从未设置 PIN）：**本地通道（adb 与 slash）
     均可发起，release 包 slash 面板同权**（本地持机用户最高权限，
     见设计 §5.3），免旧 PIN，审计标记 `pin-init`；MCP 等非本地
     通道上限 1，物理不可达；
  2. **改 PIN**：须处于已解锁会话，经 stdin 交互给旧+新 PIN；
     slash 走专门设置面板。
- 新 PIN 规则：4–32 位 `[A-Za-z0-9]`，二次确认一致；只存加盐哈希。

---

## 4. `nav` —— 导航

### `nav.page`
- 类 读 · 级 0 · 幂等 · 起始 P1
- 返回：`{"index": 0..3, "name": "console|chat|notes|me"}`
  （name 为与 UI 标签解耦的稳定 id：终端=console、聊天=chat、
  笔记=notes、主页=me；显示文案改名不影响协议）

### `nav.goto`
- 类 写 · 级 2 · 幂等 · 起始 P1
- 参数：`--page <name|index>`（必填；console/chat/notes/me 或 0..3）
- 走 NavPhysicsController 与横滑手势同一路径（带动画落位），返回切换前后页。
- 冲突：日记编辑中有未落盘防抖内容时不拦截（防抖服务会照常 flush），
  但返回 `warnings: ["diary-flush-pending"]`。
- 示例：
  ```bash
  scripts/echo-cmd nav.goto --page notes
  /nav goto notes --stay
  ```

---

## 5. `diary` —— 日记模块

域对象 = 日记文档；日期参数省略时取日记日今天。所有结果与 meta 表
口径一致（不额外解析正文时不读 .sy）。

### `diary.list`
- 类 读 · 级 1 · 幂等 · 起始 P1
- 参数：`--month YYYY-MM`（可选，缺省列全部）、`--limit`（默认 50）、
  `--cursor`（分页透传）
- 返回：`items:[{date,title,state,preview,blockCount,updatedAt}]`，
  倒序；`cursor`。

### `diary.get`
- 类 读 · 级 1 · 幂等 · 起始 P1
- 参数：`--date YYYY-MM-DD`（必填）
- 返回：完整文档（id/title/date/state/custom 字段/blocks 含类型、
  级别、底色、updatedAt、文件路径）；块级只读由文档级 state（exported）
  表达，**2026-10-18 日模板重设后 data 只读块退役，线格式不再单列
  `readonly` 字段**。
- 错误：`NOT_FOUND`（5）。

### `diary.ensure`
- 类 写 · 级 2 · **幂等** · 起始 P1
- 参数：`--date YYYY-MM-DD`（可选）
- 作用：与进模块 bootstrap 完全相同的 `composer.ensureDay`（未来日拒绝、
  in-flight 去重、命中已存在草稿直接返回）。**2026-10-18 日模板重设后
  成稿只写文档根 `custom-*`，原 `--wait-snapshot` 占位参数已删除。**
- 返回：`{"created": bool, "document": {…同 diary.get 摘要…}}`。

### `diary.goto`
- 类 写 · 级 2 · 幂等 · 起始 P5
- 参数：
  - `--date YYYY-MM-DD`（可选，给出即**直达该日编辑页**，与 `--level` 互斥）；
  - `--level year|month|day|editor`（可选，缺省且无 `--date` 时=`year`）；
  - `--year`（可选，`level=month/day/editor` 时必给）；
  - `--month`（可选，`level=day/editor` 时必给，1-12）；
  - `--day`（可选，`level=editor` 时必给，1-31）。
- 作用：驱动笔记页**内层**路由栈（年→月→日→编辑页），经
  `DiaryNavigatorController` 调与用户手动点击**完全相同**的栈操作
  （同路原则）；并先把顶层导航 snap 到 notes 页（导航控制器未注册时
  跳过，仅驱动内层栈）。
- 返回：`{"page":"notes","level":"…",…}`，editor 级另含 `date`。
- 约束：目标日历日期/年份不得晚于日记日时钟今天（**不提供未来入口**，
  越界 `USAGE`）；`--date` 与 `--level` 同时给出 `USAGE`；层级所需
  分量缺失 `USAGE`；非法日期组合（如 02-31）`USAGE`。
- 备注：命令运行在 widget 树外，需 App **已进入笔记页完成装配**
  （服务未注册时 `NOT_READY`）。
- 示例：
  ```bash
  scripts/echo-cmd diary.goto --date 2026-10-18   # 直达该日编辑页
  scripts/echo-cmd diary.goto --level day --year 2026 --month 10
  ```

### `diary.prune`
- 类 写 · 级 **3**（破坏性，需解锁+`--confirm`）· 幂等 · 起始 P1
- 参数：`--before YYYY-MM-DD`（可选，缺省=日记日时钟今天，语义同
  bootstrap 的跨天清理截止线）、`--dry-run`（布尔，只报告不删除）
- 作用：立即执行 `pruneEmptyBefore`（meta + .sy 同生共死）。
- 返回：`{"cutoff":"…","deleted":[date…],"kept":[{date,reason}]}`
- 用途：M5 持久化后跨天清理的真机即时验证，不必改时钟过夜。
- 示例：
  ```bash
  scripts/echo-cmd diary.prune --confirm --dry-run
  ```

### `diary.reset`
- 类 写 · 级 **3** · 幂等 · **仅 debug** · 起始 P1
- 参数：`--confirm`（必填）、`--keep-seeds`（布尔，清空后重灌
  "上月+昨天"种子）
- 作用：应用内清空日记仓储（meta 表与 diary/ 目录），等价于针对日记
  域的干净环境，替代伤全 App 的 `pm clear`。
- 返回：`{"removedDocs": n, "removedFiles": n}`。

### `diary.seed`
- 类 写 · 级 **3**（破坏性，需解锁+`--confirm`）· 非幂等 · **仅 debug** ·
  起始 P4
- 参数：
  - `--days N`（1..60，缺省 7）：自 `--end` 向前回推的天数（含 end 当天）；
  - `--end YYYY-MM-DD`（缺省＝日记日时钟昨天；**今天不自动种**，
    显式给 `--end` 可种当天；未来日期拒绝——`USAGE`）；
  - `--empty-every K`（0..days，缺省 0＝全部非空；K>0 时自 `--end`
    起每 K 天（含 `--end` 当天）造一篇空稿）。
- 作用：批量灌入**成稿形状**的草稿，专补跨天清理（`diary.prune`）的
  R3 实证缺口：`--empty-every` 造的空稿与 composer 空稿判定
  （`isUserEmpty`）**同一构造**，保证 prune 认得；其余非空稿沿用
  `DiarySeedData` 同源段落构造。已存在日期跳过不覆盖（要干净重灌用
  既有 `diary.reset --keep-seeds`）；全程走 `repo.upsertDraft`。
- 返回：`{"created":[date…],"empty":[date…],"skipped":[date…]}`，
  三个日期列表（升序，ISO `YYYY-MM-DD`）。
- 示例：
  ```bash
  # 造 10 天（截至 09-20），每 3 天一篇空稿
  scripts/echo-cmd diary.seed --days 10 --empty-every 3 --end 2026-09-20
  # 随后 prune dry-run 的 deleted 应恰为空稿日期（有字稿保留）
  scripts/echo-cmd diary.prune --confirm --dry-run
  ```

### `diary.export`
- 类 写 · 级 **2**（2026-10-13 修订：导出是需要工具辅助的正常操作，
  不再定 3 级；本地通道直放，MCP 仍被通道上限 1 挡住）· 幂等 · 起始 P1
- 参数：`--notebook <名>`（可选，思源笔记本名，缺省「日记」）、
  `--year YYYY`（可选，缺省导出全部年份）、
  `--month M`（可选，须与 `--year` 同给，1-12，收紧到某月——对应 UI
  的按月导出）、
  `--date YYYY-MM-DD`（可选，**P5 新增**，只打该日——按日导出；与
  `--year`/`--month` 互斥，同时给出 `USAGE`）；**不再需要 `--confirm`**
- 作用：跳过 UI 直接走 M5 导出服务生成 `.sy.zip`，写入沙盒导出目录。
  scope 命名：`all`（全部）/`yyyy`/`yyyy-MM`/`yyyy-MM-dd`（按日）。
- 返回：`{"path":"…","entries":n,"sizeBytes":n,"notebook":"…"}`；
  内容不外带，只回路径。
- 后续：人工/agent 经 SAF 或 adb pull 喂思源 3.8.6 做导入验收。
- 备注：share_plus 的"确认已发送"状态流转属于 UI 流程，不在本命令
  范围（导出产物本身可重复生成）。

### `diary.state.set`
- 类 写 · 级 2 · 非幂等 · 起始 P5
- 参数：`--date YYYY-MM-DD`（必填）、`--state draft|exported`（必填）
- 作用：在 **draft↔exported** 两态间迁移某日日记状态（**面向 MCP 的
  「恢复导出状态」入口**）：
  - `--state exported`：draft→exported（标记已导出、正文转只读）；
  - `--state draft`：exported→draft（**恢复导出状态**、正文解锁）。
- 返回：`{"date":"…","from":"…","to":"…","document":{…}}`。
- 错误：目标不存在 `NOT_FOUND`（5）；非法迁移（如 exported→archived
  以外的越权、archive 后复活）`CONFLICT`（4）。`archived` 为终态、
  归档流程走 UI，本命令**不暴露** `archived` 目标态。

### `diary.block.set`
- 类 写 · 级 2 · 非幂等 · 起始 P5
- 参数：`--date YYYY-MM-DD`（必填）、`--json`（必填，块对象或块数组）
- `--json` 每项字段（均可选）：`id` / `kind`(paragraph|heading) /
  `level`(1..6) / `text` / `background`(1..13 或 `null`) /
  `custom`(对象，键须 `custom-` 前缀，值 `null` 删键) / `index`(新块
  插入位置)。
- 作用：
  - 带 `id`：按 id 就地补丁（仅改补丁出现的字段），块不存在 `NOT_FOUND`；
  - 无 `id`：新建块，追加末尾；给 `index` 则插入该位置（越界夹取）。
- 约束：仅 **draft** 可写（exported/archived 抛 `CONFLICT`）；段落会
  清空 `level`，标题块 `level` 必须 1..6；`background` 越界 `USAGE`。
- 返回：修改后的**完整文档** JSON（同 `diary.get` 摘要口径）。
- 备注：`--json` 标注 `auditRedact`——正文内容**不写审计流水**（只记
  长度）。

### `diary.document.set`
- 类 写 · 级 2 · 非幂等 · 起始 P5
- 参数：`--date YYYY-MM-DD`（必填）、`--json`（必填，对象）
- `--json` 字段（均可选）：`title`(字符串) / `blocks`(块对象数组，
  **整体替换**现有块；每项字段同 `diary.block.set`，`id` 缺省自动
  生成思源 22 位块 ID) / `custom`(对象，按 `diary.custom.set` 规则合并)。
- 作用：全文替换某日草稿内容。
- 约束：仅 **draft** 可写（`CONFLICT`）；`id` 非法（不符 22 位规范）
  或被显式给出但格式错误 → `USAGE`。
- 返回：修改后的**完整文档** JSON。`--json` 标注 `auditRedact`。

### `diary.custom.set`
- 类 写 · 级 2 · **幂等** · 起始 P5
- 参数：`--date YYYY-MM-DD`（必填）、`--json`（必填，对象）
- 作用：**合并**（非整体替换）某日草稿的文档级 `custom-*` 自定义
  属性：键须以 `custom-` 开头且非空；值为 `null` → 删除该键；值为
  字符串/数字/布尔 → 统一转字符串落库（思源自定义属性皆文本）。
- 约束：仅 **draft** 可写（`CONFLICT`）；键前缀非法或值类型非法
  （嵌套对象/数组）→ `USAGE`。
- 返回：修改后的**完整文档** JSON。`--json` 标注 `auditRedact`。

---

## 6. `chat` —— 聊天模块（P2）

### `chat.list`
- 类 读 · 级 1 · 幂等 · 起始 P2
- 返回：`items:[{id,title,unread,lastPreview,updatedAt}]`
  （信封 result 必须是对象，统一 items 包裹，同 diary.list；不给正文）。

### `chat.get`
- 类 读 · 级 1 · 幂等 · 起始 P2
- 参数：`--id`（必填）、`--limit`（缺省 20，1..100）、`--cursor`
- 返回：会话元数据（同 list 行字段）+ `messages:[{id,conversationId,
  text,direction(in|out),createdAt}]`（新→旧）、`cursor`、`hasMore`。
- 错误：`NOT_FOUND`（5）；坏游标/非法 limit → `USAGE`（2）。

### `chat.open`
- 类 写 · 级 2 · 幂等 · 起始 P2
- 参数：`--id`（必填）、`--stay`（全局 slash 标志，adb 接受忽略）
- 作用：经 ChatSessionController 进入指定会话（与点按同路径，
  触发已读逻辑）。
- 返回：操作后的会话行（同 list 字段，`unread:false`）。
- 错误：`NOT_FOUND`（5）。

### `chat.send`
- 类 写 · 级 **3**（2026-10-13 修订：消息真实发出是外部可见副作用，
  须当次前台解锁授权；非破坏性，会话内不逐条确认、无需 `--confirm`）
  · **非幂等** · 起始 P2
- 参数：`--id`（必填）、`--text`（必填，长文本/多行用
  `--text-stdin` 从标准输入读全文，二者互斥）
- 返回：发送后的消息对象 `{id,conversationId,text,direction:"out",
  createdAt}`；会话 lastPreview 随之更新。
- 错误：空文本 `USAGE`（2）；未知会话 `NOT_FOUND`（5）。

### `chat.mark-read`
- 类 写 · 级 2 · 幂等 · 起始 P2
- 参数：`--id`（必填）
- 直接调 ChatStore.markRead，返回操作后的会话行。
- 错误：`NOT_FOUND`（5）。

### `chat.seed`
- 类 写 · 级 **3** · 非幂等 · **仅 debug** · 起始 P4
- 参数：`--count N`（1..20，缺省 1）、`--text`（缺省模拟文案；正文
  与 `chat.send` 同源，清单标 `auditRedact`——审计只记 `<redacted:N>`）
- 作用：经 `ChatStore.addIncoming(text:)` **同源入口**批量造 incoming
  会话，补齐 chat 链路的真机实证缺口（debug 下跑通 `chat.seed` →
  `chat.send` 成功路径）。**非破坏性**（只造不删）：解锁即执行，
  不弹确认卡、不要 `--confirm`（参照 `chat.send` 语义）。
  release 物理不注册。
- 返回：`{"ids":["incoming-1", …]}`（新建会话 id 列表，即 addIncoming
  落库的稳定 id）。
- 示例：
  ```bash
  scripts/echo-cmd chat.seed --count 1
  scripts/echo-cmd chat.send --id incoming-1 --text-stdin   # 端到端
  ```

---

## 7. `console` —— 机能风读数条（P2）

### `console.snapshot`
- 类 读 · 级 1 · 幂等 · 起始 P2
- 返回：`{model,tempC,powerW}`（与 `echo/device_stats` 通道同源自同一
  函数，不另造读数；尚未刷新过时 model 为「—」、数值为 null）。

### `console.refresh`
- 类 写 · 级 2 · 幂等 · 起始 P2
- 触发读数条立即刷新（走 ConsoleStatsService.refresh，与 5 秒定时器、
  UI 读数条同源，数字同步变化），返回刷新后的快照，便于验证链路
  而非等定时周期。

---

## 8. `badge` —— 导航锚点状态（P2）

对应 `NavBadgeService` 既有接口，写命令全部作用于指定页
（`--page console|chat|notes|me`，稳定 id 同 nav 域），页名解析
与 nav 域同源。级别线格式：`normal` / `notification` / `exception`。

### `badge.status`
- 类 读 · 级 1 · 幂等 · 起始 P2
- 返回：`items:[{index,name,level}]`，四页一览。

### `badge.notify`
- 类 写 · 级 2 · 幂等 · 起始 P2
- 参数：`--page`（必填）
- 对应 `postNotification`（锚点绿呼吸）；返回操作后该页状态
  `{page:{index,name}, level}`。

### `badge.exception`
- 类 写 · 级 2 · 幂等 · 起始 P2
- 参数：`--page`（必填）
- 对应 `reportException`（锚点红闪烁）；返回形状同 notify。

### `badge.view`
- 类 写 · 级 2 · 幂等 · 起始 P2
- 参数：`--page`（必填）
- 对应 `markViewed`：通知态恢复 normal，异常态不受影响；
  返回操作后实际级别（用于断言状态为何未变）。

### `badge.resolve`
- 类 写 · 级 2 · 幂等 · 起始 P2
- 参数：`--page`（必填）
- 对应 `resolveException`：异常态恢复 normal；返回形状同 view。

---

## 9. 调用示例

### 9.1 adb（agent / 自动化）

```bash
# 自检
scripts/echo-cmd sys.ping

# 04:00 日界：拨到 03:59 → 看日记日归属
scripts/echo-cmd sys.clock.set --time 2026-10-12T03:59:59
scripts/echo-cmd diary.ensure
scripts/echo-cmd diary.list --month 2026-10
scripts/echo-cmd sys.clock.set --reset

# 3 级命令：先解锁（stdin 输入 PIN，会话当次前台有效）
scripts/echo-cmd auth.unlock
scripts/echo-cmd chat.send --id incoming-1 --text "会话内发送免再解锁"
# 破坏性命令另需二次确认：
scripts/echo-cmd diary.prune --confirm                 # 默认 dry-run 预演
scripts/echo-cmd diary.prune --confirm --dry-run=false # 真实删除

# 布尔参数三形态等价：--flag / --flag=true / --flag true
# （confirm/reset 为纯开关，不取值）

# 导出为 2 级：无需解锁、无需 --confirm，直接取路径
# adb 通道 slow 命令先回 async running，包装自动轮询至 done 后打印
# 内层信封（总耗时可能 >9s，不再撞接收器预算）：
scripts/echo-cmd diary.export --notebook Echo日记
adb pull /data/local/tmp/…  # 实际路径以返回 path 为准（debug 可拉取）

# 异步作业（E4 验证）：--no-wait 只取 running 信封，轮询自己掌控
scripts/echo-cmd sys.delay --ms 12000 --no-wait
scripts/echo-cmd sys.job.get --id <上一步 jobId>   # running→done

# 机能风读数条：立即刷新（不等 5s 周期）与最近快照
scripts/echo-cmd console.refresh
scripts/echo-cmd console.snapshot

# 导航锚点：状态一览 → 造通知/异常 → 查看/解除 → 状态复原
scripts/echo-cmd badge.status
scripts/echo-cmd badge.notify --page chat
scripts/echo-cmd badge.exception --page me
scripts/echo-cmd badge.view --page chat      # 通知态恢复，异常态不动
scripts/echo-cmd badge.resolve --page me

# 聊天：真机先用调试面板「模拟：聊天新消息」造会话
scripts/echo-cmd chat.list
scripts/echo-cmd chat.get --id incoming-1 --limit 20
scripts/echo-cmd chat.get --id incoming-1 --cursor <上页 cursor>
scripts/echo-cmd chat.mark-read --id incoming-1
scripts/echo-cmd chat.open --id incoming-1
# 外发：短文本直接 --text；多行/长文本走 stdin（不进进程参数）
scripts/echo-cmd chat.send --id incoming-1 --text "收到"
printf '多行正文\n第二行' | scripts/echo-cmd chat.send --id incoming-1 --text-stdin
```

### 9.2 slash 指令台（用户）

```
/diary list 2026-10
/sys status
/nav goto notes
/diary prune?                      ← 只看帮助，不执行
/diary prune --confirm             ← 弹 PIN 面板 → 确认卡 → 执行
```

### 9.3 典型 agent 断言片段

```bash
out=$(scripts/echo-cmd diary.ensure --date 2026-10-11)
echo "$out" | jq -e '.ok and (.result.document.blocks|length==6)'
```

---

## 10. 手册维护规则

- 新增命令 = manifest 注册 + 本手册加节，二者同 PR；
- 一致性测试枚举 manifest 全量命令，缺手册小节即测试失败；
- 冻结后命令不删除不重排语义；废弃命令标 `deprecated` 并给替代别名，
  保留至少一个 MINOR 版本周期；
- debug-only 命令在标题行显式标注，release 包 `sys.help` 中不出现。
