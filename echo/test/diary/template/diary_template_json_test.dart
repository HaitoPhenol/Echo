import 'dart:math';

import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/template/daily_default_template.dart';
import 'package:echo/src/diary/template/diary_template_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validJson = '''
{
  "id": "daily-default-v1",
  "blocks": [
    { "type": "heading", "level": 2, "text": "📈 自动记录" },
    { "type": "data", "role": 1, "placeholder": "数据暂不可用，点 ↻ 重试" },
    { "type": "heading", "level": 2, "text": "💭 今天" },
    { "type": "paragraph" },
    { "type": "heading", "level": 2, "text": "🌙 睡前" },
    { "type": "paragraph" }
  ]
}
''';

  group('DiaryTemplateSpec.fromJson', () {
    test('合法骨架解析为 6 个声明', () {
      final spec = DiaryTemplateSpec.fromJson(validJson);
      expect(spec.id, 'daily-default-v1');
      expect(spec.blocks, hasLength(6));
      expect(spec.blocks[0].type, DiaryTemplateBlockType.heading);
      expect(spec.blocks[0].level, 2);
      expect(spec.blocks[1].type, DiaryTemplateBlockType.data);
      expect(spec.blocks[1].role, 1);
      expect(spec.blocks[1].placeholder, '数据暂不可用，点 ↻ 重试');
      expect(spec.blocks[3].type, DiaryTemplateBlockType.paragraph);
      expect(spec.blocks[3].text, isEmpty);
    });

    test('paragraph 可带预填文本，缺省为空串', () {
      final spec = DiaryTemplateSpec.fromJson(
        '{"id":"t","blocks":[{"type":"paragraph","text":"预置"}]}',
      );
      expect(spec.blocks.single.text, '预置');
    });

    for (final bad in [
      ['id 缺失', '{"blocks":[{"type":"paragraph"}]}'],
      ['id 空白', '{"id":"  ","blocks":[{"type":"paragraph"}]}'],
      ['blocks 缺失', '{"id":"t"}'],
      ['blocks 空', '{"id":"t","blocks":[]}'],
      ['块类型非法', '{"id":"t","blocks":[{"type":"quote"}]}'],
      ['heading 缺 level', '{"id":"t","blocks":[{"type":"heading"}]}'],
      ['heading level 越界', '{"id":"t","blocks":[{"type":"heading","level":7}]}'],
      ['paragraph 带 level', '{"id":"t","blocks":[{"type":"paragraph","level":1}]}'],
      ['data 缺 role', '{"id":"t","blocks":[{"type":"data"}]}'],
      ['data role 为 0', '{"id":"t","blocks":[{"type":"data","role":0}]}'],
      ['heading 带 role', '{"id":"t","blocks":[{"type":"heading","level":1,"role":1}]}'],
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

    test('六块结构：三标题 + data 快照 + 两空段', () {
      final doc = build();
      expect(doc.id, SyIdGenerator.dayContainer(date));
      expect(doc.title, '10月10日 周六');
      expect(doc.blocks, hasLength(6));

      final headings = doc.blocks
          .where((b) => b.kind == DiaryBlockKind.heading)
          .toList();
      expect(headings.map((b) => b.text), ['📈 自动记录', '💭 今天', '🌙 睡前']);
      expect(headings.every((b) => b.level == 2), isTrue);

      final paragraphs = doc.blocks
          .where((b) => b.kind == DiaryBlockKind.paragraph)
          .toList();
      expect(paragraphs, hasLength(3)); // data 也是段落承载
    });

    test('data 块：确定性 ID、readonly、3 号底色、占位文案', () {
      final doc = build();
      final data = doc.blocks[1];
      expect(data.id, SyIdGenerator.dataBlock(date, 1));
      expect(SyIdGenerator.isDataBlockId(data.id), isTrue);
      expect(data.readonly, isTrue);
      expect(data.background, 3);
      expect(data.text, '数据暂不可用，点 ↻ 重试');
    });

    test('所有块 ID 合 22 位规范；data 之外为随机 ID', () {
      final doc = build();
      expect(doc.blocks.every((b) => SyIdGenerator.isValid(b.id)), isTrue);
      expect(
        doc.blocks[0].id,
        isNot(SyIdGenerator.dataBlock(date, 1)),
      );
    });

    test('同日重复实例化 data 块 ID 幂等', () {
      final spec = DiaryTemplateSpec.fromJson(validJson);
      final t = DailyDefaultTemplate(spec: spec);
      final a = t.instantiate(date, SyIdGenerator(random: Random(1)));
      final b = t.instantiate(date, SyIdGenerator(random: Random(2)));
      final dataA = a.blocks.firstWhere((b) => b.readonly);
      final dataB = b.blocks.firstWhere((b) => b.readonly);
      expect(dataA.id, dataB.id);
    });

    test('模板 id 不写入文档 custom', () {
      final doc = build();
      expect(doc.custom, isEmpty);
      expect(doc.custom.containsKey('custom-echo-template'), isFalse);
    });
  });
}
