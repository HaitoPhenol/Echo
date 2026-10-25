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
            jobs: h.jobs,
            events: h.events,
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

    test('mcp 只颁发 owner 只读会话：可读 owner，写命令仍拒', () async {
      expect(await h.auth.requestUnlock(ControlChannel.mcp, '1234'), isNull);
      expect(h.auth.effectiveLevel(ControlChannel.mcp), ControlLevel.owner);
      // 解锁后 owner 级读放行、user 级写仍在裁决门拒绝。
      final read = await busWith().execute(
        channel: ControlChannel.mcp,
        cmd: 'x.get',
      );
      expect(read.ok, isTrue);
      final write = await busWith().execute(
        channel: ControlChannel.mcp,
        cmd: 'x.goto',
      );
      expect(write.error?.code, ControlErrorCode.authRequired);
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

  group('PIN 首装门禁（G0 通道本地性，2026-10-13）', () {
    test('ControlChannel.isLocal：adb/slash 本地，mcp 非本地', () {
      expect(ControlChannel.adb.isLocal, isTrue);
      expect(ControlChannel.slash.isLocal, isTrue);
      expect(ControlChannel.mcp.isLocal, isFalse);
    });

    test('release+slash 首装成功；mcp 拒绝；已设后无 oldPin 走改 PIN', () async {
      final rel = await ControlHarness.create(
        buildMode: ControlBuildMode.release,
      );
      addTearDown(rel.dispose);

      // 非本地通道：set-pin 虽总线级直放，handler 内首装门禁拒绝，
      // PIN 未被设置（错误不再提 debug/adb）。
      final mcpDenied = await rel.exec(
        'auth.set-pin',
        channel: ControlChannel.mcp,
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      expect(mcpDenied.ok, isFalse);
      expect(mcpDenied.error!.code, ControlErrorCode.authDenied);
      expect(mcpDenied.error!.message, contains('本地通道'));
      expect(await rel.pins.isPinSet(), isFalse);

      // release 风味 slash 面板：本地通道首装成功
      //（修订前条件 buildMode==debug && channel==adb 会挡住）。
      final init = await rel.execResult(
        'auth.set-pin',
        channel: ControlChannel.slash,
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      expect(init, {'pinSet': true, 'changed': false});
      expect(await rel.pins.isPinSet(), isTrue);
      expect(rel.audit.list().map((e) => e.cmd), contains('auth.pin-init'));

      // 已设 PIN 后首装路径不可达：解锁后进改 PIN 流程，缺 --old-pin
      // 报 USAGE，PIN 未被改动（首装不发会话，先 unlock）。
      await rel.execResult(
        'auth.unlock',
        channel: ControlChannel.slash,
        args: {'pin': 'echo1'},
      );
      final noOld = await rel.exec(
        'auth.set-pin',
        channel: ControlChannel.slash,
        args: {'newPin': 'echo2', 'newPinConfirm': 'echo2'},
      );
      expect(noOld.error!.code, ControlErrorCode.usage);
      expect(await rel.pins.verifyPin('echo1'), isTrue);
    });

    test('adb/debug 原首装路径保持（本地通道，与构建风味解绑后仍通）', () async {
      final fresh = await ControlHarness.create();
      addTearDown(fresh.dispose);
      final init = await fresh.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      expect(init, {'pinSet': true, 'changed': false});
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
