import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/navigation/widgets/blueprint_canvas.dart';

void main() {
  const size = Size(360, 800);
  const camera = Offset(100, 60);

  test('同一视口与种子产出完全一致的速写', () {
    final a = buildBlueprintCanvas(size: size, camera: camera, seed: 0x1234ABCD);
    final b = buildBlueprintCanvas(size: size, camera: camera, seed: 0x1234ABCD);

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
    final a = buildBlueprintCanvas(size: size, camera: camera, seed: 1);
    final b = buildBlueprintCanvas(size: size, camera: camera, seed: 2);

    final sigA = a.map((op) => '${op.kind}:${op.from}:${op.center}').join('|');
    final sigB = b.map((op) => '${op.kind}:${op.from}:${op.center}').join('|');
    expect(sigA, isNot(sigB));
  });

  test('图案由世界坐标决定，与视口尺寸无关（无平铺跳变）', () {
    final small = buildBlueprintCanvas(size: size, camera: camera, seed: 42);
    final wide = buildBlueprintCanvas(
      size: const Size(720, 800),
      camera: camera,
      seed: 42,
    );

    String key(BlueprintOp op) =>
        '${op.kind}:${op.from}:${op.to}:${op.center}:${op.text}';
    final wideSet = wide.map(key).toSet();
    for (final op in small) {
      expect(wideSet, contains(key(op)));
    }
  });

  test('平移一个粗网格周期后内容不同（说明是无限画布而非平铺）', () {
    final a = buildBlueprintCanvas(size: size, camera: camera, seed: 9);
    final b = buildBlueprintCanvas(
      size: size,
      camera: camera.translate(-128, 0),
      seed: 9,
    );

    final sigA = a.map((op) => '${op.kind}:${op.from}:${op.center}').join('|');
    final sigB = b.map((op) => '${op.kind}:${op.from}:${op.center}').join('|');
    expect(sigA, isNot(sigB));
  });

  test('速写稀疏：图元数量与坐标都在合理范围', () {
    final ops = buildBlueprintCanvas(size: size, camera: camera, seed: 0xBADF00D);

    expect(ops, isNotEmpty);
    expect(ops.length, lessThan(900));
    for (final op in ops) {
      final b = op.bounds;
      expect(b.left.isFinite && b.top.isFinite, isTrue);
      expect(b.right.isFinite && b.bottom.isFinite, isTrue);
      // 允许格点外溢一个单位，但不允许跑到视口外很远。
      expect(b.left, greaterThan(-200));
      expect(b.top, greaterThan(-200));
      expect(b.right, lessThan(size.width + 200));
      expect(b.bottom, lessThan(size.height + 200));
    }
  });

  test('几何线颜色保持低透明度，不抢正文', () {
    final ops = buildBlueprintCanvas(size: size, camera: camera, seed: 7);
    for (final op in ops) {
      expect(op.color.a, lessThanOrEqualTo(0.11));
    }
  });
}
