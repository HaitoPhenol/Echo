import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/common/domain_event_bus.dart';
import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/ui/diary_reminder_badge_subscriber.dart';
import 'package:echo/src/services/nav_badge_service.dart';

/// R5｜跨域订阅链路：日记领域事件 → 导航锚点（订阅者）互不相识。
void main() {
  final fixedNow = DateTime(2026, 6, 15, 12); // 「本月 1 日」= 2026-06-01
  DiaryClock clock() => DiaryClock(now: () => fixedNow);

  DiaryDocument doc(DateTime date, String text) {
    final day8 = SyIdGenerator.timestamp(date).substring(0, 8);
    return DiaryDocument(
      id: SyIdGenerator.dayContainer(date),
      date: DateTime(date.year, date.month, date.day),
      title: '${date.month}月${date.day}日',
      blocks: [DiaryBlock(id: '${day8}210000-echo001', text: text)],
    );
  }

  test('领域事件驱动红锚点；卸载订阅后发布方无感', () async {
    final repo = InMemoryDiaryRepository(clock: clock(), seedDebugData: false);
    addTearDown(repo.dispose);
    final bus = DomainEventBus();
    final badges = InMemoryNavBadgeService(destinationIds: ['notes']);
    addTearDown(badges.dispose);

    final subscriber = DiaryReminderBadgeSubscriber(
      events: bus,
      repository: repo,
      destinationId: 'notes',
      badges: badges,
    )..attach();
    await pumpEventQueue();
    expect(badges.levelOf('notes'), NavBadgeLevel.normal);

    // 造一篇「已结束月份」的草稿，发布方只广播事实。
    await repo.upsertDraft(doc(DateTime(2026, 5, 20), '上月备忘'));
    bus.publish(const DiaryChangedEvent());
    await pumpEventQueue();
    expect(badges.levelOf('notes'), NavBadgeLevel.exception);

    // 完成有效导出（draft→exported）→ 订阅者自动解除红锚点。
    await repo.markExported([DateTime(2026, 5, 20)], exportedAt: fixedNow);
    bus.publish(const DiaryChangedEvent());
    await pumpEventQueue();
    expect(badges.levelOf('notes'), NavBadgeLevel.normal);

    // 断开订阅者后继续发布：不应再触碰锚点，且不抛异常。
    subscriber.dispose();
    await repo.upsertDraft(doc(DateTime(2026, 4, 10), '四月稿'));
    bus.publish(const DiaryChangedEvent());
    await pumpEventQueue();
    expect(badges.levelOf('notes'), NavBadgeLevel.normal);
  });

  test('总线关闭后发布静默失效', () async {
    final bus = DomainEventBus();
    await bus.dispose();
    expect(bus.isDisposed, isTrue);
    expect(() => bus.publish(const DiaryChangedEvent()), returnsNormally);
    // 幂等关闭：重复 dispose 不抛。
    await bus.dispose();
  });
}
