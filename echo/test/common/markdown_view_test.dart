import 'package:echo/src/common/markdown_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = TextStyle(color: Color(0xFFFFFFFF), fontSize: 15, height: 1.35);

/// 取某个文本片段的样式，便于断言行内标记。
TextStyle? _styleOf(List<InlineSpan> spans, String text) {
  for (final span in spans) {
    if (span is TextSpan) {
      if (span.text == text) return span.style;
      final nested = span.children;
      if (nested != null) {
        final hit = _styleOf(nested, text);
        if (hit != null) return hit;
      }
    }
  }
  return null;
}

void main() {
  group('块级解析', () {
    test('标题、段落、列表、引用、代码块、分隔线各自成块', () {
      final blocks = parseMarkdown('''
# 标题一
## 标题二

第一段
第二行

- 甲
- 乙

1. 一
2. 二

> 引用一
> 引用二

```dart
void main() {}
```

---
''');

      expect(blocks.length, 8);
      expect((blocks[0] as MarkdownHeading).level, 1);
      expect((blocks[0] as MarkdownHeading).text, '标题一');
      expect((blocks[1] as MarkdownHeading).level, 2);
      expect((blocks[2] as MarkdownParagraph).text, '第一段\n第二行');
      final bullets = blocks[3] as MarkdownListBlock;
      expect(bullets.ordered, isFalse);
      expect(bullets.items, ['甲', '乙']);
      final ordered = blocks[4] as MarkdownListBlock;
      expect(ordered.ordered, isTrue);
      expect(ordered.items, ['一', '二']);
      expect((blocks[5] as MarkdownQuote).text, '引用一\n引用二');
      expect((blocks[6] as MarkdownCodeBlock).code, 'void main() {}');
    });

    test('未闭合的围栏代码块吃到结尾（流式输出中途）', () {
      final blocks = parseMarkdown('说明\n```\nfinal a = 1;');
      expect(blocks.length, 2);
      expect((blocks[1] as MarkdownCodeBlock).code, 'final a = 1;');
    });

    test('外层围栏比内层长时，内层围栏不会被误判为闭合', () {
      final blocks = parseMarkdown(
        '````\n示例：\n```dart\nprint(1);\n```\n结束\n````\n',
      );
      expect(blocks.length, 1);
      expect(
        (blocks.single as MarkdownCodeBlock).code,
        '示例：\n```dart\nprint(1);\n```\n结束',
      );
    });

    test('纯文本不产生多余块，空文本返回空列表', () {
      expect(parseMarkdown('你好'), hasLength(1));
      expect(parseMarkdown(''), isEmpty);
      expect(parseMarkdown('\n\n'), isEmpty);
    });
  });

  group('行内解析', () {
    test('粗体/斜体/删除线/行内代码各自带样式', () {
      final spans = parseInline(
        '**粗体** *斜体* ~~删~~ `代码`',
        _base,
      );
      expect(_styleOf(spans, '粗体')?.fontWeight, FontWeight.w700);
      expect(_styleOf(spans, '斜体')?.fontStyle, FontStyle.italic);
      expect(
        _styleOf(spans, '删')?.decoration,
        TextDecoration.lineThrough,
      );
      expect(_styleOf(spans, '代码')?.fontFamily, 'monospace');
    });

    test('链接只保留文字并着强调色', () {
      final spans = parseInline('[示例](https://example.com)', _base);
      expect(spans.first.toPlainText(), '示例');
      expect(_styleOf(spans, '示例')?.color, isNotNull);
      expect(spans.first.toPlainText(), isNot(contains('https://')));
    });

    test('未闭合标记与孤立星号按原文保留', () {
      expect(parseInline('**未闭合', _base).first.toPlainText(), '**未闭合');
      expect(parseInline('a * b * c', _base).first.toPlainText(), 'a * b * c');
      expect(parseInline(r'\*不是斜体\*', _base).first.toPlainText(), '*不是斜体*');
    });

    test('标识符里的下划线与算式星号不被当强调', () {
      final spans = parseInline('变量 snake_case_name 与 2*3*4 保持原样', _base);
      expect(spans.map((s) => s.toPlainText()).join(), '变量 snake_case_name 与 2*3*4 保持原样');
      expect(spans.every((s) => s.style?.fontStyle != FontStyle.italic), isTrue);
    });

    test('粗斜体三连星号整体生效，不留裸星号', () {
      final spans = parseInline('***重点***', _base);
      final style = _styleOf(spans, '重点');
      expect(style?.fontWeight, FontWeight.w700);
      expect(style?.fontStyle, FontStyle.italic);
      expect(spans.map((s) => s.toPlainText()).join(), '重点');
    });

    test('反斜杠只转义标点，路径与正则原样保留', () {
      expect(
        parseInline(r'C:\Users\name 与 \d+', _base)
            .map((s) => s.toPlainText())
            .join(),
        r'C:\Users\name 与 \d+',
      );
    });

    test('双下划线不做词内加粗', () {
      final spans = parseInline('foo__bar__baz', _base);
      expect(spans.map((s) => s.toPlainText()).join(), 'foo__bar__baz');
      expect(spans.every((s) => s.style?.fontWeight != FontWeight.w700), isTrue);
    });
  });

  group('MarkdownView', () {
    testWidgets('渲染后纯文本拼接正确，代码块不溢出', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 220,
            child: MarkdownView(
              text: '# 标题\n正文 **加粗** 与 `code`\n'
                  '```\n'
                  'a very long code line that should scroll horizontally\n'
                  '```',
            ),
          ),
        ),
      );
      expect(find.textContaining('标题'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
