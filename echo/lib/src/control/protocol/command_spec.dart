/// ECP 命令清单模型（manifest-first，设计文档 §2/§4）。
///
/// 每条命令在代码里声明式定义**一次**：slash 补全、adb 参数校验、
/// `sys.help`、未来 MCP JSON Schema 都从这里派生。命令处理函数只做
/// 「解包参数 → 调公开 API → 结果 JSON 化」，不写自己的校验规则。
library;

import 'control_error.dart';

/// 构建风味：debug-only 命令（拨钟/灌数/重置）只在 debug 风味注册。
enum ControlBuildMode { debug, release }

// --------------------------------------------------------------------
//  权限级别与通道
// --------------------------------------------------------------------

/// 四级权限（设计 §5.1）。
enum ControlLevel {
  /// 公开只读。
  guest(0),

  /// 所有者私人数据读取。
  owner(1),

  /// 可逆的常规业务写。
  user(2),

  /// 批量删除 / 清空 / 数据外带 / 灌数 / 鉴权变更。
  admin(3);

  const ControlLevel(this.value);
  final int value;

  static ControlLevel of(int value) =>
      ControlLevel.values.firstWhere((l) => l.value == value);
}

/// 调用通道的信任配置（设计 §5.2）。
///
/// 起始级别 = 未解锁时该通道天然拥有的级别；上限 = 解锁后最多可达
/// 级别（MCP 长期铁律：上限 1，只读）。
enum ControlChannel {
  /// adb 广播：仅 debug 包物理存在；物理控制台类比。
  adb('adb', startLevel: ControlLevel.user, maxLevel: ControlLevel.admin),

  /// slash 指令台：用户本人持机（P3 接入，级别模型先行）。
  slash('slash', startLevel: ControlLevel.user, maxLevel: ControlLevel.admin),

  /// MCP / 未来网络通道：默认只读上限，写能力永不随 debug 放开。
  mcp('mcp', startLevel: ControlLevel.guest, maxLevel: ControlLevel.owner);

  const ControlChannel(
    this.wire, {
    required this.startLevel,
    required this.maxLevel,
  });

  final String wire;
  final ControlLevel startLevel;
  final ControlLevel maxLevel;
}

// --------------------------------------------------------------------
//  参数
// --------------------------------------------------------------------

/// 受控参数类型（机读优先：校验与未来 JSON Schema 派生共用）。
enum ArgType {
  string('string'),
  integer('integer'),
  boolean('boolean'),

  /// `YYYY-MM-DD`，按 04:00 日记日语义解释，校验后为 [DateTime]（正午）。
  date('date'),

  /// `YYYY-MM`。
  month('month'),

  /// ISO 8601 本地时间 `YYYY-MM-DDTHH:mm[:ss]`，校验后为 [DateTime]。
  dateTime('dateTime');

  const ArgType(this.wire);
  final String wire;
}

/// 单个参数的清单声明。
class ParamSpec {
  const ParamSpec(
    this.name, {
    required this.type,
    this.required = false,
    this.defaults,
    this.summary = '',
    this.auditRedact = false,
  });

  /// 参数名（`--name` 中的 name）。
  final String name;
  final ArgType type;
  final bool required;

  /// 缺省值（未传参时使用；与 [required] 互斥语义）。
  final Object? defaults;
  final String summary;

  /// 审计脱敏标记：为 true 时总线不把该参数的字面值写入审计流水，
  /// 只记 `<redacted:N>`（N 为 trim 后的落库长度）。PIN、聊天正文
  /// 等敏感/隐私内容用此标记，而非在总线硬编码键名——P4 若有新的
  /// 正文类参数（备注/回复等）直接在清单标注即可，审计层零改动。
  final bool auditRedact;

  Map<String, Object?> toHelp() => {
    'name': name,
    'type': type.wire,
    'required': required,
    if (defaults != null) 'default': defaults,
    if (auditRedact) 'auditRedact': true,
    'summary': summary,
  };
}

// --------------------------------------------------------------------
//  命令规格
// --------------------------------------------------------------------

/// 命令种类：读 / 写 / 信号 / 生命周期（设计 §2 读写分治）。
enum CommandKind {
  read('read'),
  write('write'),
  signal('signal'),
  lifecycle('lifecycle');

  const CommandKind(this.wire);
  final String wire;
}

/// 一条命令的不可变清单。
///
/// 构造即校验：命名必须落在受控动词表内；3 级命令一律需要显式确认；
/// debug-only 命令只允许出现在 debug 构建（注册时二次过滤）。
class CommandSpec {
  CommandSpec({
    required this.namespace,
    required this.verb,
    required this.summary,
    required this.kind,
    required this.level,
    required this.handler,
    this.idempotent = true,
    this.debugOnly = false,
    this.slow = false,
    this.destructive = false,
    this.params = const [],
    bool? confirmRequired,
    // 测试缝：仅单测用来缩短 10s/60s 超时，生产命令一律不传
    //（生产超时只由 slow 决定，避免命令私自放宽预算）。
    Duration? timeoutOverride,
  }) : requiresConfirm = confirmRequired ?? level == ControlLevel.admin,
       timeout =
           timeoutOverride ??
           (slow ? const Duration(seconds: 60) : const Duration(seconds: 10)) {
    if (!controlledVerbs.contains(verb)) {
      throw ArgumentError.value(
        verb,
        'verb',
        '不受控动词；如需扩充先改命令手册并走评审：$namespace.$verb',
      );
    }
    if (namespace.isEmpty || !namespace.contains(RegExp(r'^[a-z][a-z0-9]*$'))) {
      throw ArgumentError.value(namespace, 'namespace', '命名空间非法');
    }
  }

  final String namespace;
  final String verb;

  /// 一句话摘要（sys.help 与未来 slash 补全同源）。
  final String summary;
  final CommandKind kind;
  final ControlLevel level;

  /// 重复执行是否产生相同效果（manual 每条标注，测试校验非空声明）。
  final bool idempotent;

  /// 仅 debug 构建注册（release manifest 中物理不存在）。
  final bool debugOnly;

  /// 长命令（导出等）：超时上限 60s，否则 10s。
  final bool slow;

  /// 破坏性命令（prune/reset 等）：清单一致性测试校验破坏性 3 级
  /// 必须同时要求 `--confirm`。
  final bool destructive;

  final List<ParamSpec> params;

  /// 3 级命令一律需要 `--confirm`（设计 §5.2）。
  final bool requiresConfirm;

  /// 执行超时。
  final Duration timeout;

  /// 处理函数：参数已由总线完成类型校验与缺省填充。
  final Future<Map<String, Object?>> Function(CommandContext context) handler;

  /// 规范全名 `<namespace>.<verb>`。
  String get name => '$namespace.$verb';

  Map<String, Object?> toHelp({bool detailed = false}) => {
    'name': name,
    'summary': summary,
    'kind': kind.wire,
    'level': level.value,
    'idempotent': idempotent,
    'debugOnly': debugOnly,
    'params': params.map((p) => p.toHelp()).toList(),
    if (detailed) ...{
      'requiresConfirm': requiresConfirm,
      'timeoutMs': timeout.inMilliseconds,
    },
  };

  /// 受控动词表（设计 §4）；扩充 = 协议变更，先改手册。
  static const Set<String> controlledVerbs = {
    // 读
    'list', 'get', 'status', 'page', 'snapshot',
    // 写
    'goto', 'open', 'create', 'set', 'send', 'refresh', 'ensure',
    // 带点/连字符的复合动词（与手册冻结名一致）
    'clock.set', 'set-pin', 'mark-read',
    // 信号
    'notify', 'exception', 'view', 'resolve',
    // 生命周期
    'prune', 'delete', 'reset', 'export',
    // 协议自身
    'ping', 'help', 'info', 'audit',
    // 鉴权
    'unlock', 'lock',
  };
}

// --------------------------------------------------------------------
//  执行上下文
// --------------------------------------------------------------------

/// 传给处理函数的运行上下文：总线句柄、通道、校验后的参数包。
class CommandContext {
  CommandContext({
    required this.bus,
    required this.channel,
    required this.spec,
    required this.args,
  });

  final ControlBusHandle bus;
  final ControlChannel channel;
  final CommandSpec spec;

  /// 已完成类型校验与缺省填充的参数包。
  final Map<String, Object?> args;

  /// 取必填/已填缺省的参数；类型由清单保证。
  T arg<T>(String name) => args[name] as T;

  /// 取可空参数（未传且无缺省为 null）。
  T? optionalArg<T>(String name) => args[name] as T?;

  /// 取已注册的域服务（仓储/时钟/控制器…）；未注册返回 null。
  T? service<T extends Object>() => bus.services.get<T>();

  /// 取域服务；对应模块尚未装配（如未进过笔记页）时抛 NOT_READY。
  T requireService<T extends Object>(String what) =>
      bus.services.require<T>(what);
}

/// 总线暴露给命令层的最小句柄。
abstract class ControlBusHandle {
  /// 类型键控的服务注册表（具体实现见 control_registry.dart）。
  ControlServices get services;

  /// 当前构建风味（首装 PIN 等命令需要区分 debug/release）。
  ControlBuildMode get buildMode;

  /// 当前清单中已注册的全部命令（`sys.help` 枚举来源）。
  List<CommandSpec> get visibleSpecs;
}

/// 权限裁决的协议层契约（auth/ 层实现）：返回 null 放行，
/// 否则返回描述拒绝原因的 [ControlException]。
///
/// 含 3 级命令的 `--confirm` 检查，保证裁决逻辑只存在于 auth 层一处。
abstract class ControlAuthorizer {
  ControlException? check(
    CommandSpec spec,
    ControlChannel channel, {
    required bool confirmed,
  });
}

/// 服务注册表的协议层契约：按类型存取，命令层不关心装配过程。
///
/// 未就绪语义统一为 [ControlException]（NOT_READY）：命令依赖的模块
/// 还没完成 bootstrap 时给调用方可判定的错误，而不是空指针。
abstract class ControlServices {
  /// 取已注册服务；未注册返回 null。
  T? get<T extends Object>();

  /// 取服务；未注册抛 NOT_READY，[what] 为中文服务名（用于报错）。
  T require<T extends Object>(String what);
}
