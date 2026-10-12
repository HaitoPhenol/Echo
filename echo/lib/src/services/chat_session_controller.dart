import 'package:flutter/material.dart';

import 'chat_store.dart';

/// 当前打开的聊天会话控制器（设计 §9.4 同路原则的 UI 收口）。
///
/// UI 点按会话行与 adb `chat.open` 命令都只调 [open]：
/// 校验会话存在 → 经 [ChatStore.markRead] 同一路径清未读 →
/// 记录当前会话 id。当前 App 尚无会话详情页，[openSessionId]
/// 是为详情页/命令回读预留的状态；已读行重复进入幂等。
///
/// 继承 [ChangeNotifier]，通过 [ChatSessionScope] 向子树提供实例。
class ChatSessionController extends ChangeNotifier {
  ChatSessionController(this._store);

  final ChatStore _store;

  String? _openSessionId;

  /// 当前打开的会话 id；无会话打开时为 null。
  String? get openSessionId => _openSessionId;

  /// 是否处于某个会话内。
  bool get isOpen => _openSessionId != null;

  /// 进入指定会话（与点按行、`chat.open` 命令同一路径）。
  ///
  /// 未知会话抛 [StateError]（命令层先经 [ChatStore.conversationOf]
  /// 判空返回 NOT_FOUND；UI 只会传入列表中存在的 id）。
  void open(String id) {
    if (_store.conversationOf(id) == null) {
      throw StateError('会话不存在：$id');
    }
    // 与旧版点按行为同一个 store 方法：未读→清绿点，已读→幂等无变化。
    _store.markRead(id);
    if (_openSessionId == id) return;
    _openSessionId = id;
    notifyListeners();
  }

  /// 退出当前会话（详情页返回 / 命令需要时使用）；幂等。
  void close() {
    if (_openSessionId == null) return;
    _openSessionId = null;
    notifyListeners();
  }
}

/// 向子树提供 [ChatSessionController]（与 [ChatStoreScope] 同范式）。
class ChatSessionScope extends InheritedNotifier<ChatSessionController> {
  const ChatSessionScope({
    super.key,
    required ChatSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 取控制器（聊天子树内必定可用，缺失即说明装配错误）。
  static ChatSessionController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, '子树中缺少 ChatSessionScope');
    return controller!;
  }

  /// 取控制器；独立挂载的组件测试（只包 ChatStoreScope）返回 null，
  /// 调用方回退到 [ChatStore.markRead] 旧路径，外部行为等价。
  static ChatSessionController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatSessionScope>()?.notifier;
}
