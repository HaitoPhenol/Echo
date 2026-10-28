import 'dart:async';

import 'package:flutter/foundation.dart';

/// 一条 incoming 消息到达的广播载荷（P4 事件源）。
///
/// 这是 services 层自己的信号类型：仓储**不认识 control 事件总线**
/// （分层接缝：services 禁止反向 import control），由 control
/// 装配层适配器订阅 [ChatRepository.incoming] 并翻译成 `chat.incoming`
/// 事件。字段均为可直接线传的 JSON 兼容标量。
@immutable
class ChatIncomingPayload {
  const ChatIncomingPayload({
    required this.id,
    required this.nickname,
    required this.preview,
    required this.text,
  });

  /// 新会话稳定 id（`incoming-<n>`）。
  final String id;

  /// 会话昵称（`新消息 <n>`）。
  final String nickname;

  /// 会话列表上的预览文案。
  final String preview;

  /// 首条 incoming 消息正文（与 chat.get 同源，owner 可读）。
  final String text;
}

/// 一条会话（脚手架阶段的不可变值对象）。
///
/// 当前只有昵称、消息预览与未读标记；接入真实数据源后在此扩展
/// （头像、时间、会话 id 等）。状态变更走 [copyWith]，保证
/// 列表元素可做身份/相等性比较。
@immutable
class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.nickname,
    required this.preview,
    required this.updatedAt,
    this.unread = false,
  });

  /// 会话稳定标识（列表 key、定向更新均以此为准，不用下标）。
  final String id;

  /// 会话昵称。
  final String nickname;

  /// 最新一条消息的预览文案。
  final String preview;

  /// 最近一次消息时间（命令层 chat.list 的 updatedAt，倒序判定备用）。
  final DateTime updatedAt;

  /// 是否有未读消息（驱动行内呼吸绿点与导航锚点通知态）。
  final bool unread;

  ChatConversation copyWith({
    bool? unread,
    String? preview,
    DateTime? updatedAt,
  }) => ChatConversation(
    id: id,
    nickname: nickname,
    preview: preview ?? this.preview,
    updatedAt: updatedAt ?? this.updatedAt,
    unread: unread ?? this.unread,
  );
}

/// 消息方向：`in` = 对方发来，`out` = 本机经 chat.send / UI 发出。
///
/// [wire] 是协议线格式（手册 §6），名称冻结后只追加不改。
enum ChatDirection {
  incoming('in'),
  outgoing('out');

  const ChatDirection(this.wire);
  final String wire;
}

/// 一条聊天消息（不可变值对象）。
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.text,
    required this.direction,
    required this.createdAt,
    this.reasoning,
    this.reasoningMs,
  });

  /// 消息稳定标识（仓储内全局序列器生成，同会话内按存储位置分页，
  /// 不假设 id 字典序可比）。
  final String id;

  /// 所属会话 id。
  final String conversationId;

  /// 消息正文（send 时已 trim；永不为空串）。
  final String text;

  /// 方向（in/out）。
  final ChatDirection direction;

  /// 创建时间（墙钟；由仓储统一注入的时钟产生）。
  final DateTime createdAt;

  /// 推理模型的思考正文（仅 AI 助手回复可能带）；无思考时为 null。
  final String? reasoning;

  /// 产生 [reasoning] 花掉的毫秒数；无思考时为 null。
  final int? reasoningMs;
}

/// 一次消息分页读取的结果（新 → 旧）。
class ChatMessagePage {
  const ChatMessagePage({required this.items, this.nextCursor});

  /// 本页消息（最新在前）。
  final List<ChatMessage> items;

  /// 下一页游标（本页最末一条消息 id）；无更多时为 null。
  final String? nextCursor;

  /// 是否还有更早的消息。
  bool get hasMore => nextCursor != null;
}

/// 聊天数据仓储：会话、消息与 incoming 信号。
///
/// 领域层（命令/UI）只依赖本接口，不关心数据落在内存还是磁盘；
/// 当前生产实现为 [InMemoryChatRepository]（重启清空），后续接入
/// 持久化时新增实现即可，调用方零改动。
abstract class ChatRepository {
  /// 当前会话列表（新消息在最前），返回不可变视图。
  List<ChatConversation> get conversations;

  /// 是否存在任意未读会话。
  bool get hasUnread;

  /// 新 incoming 消息到达流。
  Stream<ChatIncomingPayload> get incoming;

  /// 首次数据载入完成的信号（内存实现立即完成，持久化实现待读盘）。
  Future<void> get ready;

  /// 按 id 取会话；不存在返回 null。
  ChatConversation? conversationOf(String id);

  /// 确保指定会话存在（不存在则插到列表最前）；返回是否新建。
  ///
  /// 用于固定 id 的内置会话（如 AI 助手），避免首次进入时无行可点。
  bool ensureConversation({
    required String id,
    required String nickname,
    String preview = '',
  });

  /// 收到一条新消息（可选首条正文）。
  void addIncoming({String? text});

  /// 向已有会话追加一条对方消息（AI 回复等）；不改变未读标记。
  ///
  /// 与 [addIncoming] 的区别：后者新建会话，本方法只往已有会话里追加，
  /// 并同步预览与更新时间。空白文本与未知会话抛 ArgumentError/StateError。
  /// [reasoning]/[reasoningMs] 携带推理模型的思考内容，仅 AI 助手使用。
  ChatMessage appendIncoming(
    String conversationId,
    String text, {
    String? reasoning,
    int? reasoningMs,
  });

  /// 删除指定会话（消息正文一并清除）；返回是否有变化。
  bool remove(String id);

  /// 标记已读；返回是否有变化。
  bool markRead(String id);

  /// 标记未读；返回是否有变化。
  bool markUnread(String id);

  /// 向指定会话外发一条消息。
  ChatMessage send(String conversationId, String rawText);

  /// 读取会话消息页（新 → 旧，不透明 id 游标）。
  ChatMessagePage messagesOf(
    String conversationId, {
    int limit = 20,
    String? cursor,
  });

  /// 释放内部资源（广播流）。
  void dispose();
}

/// 内存实现：初始列表为空（页面展示「暂无消息」空态），重启清空。
///
/// 行为与重构前的 ChatStore 完全一致：id 序列器、分页游标、
/// 空白文本/未知会话的异常口径都不变。
class InMemoryChatRepository implements ChatRepository {
  InMemoryChatRepository({
    DateTime Function()? now,
    List<ChatConversation>? conversations,
    Map<String, List<ChatMessage>>? messages,
  }) : _now = now ?? DateTime.now {
    if (conversations != null) {
      _items.addAll(conversations);
      _restoreSequences(conversations);
    }
    if (messages != null) {
      for (final entry in messages.entries) {
        _messages[entry.key] = List<ChatMessage>.of(entry.value);
        _restoreMessageSequence(entry.value);
      }
    }
  }

  /// 墙钟来源（生产 [DateTime.now]；命令/单测注入固定时钟）。
  /// 注意：聊天时间戳与日记日界无关，不经 DiaryClock。
  final DateTime Function() _now;

  final List<ChatConversation> _items = <ChatConversation>[];

  /// 每会话消息正文，按时间**正序**保存（读取时倒序分页）。
  final Map<String, List<ChatMessage>> _messages = {};

  /// 自增序号，用于给新进来的会话生成稳定 id。
  int _incomingSeq = 0;

  /// incoming 消息广播（P4 装配适配器的事件源）。broadcast 不缓存：
  /// 订阅由 UI/装配层在创建仓储后立即建立，错过订阅的历史消息
  /// 仍可用 chat.list/messagesOf 回看。
  final StreamController<ChatIncomingPayload> _incoming =
      StreamController<ChatIncomingPayload>.broadcast();

  /// 消息全局自增序号（会话消息与外发消息共用同一序列器，
  /// 杜绝两个命名空间撞 id）。
  int _messageSeq = 0;

  @override
  Stream<ChatIncomingPayload> get incoming => _incoming.stream;

  @override
  List<ChatConversation> get conversations =>
      List<ChatConversation>.unmodifiable(_items);

  @override
  bool get hasUnread => _items.any((c) => c.unread);

  @override
  Future<void> get ready => Future<void>.value();

  @override
  ChatConversation? conversationOf(String id) {
    for (final c in _items) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  bool ensureConversation({
    required String id,
    required String nickname,
    String preview = '',
  }) {
    if (conversationOf(id) != null) return false;
    _items.insert(
      0,
      ChatConversation(
        id: id,
        nickname: nickname,
        preview: preview,
        updatedAt: _now(),
      ),
    );
    _messages.putIfAbsent(id, () => <ChatMessage>[]);
    return true;
  }

  @override
  ChatMessage appendIncoming(
    String conversationId,
    String text, {
    String? reasoning,
    int? reasoningMs,
  }) {
    final body = text.trim();
    if (body.isEmpty) {
      throw ArgumentError.value(text, 'text', '消息文本不能为空');
    }
    final index = _items.indexWhere((c) => c.id == conversationId);
    if (index < 0) {
      throw StateError('会话不存在：$conversationId');
    }
    final message = ChatMessage(
      id: 'msg-${++_messageSeq}',
      conversationId: conversationId,
      text: body,
      direction: ChatDirection.incoming,
      createdAt: _now(),
      reasoning: reasoning,
      reasoningMs: reasoningMs,
    );
    _messages.putIfAbsent(conversationId, () => <ChatMessage>[]).add(message);
    _items[index] = _items[index].copyWith(
      preview: body,
      updatedAt: message.createdAt,
    );
    return message;
  }

  /// 从已恢复的会话 id 还原 incoming 序号（`incoming-<n>` 的最大值）。
  void _restoreSequences(List<ChatConversation> conversations) {
    for (final c in conversations) {
      final match = RegExp(r'^incoming-(\d+)$').firstMatch(c.id);
      if (match == null) continue;
      final n = int.tryParse(match.group(1)!) ?? 0;
      if (n > _incomingSeq) _incomingSeq = n;
    }
  }

  /// 从已恢复的消息 id 还原全局消息序号（`msg-<n>` 的最大值）。
  void _restoreMessageSequence(List<ChatMessage> messages) {
    for (final message in messages) {
      final match = RegExp(r'^msg-(\d+)$').firstMatch(message.id);
      if (match == null) continue;
      final n = int.tryParse(match.group(1)!) ?? 0;
      if (n > _messageSeq) _messageSeq = n;
    }
  }

  @override
  void addIncoming({String? text}) {
    final seq = ++_incomingSeq;
    final time = _now();
    final id = 'incoming-$seq';
    final nickname = '新消息 $seq';
    final body = (text == null || text.trim().isEmpty)
        ? '你有一条新消息'
        : text.trim();
    _items.insert(
      0,
      ChatConversation(
        id: id,
        nickname: nickname,
        preview: body,
        updatedAt: time,
        unread: true,
      ),
    );
    _messages[id] = [
      ChatMessage(
        id: 'msg-${++_messageSeq}',
        conversationId: id,
        text: body,
        direction: ChatDirection.incoming,
        createdAt: time,
      ),
    ];
    _incoming.add(
      ChatIncomingPayload(
        id: id,
        nickname: nickname,
        preview: body,
        text: body,
      ),
    );
  }

  @override
  bool remove(String id) {
    final before = _items.length;
    _items.removeWhere((c) => c.id == id);
    _messages.remove(id);
    return _items.length != before;
  }

  @override
  bool markRead(String id) => _setUnread(id, false);

  @override
  bool markUnread(String id) => _setUnread(id, true);

  @override
  ChatMessage send(String conversationId, String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(rawText, 'text', '消息文本不能为空');
    }
    final index = _items.indexWhere((c) => c.id == conversationId);
    if (index < 0) {
      throw StateError('会话不存在：$conversationId');
    }
    final message = ChatMessage(
      id: 'msg-${++_messageSeq}',
      conversationId: conversationId,
      text: text,
      direction: ChatDirection.outgoing,
      createdAt: _now(),
    );
    _messages.putIfAbsent(conversationId, () => <ChatMessage>[]).add(message);
    _items[index] = _items[index].copyWith(
      preview: text,
      updatedAt: message.createdAt,
    );
    return message;
  }

  @override
  ChatMessagePage messagesOf(
    String conversationId, {
    int limit = 20,
    String? cursor,
  }) {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', '必须在 1..100 之间');
    }
    final stored = _messages[conversationId];
    if (stored == null) {
      throw StateError('会话不存在：$conversationId');
    }
    // 倒序视图（最新在前），不拷贝实体。
    final rows = stored.reversed.toList(growable: false);

    var start = 0;
    if (cursor != null) {
      final anchor = rows.indexWhere((m) => m.id == cursor);
      if (anchor < 0) {
        throw ArgumentError.value(cursor, 'cursor', '游标已失效或不属于该会话');
      }
      start = anchor + 1;
    }
    final remaining = rows.length - start;
    if (remaining <= 0) {
      return const ChatMessagePage(items: []);
    }
    final end = start + limit;
    final page = rows.sublist(start, end > rows.length ? rows.length : end);
    final hasMore = end < rows.length;
    return ChatMessagePage(
      items: page,
      nextCursor: hasMore ? page.last.id : null,
    );
  }

  bool _setUnread(String id, bool unread) {
    final index = _items.indexWhere((c) => c.id == id);
    if (index < 0 || _items[index].unread == unread) return false;
    _items[index] = _items[index].copyWith(unread: unread);
    return true;
  }

  @override
  void dispose() {
    _incoming.close();
  }
}
