# ECP P3-G1：slash 控制台核心（`lib/src/control/slash/`，与入口解耦）

> 分支：`feat/ecp-p3-slash-console`（G0 已落地 `8df045b`）
> 依据：docs/ecp/ecp-design.md §7（slash 人机通道 + 终端页愿景接缝）、
> §5.2；docs/code_review_report.md §G G1/G3；手册 ecp-commands.md §1.1
> 范围：纯 Dart 控制台核心（行解析/补全/视图模型/Core），**零 Widget、
> 零 UI 装配**（G2 才做搜索栏注入）。G3 的接缝验收在本期以静态约束
> 测试前置钉死。

## Repository Research

- **总线即唯一校验**：[control_bus.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/control/control_bus.dart)
  `execute({channel, cmd, rawArgs:Map, confirmed, nonce})` 已收口类型
  转换（String→int/bool/date 全支持）、未知参数/缺参 USAGE、鉴权、
  审计、超时（spec.timeout，普通 10s/slow 60s，测试缝 timeoutOverride）。
  slash 通道只需把行文本翻译成 `execute(channel: slash, …)`，**禁止
  第二套类型/必填校验**。
- **adb 脚本的两处硬编码不得照搬**：
  1. `BOOL_FLAGS=(dry-run reset keep-seeds wait-snapshot)` 手工名单
     （[echo-cmd:31](file:///home/phenol/Documents/GitHub/Echo/scripts/echo-cmd#L31)）——slash
     布尔集合必须从 `spec.params[type==boolean]` 派生；
  2. Python 侧对非布尔值做 int 猜测——slash 不需要：取值参数一律
     以 String 进 Map，总线 `_convert` 按清单转，`text="123"` 零误伤
     （比 adb 更严谨，adb 靠 string 分支 toString 兜底）。
- **kebab→camel**：CLI/手册参数形态是 `--keep-seeds`，清单是
  camelCase（`keepSeeds`）；echo-cmd Python `camelize` 是现唯一转换
  点，slash 解析器内置同款转换并以同源样例对拍（无连字符不变；
  `dry-run→dryRun`；`text-stdin` 不是命令参数，见下行）。
- **语法现状**：手册 §1.1 slash 形式为 `/命名空间 动词 [参数]`，adb
  为 `ns.verb`；解析器两种都收（`/diary list --month 2026-10` 与
  `diary.list --month=2026-10` 等价）。全局标志 `--format/--stay/
  --timeout` 总线已知忽略（globalFlags），`--confirm` 提升为
  execute.confirmed，`--stay` 同时标记在 entry 上供 G2 收起决策。
- **多行进文本**：adb 侧靠 `--text-stdin` 经环境变量注入；slash 不改
  参数契约，方案见下「多行进文本」。
- **help**：`sys.help --command <全名>` 已返回 `toHelp(detailed:true)`；
  尾随 `?`/`--help` 由 core 翻译成该调用，不新造 man 数据。
- **补全可见性**：release 风味下 bus.register 物理跳过 debugOnly，
  `visibleSpecs` 天然裁剪——补全引擎只读它，**不加二次黑白名单**。
- **错误结构**：ControlException 已带 need/elevate/retryAfterMs
  （[control_error.dart](file:///home/phenol/Documents/GitHub/Echo/echo/lib/src/control/protocol/control_error.dart)）；
  视图模型扁平透出，G2 的 PIN 面板据此直接渲染，无需解析 message。
- **测试基建**：`ControlHarness`（test/control/control_test_harness.dart）
  持真 bus + auth + registry，exec 默认 adb 通道、可传 channel；
  release 风味可构造。G1 全部经真 bus 走 slash 通道。

## Files and Modules

**新增（lib，均在 `echo/lib/src/control/slash/`）**

- `line_parser.dart`：纯函数行解析。
  - `tokenize(String) → List<SlashToken>`：单/双引号（引号内空格、
    `--`、**真实换行**均为字面，不做 shell 转义/变量展开）；无引号
    token 以空白切分。
  - `ParsedInvocation{cmd, args(Map<String,Object?>), confirmed,
    stay, helpIntent}`；`parseLine(String, {required SpecLookup})`：
    去前导 `/`；命令名支持 `ns.verb` 与 `ns verb`；`--k=v`/`--k v`/
    布尔开关；布尔集合 = spec.booleanParams ∪ {confirm, stay}
    （format/timeout 永远取值）；未知 `--x` 默认吞一个非 `--` token
    后交给总线 USAGE；kebab→camel；值一律 String（布尔给 bool）。
  - helpIntent：末 token 为 `?`、命令 token 以 `?` 结尾
    （`diary.list?`）、或出现 `--help`。
  - 解析期错误抛 `SlashUsageException`（只用于「无法形成调用」：
    引号未闭合/裸位置参数/参数缺值/命令名形态非法），由 core 映射
    USAGE 信封；**类型错误/未知参数/缺参不抛，进总线**。
- `completion.dart`：`CompletionEngine(List<CommandSpec>)` +
  `complete(String text) → CompletionResult{segment, replaceStart,
  candidates[]}`。三段：namespace（ns 去重，insert `ns.`）→
  verb（同 ns，insert `verb `）→ param（未出现的 spec.params，
  required 排前、带类型名与 summary；全局标志按命令形态追加：
  requiresConfirm 才给 `--confirm`，常驻 `--stay/--format/--timeout`）。
  正在写 `--xx` 时按参数名前缀过滤。布尔参数 insert `--flag `，
  取值参数 insert `--name `。
- `result_view.dart`：信封 → 不可变视图模型（密封类）：
  `ErrorView{code,message,need,elevate,retryAfterMs}`；
  `TableView{columns,rows}`（result.items 为 Map 列表）；
  `KeyValueView{entries}`（标量 Map；嵌套 Map 递归；List/复杂值降级
  内嵌 JsonView）；`JsonView{text}`（缩进 JSON，长按复制由 G2 做）。
  工厂 `viewOf(ControlEnvelope)`。
- `console_core.dart`：`ControlConsoleCore extends ChangeNotifier`
  （项目既有 ChangeNotifier 风格，保护项 §D.5 不引框架）。
  - 状态：`entries`（不可变 List<ConsoleEntry>，新→旧或追加顺序，
    定追加顺序）、`busy`（任一 running）、命令历史与召回指针。
  - `submitLine(String)`：空行忽略；解析失败→合成 USAGE 失败信封
    入列（不经总线）；helpIntent→改调 `sys.help --command`；正常
    →`bus.execute(channel: ControlChannel.slash, …)`；提交即写历史，
    entry 先 pending 后回填 envelope+view，每步 notifyListeners。
  - 并发策略：允许多条在飞（entry 各自 pending/done），busy=任一在跑；
    超时态**复用总线 spec.timeout**（不另造定时器），TIMEOUT 信封
    经 ErrorView 呈现。
  - `submitMultiline({required String head, required String param,
    required String text})`：多行进文本唯一入口（见下）。
  - 历史：会话内上限 100 条，连续重复去重；`recallOlder()/recallNewer()
    /resetRecall()` 实现 ↑↓；**auditRedact 参数的值在历史行中替换为
    `<redacted:N>`**（N=trim 后长度），历史不含正文/PIN 字面。
- `slash.dart`：barrel export。

**新增（test，`echo/test/control/slash/`）**

- `line_parser_test.dart`（重点）：两种命令形态、`=`/空格赋值、
  引号（含引号内换行/引号内 `--x` 字面）、布尔从 spec 派生
  （`--dry-run` 与 `--dry-run=false`；未知布尔不臆造）、kebab 转换
  与 echo-cmd camelize 对拍样例、数字保持字符串、`?` 三种形态、
  裸位置参数/未闭合引号/缺值 → SlashUsageException、confirm/stay
  提取、未知命令也能解析（交给总线 UNKNOWN_COMMAND）。
- `completion_test.dart`：空输入/`/`、ns 前缀、verb 前缀（点号与
  空格两形态）、参数段 required 优先与前缀过滤、`--confirm` 只对
  destructive 命令出现、debug 风味含 clock.set 而 release 风味
  CompletionEngine(bus.visibleSpecs) 物理不含。
- `result_view_test.dart`：items→表（列取键并集）、键值、嵌套、
  错误 need/elevate 扁平透出、JsonView 兜底。
- `console_core_test.dart`：经 harness 真 bus 走 slash——
  ping 成功流 + busy 翻转；USAGE/UNKNOWN_COMMAND 失败 entry；
  AUTH_REQUIRED entry 的 ErrorView.need=3（G2 面板消费点）；
  helpIntent 走 sys.help；超时（注册 timeoutOverride 慢 spec）收到
  TIMEOUT；历史 ↑↓ 与连续去重；**历史中 auditRedact 值占位**；
  submitMultiline 成功/互斥 USAGE/非 string 参数 USAGE。
- `slash_seam_test.dart`（G3 接缝前置）：扫 slash/ 全部 `.dart`
  源码，禁止 import `package:flutter/widgets|material|cupertino`
  （只允许 `package:flutter/foundation.dart` 的 ChangeNotifier）；
  同测可被一个「假第二消费者」纯 Dart 类持有并驱动（最小挂载证明）。

**修改**

- `docs/ecp/ecp-commands.md` §1.1：补 slash 行语法小段（两种命令
  形态等价、引号极简语义、尾随 `?`/`--help` 出 man、历史不记录
  脱敏参数字面）。契约字段不变。
- 无 android/、无 bootstrap/UI 改动（G2 再装配）。

## 多行进文本方案（不改命令参数契约）

1. **行内粘贴**：`chat.send --id x "第一行\n第二行"`——tokenizer
   双引号内允许真实换行，天然走通，参数名仍是 `text`。
2. **输入区展开（G2 UI 主路径）**：G2 的多行展开态不把全文拼回命令
   行，而是调 core 的 `submitMultiline(head: 'chat.send --id x',
   param: 'text', text: 全文)`。core 解析 head（不含正文），校验：
   命令存在、param 在 spec.params 且 ArgType.string、head 中未以
   任何形态给出该参数（同现 → USAGE，与 adb `--text/--text-stdin`
   互斥语义一致），随后把全文原样注入 args 再 execute。换行保留、
   trim 语义与 store/adb 路径完全一致。
3. PIN 不走多行也不走命令行：G2 PIN 面板采集（与 adb 脚本 stdin
   同思路），历史与审计天然无 PIN 字面。

## Dependencies and Considerations

- 解析器只做「词法 + 形状」，类型/必填/未知参数/鉴权全部总线判定，
  错误信封形状跨通道一致。
- 历史脱敏与总线审计同一标记源（ParamSpec.auditRedact），不另立名单。
- Core 不引 Widget（G3 接缝）；时间/超时全用总线预算，core 无自有
  Timer；dispose 时在飞调用不取消（总线超时兜底），仅停止监听。
- 不注册命令、不改 manifest；补全数据源 = 当前风味 visibleSpecs。
- G2 将消费：ErrorView.need/elevate（PIN 引导）、entry.stay
  （nav.goto 收起）、CompletionResult.replaceStart（输入框替换区间）。

## Validation

- `flutter analyze` 0；`flutter test` 全绿（基线 275，只增不减）；
  `dart format --set-exit-if-changed lib test` exit 0。
- 无 android/ 改动，不跑 JVM；不装机（真机矩阵在 G4，G1 无 UI 入口）。
- 独立提交（`feat(ecp): P3-G1 slash 控制台核心…`），plan 随提交入库。
