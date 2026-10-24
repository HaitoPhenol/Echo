import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../theme/mechanical_style.dart';
import 'blueprint_site.dart';

/// 无限画布版「示意底图」：直接移植 `ideas/Map.html` 的生成方式。
///
/// 原型是一个可无限拖拽的 CAD 世界坐标画布，屏幕上看到的一切都由
/// **世界格坐标的哈希**即时生成：同一格坐标永远产出同一图案，画布
/// 向任何方向平移都只是换一批可见格，因此天然无缝、不会跳变。
///
/// 本类不做 WFC 巨构与公式排版，WFC 巨构见 BlueprintSite，其余只保留三层与
/// 机能风同源的静态速写：细碎标记（micro）、块状速写（doodle）、少量注记文字。
///
/// 坐标系：**一个单位 = 4 个细网格**（[MechanicalStyle.fineGridSpacing] × 4
/// = 64dp），原型里的 0.5 / 1.0 等格距直接乘 [unit] 使用。
///
/// 每帧只按当前视口（[camera] 决定世界原点在屏幕上的位置）枚举可见格，
/// 图元由 [build] 纯函数产出，画布尺寸/位置任意变化都不影响同一格的图案。
class BlueprintCanvas {
  BlueprintCanvas._();

  /// 本次冷启动的种子（进程内固定，热重载不重摇）。
  static final int seed = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;

  /// 原型中的「一个单位」= 4 个细网格 = 64dp。
  static const double unit = MechanicalStyle.fineGridSpacing * 4;

  /// 细碎标记格距（世界单位，同原型 `MICRO_STEP`）。
  static const double microStep = 0.5;

  /// 块状速写格距（世界单位，同原型 `DOODLE_STEP`）。
  static const double doodleStep = 1.0;

  /// 出现概率：比原型稀疏，避免盖过正文。
  static const double doodleChance = 0.94;
  static const double microChance = 0.6;

  /// 视口外扩（世界单位），给图元自身尺寸留余量（原型 `M_*`）。
  static const double _doodleMargin = 1.2;
  static const double _microMargin = 0.5;

  /// 枚举视口内可见格，产出 dp 坐标的图元（纯函数，便于单测）。
  ///
  /// [camera] 是「世界原点在屏幕上的 dp 坐标」：屏幕 x = camera.dx + 世界x ×
  /// [unit]。它由网格原点平移 + 未取模的翻页位移组成，连续变化即连续平移。
  static List<BlueprintOp> build({
    required Size size,
    required Offset camera,
    required int seed,
  }) {
    final ops = <BlueprintOp>[];
    if (size.isEmpty) return ops;

    final left = -camera.dx / unit;
    final right = (size.width - camera.dx) / unit;
    final top = -camera.dy / unit;
    final bottom = (size.height - camera.dy) / unit;

    _micro(ops, camera, seed, left, right, top, bottom);
    _doodles(ops, camera, seed, left, right, top, bottom);
    // 与原型 drawFigures 一致：micro → doodle → WFC 巨构。
    ops.addAll(BlueprintSite.build(size: size, camera: camera, seed: seed));
    return ops;
  }

  /// 世界坐标 → 屏幕 dp。
  static Offset _at(Offset camera, double x, double y) =>
      Offset(camera.dx + x * unit, camera.dy + y * unit);

  // ---------------------------------------------------------------
  // 细碎标记层（0.5 单位格，约 35% 概率；同原型 genMicro）
  // ---------------------------------------------------------------
  static void _micro(
    List<BlueprintOp> ops,
    Offset camera,
    int seed,
    double left,
    double right,
    double top,
    double bottom,
  ) {
    const step = microStep;
    final x0 = ((left - _microMargin) / step).floor();
    final x1 = ((right + _microMargin) / step).floor();
    final y0 = ((top - _microMargin) / step).floor();
    final y1 = ((bottom + _microMargin) / step).floor();
    for (var gy = y0; gy <= y1; gy++) {
      for (var gx = x0; gx <= x1; gx++) {
        final rng = BlueprintRng(_hash(seed, gx, gy, 0x01C0));
        if (rng.next() > microChance) continue;
        final c = _at(
          camera,
          gx * step + rng.next() * step * 0.5,
          gy * step + rng.next() * step * 0.5,
        );
        switch (rng.nextInt(5)) {
          case 0:
            // 小十字（±0.05 单位）。
            ops
              ..add(
                BlueprintOp.line(
                  from: c - Offset(unit * 0.05, 0),
                  to: c + Offset(unit * 0.05, 0),
                  color: geom,
                ),
              )
              ..add(
                BlueprintOp.line(
                  from: c - Offset(0, unit * 0.05),
                  to: c + Offset(0, unit * 0.05),
                  color: geom,
                ),
              );
          case 1:
            ops.add(
              BlueprintOp.circle(center: c, radius: unit * 0.035, color: geom),
            );
          case 2:
            ops.add(
              BlueprintOp.line(
                from: c - Offset(unit * 0.08, 0),
                to: c + Offset(unit * 0.08, 0),
                color: faint,
                dashed: true,
              ),
            );
          case 3:
            final a = rng.next() * 2 * math.pi;
            ops.add(
              BlueprintOp.line(
                from: c,
                to: c + Offset(math.cos(a), math.sin(a)) * (unit * 0.1),
                color: faint,
              ),
            );
          default:
            ops.add(
              BlueprintOp.circle(
                center: c,
                radius: unit * 0.05,
                color: faint,
                // 虚线圆用短刻线近似，避免为一枚装饰引入 dash 绘制器。
              ),
            );
            ops.add(
              BlueprintOp.line(
                from: c - Offset(unit * 0.07, 0),
                to: c + Offset(unit * 0.07, 0),
                color: faint,
              ),
            );
        }
      }
    }
  }

  // ---------------------------------------------------------------
  // 块状速写层（1 单位格，约 60% 概率；同原型 genDoodle 的静态子集）
  // ---------------------------------------------------------------
  static void _doodles(
    List<BlueprintOp> ops,
    Offset camera,
    int seed,
    double left,
    double right,
    double top,
    double bottom,
  ) {
    const step = doodleStep;
    final x0 = ((left - _doodleMargin) / step).floor();
    final x1 = ((right + _doodleMargin) / step).floor();
    final y0 = ((top - _doodleMargin) / step).floor();
    final y1 = ((bottom + _doodleMargin) / step).floor();
    for (var gy = y0; gy <= y1; gy++) {
      for (var gx = x0; gx <= x1; gx++) {
        final rng = BlueprintRng(_hash(seed, gx, gy, 0xD00D));
        if (rng.next() > doodleChance) continue;
        final c = _at(
          camera,
          gx * step + rng.next() * step * 0.6,
          gy * step + rng.next() * step * 0.6,
        );
        _doodle(ops, rng, c);
      }
    }
  }

  static void _doodle(List<BlueprintOp> ops, BlueprintRng rng, Offset c) {
    switch (rng.nextInt(16)) {
      case 0:
        // 十字标记（±0.1~0.24 单位）。
        final e = unit * (0.1 + rng.next() * 0.14);
        ops
          ..add(
            BlueprintOp.line(
              from: c - Offset(e, 0),
              to: c + Offset(e, 0),
              color: faint,
            ),
          )
          ..add(
            BlueprintOp.line(
              from: c - Offset(0, e),
              to: c + Offset(0, e),
              color: faint,
            ),
          );
      case 1:
        ops.add(
          BlueprintOp.circle(
            center: c,
            radius: unit * (0.07 + rng.next() * 0.15),
            color: geom,
          ),
        );
      case 2:
        // 小十字。
        ops
          ..add(
            BlueprintOp.line(
              from: c - Offset(unit * 0.12, 0),
              to: c + Offset(unit * 0.12, 0),
              color: geom,
            ),
          )
          ..add(
            BlueprintOp.line(
              from: c - Offset(0, unit * 0.12),
              to: c + Offset(0, unit * 0.12),
              color: geom,
            ),
          );
      case 3:
        _dimension(ops, c, rng);
      case 4:
        ops.add(
          BlueprintOp.arc(
            center: c,
            radius: unit * (0.12 + rng.next() * 0.18),
            startAngle: rng.next() * 2 * math.pi,
            sweepAngle: 1 + rng.next() * 2,
            color: geom,
          ),
        );
      case 5:
        // 斜向短刻线。
        final a = rng.next() * 2 * math.pi;
        final d = Offset(math.cos(a), math.sin(a)) * (unit * 0.3);
        ops.add(
          BlueprintOp.line(from: c - d, to: c + d, color: faint, dashed: true),
        );
      case 6:
        // 两行坐标注记。
        ops
          ..add(
            BlueprintOp.text(
              at: c + Offset(0, -unit * 0.14),
              text: 'X=${(3300 + c.dx * 7.5).toStringAsFixed(1)}',
              fontSize: unit * 0.1,
              color: label,
            ),
          )
          ..add(
            BlueprintOp.text(
              at: c + Offset(0, -unit * 0.02),
              text: 'Y=${(530 + c.dy * 7.5).toStringAsFixed(1)}',
              fontSize: unit * 0.1,
              color: label,
            ),
          );
      case 7:
        ops.add(
          BlueprintOp.line(
            from: c - Offset(unit * 0.3, 0),
            to: c + Offset(unit * 0.3, 0),
            color: geom,
            dashed: true,
          ),
        );
      case 8:
        // 箭头。
        final a = rng.next() * 2 * math.pi;
        final tip = c + Offset(math.cos(a), math.sin(a)) * (unit * 0.3);
        ops.add(BlueprintOp.line(from: c, to: tip, color: geom));
        _arrowHead(ops, tip, c);
      case 9:
        // 虚线圆 + 圆周四枚小孔。
        final r = unit * 0.2;
        ops.add(BlueprintOp.circle(center: c, radius: r, color: geom));
        for (var i = 0; i < 4; i++) {
          final a = i * 1.5708 + 0.4;
          ops.add(
            BlueprintOp.circle(
              center: c + Offset(math.cos(a), math.sin(a)) * r,
              radius: unit * 0.028,
              color: faint,
            ),
          );
        }
      case 10:
        // 3~5 枚散布小孔。
        final n = 3 + rng.nextInt(3);
        for (var i = 0; i < n; i++) {
          final a = i / n * 2 * math.pi + rng.next() * 0.3;
          final r = unit * (0.14 + rng.next() * 0.12);
          ops.add(
            BlueprintOp.circle(
              center: c + Offset(math.cos(a), math.sin(a)) * r,
              radius: unit * 0.035,
              color: faint,
            ),
          );
        }
      case 11:
        // 小方框。
        final s = unit * (0.1 + rng.next() * 0.1);
        final box = [
          c + Offset(-s, -s),
          c + Offset(s, -s),
          c + Offset(s, s),
          c + Offset(-s, s),
        ];
        for (var i = 0; i < 4; i++) {
          ops.add(
            BlueprintOp.line(from: box[i], to: box[(i + 1) % 4], color: geom),
          );
        }
      case 12:
        // 引线 + 单字母编号。
        final a = rng.next() * 2 * math.pi;
        final dir = Offset(math.cos(a), math.sin(a));
        ops
          ..add(
            BlueprintOp.line(
              from: c,
              to: c + dir * (unit * 0.25),
              color: faint,
            ),
          )
          ..add(
            BlueprintOp.text(
              at: c + dir * (unit * 0.35),
              text: _letters[rng.nextInt(_letters.length)],
              fontSize: unit * 0.12,
              color: label,
            ),
          );
      case 13:
        // 圆心 + 左右水平刻线。
        final r = unit * (0.1 + rng.next() * 0.12);
        ops
          ..add(BlueprintOp.circle(center: c, radius: r, color: geom))
          ..add(
            BlueprintOp.line(
              from: c - Offset(r + unit * 0.1, 0),
              to: c - Offset(r, 0),
              color: faint,
            ),
          )
          ..add(
            BlueprintOp.line(
              from: c + Offset(r, 0),
              to: c + Offset(r + unit * 0.1, 0),
              color: faint,
            ),
          );
      case 14:
      default:
        // 公式条（原型 case 15 的静态文案）。
        ops.add(
          BlueprintOp.text(
            at: c,
            text: _formulas[rng.nextInt(_formulas.length)],
            fontSize: unit * 0.13,
            color: label,
          ),
        );
    }
  }

  /// 水平尺寸线：主线 + 两端刻度 + 数值。
  static void _dimension(List<BlueprintOp> ops, Offset c, BlueprintRng rng) {
    final half = unit * (0.25 + rng.next() * 0.2);
    final tick = unit * 0.1;
    final y = c.dy;
    ops
      ..add(
        BlueprintOp.line(
          from: Offset(c.dx - half, y),
          to: Offset(c.dx + half, y),
          color: geom,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: Offset(c.dx - half, y - tick),
          to: Offset(c.dx - half, y + tick),
          color: geom,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: Offset(c.dx + half, y - tick),
          to: Offset(c.dx + half, y + tick),
          color: geom,
        ),
      )
      ..add(
        BlueprintOp.text(
          at: Offset(c.dx - half + unit * 0.05, y - unit * 0.26),
          text: (half * 2 / unit).toStringAsFixed(1),
          fontSize: unit * 0.11,
          color: label,
        ),
      );
  }

  /// 箭头两撇（[tip] 为尖端，[from] 决定朝向）。
  static void _arrowHead(List<BlueprintOp> ops, Offset tip, Offset from) {
    final a = math.atan2(tip.dy - from.dy, tip.dx - from.dx);
    final size = unit * 0.09;
    for (final d in const [-0.32, 0.32]) {
      ops.add(
        BlueprintOp.line(
          from: tip,
          to: tip - Offset(math.cos(a - d), math.sin(a - d)) * size,
          color: geom,
        ),
      );
    }
  }

  /// 几何线：白 α.055（比粗网格略亮，仍远低于正文）。
  static const Color geom = Color(0x0EFFFFFF);

  /// 辅助线/暗部：白 α.03，与细网格同档。
  static const Color faint = Color(0x07FFFFFF);

  /// 微型标注文字：白 α.10，只作纹理噪声。
  static const Color label = Color(0x1AFFFFFF);

  /// 引线编号池。
  static const List<String> _letters = ['A', 'B', 'C', '1', '2', '3'];

  /// 公式文案池（不承载语义，只模拟工程图注）。
  static const List<String> _formulas = [
    '∇·B = 0',
    '∂ψ/∂t',
    '∮E·ds',
    'E = ħω',
    'λ = h/p',
    'σ = F/A',
    'Σf = ma',
  ];

  /// 32 位哈希：把种子与格点坐标混成单格随机种子（原型 `hash2`）。
  static int _hash(int seed, int a, int b, int salt) {
    var h = (seed ^ salt) & 0xFFFFFFFF;
    h = (h * 0x85EBCA6B + 0x9E3779B9) & 0xFFFFFFFF;
    h = (h * (a + 1) + 0xC2B2AE35) & 0xFFFFFFFF;
    h = (h * (b + 1) + 0x27D4EB2F) & 0xFFFFFFFF;
    h ^= h >>> 15;
    h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
    h ^= h >>> 13;
    return h & 0xFFFFFFFF;
  }
}

/// 一条速写图元（纯数据，便于单测断言）。
@immutable
class BlueprintOp {
  const BlueprintOp._({
    required this.kind,
    required this.color,
    this.center = Offset.zero,
    this.radius = 0,
    this.startAngle = 0,
    this.sweepAngle = 0,
    this.from = Offset.zero,
    this.to = Offset.zero,
    this.dashed = false,
    this.text = '',
    this.fontSize = 0,
  });

  const BlueprintOp.line({
    required Offset from,
    required Offset to,
    required Color color,
    bool dashed = false,
  }) : this._(
         kind: BlueprintOpKind.line,
         color: color,
         from: from,
         to: to,
         dashed: dashed,
       );

  const BlueprintOp.circle({
    required Offset center,
    required double radius,
    required Color color,
  }) : this._(
         kind: BlueprintOpKind.circle,
         color: color,
         center: center,
         radius: radius,
       );

  const BlueprintOp.arc({
    required Offset center,
    required double radius,
    required double startAngle,
    required double sweepAngle,
    required Color color,
  }) : this._(
         kind: BlueprintOpKind.arc,
         color: color,
         center: center,
         radius: radius,
         startAngle: startAngle,
         sweepAngle: sweepAngle,
       );

  const BlueprintOp.text({
    required Offset at,
    required String text,
    required double fontSize,
    required Color color,
  }) : this._(
         kind: BlueprintOpKind.text,
         color: color,
         center: at,
         text: text,
         fontSize: fontSize,
       );

  final BlueprintOpKind kind;
  final Color color;
  final Offset center;
  final double radius;
  final double startAngle;
  final double sweepAngle;
  final Offset from;
  final Offset to;
  final bool dashed;
  final String text;
  final double fontSize;

  /// 图元外包框（用于单测检查是否落在画布内）。
  Rect get bounds {
    switch (kind) {
      case BlueprintOpKind.line:
        return Rect.fromPoints(from, to);
      case BlueprintOpKind.circle:
      case BlueprintOpKind.arc:
        return Rect.fromCircle(center: center, radius: radius);
      case BlueprintOpKind.text:
        return Rect.fromLTWH(center.dx, center.dy, 0, fontSize);
    }
  }

  void paint(Canvas canvas) {
    switch (kind) {
      case BlueprintOpKind.line:
        final paint = Paint()
          ..color = color
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;
        if (!dashed) {
          canvas.drawLine(from, to, paint);
          return;
        }
        // 简化的等距虚线（3dp 实 / 2dp 空）。
        final delta = to - from;
        final length = delta.distance;
        if (length == 0) return;
        final dir = delta / length;
        for (double d = 0; d < length; d += 5) {
          final end = math.min(d + 3, length);
          canvas.drawLine(from + dir * d, from + dir * end, paint);
        }
      case BlueprintOpKind.circle:
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = color
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true,
        );
      case BlueprintOpKind.arc:
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          false,
          Paint()
            ..color = color
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true,
        );
      case BlueprintOpKind.text:
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              letterSpacing: 0.4,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, center);
        painter.dispose();
    }
  }
}

enum BlueprintOpKind { line, circle, arc, text }

/// 32 位 mulberry32 随机数（与原型 `Map.html` 同算法）。
///
/// micro/doodle/site 三层共用同一实现，保证同 seed 下完全可复现。
class BlueprintRng {
  BlueprintRng(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  double next() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = ((t ^ (t >>> 15)) * (1 | t)) & 0xFFFFFFFF;
    t = (t + ((t ^ (t >>> 7)) * (61 | t) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    return ((t ^ (t >>> 14)) & 0xFFFFFFFF) / 4294967296;
  }

  int nextInt(int max) => (next() * max).floor();
}

/// 单测用：暴露「视口 → 图元」的纯生成入口。
@visibleForTesting
List<BlueprintOp> buildBlueprintCanvas({
  required Size size,
  required Offset camera,
  required int seed,
}) => BlueprintCanvas.build(size: size, camera: camera, seed: seed);
