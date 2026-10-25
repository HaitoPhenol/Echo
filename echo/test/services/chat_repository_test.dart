import 'package:echo/src/services/chat_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// ChatRepository 抽象接缝：命令/UI 只依赖接口，ChatStore 只做
/// 「委托 + 变更通知」，行为与重构前一致。
void main() {
  group('ChatRepository 抽象接缝', () {
    test('注入仓储时 ChatStore 读写同源，且每次写入通知一次', () {
      final repo = InMemoryChatRepository(
        now: () => DateTime(2026, 10, 25, 10),
      );
      final store = ChatStore(repository: repo);
      var notified = 0;
      store.addListener(() => notified++);
      addTearDown(store.dispose);

      store.addIncoming(text: '你好');

      expect(repo.conversations.single.preview, '你好');
      expect(store.conversations.single.unread, isTrue);
      expect(store.hasUnread, isTrue);
      expect(notified, 1);
    });

    test('标记已读/未读/删除返回是否变化，未变化不通知', () {
      final repo = InMemoryChatRepository(
        now: () => DateTime(2026, 10, 25, 10),
      );
      final store = ChatStore(repository: repo);
      var notified = 0;
      store.addListener(() => notified++);
      addTearDown(store.dispose);
      store.addIncoming();
      final id = store.conversations.single.id;
      notified = 0;

      expect(store.markRead(id), isTrue);
      expect(store.markRead(id), isFalse);
      expect(notified, 1);

      expect(store.markUnread(id), isTrue);
      expect(store.markUnread(id), isFalse);
      expect(notified, 2);

      expect(store.remove(id), isTrue);
      expect(store.remove(id), isFalse);
      expect(notified, 3);
    });

    test('send 成功通知一次；异常路径不通知', () {
      final store = ChatStore();
      var notified = 0;
      store.addListener(() => notified++);
      addTearDown(store.dispose);
      store.addIncoming();
      final id = store.conversations.single.id;
      notified = 0;

      store.send(id, '收到');
      expect(notified, 1);

      expect(() => store.send(id, '  '), throwsArgumentError);
      expect(() => store.send('missing', 'x'), throwsStateError);
      expect(notified, 1);
    });

    test('incoming 广播经 Store 转发，载荷原文不变', () async {
      final store = ChatStore();
      addTearDown(store.dispose);
      final received = <ChatIncomingPayload>[];
      final sub = store.incoming.listen(received.add);

      store.addIncoming(text: '来自对端');
      await Future<void>.delayed(Duration.zero);

      expect(received.single.text, '来自对端');
      expect(received.single.preview, '来自对端');
      await sub.cancel();
    });

    test('自建仓储随 Store 释放：广播流关闭', () {
      final store = ChatStore();
      store.dispose();

      expect(() => store.addIncoming(), throwsStateError);
    });

    test('注入仓储不由 ChatStore 释放', () {
      final repo = InMemoryChatRepository();
      final store = ChatStore(repository: repo);
      store.dispose();

      // 外部仓储仍可写入（未被 close 的广播流影响）。
      expect(() => repo.addIncoming(), returnsNormally);
      repo.dispose();
    });
  });
}
