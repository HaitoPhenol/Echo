import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:echo/src/navigation/dock_geometry.dart';

void main() {
  const origin = Offset(200, 800);
  final buttonRadius = DockGeometry.quickArcButtonDiameter / 2;
  final maxHotRadius = buttonRadius + DockGeometry.quickArcHotMargin;

  group('layoutQuickArc 数量联动', () {
    test('0 / 1 项：空布局或单点居中，热区取最大半径', () {
      final empty = DockGeometry.layoutQuickArc(origin: origin, count: 0);
      expect(empty.centers, isEmpty);
      expect(empty.hotRadius, maxHotRadius);

      final single = DockGeometry.layoutQuickArc(origin: origin, count: 1);
      expect(single.centers, hasLength(1));
      expect(single.hotRadius, maxHotRadius);
      // 单个按钮位于曲线弧长中点：t 满足弧长 = 总长一半，
      // 即 t 处累计长度 = 总长 − t 处剩余长度（t≈0.45 附近）。
      expect(single.centers.single.dy, lessThan(origin.dy));
      expect(single.centers.single.dx, greaterThan(origin.dx));
    });

    test('2~4 项：数量一致、热区半径合法且相邻热区间隙 ≥ 10', () {
      for (var count = 2; count <= 4; count++) {
        final layout = DockGeometry.layoutQuickArc(
          origin: origin,
          count: count,
        );

        expect(layout.centers, hasLength(count));
        expect(
          layout.hotRadius,
          inInclusiveRange(buttonRadius, maxHotRadius),
          reason: '$count 项时热区半径越界',
        );

        for (var i = 1; i < count; i++) {
          final distance = (layout.centers[i] - layout.centers[i - 1]).distance;
          expect(
            distance - 2 * layout.hotRadius,
            greaterThanOrEqualTo(DockGeometry.quickArcHotMargin),
            reason: '$count 项时第 $i 个热区间隙不足 10',
          );
        }
      }
    });

    test('6 项以上：热区自动缩到下限（按钮半径），仍沿曲线单调', () {
      for (var count = 6; count <= 10; count++) {
        final layout = DockGeometry.layoutQuickArc(
          origin: origin,
          count: count,
        );
        expect(layout.centers, hasLength(count));
        expect(layout.hotRadius, buttonRadius);
        for (var i = 1; i < count; i++) {
          expect(layout.centers[i].dx > layout.centers[i - 1].dx, isTrue);
          expect(layout.centers[i].dy < layout.centers[i - 1].dy, isTrue);
        }
      }
    });

    test('任意数量：按钮沿曲线弧长等距、整体居中', () {
      // 候选弧长窗口（与算法一致）：实际结果必须与某个窗口下的
      // 居中弧长均分点吻合——同时证明"等距"与"居中"。
      const spans = [0.60, 0.72, 0.84, 0.96];

      for (var count = 2; count <= 10; count++) {
        final layout = DockGeometry.layoutQuickArc(
          origin: origin,
          count: count,
        );

        bool matchesSpan(double span) {
          for (var i = 0; i < count; i++) {
            final u = 0.5 - span / 2 + span * i / (count - 1);
            final expected = DockGeometry.pointAtArcFraction(origin, u);
            if ((expected - layout.centers[i]).distance > 0.5) {
              return false;
            }
          }
          return true;
        }

        expect(spans.any(matchesSpan), isTrue, reason: '$count 项时不是居中弧长等距布局');

        // 弦长间距差 < 1（弧长精确等距，弦长随曲率有微小差异）。
        final gaps = <double>[
          for (var i = 1; i < count; i++)
            (layout.centers[i] - layout.centers[i - 1]).distance,
        ];
        final spread = gaps.reduce(math.max) - gaps.reduce(math.min);
        expect(spread, lessThan(1), reason: '$count 项间距不等');
      }
    });
  });

  group('quickArcPoint 曲线形状', () {
    test('端点与切线方向符合实测轨迹', () {
      final start = DockGeometry.quickArcPoint(origin, 0);
      final end = DockGeometry.quickArcPoint(origin, 1);
      expect(start, origin);
      expect(end.dx, origin.dx + DockGeometry.quickArcSemiX);
      expect(end.dy, origin.dy - DockGeometry.quickArcSemiY);

      // 数值导数：起点切向竖直（dx≈0、dy<0），
      // 末端切向水平（dx>0、dy≈0）。
      const eps = 1e-6;
      final startSlope =
          (DockGeometry.quickArcPoint(origin, eps) - origin) / eps;
      final endSlope =
          (end - DockGeometry.quickArcPoint(origin, 1 - eps)) / eps;

      expect(startSlope.dx.abs(), lessThan(1e-3));
      expect(startSlope.dy, lessThan(0));
      expect(endSlope.dy.abs(), lessThan(1e-3));
      expect(endSlope.dx, greaterThan(0));
    });

    test('半轴比例 ≈ 1:1.59（实测轨迹）', () {
      final ratio = DockGeometry.quickArcSemiY / DockGeometry.quickArcSemiX;
      expect((ratio - 1.59).abs(), lessThan(0.02));
    });
  });
}
