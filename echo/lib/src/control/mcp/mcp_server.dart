import 'dart:convert';

import '../control_bus.dart';
import '../protocol/command_spec.dart';
import '../protocol/control_error.dart';

/// ECP 的 MCP Server 适配器（R4）：JSON-RPC 2.0 单行请求 → 控制总线。
///
/// 安全契约（用户 2026-10-25 裁定，长期约束）：
/// - 通道身份固定 [ControlChannel.mcp]：起始 guest，解锁后上限 owner；
/// - **只读 + 唯一解锁例外**：工具从 [ControlBus.visibleSpecs] 的
///   `kind == read` 子集自动派生，另加唯一的写工具 [unlockCommand]
///   （否则 owner 只读范围不可达）；其余写命令在适配器层即判「不可用」，
///   物理不进入总线；
/// - 解锁后仍是 owner 只读上限，`diary.state.set`/`chat.send` 等写命令
///   无论会话如何都不可达；PIN 错误退避沿用 [AuthManager] 的冷却策略；
/// - 暴露范围**包含日记与聊天正文**（owner 级只读，用户已确认）；
/// - 默认不挂载，release 物理不挂载（见 bootstrap/main 的 `--mcp` 开关）。
///
/// 不做第二份命令表：工具名、参数、必填/类型全部从 [CommandSpec] 派生；
/// 资源也只是「URI → 一条只读命令」的映射，`resources/read` 与
/// `tools/call` 走同一条 [ControlBus.execute] 路径，权限/审计不分叉。
class McpServer {
  McpServer({
    required this.bus,
    this.serverName = 'echo-mcp',
    this.serverVersion = '1.0.0',
  });

  /// MCP 协议版本（MCP 2024-11-05 基础能力：tools/resources）。
  static const String protocolVersion = '2024-11-05';

  /// 固定通道：起始 guest、上限 owner 只读。
  static const ControlChannel channel = ControlChannel.mcp;

  /// 唯一的写工具：解锁入口。
  ///
  /// 不暴露它，owner 级只读资源（日记/聊天正文）对 MCP 永远不可达。
  static const String unlockCommand = 'auth.unlock';

  final ControlBus bus;
  final String serverName;
  final String serverVersion;

  /// 可暴露给 MCP 的只读命令（一条命令 = 一个 tool）。
  ///
  /// 只读判定只用清单字段：`kind == read` 且级别不超过 owner。
  /// 写/信号/生命周期命令一律不在表内，`tools/call` 找不到即拒绝。
  List<CommandSpec> get readOnlySpecs =>
      bus.visibleSpecs.where(_isReadOnly).toList(growable: false);

  /// 实际可调用的工具集合：只读子集 + 唯一解锁例外。
  List<CommandSpec> get exposedSpecs {
    final specs = readOnlySpecs;
    final unlock = bus.specOf(unlockCommand);
    if (unlock == null) return specs;
    return [...specs, unlock];
  }

  static bool _isReadOnly(CommandSpec spec) =>
      spec.kind == CommandKind.read &&
      spec.level.value <= ControlLevel.owner.value;

  /// 处理一行 JSON-RPC 文本；返回要写回的单行 JSON（通知返回 null）。
  ///
  /// 永不抛业务异常：解析/协议错误也收敛成 JSON-RPC error 对象。
  Future<String?> handleLine(String line) async {
    final text = line.trim();
    if (text.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return jsonEncode(_failure(null, -32700, '解析错误：请求不是合法 JSON'));
    }
    if (decoded is! Map) {
      return jsonEncode(_failure(null, -32600, '请求必须是 JSON 对象'));
    }
    final response = await handle(decoded.cast<String, Object?>());
    return response == null ? null : jsonEncode(response);
  }

  /// 处理一个已解码的 JSON-RPC 请求对象（纯 Dart，单测直接调用）。
  ///
  /// 通知（无 `id` 成员）不产生响应；其余请求恒返回 JSON-RPC 2.0 对象。
  Future<Map<String, Object?>?> handle(Map<String, Object?> request) async {
    final isNotification = !request.containsKey('id');
    final id = request['id'];
    final method = request['method'];
    if (method is! String || method.isEmpty) {
      return isNotification ? null : _failure(id, -32600, '请求缺少 method');
    }

    final rawParams = request['params'];
    if (rawParams != null && rawParams is! Map) {
      return isNotification ? null : _failure(id, -32602, 'params 必须是 JSON 对象');
    }
    final params = (rawParams as Map?)?.cast<String, Object?>();

    final Map<String, Object?> response;
    switch (method) {
      case 'initialize':
        response = _success(id, _initializeResult());
      case 'notifications/initialized':
        // 标准通知：无响应；若客户端误带 id，回空结果保持宽容。
        response = _success(id, const <String, Object?>{});
      case 'ping':
        response = _success(id, const <String, Object?>{});
      case 'tools/list':
        response = _success(id, _toolsListResult());
      case 'tools/call':
        response = await _callTool(id, params);
      case 'resources/list':
        response = _success(id, {
          'resources': _resourceEntries(includeTemplates: true),
        });
      case 'resources/templates/list':
        response = _success(id, {
          'resourceTemplates': [
            for (final r in _resourceEntries(includeTemplates: true))
              if (r.containsKey('uriTemplate'))
                {
                  'uriTemplate': r['uriTemplate'],
                  'name': r['name'],
                  'description': r['description'],
                  'mimeType': r['mimeType'],
                },
          ],
        });
      case 'resources/read':
        response = await _readResource(id, params);
      default:
        response = _failure(id, -32601, '未知方法：$method');
    }
    return isNotification ? null : response;
  }

  // ---- initialize / tools -------------------------------------------------

  Map<String, Object?> _initializeResult() => {
    'protocolVersion': protocolVersion,
    'serverInfo': {'name': serverName, 'version': serverVersion},
    'capabilities': {
      'tools': {'listChanged': false},
      'resources': {'subscribe': false, 'listChanged': false},
    },
    'instructions':
        'Echo 控制面只读适配器：工具仅含只读命令，外加唯一的解锁工具 '
        'auth.unlock；日记/聊天正文为 owner 级只读，未解锁时被拒。'
        '其余写命令不可用。默认关闭，仅 debug 构建带 --mcp 启动时挂载。',
  };

  Map<String, Object?> _toolsListResult() => {
    'tools': [
      for (final spec in exposedSpecs)
        {
          'name': spec.name,
          'description': spec.summary,
          'inputSchema': _schemaFor(spec),
        },
    ],
  };

  /// 从清单参数派生 JSON Schema（name/type/required，有缺省则带 default）。
  ///
  /// 不手写枚举：清单目前没有枚举字段，未来若加入只需在这里补一次。
  static Map<String, Object?> _schemaFor(CommandSpec spec) {
    final properties = <String, Object?>{};
    final required = <String>[];
    for (final param in spec.params) {
      properties[param.name] = {
        'type': _jsonType(param.type),
        if (param.summary.isNotEmpty) 'description': param.summary,
        if (param.defaults != null) 'default': param.defaults,
      };
      if (param.required) required.add(param.name);
    }
    return {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };
  }

  static String _jsonType(ArgType type) => switch (type) {
    ArgType.integer => 'integer',
    ArgType.boolean => 'boolean',
    _ => 'string',
  };

  Future<Map<String, Object?>> _callTool(
    Object? id,
    Map<String, Object?>? params,
  ) async {
    final name = params?['name'];
    if (name is! String || name.isEmpty) {
      return _failure(id, -32602, 'tools/call 缺少 name');
    }
    final spec = exposedSpecs.where((s) => s.name == name).firstOrNull;
    if (spec == null) {
      // 只读集合之外的写命令在此物理不可达：不调用总线，不给调用方
      // 任何「存在但拒绝」之外的写能力探测面；错误形状与未知工具一致。
      return _failure(
        id,
        -32602,
        '工具不存在或 MCP 只读不可用：$name',
        data: ControlException(
          ControlErrorCode.unknownCommand,
          '工具不存在或 MCP 只读不可用：$name',
        ).toJson(),
      );
    }

    final rawArgs = params?['arguments'];
    if (rawArgs != null && rawArgs is! Map) {
      return _failure(
        id,
        -32602,
        'tools/call arguments 必须是 JSON 对象',
        data: const ControlException(
          ControlErrorCode.usage,
          'arguments 必须是 JSON 对象',
        ).toJson(),
      );
    }
    final args = (rawArgs as Map?)?.cast<String, Object?>();

    final envelope = await bus.execute(
      channel: channel,
      cmd: spec.name,
      rawArgs: args,
    );
    if (!envelope.ok) {
      final error = envelope.error!;
      return _success(id, {
        'content': [
          {'type': 'text', 'text': jsonEncode(error.toJson())},
        ],
        'isError': true,
        '_meta': {'code': error.code.wire},
      });
    }
    final result = envelope.result ?? const <String, Object?>{};
    return _success(id, {
      'content': [
        {'type': 'text', 'text': jsonEncode(result)},
      ],
      'isError': false,
      'structuredContent': result,
    });
  }

  // ---- resources ---------------------------------------------------------

  /// 资源清单：URI 一律映射到一条只读命令。
  ///
  /// 参数化资源同时给出 `uri` 与 `uriTemplate`（MCP 标准模板另见
  /// `resources/templates/list`），静态资源只给 `uri`。
  List<Map<String, Object?>> _resourceEntries({
    required bool includeTemplates,
  }) {
    const mime = 'application/json';
    final entries = <Map<String, Object?>>[
      _resource('echo://diary', '日记摘要列表', 'diary.list', mime),
      _resource(
        'echo://diary/{date}',
        '单篇日记（含正文块）',
        'diary.get',
        mime,
        template: true,
      ),
      _resource('echo://chat', '聊天会话列表', 'chat.list', mime),
      _resource(
        'echo://chat/{id}',
        '单会话元数据与消息页',
        'chat.get',
        mime,
        template: true,
      ),
      _resource(
        'echo://chat/{id}/messages',
        '单会话消息页（最多 100 条）',
        'chat.get',
        mime,
        template: true,
      ),
      _resource('echo://sys/status', 'App 现场与日记就绪概况', 'sys.status', mime),
      _resource('echo://sys/audit', '审计流水（倒序，已脱敏）', 'sys.audit', mime),
      _resource('echo://sys/info', '版本/设备信息', 'sys.info', mime),
      _resource('echo://nav/status', '当前导航页', 'nav.page', mime),
      _resource('echo://console/snapshot', '读数条快照', 'console.snapshot', mime),
      _resource('echo://badge/status', '导航锚点级别一览', 'badge.status', mime),
      _resource('echo://auth/status', 'PIN 与会话状态', 'auth.status', mime),
    ];
    if (includeTemplates) return entries;
    return entries.where((r) => !r.containsKey('uriTemplate')).toList();
  }

  Map<String, Object?> _resource(
    String uri,
    String name,
    String cmd,
    String mime, {
    bool template = false,
  }) {
    // 资源只在命令确实以只读形态注册时出现（debug/release 裁剪天然同步）。
    final spec = bus.specOf(cmd);
    return {
      'uri': uri,
      if (template) 'uriTemplate': uri,
      'name': name,
      'description': '${spec?.summary ?? cmd}（ECP 只读资源）',
      'mimeType': mime,
    };
  }

  Future<Map<String, Object?>> _readResource(
    Object? id,
    Map<String, Object?>? params,
  ) async {
    final rawUri = params?['uri'];
    if (rawUri is! String || rawUri.isEmpty) {
      return _failure(id, -32602, 'resources/read 缺少 uri');
    }
    final target = _resolveUri(rawUri);
    if (target == null) {
      return _failure(
        id,
        -32602,
        '未知 MCP 资源：$rawUri',
        data: ControlException(
          ControlErrorCode.notFound,
          '未知 MCP 资源：$rawUri',
        ).toJson(),
      );
    }
    final spec = bus.specOf(target.cmd);
    if (spec == null || !_isReadOnly(spec)) {
      return _failure(
        id,
        -32602,
        '资源对应命令不可用：$rawUri',
        data: ControlException(
          ControlErrorCode.unknownCommand,
          '资源对应命令不可用：$rawUri',
        ).toJson(),
      );
    }

    // 与 tools/call 完全同一条总线路径：权限裁决、参数校验、审计
    //（按清单级别）一律不分叉。
    final envelope = await bus.execute(
      channel: channel,
      cmd: target.cmd,
      rawArgs: target.args,
    );
    if (!envelope.ok) {
      final error = envelope.error!;
      return _failure(id, -32000, error.message, data: error.toJson());
    }
    return _success(id, {
      'contents': [
        {
          'uri': rawUri,
          'mimeType': 'application/json',
          'text': jsonEncode(envelope.result ?? const <String, Object?>{}),
        },
      ],
    });
  }

  /// `echo://...` → 命令 + 参数。未知/非法形状返回 null。
  ({String cmd, Map<String, Object?> args})? _resolveUri(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'echo') return null;
    final segments = uri.pathSegments;
    switch (uri.host) {
      case 'diary':
        if (segments.isEmpty) return (cmd: 'diary.list', args: const {});
        if (segments.length == 1) {
          return (cmd: 'diary.get', args: {'date': segments.single});
        }
        return null;
      case 'chat':
        if (segments.isEmpty) return (cmd: 'chat.list', args: const {});
        if (segments.length == 1) {
          return (cmd: 'chat.get', args: {'id': segments.single});
        }
        if (segments.length == 2 && segments.last == 'messages') {
          return (cmd: 'chat.get', args: {'id': segments.first, 'limit': 100});
        }
        return null;
      case 'sys':
        return switch (segments) {
          ['status'] => (cmd: 'sys.status', args: const {}),
          ['audit'] => (cmd: 'sys.audit', args: const {}),
          ['info'] => (cmd: 'sys.info', args: const {}),
          _ => null,
        };
      case 'nav':
        return segments.length == 1 && segments.single == 'status'
            ? (cmd: 'nav.page', args: const {})
            : null;
      case 'console':
        return segments.length == 1 && segments.single == 'snapshot'
            ? (cmd: 'console.snapshot', args: const {})
            : null;
      case 'badge':
        return segments.length == 1 && segments.single == 'status'
            ? (cmd: 'badge.status', args: const {})
            : null;
      case 'auth':
        return segments.length == 1 && segments.single == 'status'
            ? (cmd: 'auth.status', args: const {})
            : null;
      default:
        return null;
    }
  }

  // ---- JSON-RPC 响应 -----------------------------------------------------

  static Map<String, Object?> _success(Object? id, Object result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  static Map<String, Object?> _failure(
    Object? id,
    int code,
    String message, {
    Map<String, Object?>? data,
  }) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message, 'data': ?data},
  };
}
