import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/slash/console_core.dart';
import 'package:echo/src/control/slash/result_view.dart';

import '../control_test_harness.dart';

void main() {
  late ControlHarness h;
  late ControlConsoleCore core;

  setUp(() async {
    h = await ControlHarness.create();
    core = ControlConsoleCore(bus: h.bus);
    addTearDown(() {
      core.dispose();
      h.dispose();
    });
  });

  group('信封流', () {
    test('成功：running→done 回填信封与键值视图；busy 翻转', () async {
      final f = core.submitLine('sys.ping');
      // append 同步发生：拿到 Future 时命令已在飞。
      expect(core.busy, isTrue);
      expect(core.entries.single.status, ConsoleEntryStatus.running);

      final entry = await f;
      expect(core.busy, isFalse);
      expect(entry!.status, ConsoleEntryStatus.done);
      expect(entry.ok, isTrue);
      expect(entry.cmd, 'sys.ping');
      expect(entry.envelope!.cmd, 'sys.ping');
      final view = entry.view!;
      expect(view, isA<KeyValueView>());
      expect(
        (view as KeyValueView).entries.map((e) => e.key),
        containsAll(['alive', 'time', 'pid']),
      );
    });

    test('空行忽略：无 entry 无历史', () async {
      expect(await core.submitLine('   '), isNull);
      expect(core.entries, isEmpty);
      expect(core.history, isEmpty);
    });

    test('词法错误（裸位置参数）：合成 USAGE 信封，不入历史', () async {
      final entry = (await core.submitLine('diary.list 2026-10'))!;
      expect(entry.ok, isFalse);
      final v = entry.view! as ErrorView;
      expect(v.code, 'USAGE');
      expect(v.message, contains('--'));
      expect(core.history, isEmpty);
    });

    test('未知命令：总线 UNKNOWN_COMMAND 信封', () async {
      final entry = (await core.submitLine('ghost.verb --x y'))!;
      expect(entry.ok, isFalse);
      expect((entry.view! as ErrorView).code, 'UNKNOWN_COMMAND');
      // 能形成合法调用的行照常入史（无敏感值）。
      expect(core.history.single, 'ghost.verb --x y');
    });

    test('AUTH_REQUIRED：need/elevate 进 ErrorView（G2 面板消费点）', () async {
      // 全新 harness 未设 PIN/未解锁：chat.send 是 3 级。
      final entry = (await core.submitLine('chat.send --id x --text hi'))!;
      final v = entry.view! as ErrorView;
      expect(v.code, 'AUTH_REQUIRED');
      expect(v.need, 3);
      expect(v.elevate, 'auth.unlock');
    });

    test('helpIntent：改走 sys.help，entry.cmd 仍是被查命令', () async {
      final entry = (await core.submitLine('sys.ping?'))!;
      expect(entry.helpIntent, isTrue);
      expect(entry.cmd, 'sys.ping');
      expect(entry.envelope!.cmd, 'sys.help');
      expect(entry.ok, isTrue);
      expect(core.history.single, 'sys.ping ?');
    });

    test('--stay 标记在 entry 上（G2 收起决策）', () async {
      final entry = (await core.submitLine('sys.ping --stay'))!;
      expect(entry.stay, isTrue);
      expect(entry.ok, isTrue);
    });

    test('超时态复用总线预算：慢命令 → TIMEOUT 错误视图', () async {
      h.bus.register(
        CommandSpec(
          namespace: 'z',
          verb: 'get',
          summary: '测试慢命令',
          kind: CommandKind.read,
          level: ControlLevel.guest,
          timeoutOverride: const Duration(milliseconds: 30),
          handler: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            return <String, Object?>{};
          },
        ),
      );
      final entry = (await core.submitLine('z.get'))!;
      expect(entry.ok, isFalse);
      expect((entry.view! as ErrorView).code, 'TIMEOUT');
      expect(core.busy, isFalse);
    });
  });

  group('命令历史（会话内 ↑↓）', () {
    test('连续重复去重；older/newer 召回与越界', () async {
      await core.submitLine('sys.ping');
      await core.submitLine('sys.ping'); // 连续重复不新增
      await core.submitLine('sys.info');
      expect(core.history, ['sys.ping', 'sys.info']);
      expect(core.recallOlder(), 'sys.info');
      expect(core.recallOlder(), 'sys.ping');
      expect(core.recallOlder(), isNull); // 已在最旧端
      expect(core.recallNewer(), 'sys.info');
      expect(core.recallNewer(), ''); // 越过最新端 → 空输入
      expect(core.recallNewer(), isNull);
    });

    test('新提交复位召回指针', () async {
      await core.submitLine('sys.ping');
      await core.submitLine('sys.info');
      core.recallOlder();
      expect(core.recallOlder(), 'sys.ping');
      await core.submitLine('sys.audit');
      expect(core.recallOlder(), 'sys.audit'); // 已复位到最新端
    });

    test('auditRedact 参数：历史截到脱敏参数前，正文零字面', () async {
      // 即使命令被鉴权拒绝（未解锁），历史也在执行前写入——必须安全。
      await core.submitLine(
        'chat.send --id incoming-1 --text "  secret-alpha  "',
      );
      expect(core.history.single, 'chat.send --id incoming-1');
      expect(core.history.single, isNot(contains('secret')));

      // text 出现在 id 之前：截得更短（整行只剩命令名）。
      await core.submitLine('chat.send --text secret --id x');
      expect(core.history.last, 'chat.send');
    });
  });

  group('多行进文本 submitMultiline', () {
    setUp(() {
      h.chatStore.addIncoming(); // incoming-1
    });

    Future<void> unlockSlash() async {
      await h.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      await h.execResult(
        'auth.unlock',
        channel: ControlChannel.slash,
        args: {'pin': 'echo1'},
      );
    }

    test('全文经 string 参数注入，换行保留（参数契约不变）', () async {
      await unlockSlash();
      final entry = (await core.submitMultiline(
        head: 'chat.send --id incoming-1',
        param: 'text',
        text: '第一行\n第二行',
      ))!;
      expect(entry.ok, isTrue, reason: entry.view.toString());
      final msgs = h.chatStore.messagesOf('incoming-1').items;
      // messagesOf 新→旧：刚发的在最前。
      expect(msgs.first.text, '第一行\n第二行');
      // 历史同样不含正文。
      expect(core.history.last, 'chat.send --id incoming-1');
    });

    test('kebab 形态参数名也认', () async {
      await unlockSlash();
      final entry = (await core.submitMultiline(
        head: 'chat.send --id incoming-1',
        param: 'text',
        text: 'ok',
      ))!;
      expect(entry.ok, isTrue);
    });

    test('head 已给同参数 → USAGE（与 adb 互斥同语义）', () async {
      await unlockSlash();
      final entry = (await core.submitMultiline(
        head: 'chat.send --id incoming-1 --text inline',
        param: 'text',
        text: '外面的全文',
      ))!;
      expect(entry.ok, isFalse);
      expect((entry.view! as ErrorView).code, 'USAGE');
      expect((entry.view! as ErrorView).message, contains('互斥'));
    });

    test('非 string 参数 / 未知命令 → USAGE', () async {
      await unlockSlash();
      final badParam = (await core.submitMultiline(
        head: 'chat.list',
        param: 'limit', // integer
        text: '1',
      ))!;
      expect((badParam.view! as ErrorView).code, 'USAGE');

      final unknown = (await core.submitMultiline(
        head: 'ghost.verb --id x',
        param: 'text',
        text: 'x',
      ))!;
      expect((unknown.view! as ErrorView).code, 'USAGE');
    });
  });
}
