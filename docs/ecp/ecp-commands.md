# ECP 命令手册（首批）

配套设计文档：[ecp-design.md](./ecp-design.md)
版本基线：ECP v0.1（随 P1/P2 落地；"起始"列标注引入阶段）

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
- 3 级：必须 `auth.unlock` 在当次前台会话内 + `--confirm` 二次确认。

### 1.4 返回

统一信封 `{ok, cmd, ms, result | error}`，错误结构含
`code/message/need/elevate`；脚本退出码：0 成功、1 业务失败、2 用法错、
3 认证、4 冲突、5 不存在、124 超时、127 未知命令。

下文"返回"节只列 `result` 内的业务字段。

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
- 类 写 · 级 **3** · 幂等 · 起始 P1
- 两种形态：
  1. **首次初始化**（设备从未设置 PIN，仅 debug 包、仅 adb 可发起）：
     免旧 PIN，审计标记 `pin-init`；
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
  底色、readonly 标记、文件路径）。
- 错误：`NOT_FOUND`（5）。

### `diary.ensure`
- 类 写 · 级 2 · **幂等** · 起始 P1
- 参数：`--date YYYY-MM-DD`（可选）、`--wait-snapshot`（布尔，等 data
  快照拉取完成，默认 true）
- 作用：与进模块 bootstrap 完全相同的 `composer.ensureDay`（未来日拒绝、
  in-flight 去重、命中已存在草稿直接返回）。
- 返回：`{"created": bool, "document": {…同 diary.get 摘要…}}`。

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
- 类 写 · 级 **3** · 非幂等 · **仅 debug** · 起始 P4
- 参数：`--count N`（默认 7）、`--from YYYY-MM-DD`（默认回推）、
  `--with-exported`（布尔，混入 exported/archived 三态）
- 作用：批量灌构造好的假日记（标题/段落/状态），用于列表与三态 UI
  压测。返回生成清单。

### `diary.export`
- 类 写 · 级 **3**（用户裁定：导出暂定三级）· 幂等 · 起始 P1
- 参数：`--notebook <名>`（可选，思源笔记本名，缺省「日记」）、
  `--year YYYY`（可选，缺省导出全部年份）、`--confirm`（必填）
- 作用：跳过 UI 直接走 M5 导出服务生成 `.sy.zip`，写入沙盒导出目录。
- 返回：`{"path":"…","entries":n,"sizeBytes":n,"notebook":"…"}`；
  内容不外带，只回路径。
- 后续：人工/agent 经 SAF 或 adb pull 喂思源 3.8.6 做导入验收。
- 备注：share_plus 的"确认已发送"状态流转属于 UI 流程，不在本命令
  范围（导出产物本身可重复生成）。

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
- 类 写 · 级 2 · **非幂等** · 起始 P2
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

# 破坏性命令：解锁（stdin 输入 PIN）+ 二次确认
scripts/echo-cmd auth.unlock
scripts/echo-cmd diary.prune --confirm                 # 默认 dry-run 预演
scripts/echo-cmd diary.prune --confirm --dry-run=false # 真实删除

# 布尔参数三形态等价：--flag / --flag=true / --flag true
# （confirm/reset 为纯开关，不取值）

# 导出后直接取路径，绕过整个分享 UI
scripts/echo-cmd diary.export --notebook Echo日记 --confirm
adb pull /data/local/tmp/…  # 实际路径以返回 path 为准（debug 可拉取）

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
