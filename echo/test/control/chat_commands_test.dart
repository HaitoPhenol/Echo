import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/control/protocol/command_spec.dart';
import 'package:echo/src/control/protocol/control_error.dart';

import 'control_test_harness.dart';

/// `chat.*` 命令（手册 §6）协议测试：线格式字段、分页游标、
/// NOT_FOUND/USAGE 语义、通道级别裁决。
void main() {
  late ControlHarness h;

  setUp(() async {
    h = await ControlHarness.create(startTime: DateTime(2026, 10, 12, 10));
  });
  tearDown(() => h.dispose());

  group('chat.list', () {
    test('空仓 items 为空；造会话后返回冻结字段名与顺序', () async {
      final empty = await h.execResult('chat.list');
      expect(empty['items'], isEmpty);

      h.chatStore.addIncoming();
      h.chatStore.addIncoming(); // 新会话在最前
      final list = await h.execResult('chat.list');
      final items = list['items'] as List;
      expect(items, hasLength(2));
      final first = items.first as Map;
      expect(first['id'], 'incoming-2');
      expect(first['title'], '新消息 2');
      expect(first['unread'], isTrue);
      expect(first['lastPreview'], '你有一条新消息');
      expect(first['updatedAt'], '2026-10-12T10:00:00');
      // 冻结契约不含正文键。
      expect(first, isNot(contains('messages')));
      expect(first, isNot(contains('nickname')));
    });
  });

  group('chat.get', () {
    test('返回元数据 + 消息页（倒序、游标跨页）', () async {
      h.chatStore.addIncoming(); // msg-1
      h.chatStore.send('incoming-1', '第一句'); // msg-2
      h.chatStore.send('incoming-1', '第二句'); // msg-3

      final p1 = await h.execResult(
        'chat.get',
        args: {'id': 'incoming-1', 'limit': 2},
      );
      expect(p1['id'], 'incoming-1');
      expect(p1['title'], '新消息 1');
      final m1 = (p1['messages'] as List).cast<Map>();
      expect(m1.map((m) => m['id']), ['msg-3', 'msg-2']);
      expect(m1.first['direction'], 'out');
      expect(m1.first['text'], '第二句');
      expect(p1['hasMore'], isTrue);
      final cursor = p1['cursor'] as String;

      final p2 = await h.execResult(
        'chat.get',
        args: {'id': 'incoming-1', 'limit': 2, 'cursor': cursor},
      );
      final m2 = (p2['messages'] as List).cast<Map>();
      expect(m2.single['id'], 'msg-1');
      expect(m2.single['direction'], 'in');
      expect(p2['hasMore'], isFalse);
      expect(p2.containsKey('cursor'), isFalse);
    });

    test('未知 id → NOT_FOUND（退出码 5）', () async {
      final env = await h.exec('chat.get', args: {'id': 'ghost'});
      expect(env.ok, isFalse);
      expect(env.error!.code, ControlErrorCode.notFound);
    });

    test('坏游标 / limit 越界 → USAGE', () async {
      h.chatStore.addIncoming();
      expect(
        (await h.exec(
          'chat.get',
          args: {'id': 'incoming-1', 'cursor': 'msg-999'},
        )).error!.code,
        ControlErrorCode.usage,
      );
      expect(
        (await h.exec(
          'chat.get',
          args: {'id': 'incoming-1', 'limit': 0},
        )).error!.code,
        ControlErrorCode.usage,
      );
    });
  });

  group('chat.open / chat.mark-read', () {
    test('open 与点按同路径：清未读并记录 openSessionId', () async {
      h.chatStore.addIncoming();

      final r = await h.execResult('chat.open', args: {'id': 'incoming-1'});
      expect(r['unread'], isFalse);
      expect(h.chatSession.openSessionId, 'incoming-1');
      expect(h.chatStore.hasUnread, isFalse);

      // 幂等：再次 open 同样成功。
      final again = await h.execResult(
        'chat.open',
        args: {
          'id': 'incoming-1',
          'stay': true, // 全局 slash 标志，adb 接受并忽略
        },
      );
      expect(again['unread'], isFalse);
    });

    test('open 未知 id → NOT_FOUND', () async {
      expect(
        (await h.exec('chat.open', args: {'id': 'ghost'})).error!.code,
        ControlErrorCode.notFound,
      );
    });

    test('mark-read 清未读；未知 id → NOT_FOUND', () async {
      h.chatStore.addIncoming();
      final r = await h.execResult(
        'chat.mark-read',
        args: {'id': 'incoming-1'},
      );
      expect(r['unread'], isFalse);

      expect(
        (await h.exec('chat.mark-read', args: {'id': 'ghost'})).error!.code,
        ControlErrorCode.notFound,
      );
    });
  });

  group('chat.send', () {
    setUp(() async {
      // G0（2026-10-13）：chat.send 升 3 级。组内 adb/slash 调用统一
      // 预置「当次前台已解锁会话」；锁态/提权用例内部自行 lock 验证。
      await h.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});
    });

    test('G0 级别 3：未解锁 adb/slash → AUTH_REQUIRED(need 3)；'
        '解锁后会话内连发免 --confirm；mcp 恒拒', () async {
      h.chatStore.addIncoming();
      h.auth.lock(ControlChannel.adb);

      // 1) 本地两通道未解锁：need=3 的提权错误（不是 confirmRequired）。
      for (final ch in [ControlChannel.adb, ControlChannel.slash]) {
        final denied = await h.exec(
          'chat.send',
          channel: ch,
          args: {'id': 'incoming-1', 'text': 'x'},
        );
        expect(denied.ok, isFalse, reason: ch.wire);
        expect(denied.error!.code, ControlErrorCode.authRequired);
        expect(denied.error!.need, 3);
        expect(denied.error!.elevate, 'auth.unlock');
      }

      // 2) MCP 上限 1：无论任何会话状态，3 级发送物理不可达。
      final mcpDenied = await h.exec(
        'chat.send',
        channel: ControlChannel.mcp,
        args: {'id': 'incoming-1', 'text': 'x'},
      );
      expect(mcpDenied.error!.code, ControlErrorCode.authRequired);

      // 3) 两通道分别解锁（会话按通道独立持有），confirmed 保持默认
      //    false：非破坏性 3 级会话内连发，不逐条要 --confirm。
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});
      await h.execResult(
        'auth.unlock',
        channel: ControlChannel.slash,
        args: {'pin': 'echo1'},
      );
      final r1 = await h.exec(
        'chat.send',
        args: {'id': 'incoming-1', 'text': '第一封'},
      );
      final r2 = await h.exec(
        'chat.send',
        channel: ControlChannel.slash,
        args: {'id': 'incoming-1', 'text': '第二封'},
      );
      expect(r1.ok, isTrue);
      expect(r2.ok, isTrue);
      // 1 条 incoming + 2 条 outgoing 全部落库；被拒的 3 次零污染。
      expect(h.chatStore.messagesOf('incoming-1').items, hasLength(3));
    });

    test('成功：返回消息对象，会话 preview/未读状态不变', () async {
      h.chatStore.addIncoming();
      h.chatStore.markRead('incoming-1');

      final r = await h.execResult(
        'chat.send',
        args: {'id': 'incoming-1', 'text': '  你好世界  '},
      );
      expect(r['id'], 'msg-2'); // addIncoming 占 msg-1
      expect(r['conversationId'], 'incoming-1');
      expect(r['direction'], 'out');
      expect(r['text'], '你好世界');
      expect(r['createdAt'], '2026-10-12T10:00:00');

      final c = h.chatStore.conversationOf('incoming-1')!;
      expect(c.preview, '你好世界');
      expect(c.unread, isFalse); // 外发不产生未读
    });

    test('空文本 → USAGE；未知会话 → NOT_FOUND', () async {
      h.chatStore.addIncoming();
      expect(
        (await h.exec(
          'chat.send',
          args: {'id': 'incoming-1', 'text': '   '},
        )).error!.code,
        ControlErrorCode.usage,
      );
      expect(
        (await h.exec(
          'chat.send',
          args: {'id': 'ghost', 'text': 'x'},
        )).error!.code,
        ControlErrorCode.notFound,
      );
      // 两次失败都没有污染消息列表。
      expect(h.chatStore.messagesOf('incoming-1').items, hasLength(1));
    });

    test('审计脱敏（F2）：成功与失败审计均不含正文字面，N=trim 后长度', () async {
      h.chatStore.addIncoming();
      h.chatStore.markRead('incoming-1');

      // 1) 成功路径：正文带前后空白，N 按 trim 后落库长度（12）。
      await h.execResult(
        'chat.send',
        args: {'id': 'incoming-1', 'text': '  secret-alpha  '},
      );
      // 2) 失败路径①：未知会话 NOT_FOUND，正文同样必须脱敏。
      final notFound = await h.exec(
        'chat.send',
        args: {'id': 'ghost', 'text': '  secret-bravo  '},
      );
      expect(notFound.ok, isFalse);
      // 3) 失败路径②：空白文本 USAGE，N=0。
      final usage = await h.exec(
        'chat.send',
        args: {'id': 'incoming-1', 'text': '   '},
      );
      expect(usage.ok, isFalse);

      // 三条 chat.send 审计（新→旧）逐条核对：id 可见、正文只剩占位。
      final entries = h.audit
          .list(limit: 50)
          .where((e) => e.cmd == 'chat.send')
          .toList();
      expect(entries, hasLength(3));
      void expectRedacted(
        Map<String, Object?> params,
        String n,
        String literal,
      ) {
        expect(params['id'], isNotNull);
        expect(params['text'], '<redacted:$n>');
        // 整条 paramSummary 的序列化结果里也不能出现正文字面。
        expect(params.toString(), isNot(contains(literal)));
      }

      // 倒序：空白 USAGE（N=0）→ NOT_FOUND（12）→ 成功（12）。
      expect(entries[0].ok, isFalse);
      expect(entries[0].errorCode, 'USAGE');
      expectRedacted(entries[0].paramSummary, '0', 'secret');
      expect(entries[1].ok, isFalse);
      expect(entries[1].errorCode, 'NOT_FOUND');
      expectRedacted(entries[1].paramSummary, '12', 'secret-bravo');
      expect(entries[2].ok, isTrue);
      expect(entries[2].errorCode, isNull);
      expectRedacted(entries[2].paramSummary, '12', 'secret-alpha');
    });

    test('清单标注：chat.send/chat.seed 3 级非破坏（免 confirm）、非幂等', () async {
      final specs = {for (final s in h.bus.visibleSpecs) s.name: s};
      final send = specs['chat.send']!;
      expect(send.idempotent, isFalse);
      // G0：3 级但非破坏性——解锁即可，不弹确认卡/不要 --confirm。
      expect(send.level, ControlLevel.admin);
      expect(send.destructive, isFalse);
      expect(send.requiresConfirm, isFalse);
      // P4 chat.seed 同款：3 级非破坏、非幂等，且仅 debug 注册。
      final seed = specs['chat.seed']!;
      expect(seed.idempotent, isFalse);
      expect(seed.level, ControlLevel.admin);
      expect(seed.destructive, isFalse);
      expect(seed.requiresConfirm, isFalse);
      expect(seed.debugOnly, isTrue);
      for (final name in [
        'chat.list',
        'chat.get',
        'chat.open',
        'chat.mark-read',
      ]) {
        expect(specs[name]!.idempotent, isTrue, reason: name);
      }
    });

    test('通道裁决：mcp 起始 0 级且永不提权，chat 读写一律拒绝', () async {
      h.chatStore.addIncoming();
      // owner(1) 读：mcp 同样拒绝（只有 guest(0) 直通）。
      final readDenied = await h.exec('chat.list', channel: ControlChannel.mcp);
      expect(readDenied.error!.code, ControlErrorCode.authRequired);
      // user(2) 写：拒绝。
      final writeDenied = await h.exec(
        'chat.send',
        channel: ControlChannel.mcp,
        args: {'id': 'incoming-1', 'text': 'x'},
      );
      expect(writeDenied.error!.code, ControlErrorCode.authRequired);
      // 被裁决拦截的写操作不落库。
      expect(h.chatStore.messagesOf('incoming-1').items, hasLength(1));
    });
  });

  group('chat.seed（debug-only，P4 灌数）', () {
    test('release 物理不注册；debug 3 级解锁后 seed→chat.send 端到端', () async {
      final rel = await ControlHarness.create(
        buildMode: ControlBuildMode.release,
      );
      addTearDown(rel.dispose);
      expect(
        (await rel.exec('chat.seed')).error!.code,
        ControlErrorCode.unknownCommand,
      );
      expect(
        rel.bus.visibleSpecs.map((s) => s.name),
        isNot(contains('chat.seed')),
      );

      // debug：admin 3 级非破坏——未解锁 AUTH_REQUIRED，解锁即放行。
      expect(
        (await h.exec('chat.seed')).error!.code,
        ControlErrorCode.authRequired,
      );
      await h.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});

      final seeded = await h.execResult('chat.seed');
      expect(seeded['ids'], ['incoming-1']);
      // 端到端：seed 出的会话可直接 chat.send（debug 补齐成功路径）。
      final sent = await h.execResult(
        'chat.send',
        args: {'id': 'incoming-1', 'text': '端到端'},
      );
      expect(sent['conversationId'], 'incoming-1');
      expect(h.chatStore.messagesOf('incoming-1').items, hasLength(2));
    });

    test('--count 多条 + 自定义文本；越界 USAGE、正文审计脱敏', () async {
      await h.execResult(
        'auth.set-pin',
        args: {'newPin': 'echo1', 'newPinConfirm': 'echo1'},
      );
      await h.execResult('auth.unlock', args: {'pin': 'echo1'});

      for (final bad in [0, 21]) {
        expect(
          (await h.exec('chat.seed', args: {'count': bad})).error!.code,
          ControlErrorCode.usage,
          reason: 'count=$bad',
        );
      }

      final seeded = await h.execResult(
        'chat.seed',
        args: {'count': 3, 'text': '灌入正文'},
      );
      // 新会话逐个插到最前，返回其稳定 id。
      expect(seeded['ids'], ['incoming-1', 'incoming-2', 'incoming-3']);
      expect(h.chatStore.conversationOf('incoming-1')!.preview, '灌入正文');

      // 审计脱敏：正文只记 <redacted:N>（N=trim 后长度 4）。
      final entry = h.audit
          .list(limit: 20)
          .firstWhere((e) => e.cmd == 'chat.seed' && e.ok);
      expect(entry.paramSummary['text'], '<redacted:4>');
      expect(entry.paramSummary.toString(), isNot(contains('灌入正文')));
    });
  });
}
