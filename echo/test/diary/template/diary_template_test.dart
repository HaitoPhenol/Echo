import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/diary/sy/diary_model.dart';
import 'package:echo/src/diary/sy/sy_id.dart';
import 'package:echo/src/diary/template/diary_template.dart';

void main() {
  group('BlankDiaryTemplate', () {
    final ids = SyIdGenerator(random: Random(7), now: () => DateTime(2026));
    const template = BlankDiaryTemplate();

    test('id 稳定', () {
      expect(template.id, 'blank-v1');
    });

    test('实例化：确定性日容器 ID + 自然日 + 金标准标题 + 单个空段落', () {
      final doc = template.instantiate(DateTime(2026, 10, 10, 15), ids);

      expect(doc.id, SyIdGenerator.dayContainer(DateTime(2026, 10, 10)));
      expect(doc.date, DateTime(2026, 10, 10));
      expect(doc.title, '10月10日 周六');
      expect(doc.blocks, hasLength(1));
      expect(doc.blocks.single.kind, DiaryBlockKind.paragraph);
      expect(doc.blocks.single.text, isEmpty);
      expect(SyIdGenerator.isValid(doc.blocks.single.id), isTrue);
    });

    test('两次实例化的块 ID 不同', () {
      final a = template.instantiate(DateTime(2026, 10, 10), ids);
      final b = template.instantiate(DateTime(2026, 10, 11), ids);
      expect(a.blocks.single.id, isNot(b.blocks.single.id));
    });
  });
}
