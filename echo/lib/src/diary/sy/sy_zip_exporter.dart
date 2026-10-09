import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'diary_model.dart';
import 'sy_id.dart';
import 'sy_serializer.dart';

/// 把日记集合打包为思源笔记本 `.sy.zip`。
///
/// 金标准结构（见 docs/diary/sy-format-golden-3.8.6.md §3）：
///
/// ```
/// {笔记本名}/
/// ├── .siyuan/conf.json
/// ├── .siyuan/sort.json
/// ├── {年ID}.sy
/// └── {年ID}/{月ID}.sy
///     └── {年ID}/{月ID}/{日ID}.sy
/// ```
///
/// zip 仅含文件条目、`/` 分隔；archive 4.x 默认 UTF-8 文件名编码并自动
/// 置通用位 11（0x0800），中文路径无需额外处理（单测锁死该行为）。
class SyZipExporter {
  SyZipExporter({SySerializer? serializer})
      : serializer = serializer ?? const SySerializer();

  final SySerializer serializer;

  /// zip 本地文件头中通用标志位的 UTF-8 位（bit 11），测试用。
  static const int utf8FlagBit = 0x0800;

  Uint8List build({
    required String notebookName,
    required List<DiaryDocument> diaries,
    DateTime? exportedAt,
  }) {
    if (notebookName.trim().isEmpty) {
      throw ArgumentError.value(notebookName, 'notebookName', '笔记本名不能为空');
    }
    final stamp = exportedAt ?? DateTime.now();

    // 年 -> 月 -> 日记（同月按日期排序）。
    final years = <int, Map<int, List<DiaryDocument>>>{};
    for (final doc in diaries) {
      final months = years.putIfAbsent(doc.date.year, () => <int, List<DiaryDocument>>{});
      months.putIfAbsent(doc.date.month, () => []).add(doc);
    }
    for (final months in years.values) {
      for (final docs in months.values) {
        docs.sort((a, b) => a.date.compareTo(b.date));
      }
    }

    final allDocIds = <String>[];
    final entries = <_ZipEntry>[];

    for (final year in years.keys.toList()..sort()) {
      final yearId = SyIdGenerator.yearContainer(year);
      allDocIds.add(yearId);
      entries.add(_ZipEntry(
        '$notebookName/$yearId.sy',
        utf8.encode(serializer.encodeContainer(
          id: yearId,
          title: SySerializer.yearTitle(DateTime(year)),
          updatedAt: stamp,
        )),
      ));

      for (final month in years[year]!.keys.toList()..sort()) {
        final monthDate = DateTime(year, month);
        final monthId = SyIdGenerator.monthContainer(monthDate);
        allDocIds.add(monthId);
        entries.add(_ZipEntry(
          '$notebookName/$yearId/$monthId.sy',
          utf8.encode(serializer.encodeContainer(
            id: monthId,
            title: SySerializer.monthTitle(monthDate),
            updatedAt: stamp,
          )),
        ));

        for (final doc in years[year]![month]!) {
          allDocIds.add(doc.id);
          entries.add(_ZipEntry(
            '$notebookName/$yearId/$monthId/${doc.id}.sy',
            serializer.encodeBytes(doc),
          ));
        }
      }
    }

    final archive = Archive();
    archive.add(_ZipEntry(
      '$notebookName/.siyuan/conf.json',
      utf8.encode(_confJson(notebookName)),
    ).toArchiveFile());
    archive.add(_ZipEntry(
      '$notebookName/.siyuan/sort.json',
      utf8.encode(_sortJson(allDocIds)),
    ).toArchiveFile());
    for (final entry in entries) {
      archive.add(entry.toArchiveFile());
    }

    return ZipEncoder().encodeBytes(archive);
  }

  /// 金标准 conf.json 14 字段（路径/模板类置空）。
  static String _confJson(String notebookName) => jsonEncode({
        'name': notebookName,
        'sort': 0,
        'icon': '',
        'closed': true,
        'refCreateSaveBox': '',
        'refCreateSavePath': '',
        'docCreateSaveBox': '',
        'docCreateSavePath': '',
        'docCreateTemplatePath': '',
        'dailyNoteSavePath': '',
        'dailyNoteTemplatePath': '',
        'sortMode': 15,
        'encrypted': false,
        'boxCrypt': null,
      });

  /// {文档ID:1}，键字典序（金标准实测顺序）。
  static String _sortJson(List<String> ids) {
    final ordered = <String, int>{};
    for (final id in ids.toList()..sort()) {
      ordered[id] = 1;
    }
    return jsonEncode(ordered);
  }
}

class _ZipEntry {
  _ZipEntry(this.name, this.bytes);

  final String name;
  final List<int> bytes;

  ArchiveFile toArchiveFile() => ArchiveFile.bytes(name, bytes);
}
