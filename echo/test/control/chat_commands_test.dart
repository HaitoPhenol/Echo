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

    test('清单标注：chat.send 是唯一非幂等 chat 命令', () async {
      final specs = {for (final s in h.bus.visibleSpecs) s.name: s};
      expect(specs['chat.send']!.idempotent, isFalse);
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
}
