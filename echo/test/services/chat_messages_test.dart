import 'package:echo/src/services/chat_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// ChatStore 消息层（ECP P2 chat.* 命令的数据底座）纯 Dart 测试。
///
/// 全部用例注入固定步进时钟，updatedAt/消息时间戳可断言；
/// 会话 id（incoming-N）与消息 id（msg-N）是两个独立序列器。
void main() {
  /// 从固定起点起、每取一次推进 1 分钟的时钟。
  DateTime Function() steppingClock() {
    var tick = 0;
    return () => DateTime(2026, 10, 12, 10, tick++);
  }

  group('ChatStore 消息层', () {
    test('addIncoming 同时落地首条 incoming 消息与 updatedAt', () {
      final store = ChatStore(now: steppingClock());
      addTearDown(store.dispose);

      store.addIncoming();
      final c = store.conversationOf('incoming-1');
      expect(c, isNotNull);
      expect(c!.preview, '你有一条新消息');
      expect(c.updatedAt, DateTime(2026, 10, 12, 10, 0));

      final page = store.messagesOf('incoming-1');
      expect(page.items, hasLength(1));
      final m = page.items.single;
      expect(m.id, 'msg-1');
      expect(m.direction, ChatDirection.incoming);
      expect(m.direction.wire, 'in');
      expect(m.text, '你有一条新消息');
      expect(m.conversationId, 'incoming-1');
      expect(page.nextCursor, isNull);
    });

    test('send：写入 outgoing 消息并更新 preview/updatedAt，返回消息对象', () {
      final store = ChatStore(now: steppingClock());
      addTearDown(store.dispose);
      store.addIncoming(); // t=0，消息 msg-1

      var notified = 0;
      store.addListener(() => notified++);

      final sent = store.send('incoming-1', '  第二条消息  ');
      expect(sent.id, 'msg-2');
      expect(sent.direction, ChatDirection.outgoing);
      expect(sent.direction.wire, 'out');
      // 正文 trim 后落库。
      expect(sent.text, '第二条消息');
      expect(sent.createdAt, DateTime(2026, 10, 12, 10, 1));

      final c = store.conversationOf('incoming-1')!;
      expect(c.preview, '第二条消息');
      expect(c.updatedAt, sent.createdAt);
      expect(notified, 1);

      // 倒序：新消息在前。
      final page = store.messagesOf('incoming-1');
      expect(page.items.map((m) => m.id), ['msg-2', 'msg-1']);
    });

    test('send 空文本/纯空白抛 ArgumentError，且不产生消息', () {
      final store = ChatStore(now: steppingClock());
      addTearDown(store.dispose);
      store.addIncoming();

      expect(() => store.send('incoming-1', ''), throwsArgumentError);
      expect(() => store.send('incoming-1', '   \n\t '), throwsArgumentError);
      expect(store.messagesOf('incoming-1').items, hasLength(1));
      // 预览未被污染。
      expect(store.conversationOf('incoming-1')!.preview, '你有一条新消息');
    });

    test('send/messagesOf 未知会话抛 StateError（命令层映射前的兜底）', () {
      final store = ChatStore(now: steppingClock());
      addTearDown(store.dispose);
      expect(() => store.send('nope', 'x'), throwsStateError);
      expect(() => store.messagesOf('nope'), throwsStateError);
      expect(store.conversationOf('nope'), isNull);
    });

    test('messagesOf 倒序游标分页：跨页连续、无重复无遗漏', () {
      final store = ChatStore(now: steppingClock());
      addTearDown(store.dispose);
      store.addIncoming(); // 1 条 incoming（msg-1），后续 send 为 msg-2..msg-6
      for (var i = 2; i <= 6; i++) {
        store.send('incoming-1', 'm$i');
      }

      // 共 6 条，每页 2 条：3 页。
      final p1 = store.messagesOf('incoming-1', limit: 2);
      expect(p1.items.map((m) => m.id), ['msg-6', 'msg-5']);
      expect(p1.hasMore, isTrue);

      final p2 = store.messagesOf(
        'incoming-1',
        limit: 2,
        cursor: p1.nextCursor,
      );
      expect(p2.items.map((m) => m.id), ['msg-4', 'msg-3']);
      expect(p2.hasMore, isTrue);

      final p3 = store.messagesOf(
        'incoming-1',
        limit: 2,
        cursor: p2.nextCursor,
      );
      expect(p3.items.map((m) => m.id), ['msg-2', 'msg-1']);
      expect(p3.nextCursor, isNull);
      expect(p3.hasMore, isFalse);

      // 末页后再翻：空页而非报错。
      final p4 = store.messagesOf(
        'incoming-1',
        limit: 2,
        cursor: p3.items.last.id,
      );
      expect(p4.items, isEmpty);
      expect(p4.nextCursor, isNull);
    });

    test('messagesOf 非整数页大小/坏游标抛 ArgumentError', () {
      final store = ChatStore(now: steppingClock());
      addTearDown(store.dispose);
      store.addIncoming();

      expect(
        () => store.messagesOf('incoming-1', limit: 0),
        throwsArgumentError,
      );
      expect(
        () => store.messagesOf('incoming-1', limit: 101),
        throwsArgumentError,
      );
      expect(
        () => store.messagesOf('incoming-1', cursor: 'msg-999'),
        throwsArgumentError,
      );
    });

    test('remove 同时清除消息正文', () {
      final store = ChatStore(now: steppingClock());
      addTearDown(store.dispose);
      store.addIncoming();
      store.send('incoming-1', '再见');

      store.remove('incoming-1');
      expect(store.conversations, isEmpty);
      expect(() => store.messagesOf('incoming-1'), throwsStateError);
    });

    test('会话与消息两个序列器独立：多会话 id/msg-id 不互相影响', () {
      final store = ChatStore(now: steppingClock());
      addTearDown(store.dispose);
      store.addIncoming(); // incoming-1 / msg-1
      store.send('incoming-1', 'a'); // msg-2
      store.addIncoming(); // incoming-2 / msg-3
      store.send('incoming-2', 'b'); // msg-4

      expect(store.conversations.first.id, 'incoming-2');
      expect(store.messagesOf('incoming-1').items.first.id, 'msg-2');
      expect(store.messagesOf('incoming-2').items.first.id, 'msg-4');
    });
  });
}
