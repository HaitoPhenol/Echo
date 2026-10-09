import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/sy/sy_serializer.dart';
import 'package:echo/src/diary/sy/sy_zip_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

/// 解析全部本地文件头，返回 (条目名, 通用标志位)。
/// 规范：PK\x03\x04 后 +4 版本 +6 flags +26 文件名长度 +28 扩展长度。
List<MapEntry<String, int>> localHeaders(Uint8List bytes) {
  final result = <MapEntry<String, int>>[];
  var offset = 0;
  final data = ByteData.sublistView(bytes);
  while (offset + 30 <= bytes.length) {
    if (data.getUint32(offset, Endian.little) != 0x04034b50) break;
    final flags = data.getUint16(offset + 6, Endian.little);
    final nameLen = data.getUint16(offset + 26, Endian.little);
    final extraLen = data.getUint16(offset + 28, Endian.little);
    final name = utf8.decode(bytes.sublist(offset + 30, offset + 30 + nameLen));
    result.add(MapEntry(name, flags));
    offset += 30 + nameLen + extraLen;
    // 数据描述符/数据长度需从压缩信息跳过——测试只关心头标志，
    // archive 输出为 stored/deflate，直接全局搜索下一个签名更稳：
    final next = _findSignature(bytes, offset);
    if (next == null) break;
    offset = next;
  }
  return result;
}

int? _findSignature(Uint8List bytes, int from) {
  for (var i = from; i + 4 <= bytes.length; i++) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x03 &&
        bytes[i + 3] == 0x04) {
      return i;
    }
  }
  return null;
}

void main() {
  const serializer = SySerializer();
  final exporter = SyZipExporter(serializer: serializer);
  final goldenZip =
      File('test/diary/fixtures/golden_notebook_3.8.6.sy.zip').readAsBytesSync();

  group('金标准笔记本包（思源 3.8.6）', () {
    final archive = ZipDecoder().decodeBytes(goldenZip);

    test('仅文件条目、无目录条目，路径与实测一致', () {
      expect(archive.files.any((f) => f.name.endsWith('/')), isFalse);
      expect(
        archive.files.map((f) => f.name).toSet(),
        {
          '示例笔记本/.siyuan/conf.json',
          '示例笔记本/.siyuan/sort.json',
          '示例笔记本/20261010000159-mkzx9og.sy',
          '示例笔记本/20261010000159-mkzx9og/20261010000213-y3naqzj.sy',
          '示例笔记本/20261010000159-mkzx9og/'
              '20261010000213-y3naqzj/20261010000332-jtbos5h.sy',
        },
      );
    });

    test('全部本地文件头置 UTF-8 标志位 0x0800', () {
      final headers = localHeaders(Uint8List.fromList(goldenZip));
      expect(headers, hasLength(5));
      expect(
        headers.every((h) => h.value & 0x0800 != 0),
        isTrue,
        reason: '中文路径必须置 UTF-8 位，否则导入乱码',
      );
    });

    test('conf.json 为实测 14 字段', () {
      final file = archive.files
          .firstWhere((f) => f.name.endsWith('.siyuan/conf.json'));
      final conf = jsonDecode(utf8.decode(file.content)) as Map;
      expect(conf.keys, hasLength(14));
      expect(conf['name'], '示例笔记本');
      expect(conf['sort'], 0);
      expect(conf['closed'], isTrue);
      expect(conf['sortMode'], 15);
      expect(conf['encrypted'], isFalse);
      expect(conf['boxCrypt'], isNull);
      expect(conf.keys.toList().take(1), ['name']);
    });

    test('sort.json 覆盖包内全部文档（含容器）', () {
      final file = archive.files
          .firstWhere((f) => f.name.endsWith('.siyuan/sort.json'));
      final sort = jsonDecode(utf8.decode(file.content)) as Map;
      final stems = archive.files
          .where((f) => f.name.endsWith('.sy'))
          .map((f) => f.name.split('/').last.replaceAll('.sy', ''))
          .toSet();
      expect(sort.keys.map((k) => '$k').toSet(), stems);
      expect(sort.values.every((v) => v == 1), isTrue);
    });

    test('三级路径：文件名 stem == 文档根 ID', () {
      for (final file in archive.files.where((f) => f.name.endsWith('.sy'))) {
        final stem = file.name.split('/').last.replaceAll('.sy', '');
        final doc = serializer.decodeBytes(file.content).document;
        expect(doc.id, stem);
      }
    });

    test('容器层级标题：2026 / 10 月；日文档为金标准全量样本', () {
      final year = serializer
          .decodeBytes(archive.files
              .firstWhere((f) => f.name.endsWith('20261010000159-mkzx9og.sy'))
              .content)
          .document;
      final month = serializer
          .decodeBytes(archive.files
              .firstWhere((f) => f.name.endsWith('20261010000213-y3naqzj.sy'))
              .content)
          .document;
      final day = serializer
          .decodeBytes(archive.files
              .firstWhere((f) => f.name.endsWith('20261010000332-jtbos5h.sy'))
              .content)
          .document;
      expect(year.title, '2026');
      expect(month.title, '10 月');
      expect(day.title, '9日 周五');
      expect(day.blocks.first.background, 12);
    });
  });

  group('Echo 导出包构建', () {
    DiaryDocument diary(DateTime date, String mood, {int? background}) {
      return DiaryDocument(
        id: SyIdGenerator.dayContainer(date),
        date: date,
        title: SySerializer.dayTitle(date),
        custom: {'custom-mood': mood},
        updatedAt: DateTime(date.year, date.month, date.day, 21, 0, 0),
        blocks: [
          DiaryBlock(
            id: '${SyIdGenerator.timestamp(date).substring(0, 8)}210000-daaaaaa',
            kind: DiaryBlockKind.heading,
            level: 2,
            text: '今天',
            updatedAt: DateTime(date.year, date.month, date.day, 21, 0, 0),
          ),
          DiaryBlock(
            id: '${SyIdGenerator.timestamp(date).substring(0, 8)}210001-dbbbbbb',
            text: '心情：$mood',
            background: background,
            updatedAt: DateTime(date.year, date.month, date.day, 21, 0, 1),
          ),
        ],
      );
    }

    final exportedAt = DateTime(2026, 10, 10, 22, 0, 0);
    final diaries = [
      diary(DateTime(2026, 10, 10), 'good', background: 3),
      diary(DateTime(2026, 10, 9), 'normal'),
      diary(DateTime(2026, 9, 30), 'bad'),
    ];

    final bytes = exporter.build(
      notebookName: 'Echo日记测试',
      diaries: diaries,
      exportedAt: exportedAt,
    );
    final archive = ZipDecoder().decodeBytes(bytes);

    test('条目顺序与三级路径', () {
      expect(
        archive.files.map((f) => f.name),
        [
          'Echo日记测试/.siyuan/conf.json',
          'Echo日记测试/.siyuan/sort.json',
          'Echo日记测试/20260101000000-echo000.sy',
          'Echo日记测试/20260101000000-echo000/20260901000000-echo000.sy',
          'Echo日记测试/20260101000000-echo000/20260901000000-echo000/'
              '20260930080000-echo000.sy',
          'Echo日记测试/20260101000000-echo000/20261001000000-echo000.sy',
          'Echo日记测试/20260101000000-echo000/20261001000000-echo000/'
              '20261009080000-echo000.sy',
          'Echo日记测试/20260101000000-echo000/20261001000000-echo000/'
              '20261010080000-echo000.sy',
        ],
      );
    });

    test('无目录条目，中文路径本地头置 UTF-8 位', () {
      expect(archive.files.any((f) => f.name.endsWith('/')), isFalse);
      final headers = localHeaders(bytes);
      expect(headers, hasLength(8));
      expect(headers.every((h) => h.value & SyZipExporter.utf8FlagBit != 0),
          isTrue);
    });

    test('conf.json 笔记本名正确且路径字段置空', () {
      final conf = jsonDecode(utf8.decode(archive.files
          .firstWhere((f) => f.name.endsWith('conf.json'))
          .content)) as Map;
      expect(conf['name'], 'Echo日记测试');
      expect(conf['dailyNoteSavePath'], '');
      expect(conf['encrypted'], isFalse);
    });

    test('sort.json 含年+2月+3日共 6 个文档', () {
      final sort = jsonDecode(utf8.decode(archive.files
          .firstWhere((f) => f.name.endsWith('sort.json'))
          .content)) as Map;
      expect(sort.keys, {
        '20260101000000-echo000',
        '20260901000000-echo000',
        '20261001000000-echo000',
        '20260930080000-echo000',
        '20261009080000-echo000',
        '20261010080000-echo000',
      });
    });

    test('容器文档无正文、标题正确、updated 为导包时刻', () {
      final year = serializer
          .decodeBytes(archive.files
              .firstWhere((f) => f.name == 'Echo日记测试/20260101000000-echo000.sy')
              .content)
          .document;
      final month = serializer
          .decodeBytes(archive.files
              .firstWhere((f) => f.name.endsWith('20261001000000-echo000.sy'))
              .content)
          .document;
      expect(year.title, '2026');
      expect(year.blocks, isEmpty);
      expect(year.updatedAt, exportedAt);
      expect(month.title, '10 月');
      expect(month.blocks, isEmpty);
    });

    test('日文档内容、custom-* 与底色完整往返', () {
      final day = serializer
          .decodeBytes(archive.files
              .firstWhere((f) => f.name.endsWith('20261010080000-echo000.sy'))
              .content)
          .document;
      expect(day.title, '10月10日 周六');
      expect(day.custom['custom-mood'], 'good');
      expect(day.blocks.first.level, 2);
      expect(day.blocks.last.background, 3);
      expect(day.blocks.last.text, '心情：good');
    });

    test('增量幂等：重复构建容器路径不变，sort.json 一致', () {
      final again = exporter.build(
        notebookName: 'Echo日记测试',
        diaries: diaries,
        exportedAt: exportedAt,
      );
      final a = ZipDecoder().decodeBytes(bytes);
      final b = ZipDecoder().decodeBytes(again);
      expect(
        b.files.map((f) => f.name),
        a.files.map((f) => f.name),
      );
      String sortOf(Archive ar) => utf8.decode(ar.files
          .firstWhere((f) => f.name.endsWith('sort.json'))
          .content);
      expect(sortOf(b), sortOf(a));
    });

    test('空笔记本名被拒绝', () {
      expect(
        () => exporter.build(notebookName: '  ', diaries: diaries),
        throwsArgumentError,
      );
    });
  });
}
