import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/events/event.dart';
import 'package:echo/src/control/events/event_bus.dart';
import 'package:echo/src/control/protocol/command_spec.dart';

/// P4-G0 接缝验收（交接单 §G0：事件核心只依赖 flutter/foundation，
/// 与 slash 核心同纪律）：源码正则钉死零 Widget import，且一个普通
/// Dart 类（未来 MCP/内置 agent 的替身）可不依赖任何 Widget 同时
/// 消费 stream 与 poll 两条路径。
void main() {
  test('events/ 源码静态约束：零 Widget 依赖（只准 foundation）', () {
    final dir = Directory('lib/src/control/events');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .toList();
    expect(files, isNotEmpty, reason: '从 echo/ 包目录运行测试');

    final banned = RegExp(
      r'''import\s+['"]package:flutter/(widgets|material|cupertino)''',
    );
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(
        banned.hasMatch(src),
        isFalse,
        reason: '${f.path} 不得 import flutter Widget 层（P4-G0 接缝）',
      );
    }
  });

  test('假常驻消费者（未来 MCP/内置 agent 雏形）纯 Dart 双通道消费', () async {
    final bus = ControlEventBus();
    addTearDown(bus.close);

    // 订阅前发射一条：广播流不补历史，假消费者不应收到。
    bus.emit(
      type: 'nav.changed',
      level: ControlLevel.guest,
      data: {'index': 0},
    );

    final consumer = _FakeAgentConsumer(bus, ceiling: ControlLevel.owner);
    addTearDown(consumer.dispose);

    // owner ceiling 收得到 owner 级、收不到 user/admin 级。
    bus.emit(
      type: 'audit.entry',
      level: ControlLevel.owner,
      data: {'cmd': 'x'},
    );
    bus.emit(
      type: 'diary.export.completed',
      level: ControlLevel.user,
      data: {'path': '/secrets/export.sy.zip'},
    );

    // poll 游标路径：长轮询应被下一条命中事件提前唤醒。
    final polledFuture = bus.poll(
      since: bus.lastSeq,
      ceiling: ControlLevel.owner,
      wait: const Duration(seconds: 2),
    );
    bus.emit(
      type: 'chat.incoming',
      level: ControlLevel.owner,
      data: {'id': 'incoming-1'},
    );
    final polled = await polledFuture;

    await Future<void>.delayed(Duration.zero);
    expect(consumer.streamed.map((e) => e.type), [
      'audit.entry',
      'chat.incoming',
    ]);
    expect(polled.single.type, 'chat.incoming');
    expect(polled.single.data['id'], 'incoming-1');
  });
}

/// 未来 MCP/内置 agent 的最小替身：普通 Dart 类持有 StreamSubscription
/// 与游标，渲染层/传输层由后续专项决定，与事件核心无关。
class _FakeAgentConsumer {
  _FakeAgentConsumer(this.bus, {required this.ceiling}) {
    _sub = bus.stream(ceiling: ceiling).listen(_streamed.add);
  }

  final ControlEventBus bus;
  final ControlLevel ceiling;
  final List<ControlEvent> _streamed = [];
  late final StreamSubscription<ControlEvent> _sub;

  List<ControlEvent> get streamed => List.unmodifiable(_streamed);

  Future<void> dispose() => _sub.cancel();
}
