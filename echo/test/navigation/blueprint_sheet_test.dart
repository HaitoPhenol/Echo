import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/navigation/widgets/blueprint_sheet.dart';

void main() {
  const size = Size(360, 800);

  test('同一尺寸与种子产出完全一致的速写', () {
    final a = buildBlueprintSketch(size, 0x1234ABCD);
    final b = buildBlueprintSketch(size, 0x1234ABCD);

    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].kind, b[i].kind);
      expect(a[i].from, b[i].from);
      expect(a[i].to, b[i].to);
      expect(a[i].center, b[i].center);
      expect(a[i].text, b[i].text);
    }
  });

  test('不同种子产出不同的速写', () {
    final a = buildBlueprintSketch(size, 1);
    final b = buildBlueprintSketch(size, 2);

    final sigA = a.map((op) => '${op.kind}:${op.from}:${op.center}').join('|');
    final sigB = b.map((op) => '${op.kind}:${op.from}:${op.center}').join('|');
    expect(sigA, isNot(sigB));
  });

  test('速写有限且稀疏：图元数量与坐标都在合理范围', () {
    final ops = buildBlueprintSketch(size, 0x0BADF00D);

    expect(ops, isNotEmpty);
    // 三层稀疏装饰，360×800 屏上不会超过数百条。
    expect(ops.length, lessThan(600));
    for (final op in ops) {
      final b = op.bounds;
      // 允许格点外溢一个周期，但不允许无穷/NaN。
      expect(b.left.isFinite && b.top.isFinite, isTrue);
      expect(b.right.isFinite && b.bottom.isFinite, isTrue);
      expect(b.left, greaterThan(-64));
      expect(b.top, greaterThan(-64));
      expect(b.right, lessThan(size.width + 160));
      expect(b.bottom, lessThan(size.height + 160));
    }
  });

  test('几何线颜色保持低透明度，不抢正文', () {
    final ops = buildBlueprintSketch(size, 7);
    for (final op in ops) {
      expect(op.color.a, lessThanOrEqualTo(0.11));
    }
  });
}
