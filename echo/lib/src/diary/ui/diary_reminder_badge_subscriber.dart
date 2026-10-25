import 'dart:async';

import '../../common/domain_event_bus.dart';
import '../../services/nav_badge_service.dart';
import '../data/diary_repository.dart';

/// R5 跨域订阅者：把日记领域事件翻译成导航锚点的「导出提醒」状态。
///
/// 发布者（[DiaryModule] 的仓储变更监听）只知道「日记变了」，不认识
/// 本类；本类只在装配处接入，可随时断开而不影响发布方。
///
/// 判定口径与页面历史实现完全一致：`oldestDraftBefore(本月 1 日)`
/// 非空 → 红锚点，为空 → 自动解除。异步查询用代次守卫，避免快速连续
/// 事件下旧结果覆盖新结果。
class DiaryReminderBadgeSubscriber {
  DiaryReminderBadgeSubscriber({
    required this.events,
    required this.repository,
    required this.destinationId,
    this.badges,
  });

  final DomainEventBus events;
  final DiaryRepository repository;
  final String destinationId;

  /// 当前锚点服务；页面依赖变化时可替换，缺失时同步为静默跳过。
  NavBadgeService? badges;
  StreamSubscription<DomainEvent>? _subscription;
  int _generation = 0;

  /// 订阅事件总线并立即同步一次。幂等：重复调用不叠加订阅。
  void attach() {
    _subscription ??= events.events.listen((event) {
      if (event is DiaryChangedEvent) unawaited(sync());
    });
    unawaited(sync());
  }

  /// 按当前仓储数据重算锚点。锚点服务缺失时静默跳过（仍算一次代次）。
  Future<void> sync() async {
    final generation = ++_generation;
    final service = badges;
    if (service == null) return;

    final today = repository.today();
    final oldest = await repository.oldestDraftBefore(
      DateTime(today.year, today.month, 1),
    );
    // 期间又有新事件：本次结果已过时，丢弃。
    if (generation != _generation) return;

    if (oldest == null) {
      service.resolveException(destinationId);
    } else {
      service.reportException(destinationId);
    }
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    badges = null;
  }
}
