import 'sy_id.dart';

/// 日记块种类：Echo 只生成段落与标题（金标准 §5）。
enum DiaryBlockKind { paragraph, heading }

/// 编辑器面向的块模型，与 .sy 中 NodeParagraph/NodeHeading 一一映射。
class DiaryBlock {
  DiaryBlock({
    required this.id,
    this.kind = DiaryBlockKind.paragraph,
    this.level,
    this.text = '',
    this.background,
    this.readonly = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now() {
    if (!SyIdGenerator.isValid(id)) {
      throw ArgumentError.value(id, 'id', '不符合思源 22 位块 ID 规范');
    }
    if (kind == DiaryBlockKind.heading) {
      if (level == null || level! < 1 || level! > 6) {
        throw ArgumentError.value(level, 'level', '标题级别必须为 1..6');
      }
    }
  }

  /// 22 位块 ID，创建后不变（合并块时保留上一块 ID 以保块引用不断裂）。
  final String id;

  /// 段落或标题。
  DiaryBlockKind kind;

  /// 标题级别（kind == heading 时 1..6，Echo 生成 1..3）。
  int? level;

  /// 纯文本，行内换行用 `\n`。
  String text;

  /// 思源块底色色号 1..13（--b3-font-backgroundN），null 表示无底色。
  int? background;

  /// 数据注入块只读。
  bool readonly;

  /// 内容变更时间戳（与 ID 解耦，金标准 §2）。
  DateTime updatedAt;
}

/// 一篇日记，对应思源 NodeDocument。
class DiaryDocument {
  DiaryDocument({
    required this.id,
    required this.date,
    required this.title,
    Map<String, String>? custom,
    List<DiaryBlock>? blocks,
    DateTime? updatedAt,
    this.locked = false,
  })  : custom = custom ?? {},
        blocks = blocks ?? [],
        updatedAt = updatedAt ?? DateTime.now() {
    if (!SyIdGenerator.isValid(id)) {
      throw ArgumentError.value(id, 'id', '不符合思源 22 位块 ID 规范');
    }
  }

  final String id;

  /// 归属自然日，决定导出包内年/月/日三级路由。
  final DateTime date;

  String title;

  /// 文档级 custom-* 属性（weather/mood/sleep/iot-*/schedule-count）。
  final Map<String, String> custom;

  final List<DiaryBlock> blocks;

  DateTime updatedAt;

  /// 导出锁定后只读（导出即归档）。
  bool locked;
}
