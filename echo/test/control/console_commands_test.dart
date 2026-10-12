import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_error.dart';
import 'package:echo/src/services/console_stats_service.dart';

import 'control_test_harness.dart';

/// `console.*` 命令（手册 §7）协议测试：快照同源、立即刷新、
/// 通道级别裁决。
void main() {
  late ControlHarness h;

  setUp(() async {
    h = await ControlHarness.create();
  });
  tearDown(() => h.dispose());

  test('snapshot 初始为降级空快照（服务未 refresh 过）', () async {
    final r = await h.execResult('console.snapshot');
    expect(r['model'], '—');
    expect(r['tempC'], isNull);
    expect(r['powerW'], isNull);
  });

  test('refresh 拉取后返回新快照，随后 snapshot 同源同值', () async {
    final r = await h.execResult('console.refresh');
    expect(r['model'], 'test-phone');
    expect(r['tempC'], 31.0);
    expect(r['powerW'], 2.5);

    // UI/定时器/命令三处同源：服务内快照即刚刷新的值。
    final again = await h.execResult('console.snapshot');
    expect(again, r);
    expect(h.consoleStats.snapshot.tempC, 31.0);
  });

  test('reader 换数后再次 refresh 反映变化（模拟真机数值波动）', () async {
    var tick = 0;
    h.registry.set(
      ConsoleStatsService(
        autoStart: false,
        reader: () async {
          tick++;
          return {'model': 'MIX 2S', 'tempC': 29.0 + tick, 'powerW': 2.0};
        },
      ),
    );

    final first = await h.execResult('console.refresh');
    final second = await h.execResult('console.refresh');
    expect(first['tempC'], 30.0);
    expect(second['tempC'], 31.0);
  });

  test('通道裁决：mcp 起始 0 级，snapshot(1)/refresh(2) 均拒绝', () async {
    final readDenied = await h.exec(
      'console.snapshot',
      channel: ControlChannel.mcp,
    );
    expect(readDenied.error!.code, ControlErrorCode.authRequired);
    final writeDenied = await h.exec(
      'console.refresh',
      channel: ControlChannel.mcp,
    );
    expect(writeDenied.error!.code, ControlErrorCode.authRequired);
    // 被拦截的 refresh 不会改变本地快照。
    expect(h.consoleStats.snapshot.model, '—');
  });
}
