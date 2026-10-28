import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'chat_repository.dart';

/// 聊天历史的持久化仓储：内存实现 + 应用私有目录 JSON 快照。
///
/// 进程启动时异步读盘，读完把历史会话/消息灌入内存实现并 notify 一次
/// （[ChatStore] 接到后刷新列表）。所有写操作完成后串行落盘，
/// 「临时文件 + rename」原子替换；写失败只吞掉，不影响内存态。
///
/// 文件落在应用私有目录，不参与日记导出，也不写日志。
class FileChatRepository extends ChangeNotifier implements ChatRepository {
  FileChatRepository({this.directory, DateTime Function()? now})
    : _now = now,
      _memory = InMemoryChatRepository(now: now) {
    unawaited(_load());
  }

  /// 聊天历史文件名。
  static const String fileName = 'chat_history.json';

  /// 测试注入的目录；生产为 null（走 path_provider 的私有目录）。
  final Directory? directory;

  /// 注入的时钟（测试固定时间用）；读盘重建内存层时沿用，不丢口径。
  final DateTime Function()? _now;

  InMemoryChatRepository _memory;

  final Completer<void> _ready = Completer<void>();

  Future<void> _writeChain = Future<void>.value();

  bool _disposed = false;

  @override
  Future<void> get ready => _ready.future;

  /// 已排队的落盘任务（测试等待写入完成用）。
  @visibleForTesting
  Future<void> get pendingWrites => _writeChain;

  @override
  List<ChatConversation> get conversations => _memory.conversations;

  @override
  bool get hasUnread => _memory.hasUnread;

  @override
  Stream<ChatIncomingPayload> get incoming => _memory.incoming;

  @override
  ChatConversation? conversationOf(String id) => _memory.conversationOf(id);

  @override
  bool ensureConversation({
    required String id,
    required String nickname,
    String preview = '',
  }) {
    final changed = _memory.ensureConversation(
      id: id,
      nickname: nickname,
      preview: preview,
    );
    if (changed) _scheduleSave();
    return changed;
  }

  @override
  ChatMessage appendIncoming(
    String conversationId,
    String text, {
    String? reasoning,
    int? reasoningMs,
  }) {
    final message = _memory.appendIncoming(
      conversationId,
      text,
      reasoning: reasoning,
      reasoningMs: reasoningMs,
    );
    _scheduleSave();
    return message;
  }

  @override
  void addIncoming({String? text}) {
    _memory.addIncoming(text: text);
    _scheduleSave();
  }

  @override
  bool remove(String id) {
    final changed = _memory.remove(id);
    if (changed) _scheduleSave();
    return changed;
  }

  @override
  bool markRead(String id) {
    final changed = _memory.markRead(id);
    if (changed) _scheduleSave();
    return changed;
  }

  @override
  bool markUnread(String id) {
    final changed = _memory.markUnread(id);
    if (changed) _scheduleSave();
    return changed;
  }

  @override
  ChatMessage send(String conversationId, String rawText) {
    final message = _memory.send(conversationId, rawText);
    _scheduleSave();
    return message;
  }

  @override
  ChatMessagePage messagesOf(
    String conversationId, {
    int limit = 20,
    String? cursor,
  }) => _memory.messagesOf(conversationId, limit: limit, cursor: cursor);

  /// 读盘：文件不存在/损坏时保持空列表（不阻塞启动）。
  Future<void> _load() async {
    try {
      final file = await _historyFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final snapshot = _ChatSnapshot.fromJsonString(raw);
        if (snapshot != null) _adopt(snapshot);
      }
    } catch (_) {
      // 历史损坏时不阻塞启动：保留空列表，下一条消息重新建快照。
    }
    if (!_ready.isCompleted) _ready.complete();
    if (!_disposed) notifyListeners();
  }

  /// 用读盘结果重建内存层。
  ///
  /// 读盘窗口（文件 I/O 期间）若已有写入，其新建会话按原样补回去，
  /// 避免被读盘结果整体覆盖后从列表里消失。
  void _adopt(_ChatSnapshot snapshot) {
    final pending = _ChatSnapshot.fromRepository(_memory).conversations;
    _memory = InMemoryChatRepository(
      conversations: snapshot.conversations,
      messages: snapshot.messages,
      now: _now,
    );
    // 倒着补：ensureConversation 插到最前，倒序补完顺序与原先一致。
    for (final conversation in pending.reversed) {
      if (_memory.conversationOf(conversation.id) != null) continue;
      _memory.ensureConversation(
        id: conversation.id,
        nickname: conversation.nickname,
        preview: conversation.preview,
      );
    }
  }

  /// 串行落盘：先写临时文件再原子替换目标文件。
  ///
  /// 快照必须等读盘完成后再取：读盘前的内存是空的，提前取会拿空快照
  /// 覆盖已有历史文件。
  void _scheduleSave() {
    if (_disposed) return;
    _writeChain = _writeChain.then((_) async {
      try {
        await _ready.future;
        final payload = jsonEncode(
          _ChatSnapshot.fromRepository(_memory).toJson(),
        );
        final file = await _historyFile();
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(payload, flush: true);
        await tmp.rename(file.path);
      } catch (_) {
        // 落盘失败不抛给 UI：内存态已更新，下次写入会重试。
      }
    });
  }

  Future<File> _historyFile() async {
    final dir = directory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/$fileName');
  }

  @override
  void dispose() {
    _disposed = true;
    _memory.dispose();
    super.dispose();
  }
}

/// 聊天历史快照（JSON 线格式，只在 services 层使用）。
class _ChatSnapshot {
  const _ChatSnapshot({required this.conversations, required this.messages});

  final List<ChatConversation> conversations;

  /// 会话 id → 按时间正序的消息列表。
  final Map<String, List<ChatMessage>> messages;

  factory _ChatSnapshot.fromRepository(ChatRepository repo) {
    final conversations = repo.conversations;
    final messages = <String, List<ChatMessage>>{};
    for (final conversation in conversations) {
      // 按 100 条一页翻到底：单页快照会让超长会话在每次落盘时
      // 丢掉第 100 条以前的历史。
      final all = <ChatMessage>[];
      String? cursor;
      while (true) {
        final page = repo.messagesOf(
          conversation.id,
          limit: 100,
          cursor: cursor,
        );
        all.addAll(page.items);
        final next = page.nextCursor;
        if (next == null || next == cursor) break;
        cursor = next;
      }
      messages[conversation.id] = all.reversed.toList(growable: false);
    }
    return _ChatSnapshot(conversations: conversations, messages: messages);
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'conversations': [
      for (final c in conversations)
        {
          'id': c.id,
          'nickname': c.nickname,
          'preview': c.preview,
          'updatedAt': c.updatedAt.millisecondsSinceEpoch,
          'unread': c.unread,
        },
    ],
    'messages': {
      for (final entry in messages.entries)
        entry.key: [
          for (final m in entry.value)
            {
              'id': m.id,
              'text': m.text,
              'direction': m.direction.wire,
              'createdAt': m.createdAt.millisecondsSinceEpoch,
              if (m.reasoning != null) 'reasoning': m.reasoning,
              if (m.reasoningMs != null) 'reasoningMs': m.reasoningMs,
            },
        ],
    },
  };

  /// 容错解析：整体不是对象/关键数组缺失时返回 null，单条坏项跳过。
  static _ChatSnapshot? fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final conversations = <ChatConversation>[];
    final rawConversations = decoded['conversations'];
    if (rawConversations is List) {
      for (final item in rawConversations) {
        if (item is! Map) continue;
        final id = item['id'];
        final nickname = item['nickname'];
        if (id is! String || nickname is! String) continue;
        conversations.add(
          ChatConversation(
            id: id,
            nickname: nickname,
            preview: item['preview'] is String ? item['preview'] as String : '',
            updatedAt: _time(item['updatedAt']),
            unread: item['unread'] == true,
          ),
        );
      }
    }

    final messages = <String, List<ChatMessage>>{};
    final rawMessages = decoded['messages'];
    if (rawMessages is Map) {
      for (final entry in rawMessages.entries) {
        final conversationId = entry.key;
        final list = entry.value;
        if (conversationId is! String || list is! List) continue;
        final parsed = <ChatMessage>[];
        for (final item in list) {
          if (item is! Map) continue;
          final id = item['id'];
          final text = item['text'];
          if (id is! String || text is! String) continue;
          parsed.add(
            ChatMessage(
              id: id,
              conversationId: conversationId,
              text: text,
              direction: item['direction'] == ChatDirection.incoming.wire
                  ? ChatDirection.incoming
                  : ChatDirection.outgoing,
              createdAt: _time(item['createdAt']),
              reasoning: item['reasoning'] is String
                  ? item['reasoning'] as String
                  : null,
              reasoningMs: item['reasoningMs'] is num
                  ? (item['reasoningMs'] as num).toInt()
                  : null,
            ),
          );
        }
        messages[conversationId] = parsed;
      }
    }
    return _ChatSnapshot(conversations: conversations, messages: messages);
  }

  static DateTime _time(Object? value) => value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
      : DateTime.now();
}
