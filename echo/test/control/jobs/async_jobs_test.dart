import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/commands/sys_commands.dart';
import 'package:echo/src/control/control_bus.dart';
import 'package:echo/src/control/jobs/job_store.dart';
import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_envelope.dart';
import 'package:echo/src/control/protocol/control_error.dart';

import '../control_test_harness.dart';

/// P4-G1：作业化执行 + sys.job.get 轮询（E4 根治，Kotlin 零改动）。
void main() {
  group('ControlJobStore', () {
    test('容量下限 32（assert 钉死）', () {
      expect(() => ControlJobStore(capacity: 31), throwsAssertionError);
    });

    test('preferredId 取 nonce；无 nonce 生成 job-<n>；撞表不复用', () {
      final store = ControlJobStore();
      CommandSpec spec(String verb) => CommandSpec(
        namespace: 'sys',
        verb: verb,
        summary: 't',
        kind: CommandKind.read,
        level: ControlLevel.guest,
        handler: (_) async => <String, Object?>{},
      );
      final a = store.start(
        spec: spec('ping'),
        channel: ControlChannel.adb,
        confirmed: false,
        preferredId: 'ecp-1-abc',
      );
      final b = store.start(
        spec: spec('ping'),
        channel: ControlChannel.adb,
        confirmed: false,
      );
      final a2 = store.start(
        spec: spec('ping'),
        channel: ControlChannel.adb,
        confirmed: false,
        preferredId: 'ecp-1-abc',
      ); // 撞 id
      final b2 = store.start(
        spec: spec('ping'),
        channel: ControlChannel.adb,
        confirmed: false,
      );

      expect(a.id, 'ecp-1-abc');
      expect(b.id, 'job-1');
      expect(a2.id, 'job-2');
      expect(b2.id, 'job-3');
    });

    test('环 32：超容量淘汰最旧（id 映射同步消失）', () {
      final store = ControlJobStore();
      final jobs = <ControlJob>[];
      for (var i = 0; i < 33; i++) {
        jobs.add(
          store.start(
            spec: CommandSpec(
              namespace: 'sys',
              verb: 'ping',
              summary: 't',
              kind: CommandKind.read,
              level: ControlLevel.guest,
              handler: (_) async => <String, Object?>{},
            ),
            channel: ControlChannel.adb,
            confirmed: false,
            preferredId: 'j$i',
          ),
        );
      }
      expect(store.length, 32);
      expect(store.lookup(id: 'j0', channel: ControlChannel.adb), isNull);
      expect(store.lookup(id: 'j32', channel: ControlChannel.adb), jobs.last);

      // 淘汰后 complete 是空操作（离表对象不复活）。
      store.complete(jobs.first, _envelopeOk());
      expect(store.lookup(id: 'j0', channel: ControlChannel.adb), isNull);
    });

    test('跨通道隔离：adb 作业 mcp/slash 一律查不到', () {
      final store = ControlJobStore();
      final job = store.start(
        spec: CommandSpec(
          namespace: 'sys',
          verb: 'ping',
          summary: 't',
          kind: CommandKind.read,
          level: ControlLevel.guest,
          handler: (_) async => <String, Object?>{},
        ),
        channel: ControlChannel.adb,
        confirmed: false,
        preferredId: 'x',
      );
      expect(store.lookup(id: 'x', channel: ControlChannel.mcp), isNull);
      expect(store.lookup(id: 'x', channel: ControlChannel.slash), isNull);
      expect(store.lookup(id: 'x', channel: ControlChannel.adb), job);
    });
  });

  group('作业化执行（总线）', () {
    late ControlHarness h;
    setUp(() async {
      h = await ControlHarness.create();
    });
    tearDown(() => h.dispose());

    /// 轮 sys.job.get 至 done（或取到失败信封），返回最后一次信封。
    Future<ControlEnvelope> pollJob(
      String id, {
      ControlChannel channel = ControlChannel.adb,
    }) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      ControlEnvelope env = _envelopeOk();
      while (DateTime.now().isBefore(deadline)) {
        env = await h.bus.execute(
          channel: channel,
          cmd: 'sys.job.get',
          rawArgs: {'id': id},
          nonce: 'poll-$id',
        );
        if (!env.ok || env.result!['status'] == 'done') return env;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('作业 $id 5s 内未完成');
    }

    test('slow + backgroundSlow：立即回 running（async/jobId/hint），'
        '终态信封正确', () async {
      final running = await h.exec(
        'sys.delay',
        args: {'ms': 30},
        backgroundSlow: true,
        nonce: 'ecp-delay-1',
      );
      expect(running.ok, isTrue);
      expect(running.async, isTrue);
      expect(running.jobId, 'ecp-delay-1');
      expect(running.ms, lessThan(100)); // 立即返回，没真等 30ms
      expect(running.result, {
        'status': 'running',
        'jobId': 'ecp-delay-1',
        'cmd': 'sys.delay',
        'hint': 'sys.job.get --id ecp-delay-1',
      });
      // JSON 线传形状（echo-cmd 解析依赖）。
      final json = running.toJson();
      expect(json['async'], isTrue);
      expect(json['jobId'], 'ecp-delay-1');
      expect(json['nonce'], 'ecp-delay-1');

      final done = await pollJob('ecp-delay-1');
      expect(done.ok, isTrue);
      expect(done.result!['status'], 'done');
      final inner = (done.result!['envelope'] as Map).cast<String, Object?>();
      expect(inner['ok'], isTrue);
      expect(inner['cmd'], 'sys.delay');
      expect((inner['result'] as Map)['sleptMs'], 30);
      expect(inner['nonce'], 'ecp-delay-1'); // 内层信封带原 nonce
    });

    test('普通信封 JSON 不含 async/jobId（向后兼容）', () {
      final json = _envelopeOk().toJson();
      expect(json.containsKey('async'), isFalse);
      expect(json.containsKey('jobId'), isFalse);
    });

    test('fast 命令即使 backgroundSlow:true 也不作业化', () async {
      final env = await h.exec(
        'sys.ping',
        backgroundSlow: true,
        nonce: 'ping-1',
      );
      expect(env.ok, isTrue);
      expect(env.async, isFalse);
      expect(env.toJson().containsKey('async'), isFalse);
      expect(env.result!['alive'], isTrue);
      expect(h.jobs.length, 0);
    });

    test('slow + backgroundSlow:false（slash 语义）：直接等终态，'
        '不进作业表', () async {
      final env = await h.exec(
        'sys.delay',
        args: {'ms': 10},
        backgroundSlow: false,
        nonce: 'slash-like',
      );
      expect(env.ok, isTrue);
      expect(env.async, isFalse);
      expect(env.result!['sleptMs'], 10);
      expect(h.jobs.length, 0);
    });

    test('解析层 USAGE（未知参数）在作业化之前驳回：不产生作业', () async {
      final env = await h.exec(
        'sys.delay',
        args: {'bogus': 1},
        backgroundSlow: true,
        nonce: 'bad-args',
      );
      expect(env.ok, isFalse);
      expect(env.error!.code, ControlErrorCode.usage);
      expect(h.jobs.length, 0);
    });

    test('handler 业务 USAGE（--ms 越界）走作业终态信封：先 running '
        '后 done.error=USAGE', () async {
      final running = await h.exec(
        'sys.delay',
        args: {'ms': 99999},
        backgroundSlow: true,
        nonce: 'range-bad',
      );
      expect(running.async, isTrue);
      final done = await pollJob('range-bad');
      final inner = (done.result!['envelope'] as Map).cast<String, Object?>();
      expect(inner['ok'], isFalse);
      expect((inner['error'] as Map)['code'], 'USAGE');
    });

    test('同 nonce 重发：第二条退化为生成 id，两作业并存可各自轮询', () async {
      final r1 = await h.exec(
        'sys.delay',
        args: {'ms': 10},
        backgroundSlow: true,
        nonce: 'dup',
      );
      final r2 = await h.exec(
        'sys.delay',
        args: {'ms': 10},
        backgroundSlow: true,
        nonce: 'dup',
      );
      expect(r1.jobId, 'dup');
      expect(r2.jobId, 'job-1');
      expect(await pollJob('dup'), isNotNull);
      expect(await pollJob('job-1'), isNotNull);
    });

    test('diary.export 真实 slow 命令：running→done 信封含 path 且落盘', () async {
      await h.execResult('diary.ensure', args: {'date': '2026-10-10'});
      final running = await h.exec(
        'diary.export',
        backgroundSlow: true,
        nonce: 'export-1',
      );
      expect(running.async, isTrue);

      final done = await pollJob('export-1');
      final inner = (done.result!['envelope'] as Map).cast<String, Object?>();
      expect(inner['ok'], isTrue);
      final result = (inner['result'] as Map).cast<String, Object?>();
      expect(result['entries'], isPositive);
      expect(File(result['path'] as String).existsSync(), isTrue);
    });

    test('sys.job.get：NOT_FOUND（不存在/已淘汰）；跨通道 mcp 隔离', () async {
      await h.exec(
        'sys.delay',
        args: {'ms': 500},
        backgroundSlow: true,
        nonce: 'iso-1',
      );

      final missing = await h.bus.execute(
        channel: ControlChannel.adb,
        cmd: 'sys.job.get',
        rawArgs: {'id': 'no-such-job'},
        nonce: 'p',
      );
      expect(missing.error!.code, ControlErrorCode.notFound);

      // slash 起始 user(2)，免解锁即可调 owner 级 sys.job.get；
      // adb 作业在 slash 物理不可见 → NOT_FOUND（命令级隔离断言）。
      final crossSlash = await h.bus.execute(
        channel: ControlChannel.slash,
        cmd: 'sys.job.get',
        rawArgs: {'id': 'iso-1'},
        nonce: 'p',
      );
      expect(crossSlash.error!.code, ControlErrorCode.notFound);

      // mcp 起始 guest(0) 且只读铁律下永不解锁：owner 级查询在鉴权
      // 门即被拒（AUTH_REQUIRED），隔离之下连门都进不去。
      final crossMcp = await h.bus.execute(
        channel: ControlChannel.mcp,
        cmd: 'sys.job.get',
        rawArgs: {'id': 'iso-1'},
        nonce: 'p',
      );
      expect(crossMcp.error!.code, ControlErrorCode.authRequired);

      // 收尾：等本测试起的 500ms 后台作业落终态，避免它活到 teardown
      // 关闭事件中心之后才收口（P4-G2 起收口会发 command.finished）。
      final terminal = await pollJob('iso-1');
      expect(terminal.ok, isTrue);
      expect(terminal.result!['status'], 'done');
    });

    test('鉴权门：3 级作业执行期间会话焚尽 → AUTH_REQUIRED 且作业保留；'
        '重解锁后可取', () async {
      // 用共享 auth/registry 的第二条总线注册假 3 级 slow 命令
      // （不污染 harness 总线的 manifest 一致性测试）。
      await h.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});

      final jobs2 = ControlJobStore();
      h.registry.set(jobs2); // sys.job.get 按类型取表，指向 jobs2
      final bus2 =
          ControlBus(
              buildMode: ControlBuildMode.debug,
              services: h.registry,
              authorizer: h.auth,
              auditLog: h.audit,
              jobs: jobs2,
              events: h.events,
            )
            ..register(jobGet)
            ..register(
              CommandSpec(
                namespace: 'fakejob',
                verb: 'get',
                summary: '假 3 级 slow 命令',
                kind: CommandKind.write,
                level: ControlLevel.admin,
                destructive: true,
                slow: true,
                handler: (_) async {
                  await Future<void>.delayed(const Duration(milliseconds: 150));
                  return <String, Object?>{'touched': true};
                },
              ),
            );

      final running = await bus2.execute(
        channel: ControlChannel.adb,
        cmd: 'fakejob.get',
        confirmed: true,
        nonce: 'admin-job',
        backgroundSlow: true,
      );
      expect(running.async, isTrue);

      // 会话焚尽（切后台/息屏等价）。
      h.auth.lock(ControlChannel.adb);
      final denied = await bus2.execute(
        channel: ControlChannel.adb,
        cmd: 'sys.job.get',
        rawArgs: {'id': 'admin-job'},
        nonce: 'p',
      );
      expect(denied.ok, isFalse);
      expect(denied.error!.code, ControlErrorCode.authRequired);
      // 作业保留：表里仍在（只是取不回）。
      expect(
        jobs2.lookup(id: 'admin-job', channel: ControlChannel.adb),
        isNotNull,
      );

      // 重新解锁（不需要再次 --confirm）：可轮至 done。
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      ControlEnvelope env = denied;
      while (DateTime.now().isBefore(deadline)) {
        env = await bus2.execute(
          channel: ControlChannel.adb,
          cmd: 'sys.job.get',
          rawArgs: {'id': 'admin-job'},
          nonce: 'p',
        );
        if (env.ok && env.result!['status'] == 'done') break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(env.ok, isTrue, reason: env.error?.toString());
      expect(env.result!['status'], 'done');
      final inner = (env.result!['envelope'] as Map).cast<String, Object?>();
      expect((inner['result'] as Map)['touched'], isTrue);

      // 完成路径与同步共用：3 级成败入审计。
      expect(
        h.audit.list(limit: 20).any((e) => e.cmd == 'fakejob.get' && e.ok),
        isTrue,
      );
    });

    test('后台 slow 超时仍走统一收口：内层信封 TIMEOUT + 审计失败', () async {
      final jobs2 = ControlJobStore();
      h.registry.set(jobs2);
      final bus2 =
          ControlBus(
              buildMode: ControlBuildMode.debug,
              services: h.registry,
              authorizer: h.auth,
              auditLog: h.audit,
              jobs: jobs2,
              events: h.events,
            )
            ..register(jobGet)
            ..register(
              CommandSpec(
                namespace: 'fakejob',
                verb: 'status',
                summary: '假 slow 超时命令',
                kind: CommandKind.read,
                level: ControlLevel.user,
                slow: true,
                // 测试缝：10ms 预算，handler 睡 300ms → TIMEOUT。
                timeoutOverride: const Duration(milliseconds: 10),
                handler: (_) async {
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                  return <String, Object?>{};
                },
              ),
            );

      final running = await bus2.execute(
        channel: ControlChannel.adb,
        cmd: 'fakejob.status',
        nonce: 'timeout-job',
        backgroundSlow: true,
      );
      expect(running.async, isTrue);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      ControlEnvelope env = running;
      while (DateTime.now().isBefore(deadline)) {
        env = await bus2.execute(
          channel: ControlChannel.adb,
          cmd: 'sys.job.get',
          rawArgs: {'id': 'timeout-job'},
          nonce: 'p',
        );
        if (env.ok && env.result!['status'] == 'done') break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final inner = (env.result!['envelope'] as Map).cast<String, Object?>();
      expect(inner['ok'], isFalse);
      expect((inner['error'] as Map)['code'], 'TIMEOUT');
      expect(
        h.audit.list(limit: 20).any((e) => e.cmd == 'fakejob.status' && !e.ok),
        isTrue,
      );
    });
  });

  group('sys.delay 命令', () {
    test('release 构建物理不注册（UNKNOWN_COMMAND + 清单不含）；debug 注册', () async {
      final rel = await ControlHarness.create(
        buildMode: ControlBuildMode.release,
      );
      addTearDown(rel.dispose);
      final missing = await rel.exec('sys.delay', args: {'ms': 1});
      expect(missing.error!.code, ControlErrorCode.unknownCommand);
      // 物理不注册钉死：release manifest 里根本不存在这条命令，
      // 而非「存在但拒绝」（G4 派单点名的 debug-only 三命令之一）。
      expect(
        rel.bus.visibleSpecs.map((s) => s.name),
        isNot(contains('sys.delay')),
      );

      final dbg = await ControlHarness.create();
      addTearDown(dbg.dispose);
      final visible = await dbg.exec(
        'sys.delay',
        args: {'ms': 1},
        backgroundSlow: false,
      );
      expect(visible.ok, isTrue);
    });

    test('guest 级直放（未设 PIN/未解锁）；--ms 越界 USAGE', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);
      for (final bad in [-1, 30001]) {
        final env = await h.exec('sys.delay', args: {'ms': bad});
        expect(env.error!.code, ControlErrorCode.usage, reason: 'ms=$bad');
      }
      final ok = await h.exec(
        'sys.delay',
        args: {'ms': 0},
        backgroundSlow: false,
      );
      expect(ok.result!['sleptMs'], 0);
    });
  });
}

ControlEnvelope _envelopeOk() => const ControlEnvelope(
  ok: true,
  cmd: 'x',
  ms: 1,
  result: <String, Object?>{},
);
