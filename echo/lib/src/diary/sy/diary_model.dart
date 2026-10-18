import 'sy_id.dart';

/// 日记块种类：Echo 只生成段落与标题（金标准 §5）。
enum DiaryBlockKind { paragraph, heading }

/// 时间戳块的**块级**自定义属性键（App 独有解析标志）：
/// 带该属性的段落即「时间戳块」，App 内渲染为只读胶囊 chip，
/// 且导出时按段包进垂直超级块、首段加 `code` 行内标记。
///
/// 思源不渲染自定义属性，故导出后该块在思源里保留其原本（`code`）样式。
const String kEchoStampAttr = 'custom-echo-stamp';

/// 时间戳块的文本格式：`yyyy-MM-dd HH:mm`（年月日时分，用户原话）。
///
/// 与参考样本（带秒 `yyyy-MM-dd HH:mm:ss`）不同——如后续要秒仅改此处。
/// 成稿（[DiaryComposer]）与「首次输入即重打点」（编辑器控制器）共用。
String formatDiaryStamp(DateTime t) {
  String p(int value, int width) => value.toString().padLeft(width, '0');
  return '${p(t.year, 4)}-${p(t.month, 2)}-${p(t.day, 2)} '
      '${p(t.hour, 2)}:${p(t.minute, 2)}';
}

/// 时间戳「段」判定工具（[DiaryBlock.isStamp] 之上的纯函数集合）。
///
/// 段 = 某个时间戳块与其后、下一个时间戳块之前的全部块。段是否「有内容」
/// 决定该时间戳是否落盘（用户裁定：空段的时间戳只存在于 UI）。
class DiaryStamp {
  const DiaryStamp._();

  /// 最后一个时间戳块的下标；无时间戳返回 -1。
  static int lastIndex(List<DiaryBlock> blocks) {
    for (var i = blocks.length - 1; i >= 0; i--) {
      if (blocks[i].isStamp) return i;
    }
    return -1;
  }

  /// [index] 之后（同属该段）是否存在可判定为「用户内容」的块。
  ///
  /// 只认非时间戳块的非空文本；空块/纯空白不计。
  static bool segmentHasContent(List<DiaryBlock> blocks, int index) {
    for (var i = index + 1; i < blocks.length; i++) {
      if (blocks[i].isStamp) break;
      if (blocks[i].text.trim().isNotEmpty) return true;
    }
    return false;
  }

  /// 最后一个时间戳是否「待启用」：存在时间戳但该段尚无任何用户内容。
  ///
  /// 待启用 = 不落盘、且用户首次输入时需重打点为当前时间。
  static bool isPending(List<DiaryBlock> blocks) {
    final index = lastIndex(blocks);
    return index >= 0 && !segmentHasContent(blocks, index);
  }
}

/// 编辑器面向的块模型，与 .sy 中 NodeParagraph/NodeHeading 一一映射。
class DiaryBlock {
  DiaryBlock({
    required this.id,
    this.kind = DiaryBlockKind.paragraph,
    this.level,
    this.text = '',
    this.background,
    Map<String, String>? custom,
    DateTime? updatedAt,
  }) : custom = custom ?? {},
       updatedAt = updatedAt ?? DateTime.now() {
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

  /// 块级 custom-* 属性（当前仅时间戳标志 [kEchoStampAttr]）。
  /// 随 `.sy` 块 `Properties` 往返，导出时一并携带；思源忽略自定义属性。
  final Map<String, String> custom;

  /// 是否为时间戳块（App 独有解析：渲染为只读胶囊 chip，不参与正文编辑）。
  bool get isStamp => custom.containsKey(kEchoStampAttr);

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
  }) : custom = custom ?? {},
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

  /// 文档级 custom-* 属性（2026-10-18 起：custom-iot-temp/humidity、
  /// custom-weather、custom-schedule-count、custom-mood 等）。由编辑页
  /// 胶囊行读取呈现。
  final Map<String, String> custom;

  final List<DiaryBlock> blocks;

  DateTime updatedAt;

  /// 导出锁定后只读（导出即归档）。
  bool locked;
}
