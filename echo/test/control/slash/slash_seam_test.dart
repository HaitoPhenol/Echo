import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/slash/completion.dart';
import 'package:echo/src/control/slash/console_core.dart';
import 'package:echo/src/control/slash/line_parser.dart';
import 'package:echo/src/control/slash/result_view.dart';

import '../control_test_harness.dart';

/// G3 接缝验收前置（交接单 §G3：核心不依赖搜索栏 Widget，第二个消费
/// 者可挂即可）。
void main() {
  test('slash/ 源码静态约束：零 Widget 依赖（只准 foundation）', () {
    final dir = Directory('lib/src/control/slash');
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
        reason: '${f.path} 不得 import flutter Widget 层（G3 接缝）',
      );
    }
  });

  test('假第二消费者（未来终端页雏形）可纯 Dart 持有并驱动核心', () async {
    // 不创建任何 Widget：一个普通 Dart 类监听核心即可消费全部状态，
    // 证明搜索栏指令态（G2）不是必需的唯一宿主。
    final h = await ControlHarness.create();
    addTearDown(h.dispose);
    final core = ControlConsoleCore(bus: h.bus);
    addTearDown(core.dispose);

    final terminal = _FakeTerminalConsumer(core);

    final entry = (await core.submitLine('sys.ping'))!;
    expect(entry.ok, isTrue);
    expect(terminal.notifies, greaterThanOrEqualTo(2)); // running + done
    expect(terminal.lastView, isA<KeyValueView>());

    // 第二消费者也能独立用解析器/补全/视图三件套。
    final inv = parseLine('/diary list --limit 1', lookup: h.bus.specOf);
    expect(inv.cmd, 'diary.list');
    expect(
      CompletionEngine(h.bus.visibleSpecs).complete('diary.').candidates,
      isNotEmpty,
    );
    terminal.dispose();
  });
}

/// 未来终端页的最小替身：只订阅 ChangeNotifier，渲染层用什么 Widget
/// 由正式立项决定，与核心无关。
class _FakeTerminalConsumer {
  _FakeTerminalConsumer(this.core) {
    core.addListener(_onChange);
  }

  final ControlConsoleCore core;
  int notifies = 0;
  ResultView? lastView;
  bool _disposed = false;

  void _onChange() {
    if (_disposed) return;
    notifies++;
    final done = core.entries.where((e) => e.status == ConsoleEntryStatus.done);
    if (done.isNotEmpty) lastView = done.last.view;
  }

  void dispose() {
    _disposed = true;
    core.removeListener(_onChange);
  }
}
