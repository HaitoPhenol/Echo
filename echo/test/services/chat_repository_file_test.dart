import 'dart:io';

import 'package:echo/src/services/chat_repository.dart';
import 'package:echo/src/services/chat_repository_file.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _fixedNow() => DateTime.fromMillisecondsSinceEpoch(1750000000000);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('echo_chat_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('会话与消息落盘后可由新实例恢复，序号不撞车', () async {
    final repo = FileChatRepository(directory: dir, now: _fixedNow);
    await repo.ready;

    expect(
      repo.ensureConversation(
        id: 'ai-assistant',
        nickname: 'AI 助手',
        preview: '开始和 AI 对话',
      ),
      isTrue,
    );
    repo.send('ai-assistant', '你好');
    repo.appendIncoming(
      'ai-assistant',
      '你好呀',
      reasoning: '先判断问候语气',
      reasoningMs: 1200,
    );
    await repo.pendingWrites;

    expect(File('${dir.path}/${FileChatRepository.fileName}').existsSync(), isTrue);

    final restored = FileChatRepository(directory: dir, now: _fixedNow);
    addTearDown(restored.dispose);
    await restored.ready;

    final conversation = restored.conversationOf('ai-assistant');
    expect(conversation, isNotNull);
    expect(conversation!.nickname, 'AI 助手');
    expect(conversation.preview, '你好呀');
    expect(conversation.unread, isFalse);

    final page = restored.messagesOf('ai-assistant');
    expect(page.items.map((m) => m.text).toList(), ['你好呀', '你好']);
    expect(page.items.first.direction, ChatDirection.incoming);
    expect(page.items.last.direction, ChatDirection.outgoing);
    // 思考内容与耗时随消息一起持久化。
    expect(page.items.first.reasoning, '先判断问候语气');
    expect(page.items.first.reasoningMs, 1200);

    // 恢复后继续追加：消息 id 接着最大值往后排，不覆盖历史。
    final next = restored.appendIncoming('ai-assistant', '第三句');
    expect(next.id, 'msg-3');
    await restored.pendingWrites;

    repo.dispose();
  });

  test('未读标记与删除同样持久化', () async {
    final repo = FileChatRepository(directory: dir, now: _fixedNow);
    await repo.ready;
    repo.addIncoming(text: '第一条');
    await repo.pendingWrites;

    final restored = FileChatRepository(directory: dir, now: _fixedNow);
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.conversations.single.unread, isTrue);
    expect(restored.conversations.single.preview, '第一条');

    restored.markRead(restored.conversations.single.id);
    await restored.pendingWrites;

    final again = FileChatRepository(directory: dir, now: _fixedNow);
    addTearDown(again.dispose);
    await again.ready;
    expect(again.conversations.single.unread, isFalse);

    again.remove(again.conversations.single.id);
    await again.pendingWrites;

    final empty = FileChatRepository(directory: dir, now: _fixedNow);
    addTearDown(empty.dispose);
    await empty.ready;
    expect(empty.conversations, isEmpty);

    repo.dispose();
  });

  test('历史文件损坏时保持空列表且 ready 仍完成', () async {
    final file = File('${dir.path}/${FileChatRepository.fileName}');
    await file.writeAsString('{not-json');

    final repo = FileChatRepository(directory: dir, now: _fixedNow);
    addTearDown(repo.dispose);
    await repo.ready;

    expect(repo.conversations, isEmpty);
    // 损坏后仍可正常写入新数据。
    repo.ensureConversation(id: 'ai-assistant', nickname: 'AI 助手');
    repo.send('ai-assistant', '还能用');
    await repo.pendingWrites;
    expect(repo.conversationOf('ai-assistant')!.preview, '还能用');
  });
}
