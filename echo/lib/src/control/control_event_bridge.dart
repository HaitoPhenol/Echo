import 'dart:async';

import '../navigation/nav_destination_specs.dart';
import '../navigation/nav_physics.dart';
import '../services/chat_store.dart';
import 'events/event_bus.dart';
import 'events/event_types.dart';
import 'protocol/command_spec.dart';

/// P4-G2 装配层事件适配器：把 UI 服务层的变化信号翻译成控制面事件。
///
/// 依赖方向（code review 硬项，接缝测试源码断言钉死）：
/// - **允许**：control → services / navigation（本文件订阅 ChatStore
///   的 [ChatStore.incoming] 广播、挂 [NavPhysicsController] 的
///   ChangeNotifier）；
/// - **禁止**：services / navigation 反向 import control——两个被监听
///   方完全不认识事件总线，只暴露各自层的原生信号。
///
/// 生命周期与 SmartNavScreen 装配的 UI 同源服务一致：在把
/// ChatStore/NavPhysicsController 注册进 control registry 的同一处
/// [attach]，dispose 时随页面服务一起 [dispose]（取消订阅）。
class UiEventBridge {
  UiEventBridge({
    required this.events,
    required this.chatStore,
    required this.nav,
  });

  final ControlEventBus events;
  final ChatStore chatStore;
  final NavPhysicsController nav;

  StreamSubscription<ChatIncomingPayload>? _chatSub;
  bool _navAttached = false;

  /// 上次已转发的激活页（页号 diff 守卫：拖动帧里 notify 很密，
  /// 只有真正换页才发 nav.changed；初始页不发——无"变化"）。
  int? _lastPage;

  /// 订阅两个 UI 信号源并开始转发。幂等：重复调用不叠加监听。
  void attach() {
    _chatSub ??= chatStore.incoming.listen(_onIncoming);
    if (!_navAttached) {
      _navAttached = true;
      _lastPage = nav.activePage;
      nav.addListener(_onNavTick);
    }
  }

  void _onIncoming(ChatIncomingPayload p) {
    events.emit(
      type: ControlEventType.chatIncoming,
      level: ControlLevel.owner,
      data: {
        'id': p.id,
        'nickname': p.nickname,
        'preview': p.preview,
        // 首条正文随 chat.get 同为 owner(1) 可读，允许进事件载荷；
        // 未来加入更敏感字段时必须在此脱敏或抬高级别。
        'text': p.text,
      },
    );
  }

  void _onNavTick() {
    final page = nav.activePage;
    if (page == _lastPage) return;
    _lastPage = page;
    events.emit(
      type: ControlEventType.navChanged,
      level: ControlLevel.guest,
      data: {'index': page, 'page': navPageName(page)},
    );
  }

  /// 取消全部订阅（导航监听允许与 UI 控制器同寿，随其 dispose）。
  /// 取消后允许再次 [attach]。
  void dispose() {
    unawaited(_chatSub?.cancel());
    _chatSub = null;
    if (_navAttached) {
      _navAttached = false;
      nav.removeListener(_onNavTick);
    }
  }
}
