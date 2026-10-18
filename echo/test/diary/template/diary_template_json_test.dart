import 'dart:math';

import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/template/daily_default_template.dart';
import 'package:echo/src/diary/template/diary_template_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validJson = '''
{
  "id": "daily-default-v2",
  "blocks": [
    { "type": "paragraph", "background": 12 },
    { "type": "paragraph" }
  ]
}
''';

  group('DiaryTemplateSpec.fromJson', () {
    test('概述段 + 空正文段骨架解析为 2 个声明（首块带 12 号底色）', () {
      final spec = DiaryTemplateSpec.fromJson(validJson);
      expect(spec.id, 'daily-default-v2');
      expect(spec.blocks, hasLength(2));
      expect(spec.blocks.first.type, DiaryTemplateBlockType.paragraph);
      expect(spec.blocks.first.level, isNull);
      expect(spec.blocks.first.text, isEmpty);
      expect(spec.blocks.first.background, 12);
      expect(spec.blocks.last.type, DiaryTemplateBlockType.paragraph);
      expect(spec.blocks.last.text, isEmpty);
      expect(spec.blocks.last.background, isNull);
    });

    test('paragraph 可带预填文本，缺省为空串', () {
      final spec = DiaryTemplateSpec.fromJson(
        '{"id":"t","blocks":[{"type":"paragraph","text":"预置"}]}',
      );
      expect(spec.blocks.single.text, '预置');
      expect(spec.blocks.single.background, isNull);
    });

    test('paragraph 可带 1..13 底色号', () {
      final spec = DiaryTemplateSpec.fromJson(
        '{"id":"t","blocks":[{"type":"paragraph","background":7}]}',
      );
      expect(spec.blocks.single.background, 7);
    });

    test('heading 解析 level 与预填标题', () {
      final spec = DiaryTemplateSpec.fromJson(
        '{"id":"t","blocks":[{"type":"heading","level":2,"text":"今天"}]}',
      );
      expect(spec.blocks.single.type, DiaryTemplateBlockType.heading);
      expect(spec.blocks.single.level, 2);
      expect(spec.blocks.single.text, '今天');
    });

    for (final bad in [
      ['id 缺失', '{"blocks":[{"type":"paragraph"}]}'],
      ['id 空白', '{"id":"  ","blocks":[{"type":"paragraph"}]}'],
      ['blocks 缺失', '{"id":"t"}'],
      ['blocks 空', '{"id":"t","blocks":[]}'],
      ['块类型非法', '{"id":"t","blocks":[{"type":"quote"}]}'],
      // 旧 data 快照块已退役：schema 仅认 heading/paragraph。
      ['data 块已退役', '{"id":"t","blocks":[{"type":"data","role":1}]}'],
      ['heading 缺 level', '{"id":"t","blocks":[{"type":"heading"}]}'],
      [
        'heading level 越界',
        '{"id":"t","blocks":[{"type":"heading","level":7}]}',
      ],
      [
        'paragraph 带 level',
        '{"id":"t","blocks":[{"type":"paragraph","level":1}]}',
      ],
      [
        'background 越界',
        '{"id":"t","blocks":[{"type":"paragraph","background":14}]}',
      ],
      [
        'background 非整数',
        '{"id":"t","blocks":[{"type":"paragraph","background":"12"}]}',
      ],
      ['块非对象', '{"id":"t","blocks":[1]}'],
      ['JSON 语法错误', '{not json'],
      ['根是数组', '[]'],
    ]) {
      test('非法输入抛 FormatException：${bad[0]}', () {
        expect(
          () => DiaryTemplateSpec.fromJson(bad[1]),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });

  group('DailyDefaultTemplate.instantiate', () {
    final date = DateTime(2026, 10, 10);

    DiaryDocument build() {
      final spec = DiaryTemplateSpec.fromJson(validJson);
      final template = DailyDefaultTemplate(spec: spec);
      final ids = SyIdGenerator(random: Random(7), now: () => date);
      return template.instantiate(date, ids);
    }

    test('骨架：确定性日容器 ID + 金标准标题 + 概述段(12 号底色) + 空正文段', () {
      final doc = build();
      expect(doc.id, SyIdGenerator.dayContainer(date));
      expect(doc.title, '10月10日 周六');
      expect(doc.blocks, hasLength(2));
      expect(doc.blocks.first.kind, DiaryBlockKind.paragraph);
      expect(doc.blocks.first.level, isNull);
      expect(doc.blocks.first.text, isEmpty);
      expect(doc.blocks.first.background, 12); // 「一句话概述今日」段
      expect(doc.blocks.last.kind, DiaryBlockKind.paragraph);
      expect(doc.blocks.last.text, isEmpty);
      expect(doc.blocks.last.background, isNull); // 空正文段无底色
    });

    test('所有块 ID 合 22 位规范', () {
      final doc = build();
      expect(doc.blocks.every((b) => SyIdGenerator.isValid(b.id)), isTrue);
    });

    test('同日可重复实例化：每次都产出概述段 + 空正文段骨架', () {
      final spec = DiaryTemplateSpec.fromJson(validJson);
      final t = DailyDefaultTemplate(spec: spec);
      final a = t.instantiate(date, SyIdGenerator(random: Random(1)));
      final b = t.instantiate(date, SyIdGenerator(random: Random(2)));
      expect(a.blocks, hasLength(2));
      expect(b.blocks, hasLength(2));
      expect(a.blocks.first.background, 12);
      expect(b.blocks.first.background, 12);
      // 容器 ID 确定（同一自然日同一路径）；块 ID 随机故不同。
      expect(a.id, b.id);
    });

    test('模板 id 不写入文档 custom', () {
      final doc = build();
      expect(doc.custom, isEmpty);
      expect(doc.custom.containsKey('custom-echo-template'), isFalse);
    });
  });
}
