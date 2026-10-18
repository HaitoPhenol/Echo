import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_data_provider.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/ui/browser/month_list_page.dart';
import 'package:echo/src/diary/ui/diary_page.dart';
import 'package:echo/src/services/nav_badge_service.dart';

/// 「按月导出 + 导出提醒」的集成覆盖（2026-10-18 用户裁定）。
///
/// 提醒由**数据**驱动：`oldestDraftBefore(本月 1 日)` 非空即红色
/// 锚点（exception 级，不受查看清除）+ 冷启动首次进笔记页弹一次
/// 对话框；真正完成有效导出（draft→exported）后自动解除。
///
/// 本文件不碰文件 IO / 分享通道：导出动作直接用仓储 `markExported`
/// 模拟「用户已确认发送」，真实打包链路由 diary_export_service_test
/// 覆盖，月行导出 UI 由 diary_m5_test 覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 固定墙钟 2026-06-15 中午（避开 04:00 日界）：
  // 「本月 1 日」= 2026-06-01，故 5 月及更早的 draft 属待导出。
  final fixedNow = DateTime(2026, 6, 15, 12);
  DiaryClock fixedClock() => DiaryClock(now: () => fixedNow);

  /// 造一篇带正文的 draft（非空，避免被跨天空稿清理掉）。
  DiaryDocument doc(DateTime date, String text) {
    final day8 = SyIdGenerator.timestamp(date).substring(0, 8);
    return DiaryDocument(
      id: SyIdGenerator.dayContainer(date),
      date: DateTime(date.year, date.month, date.day),
      title: '${date.month}月${date.day}日',
      blocks: [DiaryBlock(id: '${day8}210000-echo001', text: text)],
    );
  }

  InMemoryDiaryRepository emptyRepo() =>
      InMemoryDiaryRepository(clock: fixedClock(), seedDebugData: false);

  /// 只挂日记页的测试壳：提供锚点 scope（提醒据此上报红锚点）。
  Widget app({
    required InMemoryDiaryRepository repository,
    required NavBadgeService badges,
    GlobalKey<DiaryPageState>? pageKey,
  }) {
    return MaterialApp(
      home: NavBadgeScope(
        service: badges,
        child: Scaffold(
          body: DiaryPage(
            key: pageKey,
            clock: fixedClock(),
            dataProvider: FakeDiaryDataProvider(),
            repository: repository,
          ),
        ),
      ),
    );
  }

  group('导出提醒 · 锚点', () {
    testWidgets('存在已结束月份 draft：notes 上报 exception；补齐导出后自动解除', (
      tester,
    ) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      // 上月一篇（已结束月份）→ 待导出。
      await repo.upsertDraft(doc(DateTime(2026, 5, 20), '上月的备忘'));

      final badges = InMemoryNavBadgeService(destinationIds: ['notes']);
      addTearDown(badges.dispose);
      await tester.pumpWidget(app(repository: repo, badges: badges));
      await tester.pumpAndSettle();

      expect(
        badges.levelOf('notes'),
        NavBadgeLevel.exception,
        reason: '有已结束月份的未导出草稿 → 红锚点',
      );

      // 「有效导出」= draft→exported；仓储通知触发锚点重算并解除。
      await repo.markExported([DateTime(2026, 5, 20)], exportedAt: fixedNow);
      await tester.pumpAndSettle();
      expect(
        badges.levelOf('notes'),
        NavBadgeLevel.normal,
        reason: '待导出清零 → 红锚点自动解除',
      );
    });

    testWidgets('只导出部分月份：仍有更早月份未导出 → 红锚点保持', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      await repo.upsertDraft(doc(DateTime(2026, 4, 10), '四月稿'));
      await repo.upsertDraft(doc(DateTime(2026, 5, 20), '五月稿'));

      final badges = InMemoryNavBadgeService(destinationIds: ['notes']);
      addTearDown(badges.dispose);
      await tester.pumpWidget(app(repository: repo, badges: badges));
      await tester.pumpAndSettle();
      expect(badges.levelOf('notes'), NavBadgeLevel.exception);

      // 只补齐 5 月，4 月仍欠 → 锚点不得解除。
      await repo.markExported([DateTime(2026, 5, 20)], exportedAt: fixedNow);
      await tester.pumpAndSettle();
      expect(
        badges.levelOf('notes'),
        NavBadgeLevel.exception,
        reason: '漏月须一直提醒到补齐',
      );
    });

    testWidgets('无待导出（仅有本月稿）：锚点保持常态，且不弹提醒', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final badges = InMemoryNavBadgeService(destinationIds: ['notes']);
      addTearDown(badges.dispose);
      final pageKey = GlobalKey<DiaryPageState>();

      await tester.pumpWidget(
        app(repository: repo, badges: badges, pageKey: pageKey),
      );
      await tester.pumpAndSettle(); // bootstrap 自动成稿今天（本月）

      expect(badges.levelOf('notes'), NavBadgeLevel.normal);
      pageKey.currentState!.maybeShowExportReminder();
      await tester.pumpAndSettle();
      expect(find.text('日记还没导出'), findsNothing);
    });
  });

  group('导出提醒 · 对话框', () {
    testWidgets('冷启动首次进笔记页：弹一次；「稍后」不跳转，同进程不再弹', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      await repo.upsertDraft(doc(DateTime(2026, 5, 20), '上月的备忘'));

      final badges = InMemoryNavBadgeService(destinationIds: ['notes']);
      addTearDown(badges.dispose);
      final pageKey = GlobalKey<DiaryPageState>();
      await tester.pumpWidget(
        app(repository: repo, badges: badges, pageKey: pageKey),
      );
      await tester.pumpAndSettle();

      // 导航屏在首次切到笔记页时调用本方法。
      pageKey.currentState!.maybeShowExportReminder();
      await tester.pumpAndSettle();
      expect(find.text('日记还没导出'), findsOneWidget);
      expect(find.textContaining('2026 年 5 月'), findsOneWidget);

      // 「稍后」：不跳转，红锚点仍在。
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthListPage), findsNothing);
      expect(badges.levelOf('notes'), NavBadgeLevel.exception);

      // 同一次进程内再次请求：不再弹（每次冷启动仅一次）。
      pageKey.currentState!.maybeShowExportReminder();
      await tester.pumpAndSettle();
      expect(find.text('日记还没导出'), findsNothing);
    });

    testWidgets('「去导出」跳转到最早待导出月份所在的月列表', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      // 4 月与 5 月都欠 → 应跳到**最早**的 2026 年（4 月所在年份）。
      await repo.upsertDraft(doc(DateTime(2026, 4, 10), '四月稿'));
      await repo.upsertDraft(doc(DateTime(2026, 5, 20), '五月稿'));

      final badges = InMemoryNavBadgeService(destinationIds: ['notes']);
      addTearDown(badges.dispose);
      final pageKey = GlobalKey<DiaryPageState>();
      await tester.pumpWidget(
        app(repository: repo, badges: badges, pageKey: pageKey),
      );
      await tester.pumpAndSettle();

      pageKey.currentState!.maybeShowExportReminder();
      await tester.pumpAndSettle();
      expect(find.textContaining('2026 年 4 月'), findsOneWidget);

      await tester.tap(find.text('去导出'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthListPage), findsOneWidget);
      // 内层栈被重置为 [年列表, 4 月所在年份的月列表]。
      expect(find.text('2026 年'), findsOneWidget);
      expect(find.text('4 月'), findsOneWidget);
    });
  });
}
