import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/editor/block_editor_controller.dart';
import 'package:echo/src/diary/editor/block_editor_view.dart';
import 'package:echo/src/diary/editor/editor_scope.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/ui/browser/day_editor_page.dart';
import 'package:echo/src/diary/ui/browser/day_list_page.dart';
import 'package:echo/src/diary/ui/browser/month_list_page.dart';
import 'package:echo/src/diary/ui/diary_page.dart';
import 'package:echo/src/diary/ui/widgets/diary_list_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 找当前月里一个保证没有种子草稿的日期（排除今天/昨天）；
  /// 从月底往前找，命中列表顶部可见行，避免额外滚动。
  int emptyDayOf(DateTime now) {
    for (var d = 28; d >= 1; d--) {
      if (d != now.day && d != now.day - 1) return d;
    }
    throw StateError('unreachable');
  }

  group('日记层级浏览（M3）', () {
    testWidgets('年→月→日→编辑器下钻，种子内容可见', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DiaryPage()));
      await tester.pumpAndSettle();

      final now = DateTime.now();

      expect(find.text('日记'), findsOneWidget);

      // 年列表 → 月列表（标题与行同年份，取行）。
      await tester.tap(find.byType(DiaryListRow).first);
      await tester.pumpAndSettle();
      expect(find.byType(MonthListPage), findsOneWidget);
      // 回归：opaque 路由落定后下层年页被移出绘制（Offstage 保活），
      // 不能与月页叠绘（半透明路由 secondary 复位会导致永久叠影）。
      expect(
        find.text('日记'),
        findsNothing,
        reason: '年页应在 opaque 月页落定后 Offstage',
      );

      // 月列表 → 日列表。
      await tester.tap(find.text('${now.month} 月').last);
      await tester.pumpAndSettle();
      expect(find.byType(DayListPage), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);

      // 今天有 debug 种子，编辑器直接显示正文（日列表在下层仍保活，
      // 故在 DayEditorPage 子树内断言，避免命中列表预览）。
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      expect(find.byType(DayEditorPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DayEditorPage),
          matching: find.text('今天的第一条记录。'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('空日新建：输入后系统返回落盘，日列表出现预览', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DiaryPage()));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final emptyDay = emptyDayOf(now);

      await tester.tap(find.byType(DiaryListRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('${now.month} 月').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('$emptyDay日'));
      await tester.pumpAndSettle();

      // 空文档：占位提示可见。
      expect(find.text('写点什么…'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '测试草稿内容');
      await tester.pump();
      expect(find.text('编辑中'), findsOneWidget);

      // 系统返回键：DiaryPage PopScope 收口到内层 Navigator，
      // 编辑器自己的 PopScope 在 pop 时 flush。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(DayEditorPage), findsNothing);
      expect(find.byType(DayListPage), findsOneWidget);
      expect(find.text('测试草稿内容'), findsOneWidget); // 行预览
    });
  });

  group('编辑器块组件（M2）', () {
    testWidgets('200 块懒加载并可滚到底部', (tester) async {
      // 固定 2026-05-15（无种子），装载一篇 200 块的草稿。
      final fixedNow = DateTime(2026, 5, 15, 9);
      final ids = SyIdGenerator(random: Random(1), now: () => fixedNow);
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
        now: () => fixedNow,
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
