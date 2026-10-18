import 'dart:convert';

import 'diary_capsule_items.dart';
import 'diary_model.dart';
import 'sy_id.dart';

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

  static final RegExp _backgroundPattern = RegExp(
    r'var\(--b3-font-background(\d+)\)',
  );

  static const List<String> _weekdays = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  // ---- 编码 ----------------------------------------------------------------

  /// 序列化为 .sy 字节（UTF-8）。
  List<int> encodeBytes(DiaryDocument doc) => utf8.encode(encodeJson(doc));

  /// 序列化为 .sy JSON 字符串（单行紧凑）。
  String encodeJson(DiaryDocument doc) => jsonEncode(_encodeDocument(doc));

  // ---- 导出编码（思源目标结构：超级块 + code 行内标记）---------------------

  /// 导出专用编码：在**扁平草稿**之上叠加思源目标结构。
  ///
  /// 与 [encodeJson] 的分工（见 plan 决策 5）：
  /// * [encodeJson] / [encodeBytes] —— **扁平**，供落盘、撤销快照、导入
  ///   三条链路使用，不含任何 `NodeSuperBlock` 与行内标记；
  /// * [encodeExportJson] / [encodeExportBytes] —— **导出**，供
  ///   [SyZipExporter] 生成思源导入包，叠加：
  ///   1. 文档**首行**一个水平超级块（`Data:'col'`），把文档根 `custom-*`
  ///      里有值的胶囊槽位（[buildDiaryCapsuleItems]）写成带 `code` 行内标记
  ///      的段落（参考样本首行结构）；
  ///   2. 每个「段」（一个 [DiaryBlock.isStamp] 时间戳块 + 其后到下一
  ///      时间戳前的正文块）包成一个垂直超级块（`Data:'row'`），首段即
  ///      带 `code` 标记的时间戳；时间戳块同时携带 [kEchoStampAttr] 块级
  ///      自定义属性——思源不渲染自定义属性，故在思源里保留其 `code`
  ///      原本样式。
  ///
  /// [ids] 为超级块外壳与合成胶囊段的 ID 来源（与仓储同源，避免冲突）。
  String encodeExportJson(DiaryDocument doc, SyIdGenerator ids) =>
      jsonEncode(_encodeExportDocument(doc, ids));

  /// [encodeExportJson] 的 UTF-8 字节形式。
  List<int> encodeExportBytes(DiaryDocument doc, SyIdGenerator ids) =>
      utf8.encode(encodeExportJson(doc, ids));

  /// 编码空容器文档（年/月层级用，无正文块）。
  String encodeContainer({
    required String id,
    required String title,
    required DateTime updatedAt,
    Map<String, String>? custom,
  }) {
    return jsonEncode(
      _rootNode(
        id: id,
        title: title,
        updatedAt: updatedAt,
        custom: custom,
        children: null,
      ),
    );
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
    final properties = <String, Object?>{
      // 块级 custom-*（当前仅时间戳标志）随 Properties 往返；思源忽略自定义属性。
      for (final entry in block.custom.entries) entry.key: entry.value,
      'id': block.id,
    };
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

  // ---- 导出编码内部工具 -----------------------------------------------------

  /// 导出文档结构：首行胶囊 col 超级块（如有值）+ 段分组（row 超级块）。
  Map<String, Object?> _encodeExportDocument(
    DiaryDocument doc,
    SyIdGenerator ids,
  ) {
    final children = <Map<String, Object?>>[];
    final capsule = _capsuleSuperBlock(doc, ids);
    if (capsule != null) children.add(capsule);
    children.addAll(_rowSegments(doc, ids));
    return _rootNode(
      id: doc.id,
      title: doc.title,
      updatedAt: doc.updatedAt,
      custom: doc.custom,
      children: children.isEmpty ? null : children,
    );
  }

  /// 首行水平超级块：把文档根 `custom-*` 中**有值**的胶囊槽位写成带 `code`
  /// 行内标记的段落；五个槽位全空则返回 null（不生成空超级块）。
  ///
  /// 合成段落与外壳的 `updated` 统一取 `doc.updatedAt`（参考样本中胶囊
  /// 各段共享同一 updated，即超级块创建时刻）。
  Map<String, Object?>? _capsuleSuperBlock(
    DiaryDocument doc,
    SyIdGenerator ids,
  ) {
    final items = buildDiaryCapsuleItems(
      doc.custom,
    ).where((item) => item.hasValue).toList(growable: false);
    if (items.isEmpty) return null;
    return _superBlock(
      id: ids.next(),
      layout: 'col',
      updated: doc.updatedAt,
      children: [
        for (final item in items)
          _codeParagraph(
            id: ids.next(),
            text: item.exportText!,
            updated: doc.updatedAt,
          ),
      ],
    );
  }

  /// 段分组：扫描扁平块列表，遇 `isStamp` 即开新段（该 stamp 起、到下一个
  /// stamp 前），每段包成一个垂直超级块。
  ///
  /// 首个 stamp 之前的散块按顶层扁平块输出（防御：新骨架下通常不存在）。
  /// 「超级块内回车自动并入」由派生式分组天然满足——新正文块落点必在本段
  /// 区间内（见 plan 决策 6）。
  List<Map<String, Object?>> _rowSegments(
    DiaryDocument doc,
    SyIdGenerator ids,
  ) {
    final blocks = doc.blocks;
    final out = <Map<String, Object?>>[];
    var i = 0;
    while (i < blocks.length && !blocks[i].isStamp) {
      out.add(_encodeBlock(blocks[i]));
      i++;
    }
    while (i < blocks.length) {
      final start = i;
      i++; // 跳过本段首个 stamp
      while (i < blocks.length && !blocks[i].isStamp) {
        i++;
      }
      out.add(_segmentSuperBlock(blocks.sublist(start, i), ids));
    }
    return out;
  }

  /// 单段垂直超级块：首块（stamp）用 `code` 行内标记，其余正文块沿用扁平
  /// 编码规则；外壳 `updated` 取 stamp 的 `updatedAt`（段创建时刻）。
  Map<String, Object?> _segmentSuperBlock(
    List<DiaryBlock> segment,
    SyIdGenerator ids,
  ) {
    final stamp = segment.first;
    return _superBlock(
      id: ids.next(),
      layout: 'row',
      updated: stamp.updatedAt,
      children: [
        // stamp 块携带 custom-echo-stamp 块级属性（思源忽略，故导出后在
        // 思源里保留其 code 原本样式）。
        _codeParagraph(
          id: stamp.id,
          text: stamp.text,
          updated: stamp.updatedAt,
          custom: stamp.custom,
        ),
        for (final block in segment.skip(1)) _encodeBlock(block),
      ],
    );
  }

  /// 组装 `NodeSuperBlock`（含开/布局/关三个标记子节点，参考样本结构）。
  Map<String, Object?> _superBlock({
    required String id,
    required String layout,
    required DateTime updated,
    required List<Map<String, Object?>> children,
  }) {
    return {
      'ID': id,
      'Type': 'NodeSuperBlock',
      'Properties': _sorted({'id': id, 'updated': _stamp(updated)}),
      'Children': [
        const {'Type': 'NodeSuperBlockOpenMarker'},
        {'Type': 'NodeSuperBlockLayoutMarker', 'Data': layout},
        ...children,
        const {'Type': 'NodeSuperBlockCloseMarker'},
      ],
    };
  }

  /// 带 `code` 行内标记的段落：零宽空格 `\u200b` 包裹标记文本
  /// （思源自带 Edit 光标锚点，参考样本一致）。
  Map<String, Object?> _codeParagraph({
    required String id,
    required String text,
    required DateTime updated,
    Map<String, String>? custom,
  }) {
    final properties = <String, Object?>{
      for (final entry in (custom ?? const <String, String>{}).entries)
        entry.key: entry.value,
      'id': id,
      'updated': _stamp(updated),
    };
    return {
      'ID': id,
      'Type': 'NodeParagraph',
      'Properties': _sorted(properties),
      'Children': [
        const {'Type': 'NodeText', 'Data': '\u200b'},
        {
          'Type': 'NodeTextMark',
          'TextMarkType': 'code',
          'TextMarkTextContent': text,
        },
        const {'Type': 'NodeText', 'Data': '\u200b'},
      ],
    };
  }

  // ---- 解码 ----------------------------------------------------------------

  SyDecodeResult decodeBytes(List<int> bytes) => decode(utf8.decode(bytes));

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
      // 块级 custom-*（当前仅时间戳标志）回读，供 App 端识别只读胶囊块。
      final blockCustom = <String, String>{};
      for (final entry in blockProps.entries) {
        if (entry.key.startsWith('custom-')) {
          blockCustom[entry.key] = '${entry.value}';
        }
      }
      blocks.add(
        DiaryBlock(
          id: (blockProps['id'] ?? map['ID']) as String,
          kind: type == 'NodeHeading'
              ? DiaryBlockKind.heading
              : DiaryBlockKind.paragraph,
          level: (map['HeadingLevel'] as num?)?.toInt(),
          text: _extractText(map['Children'] as List<Object?>?),
          background: _extractBackground('${blockProps['style'] ?? ''}'),
          custom: blockCustom,
          updatedAt: updated,
        ),
      );
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
