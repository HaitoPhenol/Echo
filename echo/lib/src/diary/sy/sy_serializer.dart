import 'dart:convert';

import 'diary_model.dart';

/// .sy 解码结果：文档本体 + 子集外被跳过的顶层节点类型（供回读 UI 出占位）。
class SyDecodeResult {
  SyDecodeResult({required this.document, required this.skippedTypes});

  final DiaryDocument document;

  /// 文档直属 Children 中不属于支持子集的节点类型名（按出现顺序，可重复）。
  final List<String> skippedTypes;
}

/// DiaryDocument ↔ .sy JSON。
///
/// 输出严格对齐金标准（思源 3.8.6，见 docs/diary/sy-format-golden-3.8.6.md）：
/// 紧凑 JSON、UTF-8 无 BOM、`Spec:"2"`、Properties 键字典序、
/// 空块省略 Children、底色写 canonical CSS 变量串。
class SySerializer {
  const SySerializer();

  static const String spec = '2';

  static final RegExp _backgroundPattern =
      RegExp(r'var\(--b3-font-background(\d+)\)');

  static const List<String> _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  // ---- 编码 ----------------------------------------------------------------

  /// 序列化为 .sy 字节（UTF-8）。
  List<int> encodeBytes(DiaryDocument doc) => utf8.encode(encodeJson(doc));

  /// 序列化为 .sy JSON 字符串（单行紧凑）。
  String encodeJson(DiaryDocument doc) => jsonEncode(_encodeDocument(doc));

  /// 编码空容器文档（年/月层级用，无正文块）。
  String encodeContainer({
    required String id,
    required String title,
    required DateTime updatedAt,
    Map<String, String>? custom,
  }) {
    return jsonEncode(_rootNode(
      id: id,
      title: title,
      updatedAt: updatedAt,
      custom: custom,
      children: null,
    ));
  }

  Map<String, Object?> _encodeDocument(DiaryDocument doc) {
    final children = doc.blocks.map(_encodeBlock).toList(growable: false);
    return _rootNode(
      id: doc.id,
      title: doc.title,
      updatedAt: doc.updatedAt,
      custom: doc.custom,
      children: children.isEmpty ? null : children,
    );
  }

  Map<String, Object?> _rootNode({
    required String id,
    required String title,
    required DateTime updatedAt,
    Map<String, String>? custom,
    required List<Map<String, Object?>>? children,
  }) {
    final properties = <String, Object?>{
      for (final entry in (custom ?? const <String, String>{}).entries)
        entry.key: entry.value,
      'id': id,
      'title': title,
      'type': 'doc',
      'updated': _stamp(updatedAt),
    };
    final root = <String, Object?>{
      'ID': id,
      'Spec': spec,
      'Type': 'NodeDocument',
      'Properties': _sorted(properties),
      'Children': ?children,
    };
    return root;
  }

  Map<String, Object?> _encodeBlock(DiaryBlock block) {
    final properties = <String, Object?>{'id': block.id};
    final background = block.background;
    if (background != null) {
      properties['style'] =
          'background-color: var(--b3-font-background$background); '
          '--b3-parent-background: var(--b3-font-background$background);';
    }
    properties['updated'] = _stamp(block.updatedAt);

    final node = <String, Object?>{
      'ID': block.id,
      'Type': switch (block.kind) {
        DiaryBlockKind.paragraph => 'NodeParagraph',
        DiaryBlockKind.heading => 'NodeHeading',
      },
      if (block.kind == DiaryBlockKind.heading) 'HeadingLevel': block.level,
      'Properties': _sorted(properties),
    };
    if (block.text.isNotEmpty) {
      node['Children'] = [
        {'Type': 'NodeText', 'Data': block.text},
      ];
    }
    return node;
  }

  // ---- 解码 ----------------------------------------------------------------

  SyDecodeResult decodeBytes(List<int> bytes) =>
      decode(utf8.decode(bytes));

  SyDecodeResult decode(String source) {
    final root = jsonDecode(source) as Map<String, Object?>;
    final id = root['ID'] as String;
    final props = (root['Properties'] as Map).cast<String, Object?>();
    final date = _parseStamp(id.substring(0, 14));

    final custom = <String, String>{};
    for (final entry in props.entries) {
      if (entry.key.startsWith('custom-')) custom[entry.key] = '${entry.value}';
    }

    final blocks = <DiaryBlock>[];
    final skipped = <String>[];
    for (final node in (root['Children'] as List<Object?>? ?? const [])) {
      final map = (node as Map).cast<String, Object?>();
      final type = map['Type'] as String?;
      if (type != 'NodeParagraph' && type != 'NodeHeading') {
        skipped.add(type ?? 'Unknown');
        continue;
      }
      final blockProps =
          (map['Properties'] as Map?)?.cast<String, Object?>() ?? const {};
      final updated = blockProps['updated'] != null
          ? _parseStamp('${blockProps['updated']}')
          : date;
      blocks.add(DiaryBlock(
        id: (blockProps['id'] ?? map['ID']) as String,
        kind: type == 'NodeHeading'
            ? DiaryBlockKind.heading
            : DiaryBlockKind.paragraph,
        level: (map['HeadingLevel'] as num?)?.toInt(),
        text: _extractText(map['Children'] as List<Object?>?),
        background: _extractBackground('${blockProps['style'] ?? ''}'),
        updatedAt: updated,
      ));
    }

    return SyDecodeResult(
      document: DiaryDocument(
        id: id,
        date: date,
        title: '${props['title'] ?? ''}',
        custom: custom,
        blocks: blocks,
        updatedAt: props['updated'] != null
            ? _parseStamp('${props['updated']}')
            : date,
      ),
      skippedTypes: skipped,
    );
  }

  /// 顺序拼接 NodeText.Data 与 NodeTextMark.TextMarkTextContent；
  /// 子集外行内格式（加粗/链接等）降级为纯文本。
  String _extractText(List<Object?>? children) {
    if (children == null) return '';
    final buffer = StringBuffer();
    for (final raw in children) {
      final node = (raw as Map).cast<String, Object?>();
      switch (node['Type']) {
        case 'NodeText':
          buffer.write('${node['Data'] ?? ''}');
        case 'NodeTextMark':
          buffer.write('${node['TextMarkTextContent'] ?? ''}');
      }
    }
    return buffer.toString();
  }

  int? _extractBackground(String style) {
    final match = _backgroundPattern.firstMatch(style);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  // ---- 公共小工具 -----------------------------------------------------------

  /// 年容器标题，如「2026」。
  static String yearTitle(DateTime date) => '${date.year}';

  /// 月容器标题，如「10 月」（金标准实测）。
  static String monthTitle(DateTime date) => '${date.month} 月';

  /// 日文档标题，如「9日 周五」（金标准实测：无补零）。
  static String dayTitle(DateTime date) =>
      '${date.month}月${date.day}日 ${_weekdays[date.weekday - 1]}';

  // ---- 内部工具 -------------------------------------------------------------

  static String _stamp(DateTime t) => SyStamp.format(t);

  static DateTime _parseStamp(String stamp) => SyStamp.parse(stamp);

  /// Go 风格：map 键按字典序输出（金标准 Properties 键序）。
  static Map<String, Object?> _sorted(Map<String, Object?> source) {
    final keys = source.keys.toList()..sort();
    final ordered = <String, Object?>{};
    for (final key in keys) {
      ordered[key] = source[key];
    }
    return ordered;
  }
}

/// 思源 14 位秒级时间戳 `YYYYMMDDHHMMSS` 与 DateTime 的互转。
class SyStamp {
  const SyStamp._();

  static String format(DateTime t) {
    String p(int v, int w) => v.toString().padLeft(w, '0');
    return '${p(t.year, 4)}${p(t.month, 2)}${p(t.day, 2)}'
        '${p(t.hour, 2)}${p(t.minute, 2)}${p(t.second, 2)}';
  }

  static DateTime parse(String stamp) {
    final s = stamp.trim();
    return DateTime(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
      int.parse(s.substring(8, 10)),
      int.parse(s.substring(10, 12)),
      int.parse(s.substring(12, 14)),
    );
  }
}
