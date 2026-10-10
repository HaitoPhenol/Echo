import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_data_provider.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/export/diary_export_service.dart';
import 'package:echo/src/diary/template/daily_default_template.dart';
import 'package:echo/src/diary/template/diary_composer.dart';
import 'package:echo/src/diary/ui/browser/day_editor_page.dart';
import 'package:echo/src/diary/ui/browser/day_list_page.dart';
import 'package:echo/src/diary/ui/diary_composer_scope.dart';
import 'package:echo/src/diary/ui/diary_page.dart';
import 'package:echo/src/diary/ui/widgets/diary_list_row.dart';

/// 不碰平台通道 / 文件 IO 的假导出服务（widget 测试专用；
/// 真实打包链路由 diary_export_service_test.dart 覆盖）。
class _FakeExportService extends DiaryExportService {
  _FakeExportService({required super.repository, this.handler});

  final Future<DiaryExportOutcome> Function(int year)? handler;
  int calls = 0;

  @override
  Future<DiaryExportOutcome> exportYear(int year) {
    calls++;
    return handler?.call(year) ??
        Future.value(DiaryExportOutcome(year: year, exportedCount: 0));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 固定墙钟 2026-06-15 中午（避开 04:00 日界）。
  final fixedNow = DateTime(2026, 6, 15, 12);
  DiaryClock fixedClock() => DiaryClock(now: () => fixedNow);

  InMemoryDiaryRepository emptyRepo() =>
      InMemoryDiaryRepository(clock: fixedClock(), seedDebugData: false);

  Future<DiaryComposer> composerFor(InMemoryDiaryRepository repo) async {
    final template = await DailyDefaultTemplate.loadAsset();
    return DiaryComposer(
      template: template,
      provider: FakeDiaryDataProvider(),
      idGenerator: repo.idGenerator,
    );
  }

  Widget app({
    DiaryClock? clock,
    required InMemoryDiaryRepository repository,
    DiaryExportService? exportService,
  }) {
    // Scaffold：生产里由 SmartNavScreen body 提供（SnackBar 挂载点），
    // 直挂 DiaryPage 的测试需要手动补一个。
    return MaterialApp(
      home: Scaffold(
        body: DiaryPage(
          clock: clock ?? fixedClock(),
          dataProvider: FakeDiaryDataProvider(),
          repository: repository,
          exportService: exportService,
        ),
      ),
    );
  }

  Future<void> openMonth(WidgetTester tester) async {
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 月'));
    await tester.pumpAndSettle();
    expect(find.byType(DayListPage), findsOneWidget);
  }

  group('M5 年行导出入口', () {
    testWidgets('点分享：进行中转圈，完成 SnackBar 反馈', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final completer = Completer<DiaryExportOutcome>();
      final export = _FakeExportService(
        repository: repo,
        handler: (_) => completer.future,
      );
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.ios_share), findsOneWidget);
      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pump();
      expect(export.calls, 1);
      // 进行中：按钮位转圈。
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(
        const DiaryExportOutcome(year: 2026, exportedCount: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('已分享 1 篇 · 标记为已导出'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('当年无草稿：SnackBar 提示且不分享文案正确', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      // 默认假实现返回 exportedCount=0（bootstrap 自动成稿的今天是
      // 空稿但仍属 draft——这里假服务按 0 模拟「无待导出」口径）。
      final export = _FakeExportService(repository: repo);
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
      expect(find.text('2026 年没有待导出的草稿'), findsOneWidget);
    });
  });

  group('M5 三态日行', () {
    testWidgets('exported/archived 徽标；archived 置灰拦截点按', (tester) async {
      final clock = fixedClock();
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final composer = await composerFor(repo);
      // 13 日随后归档；14 日导出只读；15 日为 bootstrap 自动成稿的今天。
      await composer.ensureDay(DateTime(2026, 6, 13), repo);
      await composer.ensureDay(DateTime(2026, 6, 14), repo);
      await repo.markExported([
        DateTime(2026, 6, 13),
        DateTime(2026, 6, 14),
      ], exportedAt: fixedNow);
      await repo.archiveDay(DateTime(2026, 6, 13));

      await tester.pumpWidget(app(clock: clock, repository: repo));
      await tester.pumpAndSettle();
      await openMonth(tester);

      expect(find.text('已导出'), findsOneWidget);
      expect(find.text('已归档'), findsOneWidget);
      final archivedRow = tester.widget<DiaryListRow>(
        find.widgetWithText(DiaryListRow, '13日'),
      );
      expect(archivedRow.dim, isTrue);

      // 点归档行：SnackBar 拦截，不进编辑器。
      await tester.tap(find.widgetWithText(DiaryListRow, '13日'));
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorPage), findsNothing);
      expect(find.text('已归档：正文已从本机清理，仅保留索引'), findsOneWidget);

      // 点已导出行：进入只读编辑器，有横幅、无 ↻、有归档动作。
      await tester.tap(find.widgetWithText(DiaryListRow, '14日'));
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorPage), findsOneWidget);
      expect(find.text('已导出 · 只读'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.widgetWithText(TextButton, '归档'), findsOneWidget);
    });

    testWidgets('归档确认对话框：取消留在只读页；确认后回列表显已归档', (tester) async {
      final clock = fixedClock();
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final composer = await composerFor(repo);
      await composer.ensureDay(DateTime(2026, 6, 14), repo);
      await repo.markExported([DateTime(2026, 6, 14)], exportedAt: fixedNow);

      await tester.pumpWidget(app(clock: clock, repository: repo));
      await tester.pumpAndSettle();
      await openMonth(tester);
      await tester.tap(find.widgetWithText(DiaryListRow, '14日'));
      await tester.pumpAndSettle();

      // 取消：对话框关闭，编辑器还在。
      await tester.tap(find.widgetWithText(TextButton, '归档'));
      await tester.pumpAndSettle();
      expect(find.text('归档这篇日记？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorPage), findsOneWidget);
      expect(
        await repo.stateOfDay(DateTime(2026, 6, 14)),
        DiaryDocState.exported,
      );

      // 确认：迁移 archived、pop 回日列表，行置灰显「已归档」。
      await tester.tap(find.widgetWithText(TextButton, '归档'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('归档'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorPage), findsNothing);
      expect(find.byType(DayListPage), findsOneWidget);
      expect(
        await repo.stateOfDay(DateTime(2026, 6, 14)),
        DiaryDocState.archived,
      );
      final row = tester.widget<DiaryListRow>(
        find.widgetWithText(DiaryListRow, '14日'),
      );
      expect(row.dim, isTrue);
      expect(find.text('已归档'), findsOneWidget);
    });
  });

  group('M5 心情入口', () {
    testWidgets('chip 开选择器选 🙂 即落盘；清除生效', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      await tester.pumpWidget(app(repository: repo));
      await tester.pumpAndSettle();
      await openMonth(tester);
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorPage), findsOneWidget);

      // 未设置：空心心情入口。
      await tester.tap(find.byIcon(Icons.mood_outlined));
      await tester.pumpAndSettle();
      // bottom sheet：五档 + 清除（无心情时清除按钮禁用但仍在树中）。
      expect(find.text('今天心情'), findsOneWidget);
      expect(find.text('清除心情'), findsOneWidget);

      await tester.tap(find.text('🙂'));
      await tester.pumpAndSettle();
      // chip 立刻显示当前心情，且已立即落盘。
      final doc = await repo.findDay(DateTime(2026, 6, 15));
      expect(doc?.custom['custom-mood'], '🙂');

      // 再开选心情：清除可用，点后 custom 移除并落盘。
      await tester.tap(find.text('🙂'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除心情'));
      await tester.pumpAndSettle();
      final cleared = await repo.findDay(DateTime(2026, 6, 15));
      expect(cleared?.custom.containsKey('custom-mood'), isFalse);
      expect(find.byIcon(Icons.mood_outlined), findsOneWidget);
    });
  });

  group('M5 archived 占位页', () {
    testWidgets('直达 archived 日期：占位说明、无输入框、可返回', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final composer = await composerFor(repo);
      await composer.ensureDay(DateTime(2026, 6, 13), repo);
      await repo.markExported([DateTime(2026, 6, 13)], exportedAt: fixedNow);
      await repo.archiveDay(DateTime(2026, 6, 13));

      await tester.pumpWidget(
        MaterialApp(
          home: DiaryRepositoryScope(
            repository: repo,
            child: DiaryComposerScope(
              clock: fixedClock(),
              dataProvider: FakeDiaryDataProvider(),
              composer: await composerFor(repo),
              child: const DayEditorPage(year: 2026, month: 6, day: 13),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已归档'), findsOneWidget);
      expect(find.text('正文已从本机清理，仅保留日期索引'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('M5 崩溃恢复时机', () {
    testWidgets('进后台（paused）立即落盘，不等 1.5s 防抖', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      await tester.pumpWidget(app(repository: repo));
      await tester.pumpAndSettle();
      await openMonth(tester);
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();

      // 第一个可写空段（与 M4 测试同位置）。
      await tester.enterText(find.byType(TextField).at(3), 'paused 前打的字');
      await tester.pump();
      // 不等待防抖，直接发 paused 生命周期。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      final doc = await repo.findDay(DateTime(2026, 6, 15));
      expect(
        doc!.blocks.map((b) => b.text).join('\n'),
        contains('paused 前打的字'),
      );
    });
  });
}
