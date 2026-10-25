import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/mcp/mcp_server.dart';
import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_error.dart';

import '../control_test_harness.dart';

/// R4｜MCP 只读适配器：工具/资源派生、JSON-RPC 协议、权限与写边界。
///
/// 冻结口径（2026-10-25 用户裁定）：
/// - tools = `ControlBus.visibleSpecs` 的只读子集 **+ 唯一解锁例外**
///   `auth.unlock`（否则 owner 只读正文不可达）；
/// - 除 `auth.unlock` 外的写命令在**适配器层**即拒（JSON-RPC -32602，
///   data.code=UNKNOWN_COMMAND），不进入总线（审计流水条数不变可证）；
/// - 解锁后仍是 owner 只读上限，`diary.state.set`/`chat.send` 永远不可达；
/// - 总线业务失败统一放在 `result.isError=true` 的 content 里，并带
///   `_meta.code`（本组钉死；resources/read 则走 JSON-RPC error.data）；
/// - resources/read 与 tools/call 同一条总线路径，guest 未解锁时
///   owner 级正文资源回 `AUTH_REQUIRED`。
void main() {
  late ControlHarness h;
  late McpServer server;

  setUp(() async {
    h = await ControlHarness.create();
    server = McpServer(bus: h.bus);
  });

  tearDown(() => h.dispose());

  Future<Map<String, Object?>> call(
    String method, {
    Map<String, Object?>? params,
    Object? id = 1,
  }) async {
    final request = <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    };
    final raw = await server.handleLine(jsonEncode(request));
    expect(raw, isNotNull, reason: '请求应产生 JSON-RPC 响应');
    return (jsonDecode(raw!) as Map).cast<String, Object?>();
  }

  Object? resultOf(Map<String, Object?> response) {
    expect(response['error'], isNull, reason: response.toString());
    return response['result'];
  }

  Future<void> unlockMcpOwner() async {
    await h.pins.initialize(newPin: '1234', confirmPin: '1234');
    expect(await h.auth.requestUnlock(ControlChannel.mcp, '1234'), isNull);
    expect(h.auth.effectiveLevel(ControlChannel.mcp), ControlLevel.owner);
  }

  group('工具派生（清单即真相）', () {
    test('tools = 只读可见命令 + 唯一解锁例外；其余写命令不在表内', () async {
      final readOnly = h.bus.visibleSpecs
          .where(
            (s) =>
                s.kind == CommandKind.read &&
                s.level.value <= ControlLevel.owner.value,
          )
          .toList(growable: false);
      final unlock = h.bus.specOf(McpServer.unlockCommand);
      expect(unlock, isNotNull, reason: '解锁命令必须已注册');
      final exposed = [...readOnly, unlock!];

      final result = resultOf(await call('tools/list'))! as Map;
      final tools = (result['tools'] as List).cast<Map<String, Object?>>();

      expect(tools.length, exposed.length);
      expect(
        tools.map((t) => t['name']).toSet(),
        exposed.map((s) => s.name).toSet(),
      );
      expect(tools.map((t) => t['name']), contains(McpServer.unlockCommand));

      for (final tool in tools) {
        final name = tool['name'] as String;
        final spec = h.bus.specOf(name);
        expect(spec, isNotNull, reason: '$name 不在 CommandSpec 清单');
        final resolved = spec!;
        // 已裁定：解锁是唯一允许进入 tools 的写命令。
        if (name == McpServer.unlockCommand) {
          expect(resolved.kind, CommandKind.write);
        } else {
          expect(resolved.kind, CommandKind.read, reason: '$name 不是只读命令');
        }
        expect(
          resolved.level.value,
          lessThanOrEqualTo(ControlLevel.owner.value),
          reason: '$name 超出 owner 只读上限',
        );

        final schema = tool['inputSchema'] as Map;
        expect(schema['type'], 'object');
        final properties = (schema['properties'] as Map?) ?? const {};
        final required = ((schema['required'] as List?) ?? const [])
            .cast<String>()
            .toSet();

        // 双向：Schema 属性 == 清单参数；required == 清单 required。
        expect(
          properties.keys.toSet(),
          resolved.params.map((p) => p.name).toSet(),
          reason: '$name Schema 属性与 ParamSpec 不一致',
        );
        expect(
          required,
          resolved.params.where((p) => p.required).map((p) => p.name).toSet(),
          reason: '$name required 与 ParamSpec 不一致',
        );
        for (final param in resolved.params) {
          final prop = properties[param.name] as Map;
          expect(prop['type'], switch (param.type) {
            ArgType.integer => 'integer',
            ArgType.boolean => 'boolean',
            _ => 'string',
          });
        }
      }

      final names = tools.map((t) => t['name']).toSet();
      for (final write in [
        'diary.state.set',
        'diary.ensure',
        'chat.send',
        'auth.set-pin',
        'auth.lock',
      ]) {
        expect(names, isNot(contains(write)), reason: '$write 不应出现在 tools');
      }
    });
  });

  group('JSON-RPC 协议', () {
    test('initialize 返回版本/serverInfo/tools+resources 能力', () async {
      final result = resultOf(await call('initialize'))! as Map;
      expect(result['protocolVersion'], McpServer.protocolVersion);
      expect((result['serverInfo'] as Map)['name'], 'echo-mcp');
      final caps = result['capabilities'] as Map;
      expect(caps['tools'], isA<Map>());
      expect(caps['resources'], isA<Map>());
    });

    test('notifications/initialized 无响应；ping 正常', () async {
      final raw = await server.handleLine(
        jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      );
      expect(raw, isNull, reason: '通知不应产生响应');

      final pong = await call('ping');
      expect(resultOf(pong), isEmpty);
    });

    test('未知方法 -32601；非法 params -32602；坏 JSON -32700', () async {
      final unknown = await call('no/such/method');
      expect((unknown['error'] as Map)['code'], -32601);

      final badParams = await call('tools/list', params: {'x': 1});
      // tools/list 不校验额外字段，换 tools/call 的 params 形状验证。
      expect(badParams['error'], isNull);
      final rawBad = await server.handleLine(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': [1, 2],
        }),
      );
      expect(((jsonDecode(rawBad!) as Map)['error'] as Map)['code'], -32602);

      final broken = await server.handleLine('{not json');
      expect(((jsonDecode(broken!) as Map)['error'] as Map)['code'], -32700);
    });

    test('tools/call 读 sys.status 正常（owner 会话）', () async {
      await unlockMcpOwner();
      final result =
          resultOf(
                await call(
                  'tools/call',
                  params: {
                    'name': 'sys.status',
                    'arguments': <String, Object?>{},
                  },
                ),
              )!
              as Map;
      expect(result['isError'], isFalse);
      final structured = result['structuredContent'] as Map;
      expect(structured, contains('lifecycle'));
      expect(structured, contains('services'));
    });
  });

  group('只读边界（写命令物理不可达）', () {
    test('写命令在适配器层被拒且不进入总线（审计条数不变）', () async {
      await unlockMcpOwner(); // 即使 owner 会话存在，写仍不可达。
      final auditBefore = h.audit.length;

      final writes = <String, Map<String, Object?>>{
        'diary.state.set': {'date': '2026-10-12', 'state': 'exported'},
        'chat.send': {'id': 'incoming-1', 'text': 'x'},
        'diary.ensure': {'date': '2026-10-12'},
      };
      for (final entry in writes.entries) {
        final response = await call(
          'tools/call',
          params: {'name': entry.key, 'arguments': entry.value},
        );
        final error = response['error'] as Map;
        expect(error['code'], -32602, reason: '${entry.key} 应被适配器拒绝');
        expect(
          (error['data'] as Map)['code'],
          ControlErrorCode.unknownCommand.wire,
        );
      }
      // 写命令若进入总线，user/admin 级调用必入审计；条数不变即未触达。
      expect(h.audit.length, auditBefore);
    });

    test('未知工具同形拒绝；bus 业务失败落 isError content', () async {
      final unknown = await call(
        'tools/call',
        params: {'name': 'no.such', 'arguments': <String, Object?>{}},
      );
      expect((unknown['error'] as Map)['code'], -32602);

      final usage =
          resultOf(
                await call(
                  'tools/call',
                  params: {
                    'name': 'diary.get',
                    'arguments': <String, Object?>{},
                  },
                ),
              )!
              as Map;
      expect(usage['isError'], isTrue);
      expect((usage['_meta'] as Map)['code'], ControlErrorCode.usage.wire);
      final content = (usage['content'] as List).single as Map;
      expect(content['type'], 'text');
      expect(
        jsonDecode(content['text'] as String),
        containsPair('code', 'USAGE'),
      );
    });

    test('唯一写工具 auth.unlock：可解锁并读到 owner 级正文', () async {
      await h.execResult('diary.ensure', args: {'date': '2026-10-12'});
      await h.pins.initialize(newPin: '1234', confirmPin: '1234');

      // guest：正文资源仍被拒。
      final denied = await call(
        'resources/read',
        params: {'uri': 'echo://diary/2026-10-12'},
      );
      expect((denied['error'] as Map)['code'], -32000);

      final unlocked =
          resultOf(
                await call(
                  'tools/call',
                  params: {
                    'name': McpServer.unlockCommand,
                    'arguments': {'pin': '1234'},
                  },
                ),
              )!
              as Map;
      expect(unlocked['isError'], isFalse);
      expect(
        (unlocked['structuredContent'] as Map)['level'],
        ControlLevel.owner.value,
      );
      expect(h.auth.effectiveLevel(ControlChannel.mcp), ControlLevel.owner);

      final diary = await call(
        'resources/read',
        params: {'uri': 'echo://diary/2026-10-12'},
      );
      final text =
          (((resultOf(diary)! as Map)['contents'] as List).single
                  as Map)['text']
              as String;
      expect((jsonDecode(text) as Map)['date'], '2026-10-12');
    });

    test('auth.unlock PIN 错误：isError content 回 AUTH_DENIED', () async {
      await h.pins.initialize(newPin: '1234', confirmPin: '1234');

      final failed =
          resultOf(
                await call(
                  'tools/call',
                  params: {
                    'name': McpServer.unlockCommand,
                    'arguments': {'pin': '0000'},
                  },
                ),
              )!
              as Map;
      expect(failed['isError'], isTrue);
      expect(
        (failed['_meta'] as Map)['code'],
        ControlErrorCode.authDenied.wire,
      );
      expect(h.auth.isUnlocked(ControlChannel.mcp), isFalse);
    });
  });

  group('resources（同一条总线路径）', () {
    test('resources/list 含日记/聊天/sys/nav；模板可用', () async {
      final result = resultOf(await call('resources/list'))! as Map;
      final resources = (result['resources'] as List)
          .cast<Map<String, Object?>>();
      final uris = resources.map((r) => r['uri']).toSet();
      expect(
        uris,
        containsAll([
          'echo://diary',
          'echo://diary/{date}',
          'echo://chat',
          'echo://chat/{id}',
          'echo://chat/{id}/messages',
          'echo://sys/status',
          'echo://nav/status',
        ]),
      );
      expect(resources.where((r) => r.containsKey('uriTemplate')).length, 3);

      final templates =
          resultOf(await call('resources/templates/list'))! as Map;
      expect((templates['resourceTemplates'] as List).length, 3);
    });

    test('guest 未解锁：日记正文资源被拒 AUTH_REQUIRED', () async {
      final response = await call(
        'resources/read',
        params: {'uri': 'echo://diary/2026-10-12'},
      );
      final error = response['error'] as Map;
      expect(error['code'], -32000);
      expect(
        (error['data'] as Map)['code'],
        ControlErrorCode.authRequired.wire,
      );
    });

    test('owner 解锁后读日记/聊天正文；sys.audit 可见同源审计', () async {
      // UI 同源入口造一篇日记与一个 incoming 会话。
      await h.execResult('diary.ensure', args: {'date': '2026-10-12'});
      h.chatStore.addIncoming(text: '你好 MCP');
      final chatId = h.chatStore.conversations.first.id;

      await unlockMcpOwner();

      final diary = await call(
        'resources/read',
        params: {'uri': 'echo://diary/2026-10-12'},
      );
      final diaryContents = (resultOf(diary)! as Map)['contents'] as List;
      final diaryText = (diaryContents.single as Map)['text'] as String;
      final diaryJson = jsonDecode(diaryText) as Map;
      expect(diaryJson['date'], '2026-10-12');
      expect(diaryJson['blocks'], isA<List>());

      final chat = await call(
        'resources/read',
        params: {'uri': 'echo://chat/$chatId/messages'},
      );
      final chatText =
          (((resultOf(chat)! as Map)['contents'] as List).single as Map)['text']
              as String;
      final chatJson = jsonDecode(chatText) as Map;
      final messages = chatJson['messages'] as List;
      expect(messages, isNotEmpty);
      expect((messages.first as Map)['text'], '你好 MCP');

      // resources/read 与命令共用 AuditLog：解锁事件本身在审计里。
      final audit = await call(
        'resources/read',
        params: {'uri': 'echo://sys/audit'},
      );
      final auditText =
          (((resultOf(audit)! as Map)['contents'] as List).single
                  as Map)['text']
              as String;
      final entries = (jsonDecode(auditText) as Map)['entries'] as List;
      expect(
        entries.cast<Map>().any(
          (e) => e['cmd'] == 'auth.unlock' && e['channel'] == 'mcp',
        ),
        isTrue,
      );
    });

    test('未知资源 -32602 + NOT_FOUND', () async {
      final response = await call(
        'resources/read',
        params: {'uri': 'echo://diary/2026/10/12'},
      );
      final error = response['error'] as Map;
      expect(error['code'], -32602);
      expect((error['data'] as Map)['code'], ControlErrorCode.notFound.wire);
    });
  });
}
