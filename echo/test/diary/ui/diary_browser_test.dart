import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/data/diary_clock.dart';
import 'package:echo/src/diary/data/diary_data_provider.dart';
import 'package:echo/src/diary/data/diary_repository.dart';
import 'package:echo/src/diary/data/in_memory_diary_repository.dart';
import 'package:echo/src/diary/editor/block_editor_controller.dart';
import 'package:echo/src/diary/editor/block_editor_view.dart';
import 'package:echo/src/diary/editor/editor_scope.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/template/daily_default_template.dart';
import 'package:echo/src/diary/template/diary_composer.dart';
import 'package:echo/src/diary/ui/browser/day_editor_page.dart';
import 'package:echo/src/diary/ui/browser/day_list_page.dart';
import 'package:echo/src/diary/ui/browser/year_list_page.dart';
import 'package:echo/src/diary/ui/diary_page.dart';
import 'package:echo/src/diary/ui/widgets/diary_list_row.dart';

/// 天气可切换的假 provider（第二次起返回晴），验证 ↻ 刷新。
class _SwitchWeatherProvider implements DiaryDataProvider {
  int calls = 0;

  @override
  bool get isSampleData => true;

  @override
  Future<HomeEnvironment?> fetchHomeEnvironment(DateTime d) async =>
      const (tempC: 21.0, humidityPct: 45);

  @override
  Future<int?> fetchScheduleCount(DateTime d) async => 3;

  @override
  Future<String?> fetchWeather(DateTime d) async =>
      calls++ == 0 ? '多云' : '晴';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 固定墙钟 2026-06-15 中午（避开 04:00 日界），日记日 = 当天。
  final fixedNow = DateTime(2026, 6, 15, 12);
  DiaryClock fixedClock() => DiaryClock(now: () => fixedNow);

  InMemoryDiaryRepository emptyRepo() => InMemoryDiaryRepository(
        clock: fixedClock(),
        seedDebugData: false,
      );

  Widget app({
    DiaryClock? clock,
    DiaryDataProvider? provider,
    InMemoryDiaryRepository? repository,
  }) {
    return MaterialApp(
      home: DiaryPage(
        clock: clock ?? fixedClock(),
        dataProvider: provider ?? FakeDiaryDataProvider(),
        repository: repository ?? emptyRepo(),
      ),
    );
  }

  Future<void> drillToToday(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // 年 → 月 → 日。
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 月'));
    await tester.pumpAndSettle();
    expect(find.byType(DayListPage), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(find.byType(DayEditorPage), findsOneWidget);
  }

  group('M4 自动成稿', () {
    testWidgets('进模块即成稿：列表自然出现今天，编辑器为六块模板快照',
        (tester) async {
      await drillToToday(tester);

      // 三个骨架标题 + data 快照行 + 示例标注 + 3 号底色 data 块。
      expect(find.text('📈 自动记录'), findsOneWidget);
      expect(find.text('💭 今天'), findsOneWidget);
      expect(find.text('🌙 睡前'), findsOneWidget);
      expect(
        find.text('🌡️ 21°C　💧 45%　📅 3 条日程　☁️ 多云　（示例数据）'),
        findsOneWidget,
      );
      // 只读 data 块尾部有 ↻ 入口。
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      // 六块结构：1 个只读 data TextField + 5 个可写（标题/空段）。
      expect(find.byType(TextField), findsNWidgets(6));
    });

    testWidgets('写作后重进：用户文字保留，模板与快照不被二次成稿覆盖',
        (tester) async {
      await drillToToday(tester);

      await tester.enterText(find.byType(TextField).at(3), '今天写的内容');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorPage), findsNothing);

      // 日列表仍只有今天一篇（自动成稿不重复落盘）。
      expect(find.byType(DiaryListRow), findsOneWidget);

      // 再进：文字在、快照也在（ensureDay 命中既有草稿不覆盖）。
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      expect(find.text('今天写的内容'), findsOneWidget);
      expect(
        find.text('🌡️ 21°C　💧 45%　📅 3 条日程　☁️ 多云　（示例数据）'),
        findsOneWidget,
      );
    });
  });

  group('M4 ↻ 刷新', () {
    testWidgets('点 ↻ 重新取数：文本更新且落盘到 custom 与 data 块',
        (tester) async {
      await tester.pumpWidget(
        app(provider: _SwitchWeatherProvider()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 月'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      expect(find.textContaining('☁️ 多云'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.textContaining('☁️ 晴'), findsOneWidget);

      // pop 立即落盘；重进同一篇验证刷新结果已持久化。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      expect(find.textContaining('☁️ 晴'), findsOneWidget);
    });
  });

  group('M4 列表反转', () {
    testWidgets('日列表只显真实日记：无空日弱化行、无置顶特例',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 月'));
      await tester.pumpAndSettle();

      // 自动成稿后仅 15 日一行，标注「今天」但不是独立置顶行。
      final rows = find.byType(DiaryListRow);
      expect(rows, findsOneWidget);
      final row = tester.widget<DiaryListRow>(rows);
      expect(row.head, '今天');
      expect(find.text('1日'), findsNothing);
      expect(find.text('30日'), findsNothing);
    });

    testWidgets('月列表只有含日记的月份，标篇数，无「本月」弱化文案',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();

      final rows = find.byType(DiaryListRow);
      expect(rows, findsOneWidget);
      final row = tester.widget<DiaryListRow>(rows);
      expect(row.head, '6 月');
      expect(row.dim, isFalse);
      expect(row.highlight, isFalse);
      expect(find.text('本月'), findsNothing);
      expect(find.byTooltip('补记'), findsOneWidget);
    });

    testWidgets('空仓：年/月/日都有空态，不兜底当前年月', (tester) async {
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DiaryRepositoryScope(
            repository: repo,
            child: const Scaffold(body: YearListPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有日记'), findsOneWidget);
      expect(find.byType(DiaryListRow), findsNothing);
    });
  });

  group('M4 补记', () {
    testWidgets('未来日期禁选（点 16 无效，OK 仍为初始 15）；选 10 成稿',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('补记'));
      await tester.pumpAndSettle();
      expect(find.text('补记哪一天'), findsOneWidget);

      // 16 日是未来日：点击不改变选中，确认后打开的仍是 15 日。
      await tester.tap(find.text('16'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorPage), findsOneWidget);
      expect(find.text('DIARY // 2026.6.15'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // 再补记 10 日（过去）：选择器 → 成稿 → 直开编辑器。
      await tester.tap(find.byTooltip('补记'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorPage), findsOneWidget);
      expect(find.text('DIARY // 2026.6.10'), findsOneWidget);
      // 补记同样是模板成稿（进入即成稿）。
      expect(
        find.text('🌡️ 21°C　💧 45%　📅 3 条日程　☁️ 多云　（示例数据）'),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // 补记从月页直开编辑器，pop 回到月页：当月篇数变 2。
      expect(find.byType(DayListPage), findsNothing);
      final monthRow = tester.widget<DiaryListRow>(
        find.widgetWithText(DiaryListRow, '6 月'),
      );
      expect(monthRow.sub, '2 篇');
    });
  });

  group('M4 跨天空草稿清理', () {
    testWidgets('重开模块：更早的空稿被清，写过字的保留', (tester) async {
      final clock = fixedClock();
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final template = await DailyDefaultTemplate.loadAsset();
      final composer = DiaryComposer(
        template: template,
        provider: FakeDiaryDataProvider(),
        idGenerator: repo.idGenerator,
      );
      // 6/10 空稿；6/9 写了字。
      await composer.ensureDay(DateTime(2026, 6, 10), repo);
      final written = await composer.ensureDay(DateTime(2026, 6, 9), repo);
      written.blocks[3].text = '这天写了，不能清';
      await repo.upsertDraft(written);

      // 进模块（时钟已是 6/15）：自动成稿今天 + 清理早于今天的空稿。
      await tester.pumpWidget(
        app(clock: clock, repository: repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 月'));
      await tester.pumpAndSettle();

      expect(find.text('今天'), findsOneWidget); // 6/15 自动成稿保留
      expect(find.text('9日'), findsOneWidget); // 写过字保留
      expect(find.text('10日'), findsNothing); // 空稿已清
      final monthRows = find.byType(DiaryListRow);
      expect(monthRows, findsNWidgets(2));
    });
  });

  group('M4 锁定文档', () {
    testWidgets('locked 文档不显示 ↻，顶部只读横幅', (tester) async {
      final clock = fixedClock();
      final repo = emptyRepo();
      addTearDown(repo.dispose);
      final template = await DailyDefaultTemplate.loadAsset();
      final composer = DiaryComposer(
        template: template,
        provider: FakeDiaryDataProvider(),
        idGenerator: repo.idGenerator,
      );
      final doc = await composer.ensureDay(DateTime(2026, 6, 15), repo);
      doc.locked = true;
      await repo.upsertDraft(doc);

      await tester.pumpWidget(
        app(clock: clock, repository: repo),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 月'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.text('已导出 · 只读'), findsOneWidget);
    });
  });

  group('编辑器块组件（M2 回归）', () {
    testWidgets('200 块懒加载并可滚到底部', (tester) async {
      // 固定 2026-05-15（无种子），装载一篇 200 块的草稿。
      final fixed = DateTime(2026, 5, 15, 9);
      final ids = SyIdGenerator(random: Random(1), now: () => fixed);
      final date = DateTime(2026, 5, 15);
      final document = DiaryDocument(
        id: SyIdGenerator.dayContainer(date),
        date: date,
        title: '5月15日 周五',
        blocks: [
          for (var i = 0; i < 200; i++)
            DiaryBlock(
              id: ids.next(),
              text: 'BLOCK${i.toString().padLeft(3, '0')}',
            ),
        ],
      );
      final editor = BlockEditorController(
        idGenerator: ids,
        now: () => fixed,
      )..attach(document);
      addTearDown(editor.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: BlockEditorScope(
            controller: editor,
            child: const Scaffold(body: BlockEditorView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 只有进入视口的块被构建。
      expect(find.byType(BlockEditorView), findsOneWidget);

      final lastText = find.text('BLOCK199');
      expect(lastText, findsNothing); // 尚未构建
      await tester.scrollUntilVisible(
        lastText,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(lastText, findsOneWidget);
    });

    testWidgets('块首硬件退格：与上一块合并', (tester) async {
      final ids = SyIdGenerator(random: Random(2), now: () => DateTime(2026));
      final editor = BlockEditorController(idGenerator: ids);
      addTearDown(editor.dispose);
      editor.attach(
        DiaryDocument(
          id: SyIdGenerator.dayContainer(DateTime(2026, 5, 15)),
          date: DateTime(2026, 5, 15),
          title: '5月15日 周五',
        ),
      ); // 空文档自动补一个空段落块。

      await tester.pumpWidget(
        MaterialApp(
          home: BlockEditorScope(
            controller: editor,
            child: const Scaffold(body: BlockEditorView()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // 模拟软键盘回车拆块。
      await tester.enterText(find.byType(TextField), 'abc\n');
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));

      // 焦点已在第二块（空块）offset 0；硬件退格应删块并跳焦，
      // 文本不发生变化，走 Action.overridable 拦截通道。
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('abc'), findsOneWidget);
    });
  });
}
