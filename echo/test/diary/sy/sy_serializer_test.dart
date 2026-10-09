import 'dart:convert';
import 'dart:io';

import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/sy/sy_serializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const serializer = SySerializer();
  final golden = File('test/diary/fixtures/golden_daily_20261009.sy');

  group('金标准解码（思源 3.8.6 文档级样本）', () {
    final result = serializer.decode(golden.readAsStringSync());
    final doc = result.document;

    test('根节点字段', () {
      expect(doc.id, '20261009233451-u7ay0k0');
      expect(doc.title, '9日 周五');
      expect(doc.custom['custom-dailynote-20261009'], '20261009');
      expect(doc.date, DateTime(2026, 10, 9, 23, 34, 51));
      expect(doc.updatedAt, DateTime(2026, 10, 9, 23, 53, 3));
    });

    test('六个标题级别与文本完整', () {
      final headings = doc.blocks
          .where((b) => b.kind == DiaryBlockKind.heading)
          .toList();
      expect(headings.map((b) => b.level), [1, 2, 3, 4, 5, 6]);
      expect(headings.map((b) => b.text), ['一级', '二级', '三级', '四级', '五级', '六级']);
    });

    test('普通段落与行内换行', () {
      expect(doc.blocks.any((b) => b.text == '正文。'), isTrue);
      expect(doc.blocks.any((b) => b.text == '行内\n换行'), isTrue);
    });

    test('行内格式降级为纯文本（加粗/链接等）', () {
      expect(doc.blocks.any((b) => b.text == '加粗'), isTrue);
      expect(doc.blocks.any((b) => b.text == '斜体'), isTrue);
      expect(doc.blocks.any((b) => b.text == '链接嵌入'), isTrue);
    });

    test('第一个顶层段落底色为 12 号', () {
      expect(doc.blocks.first.background, 12);
    });

    test('子集外顶层节点全部记入 skippedTypes', () {
      expect(result.skippedTypes, containsAll(<String>[
        'NodeList',
        'NodeBlockquote',
        'NodeCodeBlock',
        'NodeThematicBreak',
        'NodeTable',
        'NodeHTMLBlock',
        'NodeSuperBlock',
        'NodeCallout',
      ]));
    });
  });

  group('编码（对齐金标准 canonical 形态）', () {
    test('标题块字段序：ID,Type,HeadingLevel,Properties，Properties 键排序', () {
      final d = DateTime(2026, 10, 10, 9, 0, 0);
      final doc = DiaryDocument(
        id: SyIdGenerator.dayContainer(DateTime(2026, 10, 10)),
        date: DateTime(2026, 10, 10),
        title: '10日 周六',
        updatedAt: d,
        blocks: [
          DiaryBlock(
            id: '20261010090000-aaaaaaa',
            kind: DiaryBlockKind.heading,
            level: 2,
            text: '📈 自动记录',
            updatedAt: d,
          ),
        ],
      );
      final json = serializer.encodeJson(doc);
      expect(json, contains('"Spec":"2"'));
      expect(
        json,
        contains('"Type":"NodeHeading","HeadingLevel":2,'
            '"Properties":{"id":"20261010090000-aaaaaaa","updated":"20261010090000"}'),
      );
    });

    test('底色写 b3 变量 canonical 串（不是 hex），含 parent-background', () {
      final doc = DiaryDocument(
        id: SyIdGenerator.dayContainer(DateTime(2026, 10, 10)),
        date: DateTime(2026, 10, 10),
        title: '10日 周六',
        blocks: [
          DiaryBlock(
            id: '20261010090001-bbbbbbb',
            text: '🏠 家中 21°C',
            background: 3,
            updatedAt: DateTime(2026, 10, 10, 9, 0, 1),
          ),
        ],
      );
      final json = serializer.encodeJson(doc);
      expect(json, isNot(contains('#')));
      expect(
        json,
        contains('"style":"background-color: var(--b3-font-background3); '
            '--b3-parent-background: var(--b3-font-background3);"'),
      );
      // Properties 键序 id < style < updated
      expect(json, contains('"id":"20261010090001-bbbbbbb","style":'));
    });

    test('文档级 custom-* 与标准键一起按字典序排列', () {
      final doc = DiaryDocument(
        id: SyIdGenerator.dayContainer(DateTime(2026, 10, 10)),
        date: DateTime(2026, 10, 10),
        title: '10日 周六',
        custom: {'custom-weather': '晴 18°C', 'custom-mood': 'good'},
        updatedAt: DateTime(2026, 10, 10, 9, 0, 0),
      );
      final json = serializer.encodeJson(doc);
      // custom-mood < custom-weather < id < title < type < updated
      expect(
        json,
        contains('"Properties":{"custom-mood":"good",'
            '"custom-weather":"晴 18°C","id":"20261010080000-echo000",'
            '"title":"10日 周六","type":"doc","updated":"20261010090000"}'),
      );
    });

    test('空块省略 Children 键', () {
      final doc = DiaryDocument(
        id: SyIdGenerator.dayContainer(DateTime(2026, 10, 10)),
        date: DateTime(2026, 10, 10),
        title: '10日 周六',
        blocks: [
          DiaryBlock(id: '20261010090002-ccccccc'),
        ],
      );
      final json = serializer.encodeJson(doc);
      expect(json, contains('"Properties":{"id":"20261010090002-ccccccc",'
          '"updated":"'));
      // 空段落节点后直接结束（没有 Children 键）
      expect(json, isNot(contains('NodeText')));
    });

    test('输出为 UTF-8 无 BOM 的紧凑 JSON', () {
      final doc = DiaryDocument(
        id: SyIdGenerator.dayContainer(DateTime(2026, 10, 10)),
        date: DateTime(2026, 10, 10),
        title: '10日 周六',
      );
      final bytes = serializer.encodeBytes(doc);
      expect(bytes.take(3), isNot(equals([0xEF, 0xBB, 0xBF])));
      expect(utf8.decode(bytes), serializer.encodeJson(doc));
      expect(serializer.encodeJson(doc).contains(', '), isFalse);
    });
  });

  group('子集往返幂等', () {
    test('encode → decode → encode 结果不变', () {
      final doc = DiaryDocument(
        id: SyIdGenerator.dayContainer(DateTime(2026, 10, 10)),
        date: DateTime(2026, 10, 10),
        title: '10日 周六',
        custom: {'custom-mood': 'good'},
        updatedAt: DateTime(2026, 10, 10, 9, 0, 0),
        blocks: [
          DiaryBlock(
            id: '20261010090000-aaaaaaa',
            kind: DiaryBlockKind.heading,
            level: 2,
            text: '今天',
            updatedAt: DateTime(2026, 10, 10, 9, 0, 0),
          ),
          DiaryBlock(
            id: '20261010090001-bbbbbbb',
            text: '正文第一行\n第二行',
            background: 5,
            updatedAt: DateTime(2026, 10, 10, 9, 0, 1),
          ),
        ],
      );
      final first = serializer.encodeJson(doc);
      final decoded = serializer.decode(first);
      final again = serializer.encodeJson(decoded.document);
      expect(again, first);
    });
  });

  group('标题工具', () {
    test('年/月/日标题与金标准一致', () {
      expect(SySerializer.yearTitle(DateTime(2026)), '2026');
      expect(SySerializer.monthTitle(DateTime(2026, 10)), '10 月');
      expect(SySerializer.dayTitle(DateTime(2026, 10, 9)), '10月9日 周五');
    });
  });
}
