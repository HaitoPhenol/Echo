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

  DiaryDocument makeDoc({List<DiaryBlock>? blocks, bool locked = false}) {
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
      doc = makeDoc(
        blocks: [
          DiaryBlock(
            id: firstId,
            kind: DiaryBlockKind.heading,
            level: 1,
            background: 3,
            text: '标题',
          ),
        ],
      );
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
      doc = makeDoc(
        blocks: [DiaryBlock(id: ids.next(), text: 'abcd')],
      );
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

      type(state, 'a\nb', composing: const TextRange(start: 0, end: 3));
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
      doc = makeDoc(
        blocks: [
          DiaryBlock(id: prevId, text: 'abc'),
          DiaryBlock(id: ids.next(), text: 'def'),
        ],
      );
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
      doc = makeDoc(
        blocks: [
          DiaryBlock(id: ids.next(), text: 'abc'),
          DiaryBlock(id: ids.next()),
        ],
      );
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
      doc = makeDoc(
        blocks: [DiaryBlock(id: ids.next(), text: 'abc')],
      );
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final first = controller.blocks.single;
      collapseAt(first, 0);
      expect(controller.handleBackspace(first), isFalse);
      controller.dispose();
    });

    test('光标非 0 / 有选区时不拦截', () {
      doc = makeDoc(
        blocks: [
          DiaryBlock(id: ids.next(), text: 'abc'),
          DiaryBlock(id: ids.next(), text: 'def'),
        ],
      );
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
  });

  group('T05 ↑↓ 跳焦', () {
    test('首块 offset0 向上、末块末尾向下均不拦截；边界跳焦拦截', () {
      doc = makeDoc(
        blocks: [
          DiaryBlock(id: ids.next(), text: 'abc'),
          DiaryBlock(id: ids.next(), text: 'de'),
        ],
      );
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
      doc = makeDoc(
        blocks: [DiaryBlock(id: ids.next(), text: '标题')],
      );
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      final s = controller.blocks.single;

      controller.turnInto(s, DiaryBlockKind.heading, level: 2);
      controller.setBackground(s, 12);

      final restored = const SySerializer()
          .decode(
            const SySerializer().encodeJson(controller.snapshotDocument()),
          )
          .document
          .blocks
          .single;
      expect(restored.kind, DiaryBlockKind.heading);
      expect(restored.level, 2);
      expect(restored.background, 12);
      expect(restored.text, '标题');

      controller.turnInto(s, DiaryBlockKind.paragraph);
      final again = const SySerializer()
          .decode(
            const SySerializer().encodeJson(controller.snapshotDocument()),
          )
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

    test('锁定文档上的结构命令与输入为 no-op', () {
      final locked = makeDoc(
        locked: true,
        blocks: [DiaryBlock(id: ids.next(), text: 'x')],
      );
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(locked);
      final ls = controller.blocks.single;
      controller.turnInto(ls, DiaryBlockKind.heading, level: 1);
      controller.setBackground(ls, 5);
      expect(ls.block.kind, DiaryBlockKind.paragraph);
      expect(ls.block.background, isNull);
      type(ls, 'xyz'); // 监听应直接忽略。
      expect(controller.handleBackspace(ls), isFalse);
      expect(ls.block.text, 'x');
      controller.dispose();
    });
  });

  group('T09 撤销/重做', () {
    test('回车拆块后撤销还原，重做再次拆开', () {
      final originalId = ids.next();
      doc = makeDoc(
        blocks: [DiaryBlock(id: originalId, text: 'abc')],
      );
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
      doc = makeDoc(
        blocks: [
          DiaryBlock(id: prevId, text: 'abc'),
          DiaryBlock(id: ids.next(), text: 'def'),
        ],
      );
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
      doc = makeDoc(
        blocks: [
          DiaryBlock(id: ids.next(), text: 'one'),
          DiaryBlock(id: ids.next(), text: 'two'),
        ],
      );
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

  group('M5 文档级 custom（心情入口）', () {
    test('setDocumentCustom 写入置脏随 snapshot 保留；同值 no-op；null 移除', () {
      doc = makeDoc();
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      addTearDown(controller.dispose);
      expect(controller.documentCustom, isEmpty);

      controller.setDocumentCustom('custom-mood', '🙂');
      expect(controller.documentCustom['custom-mood'], '🙂');
      expect(controller.dirty.value, isTrue);
      expect(controller.snapshotDocument().custom['custom-mood'], '🙂');

      // 同值不产生新的脏标记。
      controller.markClean();
      controller.setDocumentCustom('custom-mood', '🙂');
      expect(controller.dirty.value, isFalse);

      // null = 移除键（清心情）。
      controller.setDocumentCustom('custom-mood', null);
      expect(controller.documentCustom.containsKey('custom-mood'), isFalse);
      expect(controller.dirty.value, isTrue);
    });

    test('locked（导出只读）文档 setDocumentCustom 为 no-op', () {
      doc = makeDoc(locked: true);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      addTearDown(controller.dispose);

      controller.setDocumentCustom('custom-mood', '😢');
      expect(controller.documentCustom, isEmpty);
      expect(controller.dirty.value, isFalse);
    });

    test('documentCustom 为不可改视图', () {
      doc = makeDoc();
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      addTearDown(controller.dispose);
      expect(
        () => controller.documentCustom['custom-mood'] = '😄',
        throwsUnsupportedError,
      );
    });
  });

  group('applyCustomPatch（胶囊行数据刷新）', () {
    test('批量写入置脏、同值不置脏、null 删键且不压撤销快照', () {
      doc = makeDoc();
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      addTearDown(controller.dispose);
      expect(controller.documentCustom, isEmpty);

      controller.applyCustomPatch({
        'custom-iot-temp': '21',
        'custom-weather': '多云',
      });
      expect(controller.documentCustom, {
        'custom-iot-temp': '21',
        'custom-weather': '多云',
      });
      expect(controller.dirty.value, isTrue);
      // 系统动作不进用户撤销链。
      expect(controller.canUndo, isFalse);

      // 同值再写：无变化不产生新的脏标记。
      controller.markClean();
      controller.applyCustomPatch({'custom-iot-temp': '21'});
      expect(controller.dirty.value, isFalse);

      // null = 移除键（源本次不可用）。
      controller.applyCustomPatch({'custom-weather': null});
      expect(controller.documentCustom.containsKey('custom-weather'), isFalse);
      expect(controller.dirty.value, isTrue);

      // 删除不存在的键：无变化不置脏。
      controller.markClean();
      controller.applyCustomPatch({'custom-weather': null});
      expect(controller.dirty.value, isFalse);
    });

    test('locked（导出只读）文档 applyCustomPatch 为 no-op', () {
      doc = makeDoc(locked: true);
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      addTearDown(controller.dispose);

      controller.applyCustomPatch({'custom-iot-temp': '21'});
      expect(controller.documentCustom, isEmpty);
      expect(controller.dirty.value, isFalse);
    });

    test('未 attach（无文档）时 applyCustomPatch 为 no-op', () {
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow);
      addTearDown(controller.dispose);

      controller.applyCustomPatch({'custom-iot-temp': '21'});
      expect(controller.documentCustom, isEmpty);
      expect(controller.dirty.value, isFalse);
    });
  });

  group('时间戳块（isStamp）守卫', () {
    DiaryBlock stamp(String id, [String text = '2026-10-10 09:00']) =>
        DiaryBlock(
          id: id,
          text: text,
          custom: {kEchoStampAttr: '1'},
          updatedAt: fixedNow,
        );

    /// 时间戳 + 一个正文行 + 普通段。
    void attachWithStamp() {
      doc = makeDoc(
        blocks: [
          stamp('20261010090000-ssssss1'),
          DiaryBlock(id: '20261010090001-aaaaaaa', text: '正文'),
          DiaryBlock(id: '20261010090002-bbbbbbb', text: '普通段'),
        ],
      );
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      addTearDown(controller.dispose);
    }

    test('正文块块首退格：上一块是时间戳，不拦截（不并入只读时间戳块）', () {
      attachWithStamp();
      final body = controller.blocks[1];
      collapseAt(body, 0);

      expect(controller.handleBackspace(body), isFalse);
      expect(controller.blocks, hasLength(3));
      expect(controller.blocks.first.block.isStamp, isTrue);
    });

    test('段内唯一正文行为空时块首退格：不删自身（保证段至少留一个正文行）', () {
      attachWithStamp();
      final body = controller.blocks[1];
      // 把正文行清空：仍不允许删掉它（否则段尾只剩时间戳）。
      controller.applyValue(body, '', TextSelection.collapsed(offset: 0));
      collapseAt(body, 0);

      expect(controller.handleBackspace(body), isFalse);
      expect(controller.blocks, hasLength(3));
    });

    test('纵向移动跳过时间戳块：上一块是时间戳时继续上跳到普通段', () {
      // 排布「普通段 / 时间戳 / 正文」，从正文向上须跨过时间戳落到普通段。
      doc = makeDoc(
        blocks: [
          DiaryBlock(id: '20261010090000-ppppppp', text: '普通段'),
          stamp('20261010090001-ssssss3'),
          DiaryBlock(id: '20261010090002-qqqqqqq', text: '正文'),
        ],
      );
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      addTearDown(controller.dispose);
      final body = controller.blocks[2];
      collapseAt(body, 0);

      expect(controller.handleVerticalMove(body, up: true), isTrue);
    });

    test('纵向移动：首个正文行向上只剩时间戳时返回 false（不拦截）', () {
      doc = makeDoc(
        blocks: [
          stamp('20261010090000-ssssss2'),
          DiaryBlock(id: '20261010090001-ccccccc', text: '正文'),
        ],
      );
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      addTearDown(controller.dispose);
      final body = controller.blocks[1];
      collapseAt(body, 0);

      expect(controller.handleVerticalMove(body, up: true), isFalse);
    });

    test('turnInto / setBackground 对时间戳块为 no-op（只读）', () {
      attachWithStamp();
      final s = controller.blocks.first;

      controller.turnInto(s, DiaryBlockKind.heading, level: 1);
      expect(s.block.kind, DiaryBlockKind.paragraph);
      controller.setBackground(s, 3);
      expect(s.block.background, isNull);
      expect(controller.dirty.value, isFalse);
    });

    test('撤销/重做保留块级 custom（时间戳标志）', () {
      attachWithStamp();
      final body = controller.blocks[2];
      type(body, '普通段\n');
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.blocks.first.block.isStamp, isTrue);
      expect(controller.blocks.first.block.custom[kEchoStampAttr], '1');

      controller.redo();
      expect(controller.blocks.first.block.isStamp, isTrue);
    });
  });

  group('时间戳待启用（空段不落盘 + 首字符重打点）', () {
    late DateTime currentNow;

    DiaryBlock stamp(String id, String text) => DiaryBlock(
      id: id,
      text: text,
      custom: {kEchoStampAttr: '1'},
      updatedAt: fixedNow,
    );

    DiaryBlock para(String id, String text) =>
        DiaryBlock(id: id, text: text, updatedAt: fixedNow);

    void attachWith(List<DiaryBlock> blocks) {
      doc = makeDoc(blocks: blocks);
      controller = BlockEditorController(idGenerator: ids, now: () => currentNow)
        ..attach(doc);
      addTearDown(controller.dispose);
    }

    setUp(() => currentNow = DateTime(2026, 10, 10, 9));

    test('段时间戳 + 空正文行 → 待启用；无时间戳 / 段内已有内容 → 不待启用', () {
      attachWith([stamp('20261010090000-ssssss1', '2026-10-10 09:00'), para('20261010090001-aaaaaaa', '')]);
      expect(controller.pendingStamp, isTrue);

      attachWith([
        stamp('20261010090000-ssssss2', '2026-10-10 09:00'),
        para('20261010090001-bbbbbbb', '已有内容'),
      ]);
      expect(controller.pendingStamp, isFalse);

      attachWith([para('20261010090001-ccccccc', '无时间戳')]);
      expect(controller.pendingStamp, isFalse);
    });

    test('输入首个字符：时间戳重打点为当前时间，其后不再自动更新', () {
      attachWith([
        stamp('20261010090000-ssssss3', '2026-10-10 09:00'),
        para('20261010090001-ddddddd', ''),
      ]);
      final body = controller.blocks[1];

      currentNow = DateTime(2026, 10, 10, 9, 37);
      type(body, '今');
      expect(controller.blocks.first.block.text, '2026-10-10 09:37');
      expect(controller.pendingStamp, isFalse);

      // 继续输入：时间戳冻结在「动笔时间」，不再变。
      currentNow = DateTime(2026, 10, 10, 10, 5);
      type(body, '今天');
      expect(controller.blocks.first.block.text, '2026-10-10 09:37');
    });

    test('清空内容 → 回待启用（时间戳暂不变）；再次输入 → 重新打点', () {
      attachWith([
        stamp('20261010090000-ssssss4', '2026-10-10 09:00'),
        para('20261010090001-eeeeeee', '开始写'),
      ]);
      final body = controller.blocks[1];
      expect(controller.pendingStamp, isFalse);

      type(body, '');
      expect(controller.pendingStamp, isTrue);
      expect(controller.blocks.first.block.text, '2026-10-10 09:00');

      currentNow = DateTime(2026, 10, 10, 11, 8);
      type(body, '又写');
      expect(controller.blocks.first.block.text, '2026-10-10 11:08');
      expect(controller.pendingStamp, isFalse);
    });

    test('机制只作用于最后一个时间戳：更早的时间戳不被改写', () {
      attachWith([
        stamp('20261010090000-ssssss5', '2026-10-10 08:00'),
        para('20261010090001-fffffff', '前文已保存'),
        stamp('20261010093000-ssssss6', '2026-10-10 09:30'),
        para('20261010093001-ggggggg', ''),
      ]);
      final body = controller.blocks[3];

      currentNow = DateTime(2026, 10, 10, 9, 42);
      type(body, '新段首字');

      expect(controller.blocks[2].block.text, '2026-10-10 09:42');
      expect(controller.blocks[0].block.text, '2026-10-10 08:00');
    });
  });

  group('T11 拖动重排', () {
    /// 挂载三块文档（块0/块1/块2），返回控制器（已注册 tearDown）。
    BlockEditorController mountThree({bool locked = false}) {
      doc = makeDoc(
        locked: locked,
        blocks: [
          for (var i = 0; i < 3; i++) DiaryBlock(id: ids.next(), text: '块$i'),
        ],
      );
      controller = BlockEditorController(idGenerator: ids, now: () => fixedNow)
        ..attach(doc);
      addTearDown(controller.dispose);
      return controller;
    }

    List<String> texts() =>
        controller.blocks.map((s) => s.block.text).toList(growable: false);

    test('下移：moveBlockAt(0, 2) 把首块插到末位，块对象整体搬移', () {
      final c = mountThree();
      final moved = c.blocks.first.block;

      c.moveBlockAt(0, 2);

      expect(texts(), ['块1', '块2', '块0']);
      expect(identical(c.blocks.last.block, moved), isTrue);
      expect(c.dirty.value, isTrue);
    });

    test('上移：moveBlockAt(2, 0) 把末块插到首位', () {
      final c = mountThree();
      c.moveBlockAt(2, 0);
      expect(texts(), ['块2', '块0', '块1']);
    });

    test('目标下标越界收敛到末位', () {
      final c = mountThree();
      c.moveBlockAt(0, 99);
      expect(texts(), ['块1', '块2', '块0']);
    });

    test('落点未变 / 源下标越界：no-op 不压快照不置脏', () {
      final c = mountThree();
      c.moveBlockAt(1, 1);
      c.moveBlockAt(-1, 0);
      c.moveBlockAt(9, 0);

      expect(texts(), ['块0', '块1', '块2']);
      expect(c.canUndo, isFalse);
      expect(c.dirty.value, isFalse);
    });

    test('撤销回到原序，重做再回到新序', () {
      final c = mountThree();
      c.moveBlockAt(0, 2);
      expect(c.canUndo, isTrue);

      c.undo();
      expect(texts(), ['块0', '块1', '块2']);

      c.redo();
      expect(texts(), ['块1', '块2', '块0']);
    });

    test('locked 文档：重排 no-op', () {
      final c = mountThree(locked: true);
      c.moveBlockAt(0, 2);
      expect(texts(), ['块0', '块1', '块2']);
      expect(c.canUndo, isFalse);
    });
  });
}
