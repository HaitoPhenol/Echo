import 'package:flutter/material.dart';

import 'chat_repository.dart';

export 'chat_repository.dart';

/// 聊天会话列表的视图服务。
///
/// 页面只依赖本类读写会话（新增 / 删除 / 已读 / 未读 / 消息），
/// 不关心数据落地方式——实际数据由 [ChatRepository] 承担，
/// 本类只负责「变更后通知依赖组件重建」与向子树提供实例。
///
/// 继承 [ChangeNotifier]，通过 [ChatStoreScope] 向子树提供实例；
/// 默认装配 [InMemoryChatRepository]（重启清空），接入持久化仓储时
/// 从构造参数注入即可，UI 零改动。
class ChatStore extends ChangeNotifier implements ChatRepository {
  ChatStore({DateTime Function()? now, ChatRepository? repository})
    : _owned = repository == null,
      _repository = repository ?? InMemoryChatRepository(now: now);

  final ChatRepository _repository;

  /// 仓储是否由本 Store 创建（注入的外部实例不由本类释放）。
  final bool _owned;

  ChatRepository get _repo => _repository;

  @override
  List<ChatConversation> get conversations => _repo.conversations;

  @override
  bool get hasUnread => _repo.hasUnread;

  @override
  Stream<ChatIncomingPayload> get incoming => _repo.incoming;

  @override
  ChatConversation? conversationOf(String id) => _repo.conversationOf(id);

  @override
  void addIncoming({String? text}) {
    _repo.addIncoming(text: text);
    notifyListeners();
  }

  @override
  bool remove(String id) {
    final changed = _repo.remove(id);
    if (changed) notifyListeners();
    return changed;
  }

  @override
  bool markRead(String id) {
    final changed = _repo.markRead(id);
    if (changed) notifyListeners();
    return changed;
  }

  @override
  bool markUnread(String id) {
    final changed = _repo.markUnread(id);
    if (changed) notifyListeners();
    return changed;
  }

  @override
  ChatMessage send(String conversationId, String rawText) {
    final message = _repo.send(conversationId, rawText);
    notifyListeners();
    return message;
  }

  @override
  ChatMessagePage messagesOf(
    String conversationId, {
    int limit = 20,
    String? cursor,
  }) => _repo.messagesOf(conversationId, limit: limit, cursor: cursor);

  @override
  void dispose() {
    if (_owned) _repo.dispose();
    super.dispose();
  }
}

/// 向子树提供 [ChatStore]。
///
/// 与 NavBadgeScope 同样基于 [InheritedNotifier]：服务 notify 时，
/// 依赖过本 scope 的组件自动重建。
class ChatStoreScope extends InheritedNotifier<ChatStore> {
  const ChatStoreScope({
    super.key,
    required ChatStore store,
    required super.child,
  }) : super(notifier: store);

  /// 取会话服务（聊天子树内必定可用，缺失即说明装配错误）。
  static ChatStore of(BuildContext context) {
    final store = maybeOf(context);
    assert(store != null, '子树中缺少 ChatStoreScope');
    return store!;
  }

  /// 取会话服务；scope 之外返回 null。
  static ChatStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatStoreScope>()?.notifier;
}
