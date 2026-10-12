import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/control_bus.dart';
import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_error.dart';

import 'control_test_harness.dart';

/// 各权限级别的规格（矩阵用；动词按级别区分以避免同总线重名）。
CommandSpec _levelSpec(ControlLevel level) {
  final (verb, kind) = switch (level) {
    ControlLevel.guest => ('help', CommandKind.read),
    ControlLevel.owner => ('get', CommandKind.read),
    ControlLevel.user => ('goto', CommandKind.write),
    ControlLevel.admin => ('reset', CommandKind.lifecycle),
  };
  return CommandSpec(
    namespace: 'x',
    verb: verb,
    summary: 't',
    kind: kind,
    level: level,
    handler: (_) async => {},
  );
}

void main() {
  group('权限矩阵（级别 × 通道）', () {
    late DateTime now;
    late ControlHarness h;

    setUp(() async {
      h = await ControlHarness.create();
      now = h.wallTime;
      await h.pins.initialize(newPin: '1234', confirmPin: '1234');
    });

    tearDown(() => h.dispose());

    ControlBus busWith() =>
        ControlBus(
            buildMode: ControlBuildMode.debug,
            services: h.registry,
            authorizer: h.auth,
            auditLog: h.audit,
          )
          ..register(_levelSpec(ControlLevel.guest))
          ..register(_levelSpec(ControlLevel.owner))
          ..register(_levelSpec(ControlLevel.user))
          ..register(_levelSpec(ControlLevel.admin));

    test('裁决器直测：通道起始级别与上限', () {
      // mcp 起始 0：guest 放行、owner 拒绝；adb 起始 2。
      expect(
        h.auth
            .check(
              _levelSpec(ControlLevel.guest),
              ControlChannel.mcp,
              confirmed: true,
            )
            ?.code,
        isNull,
      );
      expect(
        h.auth
            .check(
              _levelSpec(ControlLevel.owner),
              ControlChannel.mcp,
              confirmed: true,
            )
            ?.code,
        ControlErrorCode.authRequired,
      );
      // adb 上未解锁：裁决顺序是先「需解锁」再「需确认」（设计 §5）；
      // 已解锁但缺 --confirm 的分支由下面的用例覆盖。
      expect(
        h.auth
            .check(
              _levelSpec(ControlLevel.admin),
              ControlChannel.adb,
              confirmed: false,
            )
            ?.code,
        ControlErrorCode.authRequired,
      );
    });

    test('mcp 永不颁发写会话：unlock 直接拒绝', () async {
      final error = await h.auth.requestUnlock(ControlChannel.mcp, '1234');
      expect(error?.code, ControlErrorCode.authDenied);
    });

    test('adb 解锁：成功升至 3 级，失败保持原级，lock 降回', () async {
      final bus = busWith();

      final locked = await bus.execute(
        channel: ControlChannel.adb,
        cmd: 'x.reset',
        confirmed: true,
      );
      expect(locked.error?.code, ControlErrorCode.authRequired);

      expect(await h.auth.requestUnlock(ControlChannel.adb, 'bad'), isNotNull);
      expect(await h.auth.requestUnlock(ControlChannel.adb, '1234'), isNull);
      expect(
        (await bus.execute(
          channel: ControlChannel.adb,
          cmd: 'x.reset',
          confirmed: true,
        )).ok,
        isTrue,
      );

      h.auth.lock(ControlChannel.adb);
      final relocked = await bus.execute(
        channel: ControlChannel.adb,
        cmd: 'x.reset',
        confirmed: true,
      );
      expect(relocked.error?.code, ControlErrorCode.authRequired);
    });

    test('3 级缺 --confirm → CONFIRM_REQUIRED', () async {
      await h.auth.requestUnlock(ControlChannel.adb, '1234');
      final env = await busWith().execute(
        channel: ControlChannel.adb,
        cmd: 'x.reset',
        confirmed: false,
      );
      expect(env.error?.code, ControlErrorCode.confirmRequired);
    });

    test('App paused（息屏/切后台）即销毁全部会话', () async {
      await h.auth.requestUnlock(ControlChannel.adb, '1234');
      expect(h.auth.isUnlocked(ControlChannel.adb), isTrue);
      h.auth.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(h.auth.isUnlocked(ControlChannel.adb), isFalse);
      expect(
        h.audit.list().map((e) => e.cmd),
        contains('auth.session-expired'),
      );

      // inactive 瞬态不销毁，resumed 不重新发会话。
      await h.auth.requestUnlock(ControlChannel.adb, '1234');
      h.auth.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(h.auth.isUnlocked(ControlChannel.adb), isTrue);
      h.auth.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(h.auth.isUnlocked(ControlChannel.adb), isTrue);
    });

    test('连续 5 次错误冷却 30s；冷却内正确 PIN 也被拒', () async {
      for (var i = 0; i < 5; i++) {
        expect(
          (await h.auth.requestUnlock(ControlChannel.adb, 'bad'))?.code,
          ControlErrorCode.authDenied,
        );
      }
      var cooling = await h.auth.requestUnlock(ControlChannel.adb, '1234');
      expect(cooling?.code, ControlErrorCode.authCooldown);
      expect(cooling?.retryAfterMs, greaterThan(0));

      h.wallTime = now.add(const Duration(seconds: 29));
      cooling = await h.auth.requestUnlock(ControlChannel.adb, '1234');
      expect(cooling?.code, ControlErrorCode.authCooldown);

      h.wallTime = now.add(const Duration(seconds: 31));
      expect(await h.auth.requestUnlock(ControlChannel.adb, '1234'), isNull);
    });

    test('未设 PIN：unlock 报 PIN_NOT_SET', () async {
      final fresh = await ControlHarness.create(
        startTime: DateTime(2026, 10, 12),
      );
      addTearDown(fresh.dispose);
      expect(
        (await fresh.auth.requestUnlock(ControlChannel.adb, '1234'))?.code,
        ControlErrorCode.pinNotSet,
      );
    });
  });

  group('PIN 存储', () {
    test('规则校验：长度/字符集/二次确认；initialize 一次性', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      expect(
        () => h.pins.initialize(newPin: '12', confirmPin: '12'),
        throwsArgumentError,
      );
      expect(
        () => h.pins.initialize(newPin: 'ab-cd', confirmPin: 'ab-cd'),
        throwsArgumentError,
      );
      expect(
        () => h.pins.initialize(newPin: 'abcd', confirmPin: 'abce'),
        throwsArgumentError,
      );

      await h.pins.initialize(newPin: 'abcd', confirmPin: 'abcd');
      expect(await h.pins.isPinSet(), isTrue);
      expect(await h.pins.verifyPin('abcd'), isTrue);
      expect(await h.pins.verifyPin('xxxx'), isFalse);

      // 已初始化后 initialize 拒绝（USAGE 语义由总线映射）；
      // change 旧 PIN 不符抛 ArgumentError。
      await expectLater(
        h.pins.initialize(newPin: 'wxyz', confirmPin: 'wxyz'),
        throwsStateError,
      );
      expect(
        () => h.pins.change(oldPin: 'nope', newPin: 'wxyz', confirmPin: 'wxyz'),
        throwsArgumentError,
      );
      await h.pins.change(oldPin: 'abcd', newPin: 'wxyz', confirmPin: 'wxyz');
      expect(await h.pins.verifyPin('wxyz'), isTrue);
    });
  });
}
