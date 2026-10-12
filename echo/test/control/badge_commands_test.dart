import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_error.dart';
import 'package:echo/src/services/nav_badge_service.dart';

import 'control_test_harness.dart';

/// `badge.*` 命令（手册 §8）协议测试：四页一览、通知/异常状态机、
/// 页名同源解析、通道级别裁决。
void main() {
  late ControlHarness h;

  setUp(() async {
    h = await ControlHarness.create();
  });
  tearDown(() => h.dispose());

  Map<String, Object?> levelOf(String name) {
    final status = h.badges.levelOf(
      const ['console', 'chat', 'notes', 'me'].indexOf(name),
    );
    return {'level': status.name};
  }

  test('status：四页下标/稳定名/初始级别一览', () async {
    final r = await h.execResult('badge.status');
    final items = (r['items'] as List).cast<Map>();
    expect(items.map((i) => i['name']), ['console', 'chat', 'notes', 'me']);
    expect(items.map((i) => i['index']), [0, 1, 2, 3]);
    expect(items.every((i) => i['level'] == 'normal'), isTrue);
  });

  test('notify → status 绿；view 通知态复原', () async {
    final r = await h.execResult('badge.notify', args: {'page': 'chat'});
    expect((r['page'] as Map)['name'], 'chat');
    expect(r['level'], 'notification');
    expect(levelOf('chat')['level'], 'notification');

    final status = await h.execResult('badge.status');
    final chat = (status['items'] as List).cast<Map>().singleWhere(
      (i) => i['name'] == 'chat',
    );
    expect(chat['level'], 'notification');

    final viewed = await h.execResult('badge.view', args: {'page': 'chat'});
    expect(viewed['level'], 'normal');
  });

  test('异常态：view 不解除，必须显式 resolve', () async {
    await h.execResult('badge.exception', args: {'page': 'me'});
    expect(levelOf('me')['level'], 'exception');

    // 查看不清除异常（服务层既有规则，命令原样透传）。
    final viewed = await h.execResult('badge.view', args: {'page': 'me'});
    expect(viewed['level'], 'exception');

    final resolved = await h.execResult('badge.resolve', args: {'page': 'me'});
    expect(resolved['level'], 'normal');

    // resolve 幂等：normal 上再调仍成功且仍 normal。
    final again = await h.execResult('badge.resolve', args: {'page': 'me'});
    expect(again['level'], 'normal');
  });

  test('下标与稳定 id 同源解析（1=chat）；未知页 → USAGE', () async {
    final byIndex = await h.execResult('badge.notify', args: {'page': '1'});
    expect((byIndex['page'] as Map)['index'], 1);
    expect(levelOf('chat')['level'], 'notification');

    expect(
      (await h.exec('badge.notify', args: {'page': 'nope'})).error!.code,
      ControlErrorCode.usage,
    );
    expect(
      (await h.exec('badge.view', args: {'page': '9'})).error!.code,
      ControlErrorCode.usage,
    );
  });

  test('通道裁决：mcp 起始 0 级，status(1)/notify(2) 均拒绝', () async {
    final readDenied = await h.exec(
      'badge.status',
      channel: ControlChannel.mcp,
    );
    expect(readDenied.error!.code, ControlErrorCode.authRequired);
    final writeDenied = await h.exec(
      'badge.notify',
      channel: ControlChannel.mcp,
      args: {'page': 'chat'},
    );
    expect(writeDenied.error!.code, ControlErrorCode.authRequired);
    expect(h.badges.levelOf(1), NavBadgeLevel.normal);
  });
}
