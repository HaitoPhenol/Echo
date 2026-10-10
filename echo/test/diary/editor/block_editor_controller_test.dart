import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/editor/block_editor_controller.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/sy/sy_serializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 10, 10, 9);
  late SyIdGenerator ids;

  late DiaryDocument doc;
  late BlockEditorController controller;

  DiaryDocument makeDoc({
    List<DiaryBlock>? blocks,
    bool locked = false,
  }) {
    return DiaryDocument(
      id: SyIdGenerator.dayContainer(fixedNow),
      date: fixedNow,
      title: '10月10日 周六',
      blocks: blocks,
      locked: locked,
    );
  }

  /// 模拟 IME 直接改写域值（软键盘回车/粘贴都走这条通道）。
  void type(BlockState s, String text, {int? caret, TextRange? composing}) {
    s.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
      composing: composing ?? TextRange.empty,
    );
  }

  void collapseAt(BlockState s, int offset) {
    s.controller.selection = TextSelection.collapsed(offset: offset);
  }

  setUp(() {
    ids = SyIdGenerator(random: Random(1), now: () => fixedNow);
  });

  group('T01 回车拆块', () {
    test('段末回车：原块保留 ID/kind，新块为空段落', () {
      final firstId = ids.next();
      doc = makeDoc(blocks: [
        DiaryBlock(
          id: firstId,
          kind: DiaryBlockKind.heading,
          level: 1,
          background: 3,
          text: '标题',
        ),
      ]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final state = controller.blocks.single;

      type(state, '标题\n');

      final blocks = controller.blocks;
      expect(blocks, hasLength(2));
      expect(blocks[0].block.id, firstId);
      expect(blocks[0].block.kind, DiaryBlockKind.heading);
      expect(blocks[0].block.level, 1);
      expect(blocks[0].block.background, 3);
      expect(blocks[0].controller.text, '标题');
      expect(blocks[1].block.kind, DiaryBlockKind.paragraph);
      expect(blocks[1].block.text, isEmpty);
      expect(blocks[1].block.id, isNot(firstId));
      controller.dispose();
    });

    test('段中回车：前后文本各归其块', () {
      doc = makeDoc(blocks: [DiaryBlock(id: ids.next(), text: 'abcd')]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final state = controller.blocks.single;

      type(state, 'ab\ncd', caret: 3);

      expect(controller.blocks.map((s) => s.block.text), ['ab', 'cd']);
      controller.dispose();
    });

    test('粘贴多行文本一次拆成多块', () {
      doc = makeDoc(blocks: [DiaryBlock(id: ids.next())]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);

      type(controller.blocks.single, 'a\nb\nc');

      expect(controller.blocks.map((s) => s.block.text), ['a', 'b', 'c']);
      controller.dispose();
    });

    test('组词（composing）期间含换行也不拆块', () {
      doc = makeDoc(blocks: [DiaryBlock(id: ids.next())]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final state = controller.blocks.single;

      type(state, 'a\nb',
          composing: const TextRange(start: 0, end: 3));
      expect(controller.blocks, hasLength(1));
      expect(controller.blocks.single.block.text, 'a\nb');

      // 上屏后换行消失（正常提交流程），仍为单块。
      type(state, 'ab', caret: 2);
      expect(controller.blocks, hasLength(1));
      controller.dispose();
    });
  });

  group('T02 块首退格', () {
    test('非空块与上一块合并：保留上块 ID，光标落在接合处', () {
      final prevId = ids.next();
      doc = makeDoc(blocks: [
        DiaryBlock(id: prevId, text: 'abc'),
        DiaryBlock(id: ids.next(), text: 'def'),
      ]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final second = controller.blocks[1];
      collapseAt(second, 0);

      final handled = controller.handleBackspace(second);

      expect(handled, isTrue);
      expect(controller.blocks, hasLength(1));
      final merged = controller.blocks.single;
      expect(merged.block.id, prevId);
      expect(merged.block.text, 'abcdef');
      controller.dispose();
    });

    test('块首空块删除，但整篇至少保留一块', () {
      doc = makeDoc(blocks: [
        DiaryBlock(id: ids.next(), text: 'abc'),
        DiaryBlock(id: ids.next()),
      ]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final empty = controller.blocks[1];
      collapseAt(empty, 0);
      expect(controller.handleBackspace(empty), isTrue);
      expect(controller.blocks, hasLength(1));

      // 仅剩唯一空块时不再删除。
      final only = controller.blocks.single;
      collapseAt(only, 0);
      expect(controller.handleBackspace(only), isFalse);
      controller.dispose();
    });

    test('第一块块首退格不拦截（交框架）', () {
      doc = makeDoc(blocks: [DiaryBlock(id: ids.next(), text: 'abc')]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final first = controller.blocks.single;
      collapseAt(first, 0);
      expect(controller.handleBackspace(first), isFalse);
      controller.dispose();
    });

    test('光标非 0 / 有选区时不拦截', () {
      doc = makeDoc(blocks: [
        DiaryBlock(id: ids.next(), text: 'abc'),
        DiaryBlock(id: ids.next(), text: 'def'),
      ]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final second = controller.blocks[1];
      collapseAt(second, 2);
      expect(controller.handleBackspace(second), isFalse);

      second.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      expect(controller.handleBackspace(second), isFalse);
      controller.dispose();
    });

    test('上一块/当前块只读时不合并', () {
      doc = makeDoc(blocks: [
        DiaryBlock(id: ids.next(), text: 'data', readonly: true),
        DiaryBlock(id: ids.next()),
      ]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final second = controller.blocks[1];
      collapseAt(second, 0);
      expect(controller.handleBackspace(second), isFalse);
      expect(controller.blocks, hasLength(2));
      controller.dispose();
    });
  });

  group('T05 ↑↓ 跳焦', () {
    test('首块 offset0 向上、末块末尾向下均不拦截；边界跳焦拦截', () {
      doc = makeDoc(blocks: [
        DiaryBlock(id: ids.next(), text: 'abc'),
        DiaryBlock(id: ids.next(), text: 'de'),
      ]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final first = controller.blocks[0];
      final second = controller.blocks[1];

      collapseAt(first, 0);
      expect(controller.handleVerticalMove(first, up: true), isFalse);
      expect(controller.handleVerticalMove(first, up: false), isFalse);

      expect(controller.handleVerticalMove(second, up: false), isFalse);
      collapseAt(second, 0);
      expect(controller.handleVerticalMove(second, up: true), isTrue);

      // 首块末尾 ↓ 跳下一块；末块末尾 ↓ 无块可跳。
      collapseAt(first, 3);
      expect(controller.handleVerticalMove(first, up: false), isTrue);
      collapseAt(second, 2);
      expect(controller.handleVerticalMove(second, up: false), isFalse);
      controller.dispose();
    });
  });

  group('T04 结构命令与序列化往返', () {
    test('转 H1–H3 / 回段落，serializer 往返一致', () {
      doc = makeDoc(blocks: [DiaryBlock(id: ids.next(), text: '标题')]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final s = controller.blocks.single;

      controller.turnInto(s, DiaryBlockKind.heading, level: 2);
      controller.setBackground(s, 12);

      final restored = const SySerializer()
          .decode(const SySerializer().encodeJson(
            controller.snapshotDocument(),
          ))
          .document
          .blocks
          .single;
      expect(restored.kind, DiaryBlockKind.heading);
      expect(restored.level, 2);
      expect(restored.background, 12);
      expect(restored.text, '标题');

      controller.turnInto(s, DiaryBlockKind.paragraph);
      final again = const SySerializer()
          .decode(const SySerializer()
              .encodeJson(controller.snapshotDocument()))
          .document
          .blocks
          .single;
      expect(again.kind, DiaryBlockKind.paragraph);
      expect(again.level, isNull);
      expect(again.background, 12); // 转段落不清底色。
      controller.dispose();
    });

    test('非法级别/色号抛 ArgumentError', () {
      doc = makeDoc(blocks: [DiaryBlock(id: ids.next())]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final s = controller.blocks.single;
      expect(
        () => controller.turnInto(s, DiaryBlockKind.heading, level: 4),
        throwsArgumentError,
      );
      expect(() => controller.setBackground(s, 0), throwsArgumentError);
      expect(() => controller.setBackground(s, 14), throwsArgumentError);
      controller.dispose();
    });

    test('只读块 / 锁定文档上的结构命令为 no-op', () {
      doc = makeDoc(blocks: [
        DiaryBlock(id: ids.next(), readonly: true),
      ]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final s = controller.blocks.single;
      controller.turnInto(s, DiaryBlockKind.heading, level: 1);
      controller.setBackground(s, 5);
      expect(s.block.kind, DiaryBlockKind.paragraph);
      expect(s.block.background, isNull);
      controller.dispose();

      final locked = makeDoc(
        locked: true,
        blocks: [DiaryBlock(id: ids.next(), text: 'x')],
      );
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(locked);
      final ls = controller.blocks.single;
      type(ls, 'xyz'); // 监听应直接忽略。
      expect(controller.handleBackspace(ls), isFalse);
      expect(ls.block.text, 'x');
      controller.dispose();
    });
  });

  group('T09 撤销/重做', () {
    test('回车拆块后撤销还原，重做再次拆开', () {
      final originalId = ids.next();
      doc = makeDoc(blocks: [DiaryBlock(id: originalId, text: 'abc')]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final state = controller.blocks.single;
      expect(controller.canUndo, isFalse);

      type(state, 'abc\n');
      expect(controller.blocks, hasLength(2));
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.blocks.map((s) => s.block.text), ['abc']);
      expect(controller.blocks.single.block.id, originalId);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.blocks.map((s) => s.block.text), ['abc', '']);
      controller.dispose();
    });

    test('合并撤销还原两块', () {
      final prevId = ids.next();
      doc = makeDoc(blocks: [
        DiaryBlock(id: prevId, text: 'abc'),
        DiaryBlock(id: ids.next(), text: 'def'),
      ]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final second = controller.blocks[1];
      collapseAt(second, 0);
      controller.handleBackspace(second);
      expect(controller.blocks, hasLength(1));

      controller.undo();
      expect(controller.blocks.map((s) => s.block.text), ['abc', 'def']);
      expect(controller.blocks[0].block.id, prevId);
      controller.dispose();
    });
  });

  group('杂项', () {
    test('普通打字标脏、snapshotDocument 同步文本且不卸载', () {
      doc = makeDoc(blocks: [DiaryBlock(id: ids.next())]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      expect(controller.dirty.value, isFalse);

      type(controller.blocks.single, 'hello');
      expect(controller.dirty.value, isTrue);
      expect(controller.snapshotDocument().blocks.single.text, 'hello');
      expect(controller.blocks, hasLength(1));
      controller.dispose();
    });

    test('detach 回灌有序块列表', () {
      doc = makeDoc(blocks: [
        DiaryBlock(id: ids.next(), text: 'one'),
        DiaryBlock(id: ids.next(), text: 'two'),
      ]);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      type(controller.blocks[0], 'one\nmore');
      final out = controller.detach();
      expect(out.blocks.map((b) => b.text), ['one', 'more', 'two']);
      controller.dispose();
    });

    test('打开空 blocks 文档自动补一个空段落', () {
      doc = makeDoc();
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      expect(controller.blocks, hasLength(1));
      controller.dispose();
    });
  });
}
