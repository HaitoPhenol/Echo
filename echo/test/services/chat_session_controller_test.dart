import 'package:echo/src/services/chat_session_controller.dart';
import 'package:echo/src/services/chat_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// ChatSessionController（chat.open 命令与点按行的同路收口）测试。
void main() {
  group('ChatSessionController', () {
    test('open：未读会话被标记已读并记录 openSessionId，通知一次', () {
      final store = ChatStore()..addIncoming();
      final controller = ChatSessionController(store);
      addTearDown(() {
        controller.dispose();
        store.dispose();
      });

      expect(controller.openSessionId, isNull);
      expect(controller.isOpen, isFalse);
      var notified = 0;
      controller.addListener(() => notified++);

      controller.open('incoming-1');
      expect(controller.openSessionId, 'incoming-1');
      expect(controller.isOpen, isTrue);
      // 未读绿点经同一个 store.markRead 清除。
      expect(store.conversationOf('incoming-1')!.unread, isFalse);
      expect(store.hasUnread, isFalse);
      expect(notified, 1);
    });

    test('重复 open 同一会话幂等：不重复通知（markRead 也幂等）', () {
      final store = ChatStore()
        ..addIncoming()
        ..markRead('incoming-1');
      final controller = ChatSessionController(store);
      addTearDown(() {
        controller.dispose();
        store.dispose();
      });

      var notified = 0;
      controller.addListener(() => notified++);

      controller.open('incoming-1');
      controller.open('incoming-1');
      expect(controller.openSessionId, 'incoming-1');
      expect(notified, 1);
      expect(store.conversationOf('incoming-1')!.unread, isFalse);
    });

    test('open 另一会话切换 openSessionId；close 清空，二者均幂等', () {
      final store = ChatStore()
        ..addIncoming() // incoming-1
        ..addIncoming(); // incoming-2（在最前）
      final controller = ChatSessionController(store);
      addTearDown(() {
        controller.dispose();
        store.dispose();
      });

      controller.open('incoming-1');
      controller.open('incoming-2');
      expect(controller.openSessionId, 'incoming-2');
      // 两个会话都经 open 清了未读。
      expect(store.hasUnread, isFalse);

      controller.close();
      expect(controller.openSessionId, isNull);
      expect(controller.isOpen, isFalse);

      var notified = 0;
      controller.addListener(() => notified++);
      controller.close(); // 已关闭再关：无通知。
      expect(notified, 0);
    });

    test('open 未知会话抛 StateError 且不改变打开状态', () {
      final store = ChatStore();
      final controller = ChatSessionController(store);
      addTearDown(() {
        controller.dispose();
        store.dispose();
      });

      expect(() => controller.open('ghost'), throwsStateError);
      expect(controller.openSessionId, isNull);
    });
  });
}
