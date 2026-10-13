// SlashConsoleController 交互编排单测（无 Widget）：
// 指令态/补全写回/确认卡/PIN 两路径与重放/release 风味/
// nav.goto 收起/焚会话复位/多行注入。全部经 ControlHarness 真总线。

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/slash/completion.dart';
import 'package:echo/src/control/slash_ui/slash_ui.dart';
import 'package:echo/src/navigation/nav_physics.dart';

import '../control_test_harness.dart';

/// 不调度帧的 TickerProvider（nav.goto 同页路径不启 ticker；
/// 即使启动也 muted 不跑帧，纯 Dart 测试不残留定时器）。
class _MutedVSync implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick)..muted = true;
}

/// 录制文本写回的最小宿主回调。
class _EditRecorder {
  final List<TextEditingValue> writes = [];
  void call(TextEditingValue v) => writes.add(v);
}

Future<void> _until(bool Function() cond, {int maxTicks = 50}) async {
  for (var i = 0; i < maxTicks && !cond(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(cond(), isTrue, reason: '条件在微任务轮询后仍未满足');
}

void main() {
  late ControlHarness h;
  late SlashConsoleController c;
  late _EditRecorder edits;
  int closeCount = 0;

  Future<void> boot({ControlBuildMode mode = ControlBuildMode.debug}) async {
    h = await ControlHarness.create(buildMode: mode);
    edits = _EditRecorder();
    closeCount = 0;
    c = SlashConsoleController(
      bus: h.bus,
      auth: h.auth,
      onEditText: edits.call,
      onRequestClose: () => closeCount++,
    );
  }

  tearDown(() async {
    c.dispose();
    await h.dispose();
  });

  group('指令态与补全', () {
    setUp(boot);

    test('首字符 / 激活；空白 / 不算；bind 空串复位', () {
      c.bind('普通搜索词');
      expect(c.active, isFalse);
      // 单独 `/` 即激活，直接给命名空间候选。
      c.bind('/');
      expect(c.active, isTrue);
      expect(c.completion.segment, CompletionSegment.namespace);
      c.bind('/di');
      expect(c.active, isTrue);
      expect(c.completion.segment, CompletionSegment.namespace);
      expect(c.completion.candidates.map((x) => x.insert), contains('diary.'));
      c.bind('');
      expect(c.active, isFalse);
    });

    test('点选候选写回输入框（onEditText）并重算下一段', () {
      c.onInputChanged('/di');
      final ns = c.completion.candidates.firstWhere(
        (x) => x.insert == 'diary.',
      );
      c.applyCandidate(ns);
      final written = edits.writes.single.text;
      expect(written, '/diary.');
      expect(c.active, isTrue);
      // 进入动词段：list/reset/prune/ensure 等。
      expect(c.completion.candidates.map((x) => x.label), contains('list'));
    });

    test('Esc 清输入退指令态', () {
      c.onInputChanged('/diary.list');
      expect(c.active, isTrue);
      c.exitSlash();
      expect(edits.writes.single.text, '');
      expect(c.active, isFalse);
    });
  });

  group('确认卡', () {
    setUp(boot);

    test('diary.prune 无 --confirm 先挂卡（不产生结果条），取消即关闭', () async {
      c.bind('/diary.prune');
      await c.submit('/diary.prune');
      expect(c.confirmPending, isNotNull);
      expect(c.confirmPending!.cmd, 'diary.prune');
      expect(c.core.entries, isEmpty);

      c.cancelConfirm();
      expect(c.confirmPending, isNull);
    });

    test('确认卡挂起的原行保留全部参数（影响范围可核对/可重投）', () async {
      await c.submit('/diary.prune --before 2026-10-01 --dry-run');
      final p = c.confirmPending;
      expect(p, isNotNull);
      expect(p!.cmd, 'diary.prune');
      // line 是用户完整原行；确认卡回显与重投都以它为准，不能只剩命令名。
      expect(p.line, contains('--before 2026-10-01'));
      expect(p.line, contains('--dry-run'));
      c.cancelConfirm();
    });

    test('确认后带参原行 + --confirm 重投（解锁后）', () async {
      await h.pins.initialize(newPin: '1234', confirmPin: '1234');
      await h.exec(
        'auth.unlock',
        channel: ControlChannel.slash,
        args: {'pin': '1234'},
      );

      await c.submit('/diary.prune --before 2026-10-01');
      expect(c.confirmPending, isNotNull);
      await c.confirmRun();
      final replay = c.core.entries.single;
      expect(replay.ok, isTrue, reason: replay.view.toString());
      expect(replay.line, '/diary.prune --before 2026-10-01 --confirm');
    });

    test('确认卡重挂后仍可走 PIN 首装', () async {
      await c.submit('/diary.prune');
      expect(c.confirmPending, isNotNull);
      await c.confirmRun();
      // 无 PIN：总线回 AUTH_REQUIRED（异步开面板，轮询）。
      await _until(() => c.pinSheet.visible);
      expect(c.pinSheet.mode, PinSheetMode.firstInstall);
    });

    test('chat.send 解锁后直跑不弹确认卡（confirmRequired=false）', () async {
      await h.pins.initialize(newPin: '1234', confirmPin: '1234');
      h.chatStore.addIncoming();
      await h.exec(
        'auth.unlock',
        channel: ControlChannel.slash,
        args: {'pin': '1234'},
      );

      c.bind('/chat.send --id incoming-1 --text 你好');
      await c.submit('/chat.send --id incoming-1 --text 你好');
      expect(c.confirmPending, isNull);
      final entry = c.core.entries.single;
      expect(entry.ok, isTrue, reason: entry.view.toString());
      expect(h.chatStore.messagesOf('incoming-1').items.first.text, '你好');
    });
  });

  group('PIN 已设：解锁→重放', () {
    setUp(boot);

    test('错 PIN 留错可重试；正确后重放原行（含 --confirm）', () async {
      await h.pins.initialize(newPin: '1234', confirmPin: '1234');

      c.bind('/diary.prune --confirm');
      await c.submit('/diary.prune --confirm');
      await _until(() => c.pinSheet.visible);
      expect(c.pinSheet.mode, PinSheetMode.unlock);

      await c.submitPin('0000');
      expect(c.pinSheet.error, isNotNull);
      expect(c.pinSheet.mode, PinSheetMode.unlock);
      expect(c.core.entries.single.ok, isFalse); // 原行 AUTH 失败仍在流里

      await c.submitPin('1234');
      await _until(() => c.core.entries.length == 2);
      final replay = c.core.entries.last;
      expect(replay.ok, isTrue, reason: replay.view.toString());
      expect(replay.line, endsWith('--confirm'));
      expect(c.pinSheet.visible, isFalse);
    });
  });

  group('release 风味首装全链路', () {
    setUp(() => boot(mode: ControlBuildMode.release));

    test('debug-only 命令物理不可见；首装两输→重放 prune', () async {
      // release 注册期物理裁剪：补全不出 diary.reset。
      c.bind('/diary.res');
      expect(
        c.completion.candidates.map((x) => x.label),
        isNot(contains('reset')),
      );
      expect(
        h.bus.visibleSpecs.map((s) => s.name),
        isNot(contains('diary.reset')),
      );

      await c.submit('/diary.prune');
      expect(c.confirmPending, isNotNull);
      await c.confirmRun();
      await _until(() => c.pinSheet.visible);
      expect(c.pinSheet.mode, PinSheetMode.firstInstall);

      // 第一遍 → 第二阶段。
      await c.submitPin('1234');
      expect(c.pinSheet.mode, PinSheetMode.firstInstallConfirm);
      // 两次不一致 → 回第一阶段并留错。
      await c.submitPin('9999');
      expect(c.pinSheet.mode, PinSheetMode.firstInstall);
      expect(c.pinSheet.error, contains('不一致'));

      // 重新走完。
      await c.submitPin('1234');
      expect(c.pinSheet.mode, PinSheetMode.firstInstallConfirm);
      await c.submitPin('1234');
      await _until(() => c.core.entries.length == 2);
      expect(c.pinSheet.visible, isFalse);
      final replay = c.core.entries.last;
      expect(replay.ok, isTrue, reason: replay.view.toString());

      // 会话确实颁发在 slash 通道。
      expect(h.auth.isUnlocked(ControlChannel.slash), isTrue);
      // 首装的 PIN 真的落了（再验一次）。
      expect(await h.pins.verifyPin('1234'), isTrue);
    });
  });

  group('nav.goto 收起语义', () {
    setUp(() async {
      await boot();
      final nav = NavPhysicsController(vsync: _MutedVSync(), pageCount: 4);
      h.registry.set(nav);
      addTearDown(nav.dispose);
    });

    test('同页 goto 成功 → 请求收起', () async {
      await c.submit('/nav.goto --page 0');
      expect(closeCount, 1);
      expect(c.core.entries.single.ok, isTrue);
    });

    test('--stay 不收起', () async {
      await c.submit('/nav.goto --page 0 --stay');
      expect(closeCount, 0);
    });

    test('越界页 USAGE 失败不收起', () async {
      await c.submit('/nav.goto --page 9');
      expect(closeCount, 0);
      expect(c.core.entries.single.ok, isFalse);
    });

    test('help 查询不收起', () async {
      c.bind('/nav.goto?');
      await c.submit('/nav.goto?');
      expect(closeCount, 0);
      expect(c.core.entries.single.helpIntent, isTrue);
    });
  });

  group('会话焚尽与多行', () {
    setUp(boot);

    test('首装第二阶段被焚会话 → 清暂存回第一阶段', () async {
      await c.submit('/diary.prune');
      await c.confirmRun();
      await _until(() => c.pinSheet.visible);
      await c.submitPin('1234');
      expect(c.pinSheet.mode, PinSheetMode.firstInstallConfirm);

      // 模拟切后台（息屏）：即使尚未产生会话，面板也要清掉第一遍暂存。
      h.auth.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(c.pinSheet.mode, PinSheetMode.firstInstall);
      expect(c.pinSheet.error, isNull);
    });

    test('cancelPin 关闭面板且不重放', () async {
      await c.submit('/diary.prune --confirm');
      await _until(() => c.pinSheet.visible);
      c.cancelPin();
      expect(c.pinSheet.visible, isFalse);
      // 只有原 AUTH 失败一条，没有重放条。
      expect(c.core.entries.length, 1);
    });

    test('多行可行性随命令参数变化；提交换行保留、历史脱敏', () async {
      c.bind('/diary.list');
      expect(c.canOpenMultiline, isFalse);
      c.bind('/chat.send --id incoming-1');
      expect(c.canOpenMultiline, isTrue);

      // 未解锁先走完首装+解锁（chat.send 3 级）。
      h.chatStore.addIncoming();
      c.openMultiline();
      expect(c.multilineOpen, isTrue);
      await c.submitMultilineText('第一行\n第二行');
      // AUTH_REQUIRED → 首装面板；多行已提交总线，先把 PIN 走完，
      // 但原提交缺 PIN 已失败——多行 AUTH 路径同样进面板。
      await _until(() => c.pinSheet.visible);
      await c.submitPin('1234');
      await c.submitPin('1234');
      // 未重放多行（设计：重放只服务面板挂起行；多行正文不重发，
      // 避免敏感正文二次发送）——用户需重新展开提交一次。
      expect(c.pinSheet.visible, isFalse);
      List outgoingOf(String id) => h.chatStore
          .messagesOf(id)
          .items
          .where((m) => m.direction.name == 'outgoing')
          .toList();
      expect(outgoingOf('incoming-1'), isEmpty);

      // 解锁后再次多行：成功，换行原样保留。
      c.bind('/chat.send --id incoming-1');
      c.openMultiline();
      await c.submitMultilineText('第一行\n第二行');
      await _until(() => outgoingOf('incoming-1').isNotEmpty);
      expect(outgoingOf('incoming-1').single.text, '第一行\n第二行');
      // 历史不含正文（截到 --id 为止）。
      expect(c.core.history.last, 'chat.send --id incoming-1');
    });
  });
}
