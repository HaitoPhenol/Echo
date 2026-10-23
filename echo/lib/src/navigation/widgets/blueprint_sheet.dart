import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 冷启动一次性生成的「示意底图」。
///
/// 参考 `ideas/Map.html`（无限 CAD 画布）的生成方法，取其中**静态**的
/// 三层装饰：细碎标记（micro）、块状速写（doodle）、引线标注（annotation）。
/// 与原型不同，这里不做 WFC 巨构与公式排版——只保留与机能风底纹同源的
/// 稀疏工程速写，避免抢正文。
///
/// 生命周期：
/// 1. 冷启动时取时间种子 [seed]（进程内固定）；
/// 2. [ensure] 按屏幕尺寸把整张速写**一次性栅格化**为 [ui.Image] 并缓存；
/// 3. 背景层只需每帧 `drawImageRect`，生成与排版开销只付一次。
///
/// 随机数用 32 位 mulberry32 + 单元哈希：同一种子/尺寸产出完全一致。
class BlueprintSheet {
  BlueprintSheet._();

  /// 本次冷启动的种子（进程内固定，热重载不重摇）。
  static final int seed =
      DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;

  /// 速写单元间距（dp）：块状速写按 128dp 分格、细碎标记按 32dp 分格，
  /// 与背景粗网格/细网格同周期，落点始终压在格线上。
  static const double doodleSpacing = 128;
  static const double microSpacing = 32;

  /// 块状速写的出现概率（原型 DOODLE_P = .94，这里刻意稀疏）。
  static const double doodleChance = 0.5;

  /// 细碎标记的出现概率（原型 MICRO_P = .6，这里只取少量）。
  static const double microChance = 0.16;

  static ui.Image? _image;
  static Size? _imageSize;
  static double? _imageDpr;
  static Future<ui.Image?>? _pending;

  /// 已缓存且与当前尺寸匹配的图（没有则返回 null）。
  static ui.Image? peek(Size size, double dpr) =>
      _imageSize == size && _imageDpr == dpr ? _image : null;

  /// 取（必要时生成）当前尺寸的速写图。
  ///
  /// 尺寸或像素密度变化（如旋转）时重新生成；同一时刻只跑一份生成任务。
  static Future<ui.Image?> ensure(Size size, double dpr) {
    final cached = peek(size, dpr);
    if (cached != null) return Future<ui.Image?>.value(cached);
    final pending = _pending;
    if (pending != null) return pending;
    final future = _rasterize(size, dpr);
    _pending = future;
    return future.whenComplete(() => _pending = null);
  }

  static Future<ui.Image?> _rasterize(Size size, double dpr) async {
    if (size.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    for (final op in BlueprintSketch.build(size, seed)) {
      op.paint(canvas);
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        (size.width * dpr).round(),
        (size.height * dpr).round(),
      );
      _image = image;
      _imageSize = size;
      _imageDpr = dpr;
      return image;
    } finally {
      picture.dispose();
    }
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
  }) : this._(kind: BlueprintOpKind.circle, color: color, center: center, radius: radius);

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

/// 速写排版（纯函数：给定尺寸与种子产出图元列表）。
abstract final class BlueprintSketch {
  BlueprintSketch._();

  /// 几何线：白 α.055（比粗网格略亮，仍远低于正文）。
  static const Color _geom = Color(0x0EFFFFFF);

  /// 辅助线/暗部：白 α.03，与细网格同档。
  static const Color _faint = Color(0x07FFFFFF);

  /// 微型标注文字：白 α.10，6dp 左右，只作纹理噪声。
  static const Color _label = Color(0x1AFFFFFF);

  /// 标注文案池（不承载语义，只模拟工程图注）。
  static const List<String> _notes = [
    'REF 03',
    'TYP',
    'SEC.02',
    '4× Ø6 EQ SP',
    'SEE NOTE 1',
    'DATUM A',
  ];

  static List<BlueprintOp> build(Size size, int seed) {
    final ops = <BlueprintOp>[];
    _micro(ops, size, seed);
    _doodles(ops, size, seed);
    _annotations(ops, size, seed);
    return ops;
  }

  // ---------------------------------------------------------------
  // 细碎标记层（32dp 格，约 16% 概率）
  // ---------------------------------------------------------------
  static void _micro(List<BlueprintOp> ops, Size size, int seed) {
    final step = BlueprintSheet.microSpacing;
    final cols = (size.width / step).ceil();
    final rows = (size.height / step).ceil();
    for (var gy = 0; gy <= rows; gy++) {
      for (var gx = 0; gx <= cols; gx++) {
        final rng = _Rng(_hash(seed, gx, gy, 0x01C0));
        if (rng.next() > BlueprintSheet.microChance) continue;
        final x = gx * step + rng.next() * step * 0.6;
        final y = gy * step + rng.next() * step * 0.6;
        final c = Offset(x, y);
        switch (rng.nextInt(5)) {
          case 0:
            // 小十字。
            ops
              ..add(
                BlueprintOp.line(
                  from: c - const Offset(1.5, 0),
                  to: c + const Offset(1.5, 0),
                  color: _geom,
                ),
              )
              ..add(
                BlueprintOp.line(
                  from: c - const Offset(0, 1.5),
                  to: c + const Offset(0, 1.5),
                  color: _geom,
                ),
              );
          case 1:
            ops.add(BlueprintOp.circle(center: c, radius: 0.8, color: _label));
          case 2:
            // 短刻线。
            final a = rng.next() * math.pi;
            final d = Offset(math.cos(a), math.sin(a)) * 2.4;
            ops.add(
              BlueprintOp.line(
                from: c - d,
                to: c + d,
                color: _faint,
                dashed: true,
              ),
            );
          case 3:
            final a = rng.next() * 2 * math.pi;
            ops.add(
              BlueprintOp.line(
                from: c,
                to: c + Offset(math.cos(a), math.sin(a)) * 3,
                color: _faint,
              ),
            );
          default:
            ops.add(
              BlueprintOp.arc(
                center: c,
                radius: 2.2,
                startAngle: rng.next() * 2 * math.pi,
                sweepAngle: 1 + rng.next() * 1.6,
                color: _faint,
              ),
            );
        }
      }
    }
  }

  // ---------------------------------------------------------------
  // 块状速写层（128dp 格，约 50% 概率；单块约 16~28dp）
  // ---------------------------------------------------------------
  static void _doodles(List<BlueprintOp> ops, Size size, int seed) {
    final step = BlueprintSheet.doodleSpacing;
    final cols = (size.width / step).ceil();
    final rows = (size.height / step).ceil();
    for (var gy = 0; gy <= rows; gy++) {
      for (var gx = 0; gx <= cols; gx++) {
        final rng = _Rng(_hash(seed, gx, gy, 0xD00D));
        if (rng.next() > BlueprintSheet.doodleChance) continue;
        final c = Offset(
          (gx * step + 16 + rng.next() * (step - 32)).clamp(
            12.0,
            size.width - 12,
          ),
          (gy * step + 16 + rng.next() * (step - 32)).clamp(
            12.0,
            size.height - 12,
          ),
        );
        switch (rng.nextInt(6)) {
          case 0:
            _crosshair(ops, c, rng);
          case 1:
            _circleBolts(ops, c, rng);
          case 2:
            _dimension(ops, c, rng);
          case 3:
            _arcTick(ops, c, rng);
          case 4:
            _hatchBox(ops, c, rng);
          default:
            _coords(ops, c, rng);
        }
      }
    }
  }

  /// 十字标定 + 同心圆。
  static void _crosshair(List<BlueprintOp> ops, Offset c, _Rng rng) {
    final r = 5 + rng.next() * 6;
    ops.add(BlueprintOp.circle(center: c, radius: r, color: _geom));
    ops.add(BlueprintOp.circle(center: c, radius: r * 0.32, color: _faint));
    ops
      ..add(
        BlueprintOp.line(
          from: c - Offset(r + 5, 0),
          to: c + Offset(r + 5, 0),
          color: _faint,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: c - Offset(0, r + 5),
          to: c + Offset(0, r + 5),
          color: _faint,
        ),
      );
  }

  /// 圆 + 圆周四枚小孔。
  static void _circleBolts(List<BlueprintOp> ops, Offset c, _Rng rng) {
    final r = 5 + rng.next() * 5;
    ops.add(BlueprintOp.circle(center: c, radius: r, color: _geom));
    final a0 = rng.next() * math.pi;
    for (var i = 0; i < 4; i++) {
      final a = a0 + i * math.pi / 2;
      ops.add(
        BlueprintOp.circle(
          center: c + Offset(math.cos(a), math.sin(a)) * r,
          radius: 0.9,
          color: _label,
        ),
      );
    }
  }

  /// 水平尺寸线：两端短竖线 + 中间数值。
  static void _dimension(List<BlueprintOp> ops, Offset c, _Rng rng) {
    final half = 8 + rng.next() * 6;
    final y = c.dy;
    ops
      ..add(
        BlueprintOp.line(
          from: Offset(c.dx - half, y),
          to: Offset(c.dx + half, y),
          color: _geom,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: Offset(c.dx - half, y - 2.5),
          to: Offset(c.dx - half, y + 2.5),
          color: _geom,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: Offset(c.dx + half, y - 2.5),
          to: Offset(c.dx + half, y + 2.5),
          color: _geom,
        ),
      )
      ..add(
        BlueprintOp.text(
          at: Offset(c.dx - half + 2, y - 8),
          text: (half * 2).toStringAsFixed(1),
          fontSize: 5.5,
          color: _label,
        ),
      );
  }

  /// 圆弧 + 径向刻线。
  static void _arcTick(List<BlueprintOp> ops, Offset c, _Rng rng) {
    final r = 6 + rng.next() * 6;
    final a = rng.next() * 2 * math.pi;
    ops.add(
      BlueprintOp.arc(
        center: c,
        radius: r,
        startAngle: a,
        sweepAngle: 1.2 + rng.next() * 1.8,
        color: _geom,
      ),
    );
    ops.add(
      BlueprintOp.line(
        from: c,
        to: c + Offset(math.cos(a), math.sin(a)) * r,
        color: _faint,
        dashed: true,
      ),
    );
  }

  /// 小矩形 + 斜向剖面线。
  static void _hatchBox(List<BlueprintOp> ops, Offset c, _Rng rng) {
    final w = 10 + rng.next() * 8;
    final h = 8 + rng.next() * 8;
    final rect = Rect.fromLTWH(c.dx - w / 2, c.dy - h / 2, w, h);
    ops
      ..add(
        BlueprintOp.line(
          from: rect.topLeft,
          to: rect.topRight,
          color: _geom,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: rect.topRight,
          to: rect.bottomRight,
          color: _geom,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: rect.bottomRight,
          to: rect.bottomLeft,
          color: _geom,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: rect.bottomLeft,
          to: rect.topLeft,
          color: _geom,
        ),
      );
    const gap = 4.0;
    for (double d = gap; d < w; d += gap) {
      final x = rect.left + d;
      final y = rect.top + 2;
      final end = math.min(rect.bottom, y + (w - d));
      ops.add(BlueprintOp.line(from: Offset(x, y), to: Offset(x, end), color: _faint));
    }
  }

  /// 坐标注记：小圆点 + 两行极小的 X/Y 值。
  static void _coords(List<BlueprintOp> ops, Offset c, _Rng rng) {
    ops.add(BlueprintOp.circle(center: c, radius: 0.7, color: _label));
    final x = (3300 + (c.dx - c.dy) * 0.7).toStringAsFixed(1);
    final y = (530 + c.dy * 0.9).toStringAsFixed(1);
    ops
      ..add(
        BlueprintOp.text(
          at: c + const Offset(3, -9),
          text: 'X=$x',
          fontSize: 5,
          color: _label,
        ),
      )
      ..add(
        BlueprintOp.text(
          at: c + const Offset(3, -2),
          text: 'Y=$y',
          fontSize: 5,
          color: _label,
        ),
      );
    final a = rng.next() * 2 * math.pi;
    ops.add(
      BlueprintOp.line(
        from: c,
        to: c + Offset(math.cos(a), math.sin(a)) * 4,
        color: _faint,
      ),
    );
  }

  // ---------------------------------------------------------------
  // 引线标注层（整张 4~6 条，位置随机）
  // ---------------------------------------------------------------
  static void _annotations(List<BlueprintOp> ops, Size size, int seed) {
    final rng = _Rng(_hash(seed, 0x51, 0x2F, 0xA77A));
    final count = 4 + rng.nextInt(3);
    for (var i = 0; i < count; i++) {
      final x = 20 + rng.next() * (size.width - 40);
      final y = 60 + rng.next() * (size.height - 120);
      final a = rng.next() * 2 * math.pi;
      final len = 14 + rng.next() * 16;
      final end = Offset(x, y) + Offset(math.cos(a), math.sin(a)) * len;
      ops
        ..add(BlueprintOp.circle(center: Offset(x, y), radius: 1, color: _faint))
        ..add(
          BlueprintOp.line(
            from: Offset(x, y),
            to: end,
            color: _faint,
            dashed: i.isOdd,
          ),
        )
        ..add(
          BlueprintOp.text(
            at: end + const Offset(2, -6),
            text: _notes[rng.nextInt(_notes.length)],
            fontSize: 5.5,
            color: _label,
          ),
        );
    }
  }

  /// 32 位哈希：把种子与格点坐标混成单格随机种子。
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

/// 32 位 mulberry32 随机数（与原型 `Map.html` 同算法）。
class _Rng {
  _Rng(int seed) : _state = seed & 0xFFFFFFFF;

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

/// 单测用：暴露种子与尺寸的生成入口（不触发栅格化）。
@visibleForTesting
List<BlueprintOp> buildBlueprintSketch(Size size, int seed) =>
    BlueprintSketch.build(size, seed);
