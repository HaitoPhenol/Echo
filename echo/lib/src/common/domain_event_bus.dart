import 'dart:async';

/// 领域事件总线（中立层）：只描述「某个领域发生了什么」的事实。
///
/// 约束（R5）：
/// - 本文件不 import control / diary / navigation / pages，任何层都可依赖；
/// - **发布者不认识订阅者**：发布方只 `publish`，由装配处决定谁订阅；
/// - 事件载荷只放事实，不放 UI 回调，避免把表现层语义带进领域层。
sealed class DomainEvent {
  const DomainEvent();
}

/// 日记数据发生变化：成稿、保存、导出状态迁移、删除或清理。
///
/// 不携带具体日期/内容——订阅者若需明细，应回查仓储，事件只负责
/// 「有变化」这一事实，防止订阅者偷懒依赖易失的快照。
class DiaryChangedEvent extends DomainEvent {
  const DiaryChangedEvent();
}

/// 进程内广播型事件总线（同步入队、异步派发）。
///
/// 没有订阅者时 `publish` 是空操作；[dispose] 后发布/订阅均静默失效，
/// 便于模块随页面拆卸时不产生「已关闭控制器」异常。
class DomainEventBus {
  final StreamController<DomainEvent> _controller =
      StreamController<DomainEvent>.broadcast();
  bool _disposed = false;

  Stream<DomainEvent> get events => _controller.stream;

  bool get isDisposed => _disposed;

  void publish(DomainEvent event) {
    if (_disposed) return;
    _controller.add(event);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.close();
  }
}
