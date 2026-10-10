import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/editor/block_editor_controller.dart';
import 'package:echo/src/diary/editor/block_editor_view.dart';
import 'package:echo/src/diary/editor/editor_history_buttons.dart';
import 'package:echo/src/diary/editor/editor_scope.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 单块文档的标准挂载骨架。
  BlockEditorController mount(DateTime now) {
    final ids = SyIdGenerator(random: Random(7), now: () => now);
    final date = DateTime(now.year, now.month, now.day);
    final document = DiaryDocument(
      id: SyIdGenerator.dayContainer(date),
      date: date,
      title: '测试日',
      blocks: [DiaryBlock(id: ids.next(), text: '你好')],
    );
    return BlockEditorController(idGenerator: ids, now: () => now)
      ..attach(document);
  }

  Widget harness(BlockEditorController editor, {Widget? header}) {
    return MaterialApp(
      home: BlockEditorScope(
        controller: editor,
        child: Scaffold(
          body: Column(
            children: [
              ?header,
              const Expanded(child: BlockEditorView()),
            ],
          ),
        ),
      ),
    );
  }

  group('块标排版浮层（M3）', () {
    testWidgets('点块标浮出工具条：转标题/上色/清除，状态即时生效',
        (tester) async {
      final editor = mount(DateTime(2026, 5, 15, 9));
      addTearDown(editor.dispose);
      await tester.pumpWidget(harness(editor));
      await tester.pump();

      // 初始无浮层。
      expect(find.byKey(const ValueKey('diary-turn-h2')), findsNothing);

      await tester.tap(find.byIcon(Icons.drag_indicator));
      // 选中态经 postFrame 触发 OverlayPortal.show，浮层再下一帧上树。
      await tester.pump();
      await tester.pump();
      expect(find.text('正文'), findsOneWidget);
      expect(find.text('H1'), findsOneWidget);
      expect(find.text('H2'), findsOneWidget);
      expect(find.text('H3'), findsOneWidget);
      for (var n = 1; n <= 13; n++) {
        expect(find.byKey(ValueKey('diary-bg-$n')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('diary-bg-clear')), findsOneWidget);

      // 转 H2。
      await tester.tap(find.byKey(const ValueKey('diary-turn-h2')));
      await tester.pump();
      final block = editor.blocks.single.block;
      expect(block.kind, DiaryBlockKind.heading);
      expect(block.level, 2);

      // 上 7 号底色。
      await tester.tap(find.byKey(const ValueKey('diary-bg-7')));
      await tester.pump();
      expect(editor.blocks.single.block.background, 7);

      // 浮层保持打开：无色清除。
      await tester.tap(find.byKey(const ValueKey('diary-bg-clear')));
      await tester.pump();
      expect(editor.blocks.single.block.background, isNull);
    });

    testWidgets('点浮层外部屏障取消选中并关闭浮层', (tester) async {
      final editor = mount(DateTime(2026, 5, 15, 9));
      addTearDown(editor.dispose);
      await tester.pumpWidget(harness(editor));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.drag_indicator));
      await tester.pump();
      await tester.pump();
      expect(find.text('H1'), findsOneWidget);
      expect(editor.selectedBlockId, editor.blocks.single.block.id);

      // 点屏内空白处（命中全屏屏障而非工具条；测试表面高 600）。
      await tester.tapAt(const Offset(10, 400));
      await tester.pump();
      expect(editor.selectedBlockId, isNull);
      await tester.pump();
      await tester.pump();
      expect(find.text('H1'), findsNothing);
    });
  });

  group('标题栏撤销/重做（M3）', () {
    testWidgets('结构操作后撤销重做按钮驱动历史栈', (tester) async {
      final editor = mount(DateTime(2026, 5, 15, 9));
      addTearDown(editor.dispose);
      await tester.pumpWidget(
        harness(editor, header: EditorHistoryButtons(controller: editor)),
      );
      await tester.pump();

      IconButton undo() =>
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo));
      IconButton redo() =>
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.redo));

      expect(editor.canUndo, isFalse);
      expect(undo().onPressed, isNull);
      expect(redo().onPressed, isNull);

      // 直接走控制器命令（等价于浮层 H1）。
      editor.turnInto(editor.blocks.single, DiaryBlockKind.heading, level: 1);
      await tester.pump();
      expect(editor.blocks.single.block.kind, DiaryBlockKind.heading);
      expect(undo().onPressed, isNotNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
      await tester.pump();
      expect(editor.blocks.single.block.kind, DiaryBlockKind.paragraph);
      expect(redo().onPressed, isNotNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.redo));
      await tester.pump();
      expect(editor.blocks.single.block.kind, DiaryBlockKind.heading);
    });
  });
}
