import 'package:flutter/material.dart';

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
    this.unread = false,
  });

  /// 会话稳定标识（列表 key、定向更新均以此为准，不用下标）。
  final String id;

  /// 会话昵称。
  final String nickname;

  /// 最新一条消息的预览文案。
  final String preview;

  /// 是否有未读消息（驱动行内呼吸绿点与导航锚点通知态）。
  final bool unread;

  ChatConversation copyWith({bool? unread}) => ChatConversation(
    id: id,
    nickname: nickname,
    preview: preview,
    unread: unread ?? this.unread,
  );
}

/// 聊天会话列表的数据服务。
///
/// 页面层只依赖本类读写会话（新增 / 删除 / 已读 / 未读），
/// 不关心导航锚点如何响应——锚点联动由装配层监听本服务完成。
/// 继承 [ChangeNotifier]，通过 [ChatStoreScope] 向子树提供实例，
/// 数据变化时依赖组件自动重建。
///
/// 当前为内存实现：初始列表为空（页面展示「暂无消息」空态），
/// 重启清空；接入消息模块后替换为真实实现即可。
class ChatStore extends ChangeNotifier {
  ChatStore() : _items = <ChatConversation>[];

  final List<ChatConversation> _items;

  /// 自增序号，用于给新进来的会话生成稳定 id。
  int _incomingSeq = 0;

  /// 当前会话列表（新消息在最前），返回不可变视图防外部绕过服务修改。
  List<ChatConversation> get conversations =>
      List<ChatConversation>.unmodifiable(_items);

  /// 是否存在任意未读会话。
  bool get hasUnread => _items.any((c) => c.unread);

  /// 收到一条新消息：在列表最前插入一条未读会话。
  void addIncoming() {
    _items.insert(
      0,
      ChatConversation(
        id: 'incoming-${++_incomingSeq}',
        nickname: '新消息 $_incomingSeq',
        preview: '你有一条新消息',
        unread: true,
      ),
    );
    notifyListeners();
  }

  /// 删除指定会话。
  void remove(String id) {
    final before = _items.length;
    _items.removeWhere((c) => c.id == id);
    if (_items.length != before) notifyListeners();
  }

  /// 标记指定会话已读（清除行内绿点）。
  void markRead(String id) => _setUnread(id, false);

  /// 标记指定会话为未读（左滑操作，恢复行内绿点）。
  void markUnread(String id) => _setUnread(id, true);

  void _setUnread(String id, bool unread) {
    final index = _items.indexWhere((c) => c.id == id);
    if (index < 0 || _items[index].unread == unread) return;
    _items[index] = _items[index].copyWith(unread: unread);
    notifyListeners();
  }
}

/// 向子树提供 [ChatStore]。
///
/// 与 NavBadgeScope 同样基于 [InheritedNotifier]：服务 notify 时
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
