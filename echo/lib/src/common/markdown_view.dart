import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 聊天气泡用的轻量 Markdown 渲染。
///
/// 只覆盖对话里常见的子集：标题、段落、无序/有序列表、引用、围栏代码块、
/// 分隔线，以及行内 `**粗体**`、`*斜体*`/`_斜体_`、`` `代码` ``、`~~删除线~~`、
/// `[文字](链接)`。刻意不引第三方包：一来离线可用，二来排版可以直接沿用
/// 日记正文的字号/行高口径（见 `diary/editor/block_widget.dart` 的
/// `blockTextStyle`，段落 16/1.55，标题按层级放大）。
///
/// 链接只做样式标记（项目未引入系统浏览器能力），不响应点按。
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.text,
    this.style,
    this.spacing = 8,
    this.selectable = false,
  });

  final String text;

  /// 段落基准样式；标题/代码/引用都从它派生。
  final TextStyle? style;

  /// 块与块之间的竖向间距。
  final double spacing;

  /// 长按可选取文字（聊天气泡里需要复制时打开）。
  final bool selectable;

  static const TextStyle _defaultStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 15,
    height: 1.35,
  );

  @override
  Widget build(BuildContext context) {
    final base = style ?? _defaultStyle;
    final blocks = parseMarkdown(text);
    if (blocks.isEmpty) return const SizedBox.shrink();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == blocks.length - 1 ? 0 : spacing,
            ),
            child: _buildBlock(blocks[i], base),
          ),
      ],
    );
    // 用 SelectionArea 包整块，才能跨段/跨行连续选取。
    return selectable
        ? SourceSelectionArea(
            resolveCopy: (selected) =>
                resolveMarkdownSelection(text, selected) ?? text,
            child: content,
          )
        : content;
  }

  Widget _buildBlock(MarkdownBlock block, TextStyle base) {
    switch (block) {
      case MarkdownParagraph(:final text):
        return _rich(text, base);
      case MarkdownHeading(:final level, :final text):
        final scale = switch (level) {
          1 => 1.6,
          2 => 1.35,
          3 => 1.18,
          _ => 1.05,
        };
        final size = (base.fontSize ?? 15) * scale;
        return _rich(
          text,
          base.copyWith(
            fontSize: size,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        );
      case MarkdownCodeBlock(:final code):
        return _CodeBlock(code: code, base: base);
      case MarkdownQuote(:final text):
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.tone2, width: 2)),
          ),
          child: _rich(text, base.copyWith(color: AppColors.textMuted)),
        );
      case MarkdownDivider():
        return Container(height: 1, color: AppColors.tone1);
      case MarkdownListBlock(:final items, :final ordered, :final start):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  top: i == 0 ? 0 : spacing * 0.5,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: ordered
                          ? 14.0 + 7.0 * '${start + i}'.length
                          : 14,
                      child: Text(
                        ordered ? '${start + i}.' : '•',
                        style: base.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                    Expanded(child: _rich(items[i], base)),
                  ],
                ),
              ),
          ],
        );
    }
  }

  Widget _rich(String source, TextStyle base) {
    final span = TextSpan(children: parseInline(source, base));
    return Text.rich(span);
  }
}

/// 可跨段选取的区域，复制时把选区还原成**原文**（含 Markdown 标记与换行）。
class SourceSelectionArea extends StatefulWidget {
  const SourceSelectionArea({
    super.key,
    required this.resolveCopy,
    required this.child,
  });

  /// 把选区里的渲染文本还原成源文本；拿不到匹配时由调用方给兜底。
  final String Function(String selectedPlainText) resolveCopy;
  final Widget child;

  @override
  State<SourceSelectionArea> createState() => _SourceSelectionAreaState();
}

class _SourceSelectionAreaState extends State<SourceSelectionArea> {
  String _selected = '';

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) {
        _selected = content?.plainText ?? '';
      },
      contextMenuBuilder: (context, state) {
        // 只替换「复制」的行为，全选/分享等系统项照旧保留。
        final items = [
          for (final item in state.contextMenuButtonItems)
            if (item.type == ContextMenuButtonType.copy)
              ContextMenuButtonItem(
                label: '复制',
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: widget.resolveCopy(_selected)),
                  );
                  state.hideToolbar();
                },
              )
            else
              item,
        ];
        if (items.isEmpty) {
          items.add(
            ContextMenuButtonItem(
              label: '复制',
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: widget.resolveCopy(_selected)),
                );
                state.hideToolbar();
              },
            ),
          );
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: items,
        );
      },
      child: widget.child,
    );
  }
}

/// 纯文本气泡：把选区扩展到整行，复制这些行的原文；找不到时返回 null。
String? resolvePlainSelection(String source, String selected) {
  final sel = selected.trim();
  if (sel.isEmpty) return null;
  final normalized = source.replaceAll('\r\n', '\n');
  final idx = normalized.indexOf(sel);
  if (idx < 0) return null;
  final startLine = '\n'.allMatches(normalized.substring(0, idx)).length;
  final endOffset = idx + sel.length;
  final endLine =
      '\n'.allMatches(normalized.substring(0, endOffset - 1)).length + 1;
  final lines = normalized.split('\n');
  final end = endLine.clamp(0, lines.length);
  final begin = startLine.clamp(0, end);
  return lines.sublist(begin, end).join('\n');
}

/// Markdown 气泡：按渲染单元（标题/段落一行/列表项/代码行）定位选区，
/// 再复制这些单元对应的源文本行。
String? resolveMarkdownSelection(String source, String selected) {
  final sel = selected.trim();
  if (sel.isEmpty) return null;
  final normalized = source.replaceAll('\r\n', '\n');
  final blocks = parseMarkdown(normalized);
  if (blocks.isEmpty) return null;

  // 各单元渲染后的纯文本按出现顺序拼接，与选区文本对齐；块内换行保留。
  final units = <_RenderedUnit>[];
  final joined = StringBuffer();
  for (final block in blocks) {
    final lineUnits = _renderedUnits(block);
    for (var i = 0; i < lineUnits.length; i++) {
      final unit = lineUnits[i];
      // 同一块内的多行在渲染时是一个 Text，选区里带 `\n`。
      final text = i == lineUnits.length - 1 ? unit.text : '${unit.text}\n';
      units.add(
        _RenderedUnit(
          start: joined.length,
          end: joined.length + text.length,
          line: unit.line,
        ),
      );
      joined.write(text);
    }
  }
  final haystack = joined.toString();
  final matches = sel.allMatches(haystack).toList(growable: false);
  if (matches.isEmpty) return null;

  final lines = normalized.split('\n');
  String? result;
  (int, int)? resultRange;
  for (final match in matches) {
    final hits = units
        .where((unit) => unit.start < match.end && unit.end > match.start)
        .toList(growable: false);
    if (hits.isEmpty) return null;
    final begin = hits.first.line.clamp(0, lines.length);
    final finish = (hits.last.line + 1).clamp(begin, lines.length);
    // 选区文本在消息里出现多次且指向不同行时，宁可退回兜底也不复制错行。
    if (resultRange != null && resultRange != (begin, finish)) return null;
    resultRange = (begin, finish);
    result = lines.sublist(begin, finish).join('\n');
  }
  return result;
}

class _RenderedUnit {
  const _RenderedUnit({
    required this.start,
    required this.end,
    required this.line,
  });

  final int start;
  final int end;
  final int line;
}

class _TextUnit {
  const _TextUnit(this.text, this.line);

  final String text;
  final int line;
}

/// 一个块拆成可按行定位的渲染单元。
List<_TextUnit> _renderedUnits(MarkdownBlock block) {
  String plain(String text) => parseInline(text, _plainBaseStyle)
      .map((span) => span is TextSpan ? span.toPlainText() : '')
      .join();

  switch (block) {
    case MarkdownParagraph(:final text, :final startLine):
      final parts = plain(text).split('\n');
      return [
        for (var i = 0; i < parts.length; i++) _TextUnit(parts[i], startLine + i),
      ];
    case MarkdownHeading(:final text, :final startLine):
      return [_TextUnit(plain(text), startLine)];
    case MarkdownQuote(:final text, :final startLine):
      final parts = plain(text).split('\n');
      return [
        for (var i = 0; i < parts.length; i++) _TextUnit(parts[i], startLine + i),
      ];
    case MarkdownCodeBlock(:final code, :final startLine):
      final parts = code.split('\n');
      return [
        // 代码内容从围栏下一行开始。
        for (var i = 0; i < parts.length; i++)
          _TextUnit(parts[i], startLine + 1 + i),
      ];
    case MarkdownListBlock(
        :final items,
        :final ordered,
        :final start,
        :final startLine,
      ):
      return [
        for (var i = 0; i < items.length; i++)
          _TextUnit(
            '${ordered ? '${start + i}.' : '•'}${plain(items[i])}',
            startLine + i,
          ),
      ];
    case MarkdownDivider():
      return const [];
  }
}

/// 围栏代码块：等宽字体 + 底色，长行软换行。
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.base});

  final String code;
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    final style = base.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier New'],
      fontSize: (base.fontSize ?? 15) - 2,
      height: 1.45,
      color: AppColors.textPrimary,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.tone1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(code, style: style),
    );
  }
}

// ---------------------------------------------------------------------------
// 块级解析
// ---------------------------------------------------------------------------

/// 选区还原时算渲染纯文本用的基准样式（样式不影响文字内容）。
const TextStyle _plainBaseStyle = TextStyle(fontSize: 15, height: 1.35);

/// Markdown 块。
sealed class MarkdownBlock {
  const MarkdownBlock({this.startLine = 0, this.endLine = 0});

  /// 块在源文本里占的行范围（`[startLine, endLine)`），复制原文时用。
  final int startLine;
  final int endLine;
}

class MarkdownParagraph extends MarkdownBlock {
  const MarkdownParagraph(
    this.text, {
    super.startLine,
    super.endLine,
  });

  final String text;
}

class MarkdownHeading extends MarkdownBlock {
  const MarkdownHeading(
    this.level,
    this.text, {
    super.startLine,
    super.endLine,
  });

  final int level;
  final String text;
}

class MarkdownCodeBlock extends MarkdownBlock {
  const MarkdownCodeBlock(this.code, {super.startLine, super.endLine});

  final String code;
}

class MarkdownQuote extends MarkdownBlock {
  const MarkdownQuote(this.text, {super.startLine, super.endLine});

  final String text;
}

class MarkdownListBlock extends MarkdownBlock {
  const MarkdownListBlock({
    required this.items,
    required this.ordered,
    this.start = 1,
    super.startLine,
    super.endLine,
  });

  final List<String> items;
  final bool ordered;
  final int start;
}

class MarkdownDivider extends MarkdownBlock {
  const MarkdownDivider({super.startLine, super.endLine});
}

final RegExp _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _orderedItemPattern = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
final RegExp _bulletItemPattern = RegExp(r'^\s*[-*+]\s+(.*)$');
final RegExp _dividerPattern = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
final RegExp _fencePattern = RegExp(r'^\s*(?:```|~~~)');
final RegExp _fenceOpenPattern = RegExp(r'^\s*(`{3,}|~{3,})');

/// 把整段文本拆成块。空文本返回空列表。
List<MarkdownBlock> parseMarkdown(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MarkdownBlock>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      i++;
      continue;
    }

    // 围栏代码块：未闭合时一直吃到结尾（流式输出中途很常见）。
    // 闭合行必须同字符、长度不短于开启围栏，且整行只有围栏。
    final fence = _fenceOpenPattern.firstMatch(trimmed);
    if (fence != null) {
      final startLine = i;
      final marker = fence.group(1)!;
      final closer = RegExp(
        '^\\s*${RegExp.escape(marker[0])}{${marker.length},}\\s*\$',
      );
      i++;
      final code = <String>[];
      while (i < lines.length && !closer.hasMatch(lines[i])) {
        code.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      blocks.add(
        MarkdownCodeBlock(
          code.join('\n'),
          startLine: startLine,
          endLine: i,
        ),
      );
      continue;
    }

    final heading = _headingPattern.firstMatch(trimmed);
    if (heading != null) {
      blocks.add(
        MarkdownHeading(
          heading.group(1)!.length,
          heading.group(2)!.trim(),
          startLine: i,
          endLine: i + 1,
        ),
      );
      i++;
      continue;
    }

    if (_dividerPattern.hasMatch(trimmed)) {
      blocks.add(MarkdownDivider(startLine: i, endLine: i + 1));
      i++;
      continue;
    }

    if (trimmed.startsWith('>')) {
      final startLine = i;
      final quoted = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        final content = lines[i].trim();
        quoted.add(content.substring(1).trimLeft());
        i++;
      }
      blocks.add(
        MarkdownQuote(
          quoted.join('\n'),
          startLine: startLine,
          endLine: i,
        ),
      );
      continue;
    }

    final ordered = _orderedItemPattern.firstMatch(line);
    final bullet = ordered == null ? _bulletItemPattern.firstMatch(line) : null;
    if (ordered != null || bullet != null) {
      final startLine = i;
      final items = <String>[];
      final isOrdered = ordered != null;
      var start = 1;
      while (i < lines.length) {
        final current = lines[i];
        if (_fencePattern.hasMatch(current.trim()) ||
            _headingPattern.hasMatch(current.trim()) ||
            current.trim().startsWith('>') ||
            current.trim().isEmpty ||
            _dividerPattern.hasMatch(current.trim())) {
          break;
        }
        final nextOrdered = _orderedItemPattern.firstMatch(current);
        final nextBullet = _bulletItemPattern.firstMatch(current);
        if (isOrdered) {
          if (nextOrdered == null) break;
          if (items.isEmpty) start = int.tryParse(nextOrdered.group(1)!) ?? 1;
          items.add(nextOrdered.group(2)!.trim());
        } else {
          if (nextBullet == null) break;
          items.add(nextBullet.group(1)!.trim());
        }
        i++;
      }
      blocks.add(
        MarkdownListBlock(
          items: items,
          ordered: isOrdered,
          start: start,
          startLine: startLine,
          endLine: i,
        ),
      );
      continue;
    }

    // 普通段落：连续非空行合成一段，行间保留换行。
    final startLine = i;
    final paragraph = <String>[];
    while (i < lines.length) {
      final current = lines[i];
      final currentTrimmed = current.trim();
      if (currentTrimmed.isEmpty ||
          _fencePattern.hasMatch(currentTrimmed) ||
          _headingPattern.hasMatch(currentTrimmed) ||
          currentTrimmed.startsWith('>') ||
          _dividerPattern.hasMatch(currentTrimmed) ||
          _orderedItemPattern.hasMatch(current) ||
          _bulletItemPattern.hasMatch(current)) {
        break;
      }
      paragraph.add(currentTrimmed);
      i++;
    }
    blocks.add(
      MarkdownParagraph(
        paragraph.join('\n'),
        startLine: startLine,
        endLine: i,
      ),
    );
  }

  return blocks;
}

// ---------------------------------------------------------------------------
// 行内解析
// ---------------------------------------------------------------------------

/// 把一行文本解析成带样式的 span；支持一层层嵌套的粗体/斜体/删除线。
List<InlineSpan> parseInline(String text, TextStyle base, {int depth = 0}) {
  if (text.isEmpty) return const [];
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: base));
    buffer.clear();
  }

  var i = 0;
  while (i < text.length) {
    final char = text[i];

    // 反斜杠转义：只吃 ASCII 标点，避免把 `C:\Users`、`\d+` 这类
    // 路径/正则的反斜杠吞掉。
    if (char == '\\' && i + 1 < text.length && _isPunctuation(text[i + 1])) {
      buffer.write(text[i + 1]);
      i += 2;
      continue;
    }

    // 行内代码优先级最高：内容按原样展示。
    if (char == '`') {
      final end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        spans.add(
          TextSpan(
            text: text.substring(i + 1, end),
            style: base.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Courier New'],
              fontSize: (base.fontSize ?? 15) - 1,
              backgroundColor: AppColors.tone1,
            ),
          ),
        );
        i = end + 1;
        continue;
      }
    }

    // 链接：[文字](url)。同样受递归深度约束，防止嵌套 `[` 爆栈。
    if (char == '[' && depth < 6) {
      final close = text.indexOf('](', i + 1);
      if (close > i + 1) {
        final urlEnd = text.indexOf(')', close + 2);
        if (urlEnd > close) {
          flush();
          final label = text.substring(i + 1, close);
          spans.addAll(
            parseInline(
              label,
              base.copyWith(
                color: AppColors.accentBlue,
                decoration: TextDecoration.underline,
              ),
              depth: depth + 1,
            ),
          );
          i = urlEnd + 1;
          continue;
        }
      }
    }

    if (depth < 6) {
      final styled = _matchPaired(text, i);
      if (styled != null) {
        flush();
        spans.addAll(
          parseInline(
            styled.inner,
            styled.apply(base),
            depth: depth + 1,
          ),
        );
        i = styled.end + styled.marker.length;
        continue;
      }
    }

    buffer.write(char);
    i++;
  }

  flush();
  return spans;
}

class _PairedMark {
  const _PairedMark({
    required this.marker,
    required this.inner,
    required this.end,
    required this.apply,
  });

  final String marker;
  final String inner;

  /// 结束标记的起始下标。
  final int end;

  /// 把强调样式叠加到基准样式上。
  final TextStyle Function(TextStyle base) apply;
}

final List<(String, TextStyle Function(TextStyle))> _pairedMarkers = [
  (
    '***',
    (base) => base.copyWith(
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.italic,
    ),
  ),
  ('**', (base) => base.copyWith(fontWeight: FontWeight.w700)),
  ('__', (base) => base.copyWith(fontWeight: FontWeight.w700)),
  (
    '~~',
    (base) => base.copyWith(decoration: TextDecoration.lineThrough),
  ),
  ('*', (base) => base.copyWith(fontStyle: FontStyle.italic)),
  ('_', (base) => base.copyWith(fontStyle: FontStyle.italic)),
];

_PairedMark? _matchPaired(String text, int start) {
  for (final (marker, apply) in _pairedMarkers) {
    if (!text.startsWith(marker, start)) continue;
    // 强调标记不能吞掉空白：`a * b * c` 不当斜体处理。
    if (start + marker.length >= text.length) continue;
    if (_isSpace(text[start + marker.length])) continue;
    final end = text.indexOf(marker, start + marker.length);
    if (end <= start + marker.length) continue;
    if (_isSpace(text[end - 1])) continue;
    // 单字符星号/下划线必须是"词边界"：`snake_case`、`2*3*4` 不当强调。
    // 双下划线按 CommonMark 同样不允许词内加粗（`foo__bar__baz`）。
    if (marker.length == 1 || marker.startsWith('_')) {
      final before = start == 0 ? '' : text[start - 1];
      final after = end + marker.length < text.length
          ? text[end + marker.length]
          : '';
      if (_isWordChar(before) || _isWordChar(after)) continue;
    }
    return _PairedMark(
      marker: marker,
      inner: text.substring(start + marker.length, end),
      end: end,
      apply: apply,
    );
  }
  return null;
}

bool _isSpace(String char) => char.trim().isEmpty;

// 下划线也算"词内"：`foo__bar__baz` 里的第二个 `_` 不该当强调起点。
final RegExp _wordCharPattern = RegExp(r'[A-Za-z0-9_]');

bool _isWordChar(String char) => _wordCharPattern.hasMatch(char);

final RegExp _punctuationPattern = RegExp(r'''[!-/:-@\[-`{-~]''');

bool _isPunctuation(String char) => _punctuationPattern.hasMatch(char);
