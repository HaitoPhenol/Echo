import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/editor/block_editor_controller.dart';
import 'package:echo/src/diary/editor/block_editor_view.dart';
import 'package:echo/src/diary/editor/block_widget.dart';
import 'package:echo/src/diary/editor/diary_capsule_chip.dart';
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
    testWidgets('点块标浮出工具条：转标题/上色/清除，状态即时生效', (tester) async {
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

    Finder findPopoverCard() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == const Color(0xFF151920),
    );

    testWidgets('浮层宽度不超出屏幕（色块在屏宽约束内折行）', (tester) async {
      final editor = mount(DateTime(2026, 5, 15, 9));
      addTearDown(editor.dispose);
      await tester.pumpWidget(harness(editor));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.drag_indicator));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      final card = tester.getRect(findPopoverCard());
      final blockRect = tester.getRect(find.byType(BlockWidget));
      // 浮层与块内容区对齐（块外还有 10dp margin），右缘不超出块本身。
      expect(card.left, greaterThanOrEqualTo(blockRect.left));
      expect(card.right, lessThanOrEqualTo(blockRect.right + 1));
    });

    testWidgets('靠近屏幕底部的块：浮层自动翻到块标上方且不出屏', (tester) async {
      final now = DateTime(2026, 5, 15, 9);
      final ids = SyIdGenerator(random: Random(7), now: () => now);
      final date = DateTime(now.year, now.month, now.day);
      final document = DiaryDocument(
        id: SyIdGenerator.dayContainer(date),
        date: date,
        title: '测试日',
        blocks: [
          for (var i = 1; i <= 12; i++) DiaryBlock(id: ids.next(), text: '块$i'),
        ],
      );
      final editor = BlockEditorController(idGenerator: ids, now: () => now)
        ..attach(document);
      addTearDown(editor.dispose);
      await tester.pumpWidget(harness(editor));
      await tester.pump();

      // 滚到最后一块（测试表面高 600）。
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      final lastBlock = find.text('块12');
      expect(lastBlock, findsOneWidget);
      final lastHandle = find.descendant(
        of: find.ancestor(of: lastBlock, matching: find.byType(BlockWidget)),
        matching: find.byIcon(Icons.drag_indicator),
      );
      final handleRect = tester.getRect(lastHandle);

      await tester.tap(lastHandle);
      // show 上树 → 实测宽高 setState（可能再翻一次朝向），泵到收敛。
      await tester.pump();
      await tester.pumpAndSettle();

      final card = tester.getRect(findPopoverCard());
      expect(find.text('H1'), findsOneWidget);
      // 翻到上方：卡片底边不越过块标顶边（含 6dp 间隙，容 1px 误差）。
      expect(card.bottom, lessThanOrEqualTo(handleRect.top - 5));
      expect(card.top, greaterThanOrEqualTo(0));
      expect(card.bottom, lessThanOrEqualTo(600));
      expect(card.right, lessThanOrEqualTo(800));
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

      // 撤销/重做入口是裸图标 + GestureDetector（非 IconButton），
      // 启用态以 onTap 可空性表达。
      GestureDetector undo() => tester.widget<GestureDetector>(
        find.ancestor(of: find.byIcon(Icons.undo), matching: find.byType(GestureDetector)).first,
      );
      GestureDetector redo() => tester.widget<GestureDetector>(
        find.ancestor(of: find.byIcon(Icons.redo), matching: find.byType(GestureDetector)).first,
      );

      expect(editor.canUndo, isFalse);
      expect(undo().onTap, isNull);
      expect(redo().onTap, isNull);

      // 直接走控制器命令（等价于浮层 H1）。
      editor.turnInto(editor.blocks.single, DiaryBlockKind.heading, level: 1);
      await tester.pump();
      expect(editor.blocks.single.block.kind, DiaryBlockKind.heading);
      expect(undo().onTap, isNotNull);

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(editor.blocks.single.block.kind, DiaryBlockKind.paragraph);
      expect(redo().onTap, isNotNull);

      await tester.tap(find.byIcon(Icons.redo));
      await tester.pump();
      expect(editor.blocks.single.block.kind, DiaryBlockKind.heading);
    });
  });

  group('时间戳块渲染（App 独有胶囊）', () {
    /// 时间戳段（只读胶囊）+ 一个可写正文块的文档骨架。
    BlockEditorController mountStampDoc(DateTime now, {bool locked = false}) {
      final ids = SyIdGenerator(random: Random(7), now: () => now);
      final date = DateTime(now.year, now.month, now.day);
      final document = DiaryDocument(
        id: SyIdGenerator.dayContainer(date),
        date: date,
        title: '测试日',
        locked: locked,
        blocks: [
          DiaryBlock(
            id: ids.next(),
            text: '2026-05-15 09:00',
            custom: const {kEchoStampAttr: '1'},
          ),
          DiaryBlock(id: ids.next(), text: '正文'),
        ],
      );
      return BlockEditorController(idGenerator: ids, now: () => now)
        ..attach(document);
    }

    testWidgets('stamp 块渲染为只读胶囊 chip：无 TextField、无块标', (tester) async {
      final editor = mountStampDoc(DateTime(2026, 5, 15, 9));
      addTearDown(editor.dispose);
      await tester.pumpWidget(harness(editor));
      await tester.pump();

      // 胶囊 chip 以 `diary-stamp-<id>` 为键，且文案即时间戳。
      final stampChip = find.byWidgetPredicate(
        (w) =>
            w is DiaryCapsuleChip &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('diary-stamp-'),
      );
      expect(stampChip, findsOneWidget);
      expect((tester.widget(stampChip) as DiaryCapsuleChip).label, '2026-05-15 09:00');

      // 两个块中只有正文块可写：全文仅 1 个 TextField。
      expect(find.byType(TextField), findsOneWidget);
      // 时间戳块不渲染块标：整篇仅正文块的 1 个 drag_indicator。
      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    });

    testWidgets('普通块不受影响：块标与浮层照常可用', (tester) async {
      final editor = mountStampDoc(DateTime(2026, 5, 15, 9));
      addTearDown(editor.dispose);
      await tester.pumpWidget(harness(editor));
      await tester.pump();

      // 点唯一的块标（正文块），浮层正常上树。
      await tester.tap(find.byIcon(Icons.drag_indicator));
      await tester.pump();
      await tester.pump();
      expect(find.text('H2'), findsOneWidget);
      expect(editor.selectedBlockId, editor.blocks.last.block.id);
    });
  });

  group('块类型图标与拖拽重排（M3 补丁接线）', () {
    /// 按给定文本挂载多块文档（依次发 ID）。
    BlockEditorController mountMulti(List<String> texts, {bool locked = false}) {
      final now = DateTime(2026, 5, 15, 9);
      final ids = SyIdGenerator(random: Random(7), now: () => now);
      final date = DateTime(now.year, now.month, now.day);
      final document = DiaryDocument(
        id: SyIdGenerator.dayContainer(date),
        date: date,
        title: '测试日',
        locked: locked,
        blocks: [
          for (final text in texts) DiaryBlock(id: ids.next(), text: text),
        ],
      );
      return BlockEditorController(idGenerator: ids, now: () => now)
        ..attach(document);
    }

    testWidgets('类型图标浮在把手下方、仅光标在本块时显示：段落 notes → H1 looks_one', (
      tester,
    ) async {
      final editor = mountMulti(['正文']);
      addTearDown(editor.dispose);
      await tester.pumpWidget(harness(editor));
      await tester.pump();

      final block = editor.blocks.single;
      final typeIcon = find.byKey(
        ValueKey<String>('diary-type-${block.block.id}'),
      );
      // 未聚焦：浮游图标隐藏，也不占布局。
      expect(typeIcon, findsNothing);

      block.focusNode.requestFocus();
      await tester.pump();
      expect(typeIcon, findsOneWidget);
      expect(
        find.descendant(of: typeIcon, matching: find.byIcon(Icons.notes)),
        findsOneWidget,
      );
      // 浮游位置：在拖拽把手正下方，不参与横向排版。
      final iconCenter = tester.getCenter(typeIcon);
      final handleCenter = tester.getCenter(find.byIcon(Icons.drag_indicator));
      expect(iconCenter.dy, greaterThan(handleCenter.dy));
      expect((iconCenter.dx - handleCenter.dx).abs(), lessThan(1));

      editor.turnInto(block, DiaryBlockKind.heading, level: 1);
      await tester.pump();
      expect(
        find.descendant(of: typeIcon, matching: find.byIcon(Icons.looks_one)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.notes), findsNothing);
    });

    testWidgets('把手包在长按拖拽监听内；只读文档禁用起拖', (tester) async {
      ReorderableDelayedDragStartListener listenerOf() =>
          tester.widget<ReorderableDelayedDragStartListener>(
            find.ancestor(
              of: find.byIcon(Icons.drag_indicator),
              matching: find.byType(ReorderableDelayedDragStartListener),
            ),
          );

      final editor = mountMulti(['正文']);
      addTearDown(editor.dispose);
      await tester.pumpWidget(harness(editor));
      await tester.pump();
      expect(listenerOf().enabled, isTrue);
      expect(listenerOf().index, 0);

      // 已导出（locked）文档：把手保留可见，但拖拽起点禁用。
      final locked = mountMulti(['正文'], locked: true);
      addTearDown(locked.dispose);
      await tester.pumpWidget(harness(locked));
      await tester.pump();
      expect(listenerOf().enabled, isFalse);
    });

    testWidgets('长按把手向下拖：块落到末位并压入撤销', (tester) async {
      final editor = mountMulti(['块0', '块1', '块2']);
      addTearDown(editor.dispose);
      await tester.pumpWidget(harness(editor));
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_indicator).first),
      );
      // 先熬过长按延迟（DelayedMultiDragGestureRecognizer）才开始拖。
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 400));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(editor.blocks.map((s) => s.block.text), ['块1', '块2', '块0']);
      expect(editor.canUndo, isTrue);
    });
  });
}
