import 'dart:convert';

/// 模板块种类（Echo 内部模板 schema，非思源格式）。
enum DiaryTemplateBlockType { heading, paragraph, data }

/// 模板中的单个块声明。
///
/// - [DiaryTemplateBlockType.heading]：[level] 必填 1..6，[text] 为预填标题；
/// - [DiaryTemplateBlockType.paragraph]：普通段落，[text] 默认空；
/// - [DiaryTemplateBlockType.data]：data 快照块，[role] 必填正整数，
///   [placeholder] 为数据全不可用时的占位文案，实例化后 readonly+底色 3。
class DiaryTemplateBlockSpec {
  const DiaryTemplateBlockSpec({
    required this.type,
    this.level,
    this.text = '',
    this.role,
    this.placeholder = '',
  });

  final DiaryTemplateBlockType type;
  final int? level;
  final String text;
  final int? role;
  final String placeholder;
}

/// 声明式日模板（assets/diary/templates/*.json 的内存表示）。
class DiaryTemplateSpec {
  const DiaryTemplateSpec({required this.id, required this.blocks});

  /// 模板稳定标识（M4 不写入文档；M5 可存 meta 追溯成稿来源）。
  final String id;

  final List<DiaryTemplateBlockSpec> blocks;

  /// 解析模板 JSON；任何不符合 schema 的输入抛 [FormatException]。
  factory DiaryTemplateSpec.fromJson(String source) {
    final Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('模板 JSON 非法：${e.message}');
    }
    if (raw is! Map<String, Object?>) {
      throw const FormatException('模板根必须是 JSON 对象');
    }

    final id = raw['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('模板 id 必须是非空字符串');
    }

    final rawBlocks = raw['blocks'];
    if (rawBlocks is! List<Object?> || rawBlocks.isEmpty) {
      throw const FormatException('模板 blocks 必须是非空数组');
    }

    final blocks = <DiaryTemplateBlockSpec>[];
    for (var i = 0; i < rawBlocks.length; i++) {
      final entry = rawBlocks[i];
      if (entry is! Map<String, Object?>) {
        throw FormatException('第 $i 个块必须是 JSON 对象');
      }
      final typeStr = entry['type'];
      final type = switch (typeStr) {
        'heading' => DiaryTemplateBlockType.heading,
        'paragraph' => DiaryTemplateBlockType.paragraph,
        'data' => DiaryTemplateBlockType.data,
        _ => throw FormatException(
            '第 $i 个块 type 非法：$typeStr（仅 heading/paragraph/data）'),
      };

      int? readOptInt(String key) {
        final v = entry[key];
        if (v == null) return null;
        if (v is! int) throw FormatException('第 $i 个块 $key 必须是整数');
        return v;
      }

      final level = readOptInt('level');
      if (type == DiaryTemplateBlockType.heading) {
        if (level == null || level < 1 || level > 6) {
          throw FormatException('第 $i 个 heading 块必须带 1..6 的 level');
        }
      } else if (level != null) {
        throw FormatException('第 $i 个非 heading 块不得带 level');
      }

      final role = readOptInt('role');
      if (type == DiaryTemplateBlockType.data) {
        if (role == null || role < 1) {
          throw FormatException('第 $i 个 data 块必须带正整数 role');
        }
      } else if (role != null) {
        throw FormatException('第 $i 个非 data 块不得带 role');
      }

      final text = entry['text'] ?? '';
      if (text is! String) {
        throw FormatException('第 $i 个块 text 必须是字符串');
      }
      final placeholder = entry['placeholder'] ?? '';
      if (placeholder is! String) {
        throw FormatException('第 $i 个块 placeholder 必须是字符串');
      }

      blocks.add(DiaryTemplateBlockSpec(
        type: type,
        level: level,
        text: text,
        role: role,
        placeholder: placeholder,
      ));
    }

    return DiaryTemplateSpec(id: id.trim(), blocks: List.unmodifiable(blocks));
  }
}
