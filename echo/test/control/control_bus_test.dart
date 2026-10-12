import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/auth/audit_log.dart';
import 'package:echo/src/control/control_bus.dart';
import 'package:echo/src/control/control_registry.dart';
import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_envelope.dart';
import 'package:echo/src/control/protocol/control_error.dart';

/// 永远放行/永远拒绝的裁决器（不涉及会话，纯总线测试用）。
class _AllowAll implements ControlAuthorizer {
  @override
  ControlException? check(
    CommandSpec spec,
    ControlChannel channel, {
    required bool confirmed,
  }) => null;
}

class _DenyAll implements ControlAuthorizer {
  _DenyAll(this.error);
  final ControlException error;

  @override
  ControlException? check(
    CommandSpec spec,
    ControlChannel channel, {
    required bool confirmed,
  }) => error;
}

CommandSpec _spec(
  String namespace,
  String verb,
  ControlLevel level, {
  bool debugOnly = false,
  List<ParamSpec> params = const [],
}) => CommandSpec(
  namespace: namespace,
  verb: verb,
  summary: 't',
  kind: CommandKind.read,
  level: level,
  debugOnly: debugOnly,
  params: params,
  handler: (_) async => {'ok': true},
);

Future<ControlEnvelope> _run(
  ControlBus bus,
  String cmd, {
  Map<String, Object?>? args,
  bool confirmed = false,
}) => bus.execute(
  channel: ControlChannel.adb,
  cmd: cmd,
  rawArgs: args,
  confirmed: confirmed,
);

void main() {
  ControlBus busWith(
    ControlAuthorizer auth, {
    ControlBuildMode mode = ControlBuildMode.debug,
    Iterable<CommandSpec> specs = const [],
  }) {
    final bus = ControlBus(
      buildMode: mode,
      services: ControlRegistry(),
      authorizer: auth,
      auditLog: AuditLog(),
    );
    bus.registerAll(specs);
    return bus;
  }

  group('ControlBus 注册/发现', () {
    test('重名注册抛 StateError', () {
      final bus = busWith(
        _AllowAll(),
        specs: [_spec('ns', 'get', ControlLevel.guest)],
      );
      expect(
        () => bus.register(_spec('ns', 'get', ControlLevel.guest)),
        throwsStateError,
      );
    });

    test('debug-only 命令在 release 不注册（物理不存在）', () {
      final debug = busWith(
        _AllowAll(),
        mode: ControlBuildMode.debug,
        specs: [_spec('ns', 'reset', ControlLevel.admin, debugOnly: true)],
      );
      final release = busWith(
        _AllowAll(),
        mode: ControlBuildMode.release,
        specs: [_spec('ns', 'reset', ControlLevel.admin, debugOnly: true)],
      );
      expect(debug.specOf('ns.reset'), isNotNull);
      expect(release.specOf('ns.reset'), isNull);
    });

    test('非法动词/命名空间在构造期拒绝', () {
      expect(
        () => CommandSpec(
          namespace: 'ns',
          verb: 'explode',
          summary: 'x',
          kind: CommandKind.write,
          level: ControlLevel.user,
          handler: (_) async => {},
        ),
        throwsArgumentError,
      );
      expect(
        () => CommandSpec(
          namespace: 'BadName',
          verb: 'get',
          summary: 'x',
          kind: CommandKind.read,
          level: ControlLevel.guest,
          handler: (_) async => {},
        ),
        throwsArgumentError,
      );
    });
  });

  group('ControlBus 执行收口', () {
    test('未知命令 → UNKNOWN_COMMAND(127)', () async {
      final env = await _run(busWith(_AllowAll()), 'ns.nope');
      expect(env.ok, isFalse);
      expect(env.exitCode, 127);
      expect(env.error!.code, ControlErrorCode.unknownCommand);
    });

    test('裁决拒绝 → 原样返回错误码', () async {
      final bus = busWith(
        _DenyAll(const ControlException(ControlErrorCode.authRequired, 'x')),
        specs: [_spec('ns', 'get', ControlLevel.owner)],
      );
      final env = await _run(bus, 'ns.get');
      expect(env.exitCode, 3);
      expect(env.error!.code, ControlErrorCode.authRequired);
    });

    test('必填缺失/类型不符/未知参数 → USAGE', () async {
      final bus = busWith(
        _AllowAll(),
        specs: [
          _spec(
            'ns',
            'get',
            ControlLevel.guest,
            params: [
              ParamSpec('date', type: ArgType.date, required: true),
              ParamSpec('limit', type: ArgType.integer),
            ],
          ),
        ],
      );
      expect((await _run(bus, 'ns.get')).error!.code, ControlErrorCode.usage);
      expect(
        (await _run(bus, 'ns.get', args: {'date': '2026-13-40'})).error!.code,
        ControlErrorCode.usage,
      );
      expect(
        (await _run(
          bus,
          'ns.get',
          args: {'date': '2026-10-12', 'limit': 'x'},
        )).error!.code,
        ControlErrorCode.usage,
      );
      expect(
        (await _run(
          bus,
          'ns.get',
          args: {'date': '2026-10-12', 'bogus': 1},
        )).error!.code,
        ControlErrorCode.usage,
      );
    });

    test('缺省值填充 + 日期严格解析', () async {
      Object? seen;
      final bus = busWith(
        _AllowAll(),
        specs: [
          CommandSpec(
            namespace: 'ns',
            verb: 'get',
            summary: 't',
            kind: CommandKind.read,
            level: ControlLevel.guest,
            params: [
              ParamSpec('limit', type: ArgType.integer, defaults: 50),
              ParamSpec('date', type: ArgType.date),
            ],
            handler: (ctx) async {
              seen = {
                'limit': ctx.arg<int>('limit'),
                'date': ctx.arg<DateTime>('date').toIso8601String(),
              };
              return {};
            },
          ),
        ],
      );

      final env = await _run(bus, 'ns.get', args: {'date': '2026-10-12'});
      expect(env.ok, isTrue, reason: env.error?.toString());
      expect(seen, {'limit': 50, 'date': '2026-10-12T00:00:00.000'});
    });

    test('slow 规格超时为 60s（普通 10s）', () {
      final bus = busWith(
        _AllowAll(),
        specs: [
          CommandSpec(
            namespace: 'ns',
            verb: 'get',
            summary: 't',
            kind: CommandKind.read,
            level: ControlLevel.guest,
            slow: true,
            handler: (_) async => {},
          ),
        ],
      );
      expect(bus.specOf('ns.get')!.timeout, const Duration(seconds: 60));
    });
  });

  group('ControlBus 审计', () {
    test('≥2 级命令成功入审计，1 级不入', () async {
      late AuditLog audit;
      final bus =
          ControlBus(
            buildMode: ControlBuildMode.debug,
            services: ControlRegistry(),
            authorizer: _AllowAll(),
            auditLog: audit = AuditLog(),
          )..registerAll([
            _spec('r', 'get', ControlLevel.owner),
            _spec('w', 'set', ControlLevel.user),
          ]);
      await _run(bus, 'r.get');
      await _run(bus, 'w.set');
      final cmds = audit.list().map((e) => e.cmd).toSet();
      expect(cmds, contains('w.set'));
      expect(cmds, isNot(contains('r.get')));
    });

    test('清单标 auditRedact 的参数脱敏（N=trim 后长度）', () async {
      late AuditLog audit;
      final bus =
          ControlBus(
            buildMode: ControlBuildMode.debug,
            services: ControlRegistry(),
            authorizer: _AllowAll(),
            auditLog: audit = AuditLog(),
          )..register(
            _spec(
              'w',
              'set',
              ControlLevel.user,
              params: [
                ParamSpec('pin', type: ArgType.string, auditRedact: true),
                // 未标记者照常落字面，证明脱敏由清单标记驱动而非键名。
                ParamSpec('note', type: ArgType.string),
              ],
            ),
          );
      await _run(bus, 'w.set', args: {'pin': '  123456  ', 'note': '明文'});
      final params = audit.list().single.paramSummary;
      expect(params['pin'], isNot(contains('123456')));
      expect(params['pin'], '<redacted:6>'); // trim 后长度，非原始 10
      expect(params['note'], '明文');
    });

    test('E3：过鉴权后业务失败仍入审计（ok=false + 错误码）', () async {
      late AuditLog audit;
      final bus =
          ControlBus(
            buildMode: ControlBuildMode.debug,
            services: ControlRegistry(),
            authorizer: _AllowAll(),
            auditLog: audit = AuditLog(),
          )..register(
            CommandSpec(
              namespace: 'w',
              verb: 'ensure',
              summary: 't',
              kind: CommandKind.write,
              level: ControlLevel.user,
              // 已通过裁决（_AllowAll），handler 抛业务异常：
              // 修复前此类失败完全不入审计。
              handler: (_) async => throw const ControlException(
                ControlErrorCode.conflict,
                '该日已归档',
              ),
            ),
          );

      final env = await _run(bus, 'w.ensure');
      expect(env.ok, isFalse);
      expect(env.error!.code, ControlErrorCode.conflict);

      final entry = audit.list().single;
      expect(entry.cmd, 'w.ensure');
      expect(entry.ok, isFalse);
      expect(entry.errorCode, ControlErrorCode.conflict.wire);
    });

    test('E3：3 级命令执行超时入审计（ok=false + TIMEOUT）', () async {
      late AuditLog audit;
      final bus =
          ControlBus(
            buildMode: ControlBuildMode.debug,
            services: ControlRegistry(),
            authorizer: _AllowAll(),
            auditLog: audit = AuditLog(),
          )..register(
            CommandSpec(
              namespace: 'w',
              verb: 'reset',
              summary: 't',
              kind: CommandKind.lifecycle,
              level: ControlLevel.admin,
              slow: true,
              // 测试缝把 60s 预算压到 50ms，handler 永不完成。
              timeoutOverride: const Duration(milliseconds: 50),
              handler: (_) =>
                  Completer<void>().future.then((_) => <String, Object?>{}),
            ),
          );

      final env = await _run(bus, 'w.reset', confirmed: true);
      expect(env.ok, isFalse);
      expect(env.error!.code, ControlErrorCode.timeout);

      final entry = audit.list().single;
      expect(entry.cmd, 'w.reset');
      expect(entry.ok, isFalse);
      expect(entry.errorCode, ControlErrorCode.timeout.wire);
    });
  });
}
