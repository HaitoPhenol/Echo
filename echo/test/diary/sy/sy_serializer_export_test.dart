import 'dart:convert';
import 'dart:math';

import 'package:echo/src/diary/sy/diary_capsule_items.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/sy/sy_serializer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 导出专用编码（[SySerializer.encodeExportJson]）的结构验证。
///
/// 参照样本 `artifacts/模板参考 36859.sy.zip`：
/// * 首行 = 水平超级块（`Data:'col'`）+ 每个有值胶囊一段
///   `NodeText('') + NodeTextMark(code) + NodeText('')`；
/// * 每段 = 垂直超级块（`Data:'row'`），首段为 `code` 时间戳、携带
///   `custom-echo-stamp` 块级属性，其后是正文；
/// * 落盘/撤销走的**扁平**编码不得含任何 `NodeSuperBlock`。
void main() {
  const serializer = SySerializer();
  final now = DateTime(2026, 10, 18, 23, 16, 49);
  const zwsp = '\u200b';

  SyIdGenerator ids() => SyIdGenerator(random: Random(1), now: () => now);

  DiaryBlock stamp(String id, String text, DateTime at) => DiaryBlock(
    id: id,
    text: text,
    custom: {kEchoStampAttr: '1'},
    updatedAt: at,
  );

  DiaryBlock para(String id, String text) =>
      DiaryBlock(id: id, text: text, updatedAt: now);

  DiaryDocument sampleDoc({
    Map<String, String>? custom,
    List<DiaryBlock>? blocks,
  }) => DiaryDocument(
    id: SyIdGenerator.dayContainer(now),
    date: DateTime(2026, 10, 18),
    title: '10月18日 周日',
    custom: custom ?? {},
    updatedAt: now,
    blocks:
        blocks ??
        [
          stamp(
            '20261018100000-ssssss1',
            '2026-10-18 10:00',
            DateTime(2026, 10, 18, 10, 0),
          ),
          para('20261018100001-aaaaaaa', '第一段正文'),
          para('20261018100002-bbbbbbb', '第二行'),
          stamp(
            '20261018103000-ssssss2',
            '2026-10-18 10:30',
            DateTime(2026, 10, 18, 10, 30),
          ),
          para('20261018103001-ccccccc', '第二段正文'),
        ],
  );

  Map<String, Object?> exportRoot(DiaryDocument doc) =>
      jsonDecode(serializer.encodeExportJson(doc, ids()))
          as Map<String, Object?>;

  List<Map<String, Object?>> childrenOf(Map<String, Object?> node) =>
      (node['Children'] as List).cast<Map<String, Object?>>();

  /// 断言一段为 `NodeText('') + NodeTextMark(code) + NodeText('')`，
  /// 返回 code 文本内容。
  String codeText(Map<String, Object?> paragraph) {
    final children = childrenOf(paragraph);
    expect(children, hasLength(3));
    expect(children[0], {'Type': 'NodeText', 'Data': zwsp});
    expect(children[1]['Type'], 'NodeTextMark');
    expect(children[1]['TextMarkType'], 'code');
    expect(children[2], {'Type': 'NodeText', 'Data': zwsp});
    return children[1]['TextMarkTextContent'] as String;
  }

  group('扁平编码与导出编码分工', () {
    test('扁平草稿编码（落盘/撤销）不含超级块与行内标记，但保留块级 custom', () {
      final flat = serializer.encodeJson(sampleDoc());
      expect(flat, isNot(contains('NodeSuperBlock')));
      expect(flat, isNot(contains('NodeTextMark')));
      // 时间戳标志随扁平编码往返（落盘/撤销需要它）。
      expect(flat, contains('custom-echo-stamp'));
    });

    test('导出编码叠加超级块结构', () {
      final json = serializer.encodeExportJson(sampleDoc(), ids());
      expect(json, contains('NodeSuperBlock'));
      expect(json, contains('NodeTextMark'));
      expect(json, contains('"TextMarkType":"code"'));
    });
  });

  group('首行胶囊 col 超级块', () {
    test('有值槽位生成水平超级块，段结构与参考样本逐位一致', () {
      final doc = sampleDoc(
        custom: {
          kCapsuleTempKey: '21',
          kCapsuleWeatherKey: '多云',
          kCapsuleMoodKey: '🙂',
        },
      );
      final children = childrenOf(exportRoot(doc));
      final col = children.first;
      expect(col['Type'], 'NodeSuperBlock');

      final kids = childrenOf(col);
      expect(kids.first['Type'], 'NodeSuperBlockOpenMarker');
      expect(kids[1]['Type'], 'NodeSuperBlockLayoutMarker');
      expect(kids[1]['Data'], 'col');
      expect(kids.last['Type'], 'NodeSuperBlockCloseMarker');

      final capsules = kids.sublist(2, kids.length - 1);
      expect(capsules, hasLength(3));
      // 槽位顺序固定：温度 → 湿度 → 天气 → 日程 → 心情（缺值不输出）。
      expect(capsules.map(codeText).toList(), ['🌡️21°C', '☁️ 多云', '🙂']);
    });

    test('五个槽位全空：不生成首行胶囊超级块', () {
      final children = childrenOf(exportRoot(sampleDoc()));
      // 首行无胶囊 → 第一个节点是时间戳段上一行的空段落，其后才是 row 段。
      expect(children.first['Type'], 'NodeParagraph');
      expect(children.first.containsKey('Children'), isFalse);
      expect(children[1]['Type'], 'NodeSuperBlock');
      expect(childrenOf(children[1])[1]['Data'], 'row');
    });

    test('无时间戳段的文档：胶囊行后跟顶层扁平段落', () {
      final doc = sampleDoc(
        custom: {kCapsuleTempKey: '21'},
        blocks: [para('20261018120000-ppppppp', '只有正文')],
      );
      final children = childrenOf(exportRoot(doc));
      expect(childrenOf(children.first)[1]['Data'], 'col');
      expect(children[1]['Type'], 'NodeParagraph');
      expect(children[1]['ID'], '20261018120000-ppppppp');
    });

    test('概述段（12 号底色）在胶囊行之后、首个 row 段之前顶层输出', () {
      final doc = sampleDoc(
        custom: {kCapsuleTempKey: '21'},
        blocks: [
          DiaryBlock(
            id: '20261018080000-summary',
            background: 12,
            updatedAt: now,
          ),
          stamp(
            '20261018100000-ssssss1',
            '2026-10-18 10:00',
            DateTime(2026, 10, 18, 10, 0),
          ),
          para('20261018100001-aaaaaaa', '第一段正文'),
        ],
      );
      final children = childrenOf(exportRoot(doc));
      // 0 = 首行 col 胶囊超级块；1 = 概述段（顶层段落）；
      // 2 = 时间戳段上一行空段落；3 = 首个 row 段。
      expect(childrenOf(children[0])[1]['Data'], 'col');
      expect(children[1]['Type'], 'NodeParagraph');
      expect(children[1]['ID'], '20261018080000-summary');
      final style =
          (children[1]['Properties'] as Map)['style'] as String;
      expect(style, contains('var(--b3-font-background12)'));
      expect(children[2]['Type'], 'NodeParagraph');
      expect(children[2].containsKey('Children'), isFalse);
      expect(children[3]['Type'], 'NodeSuperBlock');
      expect(childrenOf(children[3])[1]['Data'], 'row');
    });
  });

  group('每段垂直超级块', () {
    test('两个时间戳 = 两个 row 超级块，段内正文同包，stamp 带 code 与块级标志', () {
      final children = childrenOf(exportRoot(sampleDoc()));
      // [空行, 段1, 空行, 段2]：每个时间戳段上一行都插了空段落。
      expect(children, hasLength(4));
      for (final i in [0, 2]) {
        expect(children[i]['Type'], 'NodeParagraph');
        expect(children[i].containsKey('Children'), isFalse);
      }
      for (final i in [1, 3]) {
        final seg = children[i];
        expect(seg['Type'], 'NodeSuperBlock');
        final kids = childrenOf(seg);
        expect(kids.first['Type'], 'NodeSuperBlockOpenMarker');
        expect(kids[1]['Type'], 'NodeSuperBlockLayoutMarker');
        expect(kids[1]['Data'], 'row');
        expect(kids.last['Type'], 'NodeSuperBlockCloseMarker');
      }

      // 第一段：open, layout, stamp, 正文 a, 正文 b, close
      final seg1 = childrenOf(children[1]);
      expect(seg1, hasLength(6));
      expect(codeText(seg1[2]), '2026-10-18 10:00');
      final stampProps = (seg1[2]['Properties'] as Map).cast<String, Object?>();
      expect(stampProps['custom-echo-stamp'], '1');
      expect(stampProps['id'], '20261018100000-ssssss1');
      // 段内正文块是普通段落（纯 NodeText，无 code 标记）。
      expect(childrenOf(seg1[3]).single['Type'], 'NodeText');
      expect(childrenOf(seg1[3]).single['Data'], '第一段正文');

      // 第二段：open, layout, stamp, 正文 c, close
      final seg2 = childrenOf(children[3]);
      expect(seg2, hasLength(5));
      expect(codeText(seg2[2]), '2026-10-18 10:30');
      expect(
        (seg2[2]['Properties'] as Map)['custom-echo-stamp'],
        '1',
      );
    });

    test('首个时间戳之前的散块按顶层扁平输出（防御性）', () {
      final doc = sampleDoc(
        blocks: [
          para('20261018090000-prepre1', '段前散块'),
          stamp(
            '20261018100000-ssssss3',
            '2026-10-18 10:00',
            DateTime(2026, 10, 18, 10, 0),
          ),
          para('20261018100001-hhhhhhh', '段内正文'),
        ],
      );
      final children = childrenOf(exportRoot(doc));
      // [散块, 空行, 段]。
      expect(children, hasLength(3));
      expect(children.first['Type'], 'NodeParagraph');
      expect(children.first['ID'], '20261018090000-prepre1');
      expect(children[1]['Type'], 'NodeParagraph');
      expect(children[1].containsKey('Children'), isFalse);
      expect(children[2]['Type'], 'NodeSuperBlock');
    });
  });

  group('canonical 形态', () {
    test('超级块与 stamp 段 Properties 键字典序', () {
      final json = serializer.encodeExportJson(sampleDoc(), ids());
      // 超级块外壳：id < updated
      expect(
        json,
        contains(RegExp(r'"Properties":\{"id":"\d{14}-[a-z0-9]{7}","updated":"')),
      );
      // stamp 段：custom-echo-stamp < id < updated
      expect(
        json,
        contains(
          '"Properties":{"custom-echo-stamp":"1",'
          '"id":"20261018100000-ssssss1","updated":"20261018100000"}',
        ),
      );
    });
  });
}
