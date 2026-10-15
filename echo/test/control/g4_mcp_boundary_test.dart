import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_error.dart';

import 'control_test_harness.dart';

/// G4｜MCP 只读边界负向测试（假通道，不写任何传输）。
///
/// 冻结矩阵（设计 §5，2026-10-14 裁定）：mcp 通道起始且恒为 guest(0)，
/// 只读铁律下永不解锁；任何 ≥2 级命令在**鉴权门**即 `AUTH_REQUIRED`，
/// 连 handler 都到不了。事件 ceiling 物理过滤（bus.poll 直测）与
/// 跨通道作业隔离（slash 取 adb 作业 → NOT_FOUND）的机制断言已分别在
/// `events/event_integration_test.dart` 与 `jobs/async_jobs_test.dart`
/// 钉死，本组只做 §G4 清单点名项的**汇总复验与补漏**（mcp→AUTH_REQUIRED、
/// debug-only 命令 release 物理不存在的双重保险），不重复机制测试。
void main() {
  group('G4｜MCP 只读边界负向（假通道）', () {
    test('mcp 发 ≥2 级命令一律在鉴权门 AUTH_REQUIRED；0 级读命令放行', () async {
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      // 对照组：0 级命令按通道起始级别直放（mcp 起始＝guest）。
      final ping = await h.exec('sys.ping', channel: ControlChannel.mcp);
      expect(ping.ok, isTrue, reason: 'mcp 起始即 guest，0 级读命令应放行');

      // owner(1)/user(2)/admin(3) 各取代表，覆盖读与写、破坏与非破坏。
      final denied = <String, Map<String, Object?>>{
        'sys.status': <String, Object?>{}, // owner 1 读
        'diary.list': <String, Object?>{}, // owner 1 读
        'diary.ensure': {'date': '2026-10-10'}, // user 2 写
        'diary.export': <String, Object?>{}, // user 2 写（非破坏）
        'nav.goto': {'page': 'chat'}, // user 2 写
        'chat.send': {'id': 'incoming-1', 'text': 'x'}, // admin 3（非破坏）
        'diary.prune': {'before': '2026-10-11'}, // admin 3 破坏
      };
      for (final entry in denied.entries) {
        final env = await h.exec(
          entry.key,
          channel: ControlChannel.mcp,
          args: entry.value,
          confirmed: true,
        );
        expect(
          env.error?.code,
          ControlErrorCode.authRequired,
          reason: '${entry.key} 应在鉴权门被拒',
        );
      }
    });

    test('mcp 取 owner 级读命令：连事件环/作业表层都到不了', () async {
      // 与 event_integration_test（sys.events）和 async_jobs_test
      // （sys.job.get）的既有钉死一致，按 §G4 清单汇总复验。
      final h = await ControlHarness.create();
      addTearDown(h.dispose);

      final events = await h.exec('sys.events', channel: ControlChannel.mcp);
      expect(events.error?.code, ControlErrorCode.authRequired);

      final job = await h.exec(
        'sys.job.get',
        channel: ControlChannel.mcp,
        args: {'id': 'whatever'},
      );
      // 注意：是 AUTH_REQUIRED 而非 NOT_FOUND——门都没过，谈不上隔离。
      expect(job.error?.code, ControlErrorCode.authRequired);
    });

    test('debug-only 命令 release 物理不存在：UNKNOWN_COMMAND + 清单不含', () async {
      // §G4 点名的 seed/reset 双重保险，并顺带纳入同期 debug-only 命令，
      // 钉死「release manifest 里根本不存在」而非「存在但拒绝」。
      final rel = await ControlHarness.create(
        buildMode: ControlBuildMode.release,
      );
      addTearDown(rel.dispose);
      final names = rel.bus.visibleSpecs.map((s) => s.name).toSet();

      const debugOnly = ['diary.seed', 'diary.reset', 'chat.seed', 'sys.delay'];
      for (final cmd in debugOnly) {
        expect(names, isNot(contains(cmd)), reason: '$cmd 不应出现在 release 清单');
        final env = await rel.exec(cmd);
        expect(
          env.error?.code,
          ControlErrorCode.unknownCommand,
          reason: '$cmd 应报 UNKNOWN_COMMAND',
        );
      }
    });

    test('mcp 调 release 不存在的 debug-only 命令也是 UNKNOWN_COMMAND（先于鉴权）', () async {
      // 未注册命令在派发阶段即判 UNKNOWN，早于鉴权门——与上一条互为
      // 双重保险：不存在优先于无权。
      final rel = await ControlHarness.create(
        buildMode: ControlBuildMode.release,
      );
      addTearDown(rel.dispose);
      final env = await rel.exec(
        'diary.seed',
        channel: ControlChannel.mcp,
        args: {'days': 1},
      );
      expect(env.error?.code, ControlErrorCode.unknownCommand);
    });
  });
}
