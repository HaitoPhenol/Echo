import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_data_provider.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/export/diary_export_service.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/sy/sy_serializer.dart';
import 'package:echo/src/diary/template/daily_default_template.dart';
import 'package:echo/src/diary/template/diary_composer.dart';
import 'package:echo/src/diary/ui/browser/day_editor_page.dart';
import 'package:echo/src/diary/ui/browser/day_list_page.dart';
import 'package:echo/src/diary/ui/diary_composer_scope.dart';
import 'package:echo/src/diary/ui/diary_page.dart';
import 'package:echo/src/diary/ui/widgets/diary_list_row.dart';

/// 不碰平台通道 / 文件 IO 的假导出服务（widget 测试专用；
/// 真实打包链路由 diary_export_service_test.dart 覆盖）。
///
/// 默认行为模拟生产服务的确认编排：先回调 confirmShared（由月列表
/// 弹「确认已发送」对话框），否认返回 userDenied，确认则把今天的
/// bootstrap 草稿迁移为 exported。
class _FakeExportService extends DiaryExportService {
  _FakeExportService({required super.repository, this.handler});

  final Future<DiaryExportOutcome> Function(
    int year,
    int month,
    DiaryExportConfirm? confirmShared,
  )?
  handler;
  int calls = 0;

  /// 年粒度导出调用次数与最近年份（年列表入口用）。
  int yearCalls = 0;
  int? lastYear;

  /// 最近一次调用所选渠道（null 表示尚未调用）。
  DiaryExportChannel? lastChannel;

  @override
  Future<DiaryExportOutcome> exportYear(
    int year, {
    DiaryExportChannel channel = DiaryExportChannel.share,
    DiaryExportConfirm? confirmShared,
  }) async {
    yearCalls++;
    lastYear = year;
    lastChannel = channel;
    // 年粒度只验证 UI 编排与文案，不做仓储迁移。
    final confirmed = channel == DiaryExportChannel.share
        ? await confirmShared?.call() ?? false
        : true;
    if (!confirmed) {
      return DiaryExportOutcome(
        year: year,
        exportedCount: 0,
        channel: channel,
        userDenied: true,
      );
    }
    return DiaryExportOutcome(
      year: year,
      exportedCount: 3,
      markedCount: 1,
      todayKeptCount: 1,
      channel: channel,
    );
  }

  @override
  Future<DiaryExportOutcome> exportMonth(
    int year,
    int month, {
    DiaryExportChannel channel = DiaryExportChannel.share,
    DiaryExportConfirm? confirmShared,
  }) async {
    calls++;
    lastChannel = channel;
    final h = handler;
    if (h != null) return h(year, month, confirmShared);
    // 另存有明确结果：直接模拟保存成功，不弹人工确认。
    // 与服务同口径：今日草稿入包但不迁移，昨日才置 exported。
    if (channel == DiaryExportChannel.save) {
      await repository.markExported([
        DateTime(2026, 6, 14),
      ], exportedAt: DateTime(2026, 6, 15, 12));
      return DiaryExportOutcome(
        year: year,
        month: month,
        exportedCount: 2,
        markedCount: 1,
        todayKeptCount: 1,
        channel: channel,
      );
    }
    final confirmed = await confirmShared?.call() ?? false;
    if (!confirmed) {
      return DiaryExportOutcome(
        year: year,
        month: month,
        exportedCount: 0,
        channel: channel,
        userDenied: true,
      );
    }
    await repository.markExported([
      DateTime(2026, 6, 14),
    ], exportedAt: DateTime(2026, 6, 15, 12));
    return DiaryExportOutcome(
      year: year,
      month: month,
      exportedCount: 2,
      markedCount: 1,
      todayKeptCount: 1,
      channel: channel,
    );
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

  /// 造一篇「已结束日期」的非空草稿：进笔记页时空稿会被清理，
  /// 故必须有正文才能活到导出那一刻。
  Future<void> seedPastDraft(
    InMemoryDiaryRepository repo,
    DateTime date, {
    String text = '昨日正文',
  }) async {
    final day8 = SyIdGenerator.timestamp(
      DateTime(date.year, date.month, date.day, 21),
    ).substring(0, 8);
    await repo.upsertDraft(
      DiaryDocument(
        id: SyIdGenerator.dayContainer(date),
        date: DateTime(date.year, date.month, date.day),
        title: SySerializer.dayTitle(date),
        blocks: [DiaryBlock(id: '${day8}210000-daaaaaa', text: text)],
      ),
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
    await tester.tap(find.text('2026 年'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 月'));
    await tester.pumpAndSettle();
    expect(find.byType(DayListPage), findsOneWidget);
  }

  /// 从年列表进入月份列表（导出入口现在月行）。
  Future<void> openMonthList(WidgetTester tester) async {
    await tester.tap(find.text('2026 年'));
    await tester.pumpAndSettle();
    expect(find.text('6 月'), findsOneWidget);
  }

  /// 点月行导出按钮，在渠道弹窗里选「分享」或「另存」。
  Future<void> exportVia(WidgetTester tester, String choice) async {
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();
    // 渠道弹窗顶部固定提示当前导出范围。
    expect(find.text('导出范围：2026 年 6 月'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('另存'), findsOneWidget);
    await tester.tap(find.text(choice));
    await tester.pump();
  }

  group('M5 月行导出入口', () {
    testWidgets('点分享：进行中转圈，完成 SnackBar 反馈', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final completer = Completer<DiaryExportOutcome>();
      final export = _FakeExportService(
        repository: repo,
        handler: (_, _, _) => completer.future,
      );
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle();
      await openMonthList(tester);

      expect(find.byIcon(Icons.ios_share), findsOneWidget);
      await exportVia(tester, '分享');
      expect(export.calls, 1);
      expect(export.lastChannel, DiaryExportChannel.share);
      // 进行中：按钮位转圈。
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(
        const DiaryExportOutcome(year: 2026, month: 6, exportedCount: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('已分享 2026 年 6 月 1 篇 · 标记 1 篇为已导出'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('当月无草稿：SnackBar 提示且不分享文案正确', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      // 假实现返回 exportedCount=0（bootstrap 自动成稿的今天是
      // 空稿但仍属 draft——这里假服务按 0 模拟「无待导出」口径）。
      final export = _FakeExportService(
        repository: repo,
        handler: (_, _, _) async =>
            const DiaryExportOutcome(year: 2026, month: 6, exportedCount: 0),
      );
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle();
      await openMonthList(tester);

      await exportVia(tester, '分享');
      await tester.pumpAndSettle();
      expect(find.text('2026 年 6 月没有可导出的日记'), findsOneWidget);
    });

    testWidgets('分享后确认对话框：否认保留 draft，确认才置 exported', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      // 无自定义 handler：默认假服务模拟真实确认编排（不碰文件 IO）。
      final export = _FakeExportService(repository: repo);
      // 昨日草稿用于验证「只有早于今天的 draft 被标记」。
      await seedPastDraft(repo, DateTime(2026, 6, 14));
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle(); // bootstrap 自动成稿今天（draft）
      await openMonthList(tester);

      // 第一次：点分享 → 确认对话框 → 否认。
      // 不能用 pumpAndSettle：确认未返回时按钮位转圈一直在动。
      await exportVia(tester, '分享');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('确认已发送？'), findsOneWidget);
      await tester.tap(find.text('尚未发送'));
      await tester.pump();
      expect(find.text('未标记为已导出，2026 年 6 月草稿仍保留'), findsOneWidget);
      expect(await repo.stateOfDay(DateTime(2026, 6, 14)), DiaryDocState.draft);
      expect(await repo.stateOfDay(DateTime(2026, 6, 15)), DiaryDocState.draft);
      expect(export.calls, 1);

      // SnackBar 让其自行消失，再次导出 → 对话框 → 确认。
      await tester.pump(const Duration(seconds: 3));
      await exportVia(tester, '分享');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('确认已发送？'), findsOneWidget);
      await tester.tap(find.text('确认已发送'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.text('已分享 2026 年 6 月 2 篇 · 标记 1 篇为已导出 · 今日 1 篇保持草稿'),
        findsOneWidget,
      );
      expect(
        await repo.stateOfDay(DateTime(2026, 6, 14)),
        DiaryDocState.exported,
      );
      expect(await repo.stateOfDay(DateTime(2026, 6, 15)), DiaryDocState.draft);
      expect(export.calls, 2);
    });

    testWidgets('点另存：直接迁移 exported，无人工确认', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final export = _FakeExportService(repository: repo);
      await seedPastDraft(repo, DateTime(2026, 6, 14));
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle(); // bootstrap 自动成稿今天（draft）
      await openMonthList(tester);

      await exportVia(tester, '另存');
      await tester.pumpAndSettle();
      expect(export.calls, 1);
      expect(export.lastChannel, DiaryExportChannel.save);
      // 另存有明确结果：不弹「确认已发送」，直接提示成功。
      expect(find.text('确认已发送？'), findsNothing);
      expect(
        find.text('已另存 2026 年 6 月 2 篇 · 标记 1 篇为已导出 · 今日 1 篇保持草稿'),
        findsOneWidget,
      );
      expect(
        await repo.stateOfDay(DateTime(2026, 6, 14)),
        DiaryDocState.exported,
      );
      // 今日仍在写：导出后保持 draft。
      expect(await repo.stateOfDay(DateTime(2026, 6, 15)), DiaryDocState.draft);
    });

    testWidgets('当月只有今日草稿：入包但不标记，文案说明保持草稿', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final export = _FakeExportService(
        repository: repo,
        handler: (_, _, _) async => const DiaryExportOutcome(
          year: 2026,
          month: 6,
          exportedCount: 1,
          markedCount: 0,
          todayKeptCount: 1,
          channel: DiaryExportChannel.save,
        ),
      );
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle(); // bootstrap 自动成稿今天（draft）
      await openMonthList(tester);

      await exportVia(tester, '另存');
      await tester.pumpAndSettle();
      expect(find.text('已另存 2026 年 6 月 1 篇 · 今日 1 篇保持草稿'), findsOneWidget);
      expect(await repo.stateOfDay(DateTime(2026, 6, 15)), DiaryDocState.draft);
    });

    testWidgets('另存取消：草稿保留且不迁移', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final export = _FakeExportService(
        repository: repo,
        handler: (_, _, _) async => const DiaryExportOutcome(
          year: 2026,
          month: 6,
          exportedCount: 0,
          channel: DiaryExportChannel.save,
          userDenied: true,
        ),
      );
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle();
      await openMonthList(tester);

      await exportVia(tester, '另存');
      await tester.pumpAndSettle();
      expect(find.text('已取消另存，2026 年 6 月日记仍保留'), findsOneWidget);
      expect(
        await repo.stateOfDay(DateTime(2026, 6, 15)),
        DiaryDocState.draft,
      );
    });

    testWidgets('关闭渠道弹窗：不调用导出服务', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final export = _FakeExportService(repository: repo);
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle();
      await openMonthList(tester);

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
      expect(find.text('另存'), findsOneWidget);
      // 点遮罩关闭 sheet（默认 800x600 视口左上角在遮罩内）。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('另存'), findsNothing);
      expect(export.calls, 0);
    });

    testWidgets('月行「已导出」徽标：该月全部笔记无未导出时才显示', (tester) async {
      final clock = fixedClock();
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final composer = await composerFor(repo);
      // 5 月两篇全部导出；6 月由 bootstrap 成稿今天（draft）→ 不显徽标。
      await composer.ensureDay(DateTime(2026, 5, 10), repo);
      await composer.ensureDay(DateTime(2026, 5, 11), repo);
      await repo.markExported(
        [DateTime(2026, 5, 10), DateTime(2026, 5, 11)],
        exportedAt: fixedNow,
      );

      await tester.pumpWidget(app(clock: clock, repository: repo));
      await tester.pumpAndSettle();
      await openMonthList(tester);

      expect(
        find.descendant(
          of: find.widgetWithText(DiaryListRow, '5 月'),
          matching: find.text('已导出'),
        ),
        findsOneWidget,
        reason: '5 月全部已导出，应显徽标',
      );
      expect(
        find.descendant(
          of: find.widgetWithText(DiaryListRow, '6 月'),
          matching: find.text('已导出'),
        ),
        findsNothing,
        reason: '6 月含今天的 draft，不应显徽标',
      );
    });
  });

  group('M5 年行导出入口', () {
    testWidgets('年行导出：范围提示全年，另存成功文案含年范围', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final export = _FakeExportService(repository: repo);
      await tester.pumpWidget(app(repository: repo, exportService: export));
      await tester.pumpAndSettle();

      // 年列表当前只有 2026 年，行尾即年粒度导出入口。
      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
      expect(find.text('导出范围：2026 年'), findsOneWidget);
      expect(
        find.text('范围内全部日记都会完整打包（含已导出）'),
        findsOneWidget,
      );
      await tester.tap(find.text('另存'));
      await tester.pumpAndSettle();

      expect(export.yearCalls, 1);
      expect(export.lastYear, 2026);
      expect(export.lastChannel, DiaryExportChannel.save);
      expect(
        find.text('已另存 2026 年 3 篇 · 标记 1 篇为已导出 · 今日 1 篇保持草稿'),
        findsOneWidget,
      );
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
      // 行首亮度只两档：已归档不再另占第三档灰，与普通往日行同色
      // （暗），只在与「含今天」的亮档之间区分。
      Color? headColorOf(String headText) => tester
          .widget<Text>(
            find.descendant(
              of: find.widgetWithText(DiaryListRow, headText),
              matching: find.text(headText),
            ),
          )
          .style
          ?.color;
      expect(headColorOf('13日'), headColorOf('14日'));
      expect(headColorOf('13日'), isNot(headColorOf('今天')));

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

    testWidgets('draft 空稿行显「（空稿）」；exported 空预览退化星期小字', (
      tester,
    ) async {
      // M5 反范式改造曾把空预览一律退化为星期小字，draft 空稿被误伤
      // （D2 回归）：今天的空草稿按裁定保留且可见，应恢复标注。
      final clock = fixedClock();
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final composer = await composerFor(repo);
      // 13 日导出且未写字（exported 空预览）；15 日由 bootstrap 自动成稿。
      await composer.ensureDay(DateTime(2026, 6, 13), repo);
      await repo.markExported([DateTime(2026, 6, 13)], exportedAt: fixedNow);

      await tester.pumpWidget(app(clock: clock, repository: repo));
      await tester.pumpAndSettle();
      await openMonth(tester);

      // 2026-06-15 为周一：draft 空稿显「周一（空稿）」。
      final todayRow = tester.widget<DiaryListRow>(
        find.widgetWithText(DiaryListRow, '今天'),
      );
      expect(todayRow.sub, '周一（空稿）');
      expect(find.text('周一（空稿）'), findsOneWidget);

      // 2026-06-13 为周六：exported 空预览不显「（空稿）」。
      final exportedRow = tester.widget<DiaryListRow>(
        find.widgetWithText(DiaryListRow, '13日'),
      );
      expect(exportedRow.sub, '周六');
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
    testWidgets('心情胶囊开选择器选 🙂 即落盘；清除生效', (tester) async {
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
      // 胶囊立刻显示当前心情，且已立即落盘。
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

      // 单空段骨架的第一个可写段落。
      await tester.enterText(find.byType(TextField).first, 'paused 前打的字');
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
