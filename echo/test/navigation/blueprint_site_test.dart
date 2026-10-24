import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/src/navigation/widgets/blueprint_canvas.dart';
import 'package:echo/src/navigation/widgets/blueprint_site.dart';

void main() {
  const size = Size(360, 800);
  const camera = Offset(100, 60);
  const seed = 0x51EED123;

  test('同 seed、尺寸与相机产出完全一致的巨构', () {
    final a = BlueprintSite.build(size: size, camera: camera, seed: seed);
    final b = BlueprintSite.build(size: size, camera: camera, seed: seed);

    expect(a, isNotEmpty);
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].kind, b[i].kind);
      expect(a[i].from, b[i].from);
      expect(a[i].to, b[i].to);
      expect(a[i].center, b[i].center);
      expect(a[i].radius, b[i].radius);
      expect(a[i].startAngle, b[i].startAngle);
      expect(a[i].sweepAngle, b[i].sweepAngle);
      expect(a[i].dashed, b[i].dashed);
      expect(a[i].text, b[i].text);
      expect(a[i].fontSize, b[i].fontSize);
    }
  });

  test('不同 seed 产出不同的巨构', () {
    final a = BlueprintSite.build(size: size, camera: camera, seed: 1);
    final b = BlueprintSite.build(size: size, camera: camera, seed: 2);

    expect(_signature(a), isNot(_signature(b)));
  });

  test('图元非空、坐标有限且落在视口外扩 3 个 SITE 内', () {
    final ops = BlueprintSite.build(size: size, camera: camera, seed: seed);

    expect(ops, isNotEmpty);
    const margin = 3 * 30 * BlueprintCanvas.unit;
    for (final op in ops) {
      final b = op.bounds;
      expect(
        b.left.isFinite &&
            b.top.isFinite &&
            b.right.isFinite &&
            b.bottom.isFinite,
        isTrue,
      );
      expect(b.left, greaterThan(-margin));
      expect(b.top, greaterThan(-margin));
      expect(b.right, lessThan(size.width + margin));
      expect(b.bottom, lessThan(size.height + margin));
    }
  });

  test('相机平移 1dp 时同一世界图元只差 1dp', () {
    final a = BlueprintSite.build(size: size, camera: camera, seed: seed);
    final b = BlueprintSite.build(
      size: size,
      camera: camera.translate(1, 0),
      seed: seed,
    );

    var checked = 0;
    for (final op in a) {
      final bounds = op.bounds;
      // 只看远离视口边缘的图元：边缘处的裁剪判定会随视口一起移动。
      if (bounds.left < 40 ||
          bounds.top < 40 ||
          bounds.right > size.width - 40 ||
          bounds.bottom > size.height - 40) {
        continue;
      }
      checked++;
      final matched = b.any((other) => _sameShifted(op, other, 1, 0));
      expect(matched, isTrue, reason: '未找到平移后的图元：${op.kind}');
    }
    expect(checked, greaterThan(10));
  });
}

bool _close(double a, double b) => (a - b).abs() < 1e-6;

bool _sameShifted(BlueprintOp a, BlueprintOp b, double dx, double dy) {
  if (a.kind != b.kind ||
      a.dashed != b.dashed ||
      a.text != b.text ||
      !_close(a.radius, b.radius) ||
      !_close(a.fontSize, b.fontSize) ||
      !_close(a.startAngle, b.startAngle) ||
      !_close(a.sweepAngle, b.sweepAngle)) {
    return false;
  }
  switch (a.kind) {
    case BlueprintOpKind.line:
      // 线段只带 from/to，center 恒为零。
      return _close(a.from.dx + dx, b.from.dx) &&
          _close(a.from.dy + dy, b.from.dy) &&
          _close(a.to.dx + dx, b.to.dx) &&
          _close(a.to.dy + dy, b.to.dy);
    case BlueprintOpKind.circle:
    case BlueprintOpKind.arc:
    case BlueprintOpKind.text:
      // 圆 / 弧 / 文字只带 center（文字为左上角锚点），from/to 恒为零。
      return _close(a.center.dx + dx, b.center.dx) &&
          _close(a.center.dy + dy, b.center.dy);
  }
}

String _signature(List<BlueprintOp> ops) => ops
    .map(
      (op) =>
          '${op.kind}:${op.from}:${op.to}:${op.center}:${op.radius}:${op.text}',
    )
    .join('|');
