import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'blueprint_canvas.dart';

/// 无限画布版「WFC 巨构」层：直接移植 `ideas/Map.html` 的站点生成算法。
///
/// 每个站点（site）是一个 30 世界单位的方块，内部是 5×5 个 6 单位单元。
/// 先用波函数坍缩（WFC）给单元分配 MEGA / AXIS_H / AXIS_V / DETAIL /
/// ANNO / EMPTY 六种模块，再按模块调用对应的工程图生成器，产出一组
/// **世界坐标**图元。站点只由格坐标哈希决定，同一格坐标永远产出同一图案，
/// 因此画布连续平移时不会跳变。
///
/// 性能：站点图元列表按 `(seed, sbx, sby)` 缓存（LRU 上限 40，同原型
/// `SITE_CACHE_MAX`）；每帧只把缓存里的世界坐标图元换算成屏幕 dp，
/// 不重复跑 WFC。
///
/// 渲染简化（原型能力超出 [BlueprintOp] 的语义）：
/// * 原型内置迷你 LaTeX 排版，这里改为同位置输出一条纯文本公式；
/// * 文字旋转忽略（[BlueprintOp.text] 无旋转字段）；
/// * 虚线圆/虚线弧统一画成实线圆/弧；
/// * 剖面线矩形额外补画四条边（原型只画剖面线）。
///
/// 坐标：世界→dp 为 `camera + world * BlueprintCanvas.unit`。
class BlueprintSite {
  BlueprintSite._();

  /// 站点边长（世界单位，同原型 `SITE = CELLS * BW`）。
  static const double _site = 30;

  /// 单元边长（世界单位，同原型 `BW`）。
  static const double _bw = 6;

  /// 每边单元数（同原型 `CELLS`）。
  static const int _cells = 5;

  /// 视口外扩（世界单位，同原型 `M_FIG`）。
  static const double _mFig = 10.5;

  /// 站点缓存上限（同原型 `SITE_CACHE_MAX`）。
  static const int _cacheMax = 40;

  /// 世界坐标图元缓存。键里带上 seed，使不同种子的单测互不污染；
  /// 正式运行时 seed 进程内固定，等价于按 `(sbx, sby)` 缓存。
  static final Map<String, List<_Prim>> _cache = <String, List<_Prim>>{};

  /// 枚举当前视口内可见的站点，产出 dp 坐标图元（纯函数，便于单测）。
  static List<BlueprintOp> build({
    required Size size,
    required Offset camera,
    required int seed,
  }) {
    final ops = <BlueprintOp>[];
    if (size.isEmpty) return ops;

    const unit = BlueprintCanvas.unit;
    final left = -camera.dx / unit;
    final right = (size.width - camera.dx) / unit;
    final top = -camera.dy / unit;
    final bottom = (size.height - camera.dy) / unit;

    final s0x = ((left - _mFig) / _site).floor();
    final s1x = ((right + _mFig) / _site).floor();
    final s0y = ((top - _mFig) / _site).floor();
    final s1y = ((bottom + _mFig) / _site).floor();

    for (var sby = s0y; sby <= s1y; sby++) {
      for (var sbx = s0x; sbx <= s1x; sbx++) {
        final prims = _sitePrims(sbx, sby, seed);
        for (final p in prims) {
          final bb = p.worldBounds;
          // 同原型 drawFigures：按图元外包框与视口求交。
          if (bb.right < left ||
              bb.left > right ||
              bb.bottom < top ||
              bb.top > bottom) {
            continue;
          }
          final start = ops.length;
          _emit(ops, p, camera);
          _clipLines(ops, size, start);
        }
      }
    }
    return ops;
  }

  /// 把本次新追加的线段图元裁到视口内。
  ///
  /// 巨构图元常有横贯整个站点的长线，世界外包框只负责判断「要不要画」；
  /// 落到屏幕时顺手裁到视口边界（`Canvas` 本身也会裁），既少画屏幕外的
  /// 大段，也避免图元包围盒远远超出视口。
  static void _clipLines(List<BlueprintOp> ops, Size size, int start) {
    for (var i = start; i < ops.length; i++) {
      final op = ops[i];
      if (op.kind != BlueprintOpKind.line) continue;
      final seg = _clipSegment(
        0,
        0,
        size.width,
        size.height,
        op.from.dx,
        op.from.dy,
        op.to.dx,
        op.to.dy,
      );
      if (seg == null) {
        ops.removeAt(i);
        i--;
        continue;
      }
      if (seg.$1 != op.from.dx ||
          seg.$2 != op.from.dy ||
          seg.$3 != op.to.dx ||
          seg.$4 != op.to.dy) {
        ops[i] = BlueprintOp.line(
          from: Offset(seg.$1, seg.$2),
          to: Offset(seg.$3, seg.$4),
          color: op.color,
          dashed: op.dashed,
        );
      }
    }
  }

  // ---------------------------------------------------------------
  // 站点生成（同原型 genSite）
  // ---------------------------------------------------------------
  static List<_Prim> _sitePrims(int sbx, int sby, int seed) {
    final key = '$seed:$sbx:$sby';
    final cached = _cache[key];
    if (cached != null) return cached;

    final siteSeed = _hash2(seed, sbx * 7919 + 13, sby * 104729 + 7, 0xCAD5);
    final rng = BlueprintRng(siteSeed);
    final mods = _runWfc(siteSeed);
    final sctx = _Ctx(rng);

    final ox = sbx * _site;
    final oy = sby * _site;
    final axisX = ox + _site / 2 + (rng.next() - 0.5) * 1.2;
    final axisY = oy + _site / 2 + (rng.next() - 0.5) * 1.2;

    var m0c = 99;
    var m1c = -1;
    var m0r = 99;
    var m1r = -1;
    for (var i = 0; i < mods.length; i++) {
      if (mods[i] != 'MEGA') continue;
      final col = i % _cells;
      final row = i ~/ _cells;
      m0c = math.min(m0c, col);
      m1c = math.max(m1c, col);
      m0r = math.min(m0r, row);
      m1r = math.max(m1r, row);
    }

    final prims = <_Prim>[];
    final segs = <_Seg>[];
    final circles = <_Circle>[];
    final favAX = rng.nextInt(5);
    final favDet = rng.nextInt(_detailGens.length);
    var lastAX = -1;
    var lastDet = -1;

    if (m1c >= 0) {
      final mo = _Cell(ox + m0c * _bw, oy + m0r * _bw);
      final mw = (m1c - m0c + 1) * _bw;
      final mh = (m1r - m0r + 1) * _bw;
      final megaR = BlueprintRng(
        _hash2(seed, (ox + 11).toInt(), (oy + 22).toInt(), 0x9E6A),
      );
      final k = _K(megaR);
      final geo = _Geo(
        segs: segs,
        circles: circles,
        axisX: axisX,
        axisY: axisY,
        snapX: axisX,
        snapY: axisY,
        mw: mw,
        mh: mh,
        sctx: sctx,
      );
      _megaGens[megaR.nextInt(_megaGens.length)](megaR, mo, k, geo);
      prims.addAll(k.p);
    }

    for (var i = 0; i < mods.length; i++) {
      final m = mods[i];
      if (m != 'AXIS_H' && m != 'AXIS_V') continue;
      final co = _Cell(ox + (i % _cells) * _bw, oy + (i ~/ _cells) * _bw);
      final ccx = co.x + _bw / 2;
      final ccy = co.y + _bw / 2;
      final geo = _Geo(
        segs: segs,
        circles: circles,
        axisX: axisX,
        axisY: axisY,
        snapX: (axisX - ccx).abs() < _bw * 0.55 ? axisX : null,
        snapY: (axisY - ccy).abs() < _bw * 0.55 ? axisY : null,
        sctx: sctx,
      );
      final r = BlueprintRng(
        _hash2(seed, (co.x * 7 + 1).toInt(), (co.y * 7 + 2).toInt(), 0xB10C),
      );
      final gens = m == 'AXIS_H' ? _axisHGens : _axisVGens;
      final gi = _favPick(r, gens.length, lastAX, favAX);
      lastAX = gi;
      final k = _K(r);
      gens[gi](r, co, k, geo);
      prims.addAll(k.p);
    }

    for (var i = 0; i < mods.length; i++) {
      if (mods[i] != 'DETAIL') continue;
      final co = _Cell(ox + (i % _cells) * _bw, oy + (i ~/ _cells) * _bw);
      final ccx = co.x + _bw / 2;
      final ccy = co.y + _bw / 2;
      final geo = _Geo(
        segs: segs,
        circles: circles,
        axisX: axisX,
        axisY: axisY,
        snapX: (axisX - ccx).abs() < _bw * 0.55 ? axisX : null,
        snapY: (axisY - ccy).abs() < _bw * 0.55 ? axisY : null,
        sctx: sctx,
      );
      final r = BlueprintRng(
        _hash2(seed, (co.x * 7 + 5).toInt(), (co.y * 7 + 6).toInt(), 0xD3A0),
      );
      final gi = _favPick(r, _detailGens.length, lastDet, favDet);
      lastDet = gi;
      final k = _K(r);
      _detailGens[gi](r, co, k, geo);
      prims.addAll(k.p);
    }

    for (var i = 0; i < mods.length; i++) {
      if (mods[i] != 'ANNO') continue;
      final co = _Cell(ox + (i % _cells) * _bw, oy + (i ~/ _cells) * _bw);
      final r = BlueprintRng(
        _hash2(seed, (co.x * 7 + 3).toInt(), (co.y * 7 + 4).toInt(), 0xA000),
      );
      final k = _K(r);
      _genAnno(r, co, k, segs, circles, axisX, axisY, sctx);
      prims.addAll(k.p);
    }

    for (var i = 0; i < mods.length; i++) {
      if (mods[i] != 'EMPTY') continue;
      final ccx = ox + (i % _cells) * _bw + _bw / 2;
      final ccy = oy + (i ~/ _cells) * _bw + _bw / 2;
      prims.add(_Prim.cross(ccx, ccy, 0.2));
      if (rng.next() < 0.35) {
        final f = _pickFormula(rng);
        final mw = _mathWidth(f, 0.22);
        prims.add(_Prim.math(ccx - mw / 2, ccy + 0.45, f, 0.22));
      }
    }

    final result = List<_Prim>.unmodifiable(prims);
    if (_cache.length >= _cacheMax) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
    return result;
  }

  // ---------------------------------------------------------------
  // 渲染：世界坐标图元 → dp 图元（同原型 renderPrim）
  // ---------------------------------------------------------------
  static void _emit(List<BlueprintOp> ops, _Prim p, Offset camera) {
    const unit = BlueprintCanvas.unit;
    final geom = BlueprintCanvas.geom;
    final faint = BlueprintCanvas.faint;

    switch (p.kind) {
      case _PrimKind.line:
        ops.add(
          BlueprintOp.line(
            from: _at(camera, p.x1, p.y1),
            to: _at(camera, p.x2, p.y2),
            color: p.style == _solid ? geom : faint,
            dashed: p.style != _solid,
          ),
        );
      case _PrimKind.circle:
        ops.add(
          BlueprintOp.circle(
            center: _at(camera, p.cx, p.cy),
            radius: p.r * unit,
            color: p.style == _solid ? geom : faint,
          ),
        );
      case _PrimKind.arc:
        final lo = math.min(p.a0, p.a1);
        final hi = math.max(p.a0, p.a1);
        ops.add(
          BlueprintOp.arc(
            center: _at(camera, p.cx, p.cy),
            radius: p.r * unit,
            startAngle: lo,
            sweepAngle: hi - lo,
            color: p.style == _solid ? geom : faint,
          ),
        );
      case _PrimKind.text:
        _textOp(ops, _at(camera, p.cx, p.cy), p.text, p.fh * unit);
      case _PrimKind.math:
        final fs = p.fh * unit;
        ops.add(
          BlueprintOp.text(
            at: _at(camera, p.cx, p.cy) + Offset(0, -fs * 0.7),
            text: p.text,
            fontSize: fs,
            color: BlueprintCanvas.label,
          ),
        );
      case _PrimKind.dim:
        _dimLine(ops, p, camera);
      case _PrimKind.dimRadius:
        _dimRadius(ops, p, camera, diameter: false);
      case _PrimKind.dimDiameter:
        _dimRadius(ops, p, camera, diameter: true);
      case _PrimKind.cross:
        final c = _at(camera, p.cx, p.cy);
        final e = p.r * unit;
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
      case _PrimKind.hatch:
        _hatch(ops, p, camera);
      case _PrimKind.section:
        _section(ops, p, camera);
      case _PrimKind.arrow:
        final a = _at(camera, p.x1, p.y1);
        final b = _at(camera, p.x2, p.y2);
        ops.add(BlueprintOp.line(from: a, to: b, color: faint));
        _arrowHead(ops, b, a, unit * 0.09);
    }
  }

  /// 世界坐标 → 屏幕 dp。
  static Offset _at(Offset camera, double x, double y) => Offset(
    camera.dx + x * BlueprintCanvas.unit,
    camera.dy + y * BlueprintCanvas.unit,
  );

  /// 中心对齐文字 → [BlueprintOp.text]（左上角锚点）的近似修正。
  static void _textOp(
    List<BlueprintOp> ops,
    Offset center,
    String text,
    double fontSize,
  ) {
    ops.add(
      BlueprintOp.text(
        at: center + Offset(-fontSize * 0.35 * text.length, -fontSize / 2),
        text: text,
        fontSize: fontSize,
        color: BlueprintCanvas.label,
      ),
    );
  }

  /// 尺寸线：两条引出线 + 主线 + 两端箭头 + 中点文字。
  static void _dimLine(List<BlueprintOp> ops, _Prim p, Offset camera) {
    const unit = BlueprintCanvas.unit;
    final faint = BlueprintCanvas.faint;
    final wdx = p.x2 - p.x1;
    final wdy = p.y2 - p.y1;
    final wlen = math.sqrt(wdx * wdx + wdy * wdy);
    if (wlen < 1e-4) return;

    final ux = wdx / wlen;
    final uy = wdy / wlen;
    final nx = -uy;
    final ny = ux;
    final sgn = p.off < 0 ? -1.0 : 1.0;
    final d = p.off.abs();
    final q1x = p.x1 + nx * sgn * d;
    final q1y = p.y1 + ny * sgn * d;
    final q2x = p.x2 + nx * sgn * d;
    final q2y = p.y2 + ny * sgn * d;
    final ext = math.min(0.14, d * 0.35 + 0.05);

    ops
      ..add(
        BlueprintOp.line(
          from: _at(camera, p.x1 + nx * sgn * 0.04, p.y1 + ny * sgn * 0.04),
          to: _at(camera, q1x + nx * sgn * ext, q1y + ny * sgn * ext),
          color: faint,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: _at(camera, p.x2 + nx * sgn * 0.04, p.y2 + ny * sgn * 0.04),
          to: _at(camera, q2x + nx * sgn * ext, q2y + ny * sgn * ext),
          color: faint,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: _at(camera, q1x, q1y),
          to: _at(camera, q2x, q2y),
          color: faint,
        ),
      );

    final q1 = _at(camera, q1x, q1y);
    final q2 = _at(camera, q2x, q2y);
    final as = math.min(unit * 0.09, (q2 - q1).distance * 0.06 + 3);
    _arrowHead(ops, q1, q2, as);
    _arrowHead(ops, q2, q1, as);

    final tgap = d + 0.09 + math.min(0.2, d * 0.3);
    final mx = (q1x + q2x) / 2 + nx * sgn * tgap;
    final my = (q1y + q2y) / 2 + ny * sgn * tgap;
    final text = p.text.isEmpty ? wlen.toStringAsFixed(1) : p.text;
    _textOp(ops, _at(camera, mx, my), text, 0.16 * unit);
  }

  /// 半径 / 直径标注：主线 + 箭头 + 文字。
  static void _dimRadius(
    List<BlueprintOp> ops,
    _Prim p,
    Offset camera, {
    required bool diameter,
  }) {
    const unit = BlueprintCanvas.unit;
    final faint = BlueprintCanvas.faint;
    final ca = math.cos(p.a0);
    final sa = math.sin(p.a0);

    if (!diameter) {
      final ex = p.cx + ca * p.r;
      final ey = p.cy + sa * p.r;
      final ext = math.min(0.4, p.r * 0.25 + 0.15);
      final tx = p.cx + ca * (p.r + ext);
      final ty = p.cy + sa * (p.r + ext);
      ops.add(
        BlueprintOp.line(
          from: _at(camera, p.cx, p.cy),
          to: _at(camera, tx, ty),
          color: faint,
        ),
      );
      _arrowHead(ops, _at(camera, ex, ey), _at(camera, tx, ty), unit * 0.09);
      final text = p.text.isEmpty ? 'R${p.r.toStringAsFixed(1)}' : p.text;
      _textOp(
        ops,
        _at(camera, tx + ca * 0.22, ty + sa * 0.22),
        text,
        0.12 * unit,
      );
      return;
    }

    final x1 = p.cx - ca * p.r;
    final y1 = p.cy - sa * p.r;
    final x2 = p.cx + ca * p.r;
    final y2 = p.cy + sa * p.r;
    final c = _at(camera, p.cx, p.cy);
    final a = _at(camera, x1, y1);
    final b = _at(camera, x2, y2);
    ops.add(BlueprintOp.line(from: a, to: b, color: faint));
    _arrowHead(ops, a, c, unit * 0.09);
    _arrowHead(ops, b, c, unit * 0.09);
    final text = p.text.isEmpty ? 'Ø${(p.r * 2).toStringAsFixed(1)}' : p.text;
    _textOp(
      ops,
      _at(camera, p.cx + ca * (p.r + 0.32), p.cy + sa * (p.r + 0.32)),
      text,
      0.12 * unit,
    );
  }

  /// 剖面线矩形：四条边 + 一组平行斜线（斜线裁到矩形内）。
  static void _hatch(List<BlueprintOp> ops, _Prim p, Offset camera) {
    final faint = BlueprintCanvas.faint;
    final x0 = p.x1;
    final y0 = p.y1;
    final x1 = x0 + p.hw;
    final y1 = y0 + p.hh;

    ops
      ..add(
        BlueprintOp.line(
          from: _at(camera, x0, y0),
          to: _at(camera, x1, y0),
          color: faint,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: _at(camera, x1, y0),
          to: _at(camera, x1, y1),
          color: faint,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: _at(camera, x1, y1),
          to: _at(camera, x0, y1),
          color: faint,
        ),
      )
      ..add(
        BlueprintOp.line(
          from: _at(camera, x0, y1),
          to: _at(camera, x0, y0),
          color: faint,
        ),
      );

    final cs = math.cos(p.ang);
    final sn = math.sin(p.ang);
    final corners = <Offset>[
      Offset(x0, y0),
      Offset(x1, y0),
      Offset(x1, y1),
      Offset(x0, y1),
    ];
    var dmin = double.infinity;
    var dmax = -double.infinity;
    var nmin = double.infinity;
    var nmax = -double.infinity;
    for (final c in corners) {
      final dv = c.dx * cs + c.dy * sn;
      final nv = -c.dx * sn + c.dy * cs;
      dmin = math.min(dmin, dv);
      dmax = math.max(dmax, dv);
      nmin = math.min(nmin, nv);
      nmax = math.max(nmax, nv);
    }

    if (!(p.step > 0)) return;
    for (var kv = nmin; kv <= nmax; kv += p.step) {
      final px1 = dmin * cs - kv * sn;
      final py1 = dmin * sn + kv * cs;
      final px2 = dmax * cs - kv * sn;
      final py2 = dmax * sn + kv * cs;
      final clipped = _clipSegment(x0, y0, x1, y1, px1, py1, px2, py2);
      if (clipped == null) continue;
      ops.add(
        BlueprintOp.line(
          from: _at(camera, clipped.$1, clipped.$2),
          to: _at(camera, clipped.$3, clipped.$4),
          color: faint,
        ),
      );
    }
  }

  /// 剖切符号：粗虚线 + 两端短横 + 两个字符。
  static void _section(List<BlueprintOp> ops, _Prim p, Offset camera) {
    const unit = BlueprintCanvas.unit;
    final faint = BlueprintCanvas.faint;
    final wdx = p.x2 - p.x1;
    final wdy = p.y2 - p.y1;
    final wlen = math.sqrt(wdx * wdx + wdy * wdy);
    if (wlen < 1e-4) return;
    final ux = wdx / wlen;
    final uy = wdy / wlen;

    ops.add(
      BlueprintOp.line(
        from: _at(camera, p.x1, p.y1),
        to: _at(camera, p.x2, p.y2),
        color: faint,
        dashed: true,
      ),
    );
    for (var i = 0; i < 2; i++) {
      final px = i == 0 ? p.x1 : p.x2;
      final py = i == 0 ? p.y1 : p.y2;
      ops.add(
        BlueprintOp.line(
          from: _at(camera, px - uy * 0.12, py + ux * 0.12),
          to: _at(camera, px + uy * 0.12, py - ux * 0.12),
          color: faint,
        ),
      );
    }
    _arrowHead(
      ops,
      _at(camera, p.x1, p.y1),
      _at(camera, p.x1 + ux * 0.3, p.y1 + uy * 0.3),
      unit * 0.09,
    );
    _arrowHead(
      ops,
      _at(camera, p.x2, p.y2),
      _at(camera, p.x2 - ux * 0.3, p.y2 - uy * 0.3),
      unit * 0.09,
    );
    _textOp(
      ops,
      _at(camera, p.x1 - ux * 0.25, p.y1 - uy * 0.25),
      p.ch,
      0.15 * unit,
    );
    _textOp(
      ops,
      _at(camera, p.x2 + ux * 0.25, p.y2 + uy * 0.25),
      p.ch,
      0.15 * unit,
    );
  }

  /// 箭头两撇（[tip] 为尖端，[from] 决定朝向），与画布层同思路。
  static void _arrowHead(
    List<BlueprintOp> ops,
    Offset tip,
    Offset from,
    double size,
  ) {
    final a = math.atan2(tip.dy - from.dy, tip.dx - from.dx);
    for (final d in const [-0.32, 0.32]) {
      ops.add(
        BlueprintOp.line(
          from: tip,
          to: tip - Offset(math.cos(a - d), math.sin(a - d)) * size,
          color: BlueprintCanvas.faint,
        ),
      );
    }
  }

  /// 线段裁到轴对齐矩形（Liang–Barsky），返回世界坐标端点。
  static (double, double, double, double)? _clipSegment(
    double xmin,
    double ymin,
    double xmax,
    double ymax,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    var t0 = 0.0;
    var t1 = 1.0;
    final dx = x2 - x1;
    final dy = y2 - y1;

    bool clip(double p, double q) {
      if (p.abs() < 1e-12) return q >= 0;
      final r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    }

    if (!clip(-dx, x1 - xmin)) return null;
    if (!clip(dx, xmax - x1)) return null;
    if (!clip(-dy, y1 - ymin)) return null;
    if (!clip(dy, ymax - y1)) return null;
    return (x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy);
  }

  // ---------------------------------------------------------------
  // MEGA 生成器（7 种，同原型 MEGA_GENS）
  // ---------------------------------------------------------------
  static void _megaTurbine(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    s.pub('megaName', 'TURBINE');
    final cx = geo.snapX ?? (o.x + geo.mw / 2);
    final cy = geo.snapY ?? (o.y + geo.mh / 2);
    final r1 = math.min(geo.mw, geo.mh) * 0.36 * s.style.chunk;
    g.circ(cx, cy, r1);
    g.circ(cx, cy, r1 * 0.92);
    g.circ(cx, cy, r1 * 0.22);
    g.circ(cx, cy, r1 * 0.10);
    k.c(cx, cy, r1 * 0.62, _dashed);

    final nb = 12 + r.nextInt(6);
    final a0 = r.next() * 0.5;
    for (var i = 0; i < nb; i++) {
      final a = a0 + i / nb * 6.2832;
      g.seg(
        cx + math.cos(a) * r1 * 0.24,
        cy + math.sin(a) * r1 * 0.24,
        cx + math.cos(a) * r1 * 0.90,
        cy + math.sin(a) * r1 * 0.90,
      );
    }
    for (var i = 0; i < nb; i++) {
      final a = a0 + (i + 0.5) / nb * 6.2832;
      g.circ(
        cx + math.cos(a) * r1 * 0.62,
        cy + math.sin(a) * r1 * 0.62,
        r1 * 0.055,
      );
    }
    k.cm(cx, cy, r1 * 1.12);
    if (geo.snapY != null) {
      k.l(cx - r1 * 1.3, cy, cx + r1 * 1.3, cy, _center);
    }
    if (geo.snapX != null) {
      k.l(cx, cy - r1 * 1.3, cx, cy + r1 * 1.3, _center);
    }
    k.dd(cx, cy, r1, a0 + 0.9, 'Ø${_f1(r1 * 2)}');
    k.dr(cx, cy, r1 * 0.62, a0 + 2.4, 'R${_f1(r1 * 0.62)} B.C.');
    final num = s.nextEq();
    k.m(cx - r1 * 0.9, cy + r1 * 1.6, 0.3);
    k.t(cx + 0.9, cy + r1 * 1.6, '($num)', 0.16);
  }

  static void _megaHullSec(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    s.pub('megaName', 'HULL SEC');
    final cx = geo.snapX ?? (o.x + geo.mw / 2);
    final cy = geo.snapY ?? (o.y + geo.mh / 2);
    final b = geo.mw * 0.42;
    final d = geo.mh * 0.24 * s.style.chunk;
    final yDeck = cy + d * 0.45;
    final yBase = cy - d * 0.55;

    final pts = <Offset>[];
    for (var i = 0; i <= 8; i++) {
      final t = i / 8;
      pts.add(
        Offset(
          cx - b * (0.32 + 0.68 * math.sin(t * math.pi / 2)),
          yBase + t * (yDeck - yBase),
        ),
      );
    }
    for (var i = 1; i < pts.length; i++) {
      g.seg(pts[i - 1].dx, pts[i - 1].dy, pts[i].dx, pts[i].dy);
    }
    for (var i = 1; i < pts.length; i++) {
      g.seg(
        2 * cx - pts[i - 1].dx,
        pts[i - 1].dy,
        2 * cx - pts[i].dx,
        pts[i].dy,
      );
    }
    g.seg(cx - b, yDeck, cx + b, yDeck);
    g.seg(cx - b * 0.50, yBase + d * 0.18, cx + b * 0.50, yBase + d * 0.18);
    g.seg(cx - b * 0.56, yBase + d * 0.32, cx + b * 0.56, yBase + d * 0.32);

    final nb = 4 + r.nextInt(3);
    for (var i = 1; i <= nb; i++) {
      final x = cx - b + i / (nb + 1) * 2 * b;
      g.seg(x, yBase + d * 0.32, x, yDeck);
    }
    for (var i = 0; i <= 12; i++) {
      final x = cx - b * 0.9 + i / 12 * b * 1.8;
      k.l(x, yBase, x, yDeck, _center);
    }
    k.l(cx - b, yBase + d * 0.52, cx + b, yBase + d * 0.52, _dashed);
    k.t(cx + b + 0.35, yBase + d * 0.52, 'WL', 0.15);
    k.dl(cx - b, yDeck, cx + b, yDeck, s.dimOff(r), _f1(2 * b));
    k.dl(cx + b, yBase, cx + b, yDeck, s.dimOff(r), _f1(yDeck - yBase));
    final num = s.nextEq();
    k.m(cx, cy - d * 1.1, 0.32);
    k.t(cx + 1.6, cy - d * 1.1, '($num)', 0.16);
  }

  static void _megaFrame(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    s.pub('megaName', 'FRAME');
    final cx = geo.snapX ?? (o.x + geo.mw / 2);
    final cy = geo.snapY ?? (o.y + geo.mh / 2);
    final w2 = geo.mw * 0.62;
    final h2 = geo.mh * 0.55;
    final x0 = cx - w2 / 2;
    final y0 = cy - h2 * 0.35;
    final cols = 4 + r.nextInt(3);
    final floors = 3 + r.nextInt(3);

    for (var i = 0; i <= cols; i++) {
      final x = x0 + i / cols * w2;
      g.seg(x, y0, x, y0 + h2);
      g.seg(x - 0.09, y0, x + 0.09, y0);
    }
    for (var f = 0; f <= floors; f++) {
      final y = y0 + f / floors * h2;
      g.seg(x0, y, x0 + w2, y);
    }
    final tw = w2 * 0.15;
    g.box(cx - tw / 2, y0 + h2 * 0.28, tw, h2 * 0.72);
    k.ht(
      cx - tw / 2,
      y0 + h2 * 0.28,
      tw,
      h2 * 0.72,
      math.pi / 4,
      s.style.hatch * 2.5,
    );
    final sh = y0 + h2 / floors - y0;
    g.seg(x0 + w2 * 0.84, y0, x0 + w2 * 0.96, y0 + sh);
    g.seg(x0 + w2 * 0.84, y0, x0 + w2 * 0.84, y0 + sh);
    for (var i = 0; i <= cols; i++) {
      final x = x0 + i / cols * w2;
      k.l(x, y0 + h2, x, y0 + h2 + 0.23, _center);
      k.c(x, y0 + h2 + 0.46, 0.23);
      k.t(x, y0 + h2 + 0.46, '${i + 1}', 0.22);
    }
    k.dl(x0, y0, x0 + w2, y0, -s.dimOff(r), _f1(w2));
    k.dl(x0 + w2, y0, x0 + w2, y0 + h2, s.dimOff(r), _f1(h2));
  }

  static void _megaTankFarm(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    s.pub('megaName', 'TANK FARM');
    final cy0 = geo.snapY ?? (o.y + geo.mh / 2);
    final totalW = geo.mw * 0.78;
    final x0 = geo.snapX != null
        ? geo.snapX! - totalW / 2
        : o.x + geo.mw * 0.11;
    final n = 3 + r.nextInt(2);
    final tw = totalW / n;
    final byy = cy0 - geo.mh * 0.24;
    g.box(x0 - 0.7, byy - 0.5, totalW + 1.4, geo.mh * 0.66);
    for (var i = 0; i < n; i++) {
      final cxx = x0 + tw * (i + 0.5);
      final w = tw * 0.60;
      final h = geo.mh * (0.30 + r.next() * 0.16);
      g.seg(cxx - w / 2, byy, cxx - w / 2, byy + h);
      g.seg(cxx + w / 2, byy, cxx + w / 2, byy + h);
      g.seg(cxx - w / 2, byy, cxx + w / 2, byy);
      g.seg(cxx - w / 2, byy + h, cxx, byy + h + 0.4);
      g.seg(cxx + w / 2, byy + h, cxx, byy + h + 0.4);
      k.l(cxx - w / 2, byy + h * 0.68, cxx + w / 2, byy + h * 0.68, _dashed);
      k.dl(
        cxx - w / 2,
        byy - 0.28,
        cxx + w / 2,
        byy - 0.28,
        -s.dimOff(r),
        _f1(w),
      );
    }
    g.seg(x0 - 0.7, byy - 0.22, x0 + totalW + 0.7, byy - 0.22);
    g.seg(x0 - 0.7, byy - 0.34, x0 + totalW + 0.7, byy - 0.34);
    k.dl(
      x0,
      byy + geo.mh * 0.44,
      x0 + totalW,
      byy + geo.mh * 0.44,
      s.dimOff(r),
      _f1(totalW),
    );
  }

  static void _megaGearbox(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    s.pub('megaName', 'GEARBOX');
    final axY = geo.snapY ?? (o.y + geo.mh / 2);
    final x0 = geo.snapX != null
        ? geo.snapX! - geo.mw * 0.36
        : o.x + geo.mw * 0.14;
    final len = geo.mw * 0.72;
    g.box(x0, axY - geo.mh * 0.30, len, geo.mh * 0.07);
    k.ht(
      x0,
      axY - geo.mh * 0.30,
      len,
      geo.mh * 0.07,
      math.pi / 4,
      s.style.hatch * 2,
    );

    for (var j = 0; j < 2; j++) {
      final ay = axY + (j == 0 ? geo.mh * 0.05 : -geo.mh * 0.12);
      final n = 4 + r.nextInt(3);
      final ws = <double>[];
      var tot = 0.0;
      for (var i = 0; i < n; i++) {
        final w = len * 0.66 / n * (0.7 + r.next() * 0.6);
        ws.add(w);
        tot += w;
      }
      var xx = x0 + (len - tot) / 2;
      for (var i = 0; i < n; i++) {
        final h = 0.30 + r.next() * 0.22;
        g.box(xx, ay - h / 2, ws[i], h);
        xx += ws[i];
      }
      g.box(x0 + len * 0.05, ay - 0.30, len * 0.05, 0.60);
      g.box(x0 + len * 0.90, ay - 0.30, len * 0.05, 0.60);
      k.l(x0 - 0.5, ay, x0 + len + 0.5, ay, _center);
    }
    g.box(x0 - 2.4, axY - 0.8, 2.0, 1.6);
    for (var i = 0; i < 6; i++) {
      k.l(x0 - 2.3 + i * 0.32, axY + 0.8, x0 - 2.3 + i * 0.32, axY + 1.02);
    }
    g.circ(x0 - 0.2, axY, 0.44);
    g.circ(x0 - 0.2, axY, 0.18);
    k.dl(
      x0,
      axY - geo.mh * 0.36,
      x0 + len,
      axY - geo.mh * 0.36,
      -s.dimOff(r) * 1.4,
      _f1(len),
    );
    final num = s.nextEq();
    k.m(x0 + len * 0.35, axY + geo.mh * 0.34, 0.3);
    k.t(x0 + len * 0.35 + 1.2, axY + geo.mh * 0.34, '($num)', 0.16);
  }

  static void _megaTruss(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    s.pub('megaName', 'TRUSS BR');
    final cx = geo.snapX ?? (o.x + geo.mw / 2);
    final cy = geo.snapY ?? (o.y + geo.mh / 2);
    final sp = geo.mw * 0.80;
    final th = geo.mh * 0.26;
    final x0 = cx - sp / 2;
    final x1 = cx + sp / 2;
    final yB = cy + th * 0.5;
    final yT = yB - th;
    g.seg(x0, yB, x1, yB);
    g.seg(x0, yT, x1, yT);
    final n = 6 + r.nextInt(4);
    final nodes = <double>[];
    for (var i = 0; i <= n; i++) {
      final x = x0 + sp * i / n;
      nodes.add(x);
      g.seg(x, yB, x, yT);
      if (i < n) {
        final xm = x0 + sp * (i + 0.5) / n;
        if (i % 2 == 0) {
          g.seg(x, yB, xm, yT);
          g.seg(xm, yT, x + sp / n, yB);
        } else {
          g.seg(x, yT, xm, yB);
          g.seg(xm, yB, x + sp / n, yT);
        }
      }
    }
    for (final x in nodes) {
      g.circ(x, yB, 0.09);
      g.circ(x, yT, 0.09);
    }
    g.seg(x0 - 0.5, yB, x1 + 0.5, yB);
    k.ht(x0 - 0.5, yB - 0.45, sp + 1, 0.45, math.pi / 4, s.style.hatch * 1.5);
    for (final x in [x0, x1]) {
      g.seg(x - 0.35, yB + 0.5, x, yB);
      g.seg(x + 0.35, yB + 0.5, x, yB);
      g.seg(x - 0.35, yB + 0.5, x + 0.35, yB + 0.5);
    }
    k.dl(x0, yT - 0.4, x1, yT - 0.4, -s.dimOff(r), _f1(sp));
    k.dl(x1, yB, x1, yT, s.dimOff(r), _f1(th));
  }

  static void _megaPlan(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    s.pub('megaName', 'PLAN L1');
    final cx = geo.snapX ?? (o.x + geo.mw / 2);
    final cy = geo.snapY ?? (o.y + geo.mh / 2);
    final w2 = geo.mw * 0.72;
    final h2 = geo.mh * 0.50;
    final x0 = cx - w2 / 2;
    final y0 = cy - h2 / 2;
    g.box(x0, y0, w2, h2);

    final cxN = 2 + r.nextInt(2);
    final cyN = 1 + r.nextInt(2);
    for (var i = 1; i < cxN; i++) {
      final x = x0 + w2 * i / cxN;
      final gy = y0 + h2 * (0.3 + r.next() * 0.4);
      final gap = 0.5 + r.next() * 0.4;
      g.seg(x, y0, x, gy);
      g.seg(x, gy + gap, x, y0 + h2);
    }
    for (var j = 1; j < cyN; j++) {
      final y = y0 + h2 * j / cyN;
      final gx = x0 + w2 * (0.3 + r.next() * 0.4);
      final gap = 0.5 + r.next() * 0.4;
      g.seg(x0, y, gx, y);
      g.seg(x0 + gx + gap, y, x0 + w2, y);
    }

    final ncx = 4 + r.nextInt(3);
    final ncy = 3 + r.nextInt(2);
    for (var i = 1; i < ncx; i++) {
      for (var j = 1; j < ncy; j++) {
        final px = x0 + w2 * i / ncx;
        final py = y0 + h2 * j / ncy;
        g.seg(px - 0.08, py - 0.08, px + 0.08, py + 0.08);
        g.seg(px - 0.08, py + 0.08, px + 0.08, py - 0.08);
      }
    }
    final rw = w2 / cxN;
    final rh = h2 / cyN;
    k.ht(x0, y0, rw, rh, math.pi / 4, s.style.hatch * 1.5);
    k.t(
      x0 + rw / 2,
      y0 + rh / 2 + 0.3,
      '${(rw * rh * 56.25).toStringAsFixed(0)} m²',
      0.16,
    );
    k.t(cx, y0 + h2 + 0.5, 'LEVEL 1', 0.16);
    k.dl(x0, y0, x0 + w2, y0, -s.dimOff(r), _f1(w2));
    k.dl(x0 + w2, y0, x0 + w2, y0 + h2, s.dimOff(r), _f1(h2));
  }

  // ---------------------------------------------------------------
  // AXIS_H 生成器（5 种，同原型 AXIS_H_GENS）
  // ---------------------------------------------------------------
  static void _axisHSteps(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = geo.snapY ?? (o.y + _bw / 2);
    final n = 3 + r.nextInt(3);
    final ws = <double>[];
    final hs = <double>[];
    var tw = 0.0;
    for (var i = 0; i < n; i++) {
      final w = (0.5 + r.next() * 0.8) * s.style.slender;
      final h = (0.16 + r.next() * 0.26) * s.style.chunk;
      ws.add(w);
      hs.add(h);
      tw += w;
    }
    var x = o.x + (_bw - tw) / 2;
    final x0 = x;
    final shaftSegs = <_ShaftSeg>[];
    for (var i = 0; i < n; i++) {
      g.box(x, cy - hs[i], ws[i], hs[i] * 2);
      shaftSegs.add(_ShaftSeg(x, ws[i]));
      x += ws[i];
    }
    s.pub('shaftY', cy);
    s.pub('shaftR', hs[n - 1]);
    s.pub('shaftSpan', _Span(x0, x));
    s.pub('shaftSegs', shaftSegs);
    k.l(o.x, cy, o.x + _bw, cy, _center);

    x = x0;
    for (var i = 0; i < n; i++) {
      k.dl(
        x + ws[i] / 2,
        cy - hs[i],
        x + ws[i] / 2,
        cy + hs[i],
        s.dimOff(r),
        'Ø${_f1(hs[i] * 2)}',
      );
      x += ws[i];
    }
    var base = cy - hs[0] - s.dimOff(r);
    x = x0;
    for (var i = 0; i < n; i++) {
      k.dl(x, base, x + ws[i], base, -(base - cy).abs(), _f1(ws[i]));
      x += ws[i];
      base -= 0.15;
    }
  }

  static void _axisHBeam(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = geo.snapY ?? (o.y + _bw / 2);
    final len = _bw - 0.5;
    final d = (0.30 + r.next() * 0.20) * s.style.chunk;
    final x0 = o.x + 0.25;
    final y0 = cy - d / 2;
    g.box(x0, y0, len, d);
    k.l(x0, y0 + d * 0.3, x0 + len, y0 + d * 0.3);
    for (final x in [x0 + 0.35, x0 + len - 0.35]) {
      final y = y0 + d;
      k.l(x - 0.12, y + 0.18, x, y);
      k.l(x + 0.12, y + 0.18, x, y);
      k.l(x - 0.12, y + 0.18, x + 0.12, y + 0.18);
    }
    s.pub('shaftY', cy);
    s.pub('shaftR', d / 2);
    k.l(o.x, cy, o.x + _bw, cy, _center);
    k.dl(x0, y0, x0 + len, y0, -s.dimOff(r), _f1(len));
    k.dl(x0 + len, y0, x0 + len, y0 + d, s.dimOff(r), _f1(d));
    k.t(
      x0 + len / 2,
      y0 + d + 0.42,
      _pick(r, const ['GL-1', 'KL-3', 'W12×26', 'B-2']),
      0.14,
    );
  }

  static void _axisHRound(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = geo.snapY ?? (o.y + _bw / 2);
    final rr = (0.20 + r.next() * 0.16) * s.style.chunk;
    final x0 = o.x + 0.3;
    final x1 = o.x + _bw - 0.3;
    g.seg(x0, cy - rr, x1, cy - rr);
    g.seg(x0, cy + rr, x1, cy + rr);
    k.a(x0, cy, rr, math.pi * 0.5, math.pi * 1.5);
    k.a(x1, cy, rr, -math.pi * 0.5, math.pi * 0.5);
    s.pub('shaftY', cy);
    s.pub('shaftR', rr);
    k.l(o.x, cy, o.x + _bw, cy, _center);
    k.dl(x0, cy - rr, x0, cy + rr, s.dimOff(r), _f1(rr * 2));
    k.t(x0 + (x1 - x0) / 2, cy - rr - 0.25, 'Ø${_f1(rr * 2)} WALL 2.5', 0.12);
  }

  static void _axisHTaper(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = geo.snapY ?? (o.y + _bw / 2);
    final r1 = 0.34 + r.next() * 0.22;
    final r2 = r1 * (0.5 + r.next() * 0.35);
    final p1x = o.x + 1.3;
    final p2x = o.x + _bw - 1.3;
    g.circ(p1x, cy, r1);
    g.circ(p1x, cy, r1 * 0.16);
    g.circ(p2x, cy, r2);
    g.circ(p2x, cy, r2 * 0.18);
    g.seg(p1x, cy - r1, p2x, cy - r2);
    g.seg(p1x, cy + r1, p2x, cy + r2);
    g.seg(p1x, cy - r1, p1x, cy + r1, _center);
    g.seg(p2x, cy - r2, p2x, cy + r2, _center);
    s.pub('shaftY', cy);
    s.pub('shaftR', r2);
    k.l(o.x, cy, o.x + _bw, cy, _center);
    k.dr(p1x, cy, r1, r.next() * 6.28, 'R${_f1(r1)}');
    k.dr(p2x, cy, r2, r.next() * 6.28, 'R${_f1(r2)}');
    final num = s.nextEq();
    k.m((p1x + p2x) / 2 - 0.8, cy - r1 - 0.62, 0.26);
    k.t((p1x + p2x) / 2 + 0.75, cy - r1 - 0.62, '($num)', 0.15);
  }

  static void _axisHThread(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = geo.snapY ?? (o.y + _bw / 2);
    final rr = (0.13 + r.next() * 0.08) * s.style.chunk;
    final x0 = o.x + 0.3;
    final x1 = o.x + _bw - 0.3;
    g.box(x0, cy - rr, x1 - x0, rr * 2);
    final n = ((x1 - x0) / 0.16).floor();
    for (var i = 0; i < n; i++) {
      final xx = x0 + 0.08 + i * 0.16;
      k.l(xx, cy - rr, xx + 0.08, cy + rr);
    }
    s.pub('shaftY', cy);
    s.pub('shaftR', rr);
    k.l(o.x, cy, o.x + _bw, cy, _center);
    k.dl(x0, cy + rr, x1, cy + rr, -s.dimOff(r), _f1(x1 - x0));
    k.t(
      x0 + (x1 - x0) / 2,
      cy - rr - 0.25,
      _pick(r, const ['M12×1.75', 'M16×2.0', 'TR20×4']),
      0.12,
    );
  }

  // ---------------------------------------------------------------
  // AXIS_V 生成器（5 种，同原型 AXIS_V_GENS）
  // ---------------------------------------------------------------
  static void _axisVSteps(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final n = 3 + r.nextInt(2);
    final segs = <List<double>>[];
    var th = 0.0;
    var maxW = 0.25;
    for (var i = 0; i < n; i++) {
      final h = (0.55 + r.next() * 0.7) * s.style.slender;
      final w = (0.20 + r.next() * 0.26) * s.style.chunk;
      segs.add([h, w]);
      th += h;
      maxW = math.max(maxW, w);
    }
    final y0 = o.y + (_bw - th) / 2;
    var y = y0;
    k.l(cx, o.y, cx, o.y + _bw, _center);
    for (var i = 0; i < n; i++) {
      final h = segs[i][0];
      final w = segs[i][1];
      g.box(cx - w, y, w * 2, h);
      k.dl(cx - w, y + h / 2, cx + w, y + h / 2, s.dimOff(r), 'Ø${_f1(w * 2)}');
      y += h;
    }
    s.pub('shaftX', cx);
    s.pub('shaftR', maxW);
    k.dl(cx - maxW - 0.3, y0, cx - maxW - 0.3, y0 + th, -s.dimOff(r), _f1(th));
  }

  static void _axisVShaft(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final w = (0.8 + r.next() * 0.4) * s.style.chunk;
    final len = _bw - 0.6;
    final n = 9 + r.nextInt(6);
    final y0 = o.y + 0.3;
    g.seg(cx - w / 2, y0, cx - w / 2, y0 + len);
    g.seg(cx + w / 2, y0, cx + w / 2, y0 + len);
    for (var i = 1; i < n; i++) {
      final y = y0 + len * i / n;
      k.l(cx - w / 2, y, cx + w / 2, y);
    }
    k.l(cx, y0 - 0.15, cx, y0 + len + 0.15, _center);
    s.pub('shaftX', cx);
    k.c(cx, y0 + 0.14, 0.055);
    k.ar(cx, y0 + 0.14, cx, y0 + len - 0.14);
    k.t(cx + w / 2 + 0.18, y0 + len / 2, 'UP', 0.12);
    k.dl(cx + w / 2, y0, cx + w / 2, y0 + len, s.dimOff(r), _f1(len));
  }

  static void _axisVHollow(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final len = _bw - 0.4;
    const th = 0.16;
    final gap = 0.7 + r.next() * 0.3;
    final x0 = cx - th / 2;
    final y0 = o.y + 0.2;
    final gy = y0 + 0.35 + r.next() * (len - gap - 0.7);
    g.seg(x0, y0, x0, gy);
    g.seg(x0, gy + gap, x0, y0 + len);
    g.seg(x0 + th, y0, x0 + th, gy);
    g.seg(x0 + th, gy + gap, x0 + th, y0 + len);
    for (final y in [y0, gy, gy + gap, y0 + len]) {
      k.l(x0, y, x0 + th, y);
    }
    k.l(x0 + th, gy, x0 + th + gap, gy);
    k.a(x0 + th, gy, gap, math.pi / 2, math.pi);
    s.pub('shaftX', cx);
    k.dl(x0, y0, x0, y0 + len, -s.dimOff(r), _f1(len));
  }

  static void _axisVPiston(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final bw = (0.5 + r.next() * 0.2) * s.style.chunk;
    final bh = 1.6 + r.next() * 0.8;
    final rw = bw * 0.42;
    final rl = 1.0 + r.next() * 0.8;
    final y0 = o.y + _bw / 2 - bh / 2;
    g.box(cx - bw / 2, y0, bw, bh);
    k.ht(cx - bw / 2, y0, bw, bh, math.pi / 4, s.style.hatch);
    g.box(cx - rw / 2, y0 + bh, rw, rl);
    g.seg(cx - bw / 2, y0 + bh * 0.2, cx - bw / 2 - 0.2, y0 + bh * 0.2);
    g.seg(cx + bw / 2, y0 + bh * 0.2, cx + bw / 2 + 0.2, y0 + bh * 0.2);
    s.pub('shaftX', cx);
    s.pub('shaftR', bw / 2);
    k.l(cx, y0 - 0.2, cx, y0 + bh + rl + 0.2, _center);
    k.dl(
      cx - bw / 2,
      y0 - 0.25,
      cx + bw / 2,
      y0 - 0.25,
      -s.dimOff(r),
      'Ø${_f1(bw)}',
    );
    k.dl(cx - bw / 2, y0, cx - bw / 2, y0 + bh, -s.dimOff(r), _f1(bh));
    final num = s.nextEq();
    k.m(cx - bw / 2 - 0.1, y0 + bh + rl + 0.45, 0.24);
    k.t(cx - bw / 2 + 0.5, y0 + bh + rl + 0.45, '($num)', 0.14);
  }

  static void _axisVTruss(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final wB = (1.0 + r.next() * 0.4) * s.style.chunk;
    final wT = wB * 0.5;
    final y0 = o.y + 0.3;
    final y1 = o.y + _bw - 0.5;
    g.seg(cx - wB / 2, y0, cx - wT / 2, y1);
    g.seg(cx + wB / 2, y0, cx + wT / 2, y1);
    final n = 5 + r.nextInt(4);
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final xl = cx - wB / 2 + (-wT / 2 + wB / 2) * t;
      final xr = cx + wB / 2 + (wT / 2 - wB / 2) * t;
      final y = y0 + (y1 - y0) * t;
      g.seg(xl, y, xr, y);
      if (i < n) {
        final t2 = (i + 1) / n;
        final xl2 = cx - wB / 2 + (-wT / 2 + wB / 2) * t2;
        final xr2 = cx + wB / 2 + (wT / 2 - wB / 2) * t2;
        final y2 = y0 + (y1 - y0) * t2;
        if (i % 2 == 0) {
          g.seg(xl, y, xr2, y2);
        } else {
          g.seg(xr, y, xl2, y2);
        }
      }
    }
    g.box(cx - wB * 0.7, y0 - 0.14, wB * 1.4, 0.14);
    s.pub('shaftX', cx);
    k.dl(cx - wB / 2, y0, cx + wB / 2, y0, s.dimOff(r), _f1(wB));
  }

  // ---------------------------------------------------------------
  // DETAIL 生成器（13 种，同原型 DETAIL_GENS）
  // ---------------------------------------------------------------
  static void _detailBearing(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = s.use<double>('shaftY') ?? o.y + _bw / 2;
    final sr = s.use<double>('shaftR') ?? 0.22;
    final wd = math.max(0.24, sr * 0.9);
    final rr = wd / 2;
    final l2 = 1.4 + r.next() * 0.9;
    final x0 = geo.snapX != null ? geo.snapX! - l2 / 2 : o.x + (_bw - l2) / 2;
    k.a(x0 + rr, cy, rr, math.pi / 2, math.pi * 1.5);
    k.a(x0 + l2 - rr, cy, rr, -math.pi / 2, math.pi / 2);
    g.seg(x0 + rr, cy + rr, x0 + l2 - rr, cy + rr);
    g.seg(x0 + rr, cy - rr, x0 + l2 - rr, cy - rr);
    k.cm(x0 + l2 / 2, cy, l2 / 2 + 0.18);
    k.dl(x0, cy - rr, x0, cy + rr, -s.dimOff(r), 'Ø${_f1(wd)}');
    k.dr(x0 + rr, cy, rr, math.pi * 1.3, 'R${_f1(rr)}');
    k.dl(x0, cy + rr + 0.2, x0 + l2, cy + rr + 0.2, s.dimOff(r), _f1(l2));
  }

  static void _detailSection(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final w = 2.0 + r.next() * 1.6;
    final h = 1.3 + r.next() * 0.9;
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final cy = geo.snapY ?? (o.y + _bw / 2);
    final x0 = cx - w / 2;
    final y0 = cy - h / 2;
    g.box(x0, y0, w, h);
    k.ht(x0, y0, w, h, math.pi / 4, s.style.hatch);
    k.sec(
      x0 + w / 2,
      y0 - 0.4,
      x0 + w / 2,
      y0 + h + 0.4,
      _pick(r, const ['A', 'B', 'C']),
    );
    k.dl(x0, y0, x0 + w, y0, -s.dimOff(r), _f1(w));
    if (r.next() < 0.7) {
      k.dl(x0 + w, y0, x0 + w, y0 + h, s.dimOff(r), _f1(h));
    }
  }

  static void _detailCorner(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final t = (0.14 + r.next() * 0.1) * s.style.chunk;
    final a = 1.6 + r.next() * 0.9;
    final b = 1.2 + r.next() * 0.8;
    final x0 = geo.snapX != null ? geo.snapX! - a / 2 : o.x + (_bw - a) / 2;
    final y0 = geo.snapY != null ? geo.snapY! - b / 2 : o.y + (_bw - b) / 2;
    g.seg(x0, y0, x0 + a, y0);
    g.seg(x0, y0, x0, y0 + b);
    g.seg(x0, y0 + t, x0 + a, y0 + t);
    g.seg(x0 + t, y0, x0 + t, y0 + b);
    k.a(x0 + t, y0 + b - t, t, 0, math.pi / 2);
    g.circ(x0 + a * 0.6, y0 + t * 0.5, 0.05);
    k.dl(x0, y0, x0 + a, y0, -s.dimOff(r), _f1(a));
    k.dl(x0, y0, x0, y0 + b, -s.dimOff(r), _f1(b));
  }

  static void _detailHoles(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final n = 3 + r.nextInt(3);
    final c = <_Circle>[];
    for (var i = 0; i < n; i++) {
      final x = geo.snapX != null
          ? geo.snapX! + (r.next() - 0.5) * 2
          : o.x + 0.9 + r.next() * (_bw - 1.8);
      final y = geo.snapY != null
          ? geo.snapY! + (r.next() - 0.5) * 2
          : o.y + 0.9 + r.next() * (_bw - 1.8);
      final rr = 0.2 + r.next() * 0.42;
      g.circ(x, y, rr);
      k.cm(x, y, rr + 0.14);
      c.add(_Circle(x, y, rr));
    }
    k.dr(c[0].x, c[0].y, c[0].r, r.next() * 6.28, 'R${_f1(c[0].r)}');
    if (r.next() < 0.7 && c.length > 1) {
      final e = c.last;
      final a = r.next() * 6.28;
      k.a(
        e.x,
        e.y,
        e.r * 1.3,
        a,
        a + math.pi * (0.5 + r.next() * 1.2),
        _center,
      );
    }
  }

  static void _detailWeld(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final s2 = 1.1 + r.next() * 0.6;
    final hh = 0.7 + r.next() * 0.4;
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final cy = (geo.snapY ?? (o.y + _bw / 2)) + 0.45;
    g.seg(cx - s2, cy, cx + s2, cy);
    g.seg(cx - s2, cy, cx, cy - hh);
    g.seg(cx + s2, cy, cx, cy - hh);
    k.l(cx, cy, cx, cy - hh);
    if (r.next() < 0.7) {
      g.seg(cx - s2 * 0.5, cy, cx, cy - hh);
      g.seg(cx + s2 * 0.5, cy, cx, cy - hh);
    }
    for (final p in [
      Offset(cx - s2, cy),
      Offset(cx + s2, cy),
      Offset(cx, cy - hh),
      Offset(cx, cy),
    ]) {
      k.c(p.dx, p.dy, 0.06);
    }
    k.dl(cx - s2, cy, cx + s2, cy, -s.dimOff(r), _f1(s2 * 2));
  }

  static void _detailCallout(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final cy = geo.snapY ?? (o.y + _bw / 2);
    final cr = 0.6 + r.next() * 0.3;
    k.c(cx, cy, cr, _dashed);
    g.circ(cx - 0.08, cy + 0.04, 0.16 + r.next() * 0.1);
    k.l(cx - 0.3, cy - 0.2, cx + 0.3, cy - 0.2);
    if (r.next() < 0.6) {
      final a0 = r.next() * 3;
      k.a(cx + 0.15, cy - 0.15, 0.14, a0, a0 + 2);
    }
    const a = math.pi * 0.25;
    final ex = cx + math.cos(a) * cr;
    final ey = cy + math.sin(a) * cr;
    k.ar(ex, ey, ex + 0.4, ey + 0.4);
    k.t(ex + 0.45, ey + 0.52, 'DETAIL A', 0.12);
    k.t(ex + 0.45, ey + 0.32, 'SCALE 2:1', 0.1);
  }

  static void _detailCoupling(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = s.use<double>('shaftY') ?? o.y + _bw / 2;
    final sr = s.use<double>('shaftR') ?? 0.18 + r.next() * 0.1;
    final span = s.use<_Span>('shaftSpan') ?? _Span(o.x + 0.8, o.x + _bw - 0.8);
    final segsArr = s.use<List<_ShaftSeg>>('shaftSegs');
    double jx;
    if (segsArr != null && segsArr.length > 1) {
      final ji = 1 + r.nextInt(segsArr.length - 1);
      jx = segsArr[ji].x;
    } else {
      jx = span.x0 + (span.x1 - span.x0) * (0.3 + r.next() * 0.4);
    }
    final fw = 0.3 + r.next() * 0.16;
    final fr = sr * 1.6;
    g.box(jx - fw, cy - fr, fw, fr * 2);
    g.box(jx, cy - fr, fw, fr * 2);
    for (final p in [
      Offset(-fw / 2, -fr * 0.6),
      Offset(-fw / 2, fr * 0.6),
      Offset(fw / 2, -fr * 0.6),
      Offset(fw / 2, fr * 0.6),
    ]) {
      g.circ(jx + p.dx, cy + p.dy, 0.05);
    }
    k.l(o.x, cy, o.x + _bw, cy, _center);
    k.dl(jx - fw, cy + fr, jx + fw, cy + fr, s.dimOff(r), _f1(2 * fw));
    k.t(jx, cy - fr - 0.3, 'COUPLING', 0.11);
  }

  static void _detailPillar(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = s.use<double>('shaftY') ?? o.y + _bw / 2;
    final sr = s.use<double>('shaftR') ?? 0.2;
    final bx = geo.snapX ?? (o.x + _bw / 2);
    final h2 = sr * 2.6;
    g.circ(bx, cy, sr);
    k.a(bx, cy, sr * 1.35, 0, math.pi);
    g.box(bx - sr * 1.35, cy, sr * 2.7, h2);
    g.box(bx - sr * 2.0, cy + h2, sr * 4.0, 0.16);
    for (final dx in const [-1.6, 1.6]) {
      g.circ(bx + dx * sr, cy + h2 + 0.08, 0.055);
    }
    k.l(o.x, cy, o.x + _bw, cy, _center);
    k.dl(
      bx - sr,
      cy - sr - 0.2,
      bx + sr,
      cy - sr - 0.2,
      -s.dimOff(r),
      'Ø${_f1(sr * 2)}',
    );
    k.t(bx, cy + h2 + 0.5, 'PILLAR BLK', 0.11);
  }

  static void _detailSpring(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = s.use<double>('shaftY') ?? o.y + _bw / 2;
    final sr = s.use<double>('shaftR');
    final amp = (sr != null ? sr * 1.5 : 0.28) * (0.8 + r.next() * 0.6);
    final x0 = o.x + 0.5;
    final x1 = o.x + _bw - 0.5;
    final n = 7 + r.nextInt(5);
    g.seg(x0 - 0.15, cy - amp, x0 + 0.15, cy - amp);
    g.seg(x0 - 0.15, cy + amp, x0 + 0.15, cy + amp);
    var up = true;
    for (var i = 0; i < n; i++) {
      final xa = x0 + 0.15 + (x1 - x0 - 0.3) * i / n;
      final xb = x0 + 0.15 + (x1 - x0 - 0.3) * (i + 1) / n;
      g.seg(xa, up ? cy - amp : cy + amp, xb, up ? cy + amp : cy - amp);
      up = !up;
    }
    k.l(o.x, cy, o.x + _bw, cy, _center);
    k.dl(x0, cy + amp, x1, cy + amp, s.dimOff(r), _f1(x1 - x0));
    k.t((x0 + x1) / 2, cy - amp - 0.25, 'SPRING Ø${_f1(amp * 2)}', 0.11);
  }

  static void _detailWeldSymbol(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final w = 1.7 + r.next() * 1.0;
    final h = 1.1 + r.next() * 0.8;
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final cy = geo.snapY ?? (o.y + _bw / 2);
    final x0 = cx - w / 2;
    final y0 = cy - h / 2;
    g.box(x0, y0, w, h);
    g.seg(x0, y0, x0 + w, y0 + h);
    for (final p in [Offset(x0, y0), Offset(x0 + w, y0), Offset(x0, y0 + h)]) {
      if (r.next() < 0.7) {
        g.seg(p.dx - 0.1, p.dy + 0.06, p.dx + 0.06, p.dy - 0.1);
        g.seg(p.dx - 0.1, p.dy + 0.06, p.dx + 0.02, p.dy + 0.1);
        g.seg(p.dx + 0.06, p.dy - 0.1, p.dx + 0.02, p.dy + 0.1);
      }
    }
    k.ar(x0 + w * 0.3, y0 + h * 0.3, x0 + w * 0.3 - 0.4, y0 + h * 0.3 - 0.35);
    k.t(x0 + w * 0.3 - 0.5, y0 + h * 0.3 - 0.5, '${3 + r.nextInt(5)} △', 0.12);
    k.dl(x0, y0, x0 + w, y0, -s.dimOff(r), _f1(w));
  }

  static void _detailSlots(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final w = 2.2 + r.next() * 1.2;
    final h = 1.4 + r.next() * 0.7;
    final cx = geo.snapX ?? (o.x + _bw / 2);
    final cy = geo.snapY ?? (o.y + _bw / 2);
    final x0 = cx - w / 2;
    final y0 = cy - h / 2;
    g.box(x0, y0, w, h);
    final cols = 2 + r.nextInt(2);
    final rows = 1 + r.nextInt(2);
    final sw = w / (cols + 0.6);
    final sh = 0.14 + r.next() * 0.1;
    final sr = sh / 2;
    for (var i = 0; i < cols; i++) {
      for (var j = 0; j < rows; j++) {
        final sx = x0 + sw * (i + 0.8);
        final sy = y0 + h * (j + 1) / (rows + 1);
        k.a(sx, sy, sr, math.pi / 2, math.pi * 1.5);
        k.a(sx + sw * 0.55, sy, sr, -math.pi / 2, math.pi / 2);
        g.seg(sx, sy - sr, sx + sw * 0.55, sy - sr);
        g.seg(sx, sy + sr, sx + sw * 0.55, sy + sr);
      }
    }
    k.dl(x0, y0, x0 + w, y0, -s.dimOff(r), _f1(w));
    k.dl(x0 + w, y0, x0 + w, y0 + h, s.dimOff(r), _f1(h));
  }

  static void _detailPairShaft(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final g = _GeoHelpers(k, geo.segs, geo.circles);
    final cy = s.use<double>('shaftY') ?? o.y + _bw / 2;
    final r1 = 0.3 + r.next() * 0.2;
    final r2 = r1 * (0.5 + r.next() * 0.4);
    final p1x = geo.snapX ?? o.x + _bw * 0.35;
    final p2x = p1x + 0.9 + r.next() * 0.9;
    g.circ(p1x, cy, r1);
    g.circ(p1x, cy, r1 * 0.14);
    g.circ(p2x, cy, r2);
    g.circ(p2x, cy, r2 * 0.16);
    g.seg(p1x, cy - r1, p2x, cy - r2);
    g.seg(p1x, cy + r1, p2x, cy + r2);
    k.l(o.x, cy, o.x + _bw, cy, _center);
    k.dr(p1x, cy, r1, r.next() * 6.28, 'R${_f1(r1)}');
    k.dl(p1x, cy + r1, p2x, cy + r1, s.dimOff(r), _f1(p2x - p1x));
  }

  static void _detailFormulaBoard(BlueprintRng r, _Cell o, _K k, _Geo geo) {
    final s = geo.sctx;
    final f = _pickFormula(r);
    final num = s.nextEq();
    final mw = _mathWidth(f, 0.34);
    final bw = math.max(1.8, mw + 1.2);
    const bh = 1.35;
    final bx = geo.snapX != null ? geo.snapX! - bw / 2 : o.x + (_bw - bw) / 2;
    final by = geo.snapY != null ? geo.snapY! - bh / 2 : o.y + (_bw - bh) / 2;
    k.rc(bx, by, bw, bh);
    k.l(bx, by + 0.4, bx + bw, by + 0.4);
    k.t(bx + 0.28, by + 0.21, 'EQ', 0.12);
    k.t(bx + bw - 0.35, by + 0.21, '($num)', 0.12);
    final fBase = by + 0.4 + (bh - 0.4) / 2 + 0.1 - 0.04;
    k.mText(bx + (bw - mw) / 2, fBase, 0.34, f);
    s.pub('lastEq', num);
  }

  // ---------------------------------------------------------------
  // ANNO（同原型 genAnno）
  // ---------------------------------------------------------------
  static void _genAnno(
    BlueprintRng r,
    _Cell o,
    _K k,
    List<_Seg> segs,
    List<_Circle> circles,
    double axisX,
    double axisY,
    _Ctx s,
  ) {
    final cx = o.x + _bw / 2;
    final cy = o.y + _bw / 2;
    var done = 0;
    final span = s.use<_Span>('shaftSpan');
    final segsArr = s.use<List<_ShaftSeg>>('shaftSegs');
    final sy = s.use<double>('shaftY');

    if (span != null &&
        segsArr != null &&
        segsArr.length > 1 &&
        sy != null &&
        (cy - sy).abs() < _bw * 1.5 &&
        r.next() < 0.55) {
      var base = (r.next() < 0.5 ? -1 : 1) * s.dimOff(r);
      final dir = base < 0 ? -1.0 : 1.0;
      var x = span.x0;
      for (final sg in segsArr) {
        k.dl(x, sy, x + sg.w, sy, base, _f1(sg.w));
        x += sg.w;
        base += dir * 0.14;
      }
      k.dl(span.x0, sy, span.x1, sy, base + dir * 0.05, _f1(span.x1 - span.x0));
      done++;
    }

    if (done < 2) {
      _Seg? best;
      var bestD = 1e9;
      for (final sg in segs) {
        final mx = (sg.x1 + sg.x2) / 2;
        final my = (sg.y1 + sg.y2) / 2;
        final d = math.sqrt((mx - cx) * (mx - cx) + (my - cy) * (my - cy));
        if (d < bestD) {
          bestD = d;
          best = sg;
        }
      }
      if (best != null && bestD < 9.5) {
        final dx = best.x2 - best.x1;
        final dy = best.y2 - best.y1;
        final adx = dx.abs();
        final ady = dy.abs();
        final off = (r.next() < 0.5 ? -1 : 1) * s.dimOff(r);
        if (adx > 0.2 && ady < 0.08) {
          k.dl(best.x1, best.y1, best.x2, best.y2, off, _f1(adx));
          done++;
        } else if (ady > 0.2 && adx < 0.08) {
          k.dl(best.x1, best.y1, best.x2, best.y2, off, _f1(ady));
          done++;
        } else if (adx > 0.35 && ady > 0.35) {
          k.dl(
            best.x1,
            best.y1,
            best.x2,
            best.y2,
            off,
            _f1(math.sqrt(dx * dx + dy * dy)),
          );
          done++;
        }
      }
    }

    _Circle? bc;
    var bcd = 1e9;
    for (final c in circles) {
      final d =
          math.sqrt((c.x - cx) * (c.x - cx) + (c.y - cy) * (c.y - cy)) - c.r;
      if (d < bcd) {
        bcd = d;
        bc = c;
      }
    }
    if (bc != null && bcd < 9.5 && done < 2) {
      if (r.next() < 0.5) {
        k.dr(bc.x, bc.y, bc.r, r.next() * 6.28, 'R${_f1(bc.r)}');
      } else {
        k.dd(bc.x, bc.y, bc.r, r.next() * 6.28, 'Ø${_f1(bc.r * 2)}');
      }
      done++;
    }

    if (done == 0) {
      k.cm(cx, cy, 0.22);
      k.c(cx, cy, 0.05);
      final a = r.next() * 6.28;
      final len = 0.8 + r.next() * 0.6;
      final ex = cx + math.cos(a) * len;
      final ey = cy + math.sin(a) * len;
      k.l(cx, cy, ex, ey, _center);
      k.t(
        ex + math.cos(a) * 0.18,
        ey + math.sin(a) * 0.18,
        _pick(r, const ['SEE NOTE 3', 'REF', 'TYP', '4× Ø6 EQ SP']),
        0.11,
        a,
      );
    }

    final eq = s.use<int>('lastEq');
    if (eq != null && done < 2 && r.next() < 0.34) {
      final a = r.next() * 6.28;
      final ex = cx + math.cos(a) * 0.6;
      final ey = cy + math.sin(a) * 0.6;
      k.l(cx, cy, ex, ey, _center);
      final f = _pickFormula(r);
      final mw = _mathWidth(f, 0.2);
      k.mText(ex + 0.12, ey, 0.2, f);
      k.t(ex + 0.12 + mw / 2, ey + 0.26, '($eq)', 0.1);
    }

    if (r.next() < 0.6) {
      final wx = cx + (r.next() - 0.5) * 1.4;
      final wy = cy + (r.next() - 0.5) * 1.4;
      k.t(wx, wy + 0.16, 'X=${_f1(3300 + wx * 7.5)}', 0.1);
      k.t(wx, wy - 0.02, 'Y=${_f1(530 + wy * 7.5)}', 0.1);
      k.c(wx, wy, 0.04);
    }

    if (r.next() < 0.5) {
      final px = cx + (r.next() - 0.5);
      final py = cy + (r.next() - 0.5);
      if (r.next() < 0.5) {
        k.dl(axisX, py, px, py, s.dimOff(r) * 0.8, _f1((px - axisX).abs()));
      } else {
        k.dl(px, axisY, px, py, s.dimOff(r) * 0.8, _f1((py - axisY).abs()));
      }
    }

    final mn = s.use<String>('megaName');
    if (mn != null && r.next() < 0.4) {
      final suffix = (1 + r.nextInt(9)).toString().padLeft(2, '0');
      k.t(cx, cy + 1.0, '$mn-$suffix', 0.13);
      k.l(cx, cy + 0.85, cx, cy + 0.55, _center);
    }
  }

  // ---------------------------------------------------------------
  // 生成器表
  // ---------------------------------------------------------------
  static final List<void Function(BlueprintRng, _Cell, _K, _Geo)> _megaGens =
      <void Function(BlueprintRng, _Cell, _K, _Geo)>[
        _megaTurbine,
        _megaHullSec,
        _megaFrame,
        _megaTankFarm,
        _megaGearbox,
        _megaTruss,
        _megaPlan,
      ];

  static final List<void Function(BlueprintRng, _Cell, _K, _Geo)> _axisHGens =
      <void Function(BlueprintRng, _Cell, _K, _Geo)>[
        _axisHSteps,
        _axisHBeam,
        _axisHRound,
        _axisHTaper,
        _axisHThread,
      ];

  static final List<void Function(BlueprintRng, _Cell, _K, _Geo)> _axisVGens =
      <void Function(BlueprintRng, _Cell, _K, _Geo)>[
        _axisVSteps,
        _axisVShaft,
        _axisVHollow,
        _axisVPiston,
        _axisVTruss,
      ];

  static final List<void Function(BlueprintRng, _Cell, _K, _Geo)> _detailGens =
      <void Function(BlueprintRng, _Cell, _K, _Geo)>[
        _detailBearing,
        _detailSection,
        _detailCorner,
        _detailHoles,
        _detailWeld,
        _detailCallout,
        _detailCoupling,
        _detailPillar,
        _detailSpring,
        _detailWeldSymbol,
        _detailSlots,
        _detailPairShaft,
        _detailFormulaBoard,
      ];
}

// -------------------------------------------------------------------
// 常量与随机（同原型 L41-67）
// -------------------------------------------------------------------
const int _solid = 0;
const int _dashed = 1;
const int _center = 2;

const List<String> _ftags = [
  'mech',
  'mat',
  'thermo',
  'fluid',
  'em',
  'wave',
  'quantum',
  'rel',
  'math',
  'stats',
];

/// 公式纯文本池：原型用迷你 LaTeX 排版，这里只保留同位置的文本语义。
const List<String> _formulaPool = [
  'E = mc²',
  '∇·B = 0',
  'λ = h/p',
  'a²+b² = c²',
  'PV = nRT',
  'F = ma',
  'v = fλ',
  'σ = F/A',
  'Q = mcΔT',
  'E = ħω',
];

/// 32 位哈希，忠实复刻原型 `hash2`（与画布层的 hash 变体不同）。
int _hash2(int seed, int a, int b, int salt) {
  var h = (seed ^ salt) & 0xFFFFFFFF;
  h = ((h ^ 0x9E3779B9) * 0x85EBCA6B) & 0xFFFFFFFF;
  h = ((h ^ (a & 0xFFFFFFFF)) * 0xC2B2AE35) & 0xFFFFFFFF;
  h = ((h ^ (b & 0xFFFFFFFF)) * 0x27D4EB2F) & 0xFFFFFFFF;
  h ^= h >>> 15;
  h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
  h ^= h >>> 13;
  return h & 0xFFFFFFFF;
}

T _pick<T>(BlueprintRng r, List<T> list) => list[r.nextInt(list.length)];

String _pickFormula(BlueprintRng r) =>
    _formulaPool[r.nextInt(_formulaPool.length)];

String _f1(double v) => v.toStringAsFixed(1);

/// 纯文本公式的估算宽度（世界单位），替代原型的 measureMath。
double _mathWidth(String text, double fh) => text.length * fh * 0.55;

/// 权重随机挑选（同原型 favPick）。
int _favPick(BlueprintRng r, int length, int last, int fav) {
  var gi = (r.next() < 0.3 && fav < length) ? fav : r.nextInt(length);
  if (gi == last && r.next() < 0.75) {
    gi = (gi + 1 + r.nextInt(length - 1)) % length;
  }
  return gi;
}

// -------------------------------------------------------------------
// WFC（同原型 L334-380）
// -------------------------------------------------------------------
const List<String> _modList = [
  'MEGA',
  'AXIS_H',
  'AXIS_V',
  'DETAIL',
  'ANNO',
  'EMPTY',
];

const Map<String, int> _modWeights = {
  'MEGA': 0,
  'AXIS_H': 18,
  'AXIS_V': 18,
  'DETAIL': 30,
  'ANNO': 16,
  'EMPTY': 5,
};

const Map<String, int> _adj = {
  'MEGA|MEGA': 1,
  'MEGA|AXIS_H': 1,
  'MEGA|AXIS_V': 1,
  'MEGA|DETAIL': 1,
  'MEGA|ANNO': 1,
  'AXIS_H|AXIS_H': 1,
  'AXIS_H|DETAIL': 1,
  'AXIS_H|AXIS_V': 1,
  'AXIS_V|AXIS_V': 1,
  'AXIS_V|DETAIL': 1,
  'DETAIL|DETAIL': 1,
  'DETAIL|ANNO': 1,
  'DETAIL|EMPTY': 1,
  'ANNO|ANNO': 1,
  'ANNO|EMPTY': 1,
  'EMPTY|EMPTY': 1,
};

bool _canAdj(String a, String b) => (_adj['$a|$b'] ?? _adj['$b|$a'] ?? 0) > 0;

/// 5×5 波函数坍缩：中央 3×3 初始坍缩为 MEGA，其余按最小熵加权坍缩。
List<String> _runWfc(int seed) {
  final rng = BlueprintRng(seed);
  const n = BlueprintSite._cells * BlueprintSite._cells;
  final cells = List<Set<String>>.generate(n, (_) => <String>{..._modList});
  final collapsed = List<String?>.filled(n, null);

  List<int> neighbors(int i) {
    final x = i % BlueprintSite._cells;
    final y = i ~/ BlueprintSite._cells;
    final out = <int>[];
    if (x > 0) out.add(i - 1);
    if (x < BlueprintSite._cells - 1) out.add(i + 1);
    if (y > 0) out.add(i - BlueprintSite._cells);
    if (y < BlueprintSite._cells - 1) out.add(i + BlueprintSite._cells);
    return out;
  }

  void collapse(int i, String v) {
    collapsed[i] = v;
    cells[i] = <String>{v};
    final q = <int>[...neighbors(i)];
    final seen = <int>{i};
    while (q.isNotEmpty) {
      final c = q.removeAt(0);
      if (collapsed[c] != null || seen.contains(c)) continue;
      seen.add(c);
      final nbs = neighbors(c);
      final before = cells[c].length;
      for (final n2 in nbs) {
        final cv = collapsed[n2];
        if (cv == null) continue;
        cells[c] = cells[c].where((o) => _canAdj(cv, o)).toSet();
      }
      if (cells[c].isEmpty) cells[c] = <String>{'EMPTY'};
      if (cells[c].length < before) q.addAll(nbs);
    }
  }

  String pickWeighted(Set<String> set) {
    final opts = set.toList();
    var total = 0;
    for (final o in opts) {
      total += _modWeights[o]!;
    }
    var v = rng.next() * total;
    for (final o in opts) {
      v -= _modWeights[o]!;
      if (v <= 0) return o;
    }
    return opts.last;
  }

  const c0 = (BlueprintSite._cells ~/ 2) - 1;
  for (var row = c0; row < c0 + 3; row++) {
    for (var col = c0; col < c0 + 3; col++) {
      final idx = row * BlueprintSite._cells + col;
      if (collapsed[idx] == null) collapse(idx, 'MEGA');
    }
  }

  var guard = 0;
  while (guard < n * 3) {
    guard++;
    var minE = 1 << 30;
    var minI = -1;
    for (var i = 0; i < n; i++) {
      if (collapsed[i] != null) continue;
      if (cells[i].length < minE) {
        minE = cells[i].length;
        minI = i;
      }
    }
    if (minI < 0 || minE == 0) break;
    collapse(minI, pickWeighted(cells[minI]));
  }

  for (var i = 0; i < n; i++) {
    collapsed[i] ??= cells[i].isNotEmpty ? cells[i].first : 'EMPTY';
  }
  return collapsed.map((e) => e ?? 'EMPTY').toList();
}

// -------------------------------------------------------------------
// 站点上下文（同原型 makeCtx）
// -------------------------------------------------------------------
class _Style {
  const _Style({
    required this.slender,
    required this.chunk,
    required this.hatch,
    required this.dimScale,
  });

  final double slender;
  final double chunk;
  final double hatch;
  final double dimScale;
}

class _Ctx {
  _Ctx(BlueprintRng rng)
    : style = _Style(
        slender: 0.6 + rng.next() * 0.9,
        chunk: 0.65 + rng.next() * 0.85,
        hatch: 0.05 + rng.next() * 0.05,
        dimScale: 0.7 + rng.next() * 0.7,
      ),
      ftag = _ftags[rng.nextInt(_ftags.length)];

  final _Style style;
  final String ftag;
  final Map<String, Object?> _iface = <String, Object?>{};
  int _eq = 0;

  void pub(String key, Object? value) => _iface[key] = value;

  T? use<T>(String key) => _iface[key] as T?;

  int nextEq() => ++_eq;

  double dimOff(BlueprintRng r) => (0.10 + r.next() * 0.50) * style.dimScale;
}

class _Cell {
  const _Cell(this.x, this.y);

  final double x;
  final double y;
}

class _Seg {
  const _Seg(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

class _Circle {
  const _Circle(this.x, this.y, this.r);

  final double x;
  final double y;
  final double r;
}

class _Span {
  const _Span(this.x0, this.x1);

  final double x0;
  final double x1;
}

class _ShaftSeg {
  const _ShaftSeg(this.x, this.w);

  final double x;
  final double w;
}

// -------------------------------------------------------------------
// 图元构建器与站点上下文（同原型 mk / geoHelpers）
// -------------------------------------------------------------------
class _Geo {
  const _Geo({
    required this.segs,
    required this.circles,
    required this.axisX,
    required this.axisY,
    required this.sctx,
    this.snapX,
    this.snapY,
    this.mw = 0,
    this.mh = 0,
  });

  final List<_Seg> segs;
  final List<_Circle> circles;
  final double axisX;
  final double axisY;
  final double? snapX;
  final double? snapY;
  final double mw;
  final double mh;
  final _Ctx sctx;
}

class _GeoHelpers {
  const _GeoHelpers(this.k, this.segs, this.circles);

  final _K k;
  final List<_Seg> segs;
  final List<_Circle> circles;

  void seg(double x1, double y1, double x2, double y2, [int style = _solid]) {
    k.l(x1, y1, x2, y2, style);
    if (style == _solid) segs.add(_Seg(x1, y1, x2, y2));
  }

  void box(double x, double y, double w, double h, [int style = _solid]) {
    k.rc(x, y, w, h, style);
    if (style == _solid) {
      segs
        ..add(_Seg(x, y, x + w, y))
        ..add(_Seg(x + w, y, x + w, y + h))
        ..add(_Seg(x + w, y + h, x, y + h))
        ..add(_Seg(x, y + h, x, y));
    }
  }

  void circ(double x, double y, double r, [int style = _solid]) {
    k.c(x, y, r, style);
    if (style == _solid) circles.add(_Circle(x, y, r));
  }
}

/// 图元构建器：把各生成器的调用记成世界坐标图元。
class _K {
  _K(this._rng);

  final BlueprintRng _rng;
  final List<_Prim> p = <_Prim>[];

  void l(double x1, double y1, double x2, double y2, [int style = _solid]) =>
      p.add(_Prim.line(x1, y1, x2, y2, style));

  void rc(double x, double y, double w, double h, [int style = _solid]) {
    l(x, y, x + w, y, style);
    l(x + w, y, x + w, y + h, style);
    l(x + w, y + h, x, y + h, style);
    l(x, y + h, x, y, style);
  }

  void c(double x, double y, double r, [int style = _solid]) =>
      p.add(_Prim.circle(x, y, r, style));

  void a(
    double x,
    double y,
    double r,
    double a0,
    double a1, [
    int style = _solid,
  ]) => p.add(_Prim.arc(x, y, r, a0, a1, style));

  void t(double x, double y, String str, [double h = 0.15, double rot = 0]) =>
      p.add(_Prim.txt(x, y, str, h));

  void dl(double x1, double y1, double x2, double y2, double off, String txt) =>
      p.add(_Prim.dim(x1, y1, x2, y2, off, txt));

  void dr(double x, double y, double r, double a, String txt) =>
      p.add(_Prim.dimRadius(x, y, r, a, txt));

  void dd(double x, double y, double r, double a, String txt) =>
      p.add(_Prim.dimDiameter(x, y, r, a, txt));

  void cm(double x, double y, double e) => p.add(_Prim.cross(x, y, e));

  void ht(
    double x,
    double y,
    double w,
    double h,
    double a, [
    double step = 0.1,
  ]) => p.add(_Prim.hatch(x, y, w, h, a, step));

  void sec(double x1, double y1, double x2, double y2, String ch) =>
      p.add(_Prim.section(x1, y1, x2, y2, ch));

  void ar(double x1, double y1, double x2, double y2) =>
      p.add(_Prim.arrow(x1, y1, x2, y2));

  /// 原型 `k.M(..., toks)`：这里直接落一条纯文本公式。
  String m(double x, double y, double fh) {
    final f = _pickFormula(_rng);
    p.add(_Prim.math(x, y, f, fh));
    return f;
  }

  void mText(double x, double y, double fh, String text) =>
      p.add(_Prim.math(x, y, text, fh));
}

// -------------------------------------------------------------------
// 世界坐标图元（不可变，供站点缓存复用）
// -------------------------------------------------------------------
enum _PrimKind {
  line,
  circle,
  arc,
  text,
  math,
  dim,
  dimRadius,
  dimDiameter,
  cross,
  hatch,
  section,
  arrow,
}

@immutable
class _Prim {
  const _Prim._({
    required this.kind,
    this.x1 = 0,
    this.y1 = 0,
    this.x2 = 0,
    this.y2 = 0,
    this.cx = 0,
    this.cy = 0,
    this.r = 0,
    this.a0 = 0,
    this.a1 = 0,
    this.style = _solid,
    this.text = '',
    this.fh = 0,
    this.off = 0,
    this.hw = 0,
    this.hh = 0,
    this.ang = 0,
    this.step = 0.1,
    this.ch = '',
  });

  const _Prim.line(
    double x1,
    double y1,
    double x2,
    double y2, [
    int style = _solid,
  ]) : this._(
         kind: _PrimKind.line,
         x1: x1,
         y1: y1,
         x2: x2,
         y2: y2,
         style: style,
       );

  const _Prim.circle(double x, double y, double r, [int style = _solid])
    : this._(kind: _PrimKind.circle, cx: x, cy: y, r: r, style: style);

  const _Prim.arc(
    double x,
    double y,
    double r,
    double a0,
    double a1, [
    int style = _solid,
  ]) : this._(
         kind: _PrimKind.arc,
         cx: x,
         cy: y,
         r: r,
         a0: a0,
         a1: a1,
         style: style,
       );

  const _Prim.txt(double x, double y, String str, double h)
    : this._(kind: _PrimKind.text, cx: x, cy: y, text: str, fh: h);

  const _Prim.math(double x, double y, String str, double h)
    : this._(kind: _PrimKind.math, cx: x, cy: y, text: str, fh: h);

  const _Prim.dim(
    double x1,
    double y1,
    double x2,
    double y2,
    double off,
    String txt,
  ) : this._(
        kind: _PrimKind.dim,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        off: off,
        text: txt,
      );

  const _Prim.dimRadius(double x, double y, double r, double a, String txt)
    : this._(kind: _PrimKind.dimRadius, cx: x, cy: y, r: r, a0: a, text: txt);

  const _Prim.dimDiameter(double x, double y, double r, double a, String txt)
    : this._(kind: _PrimKind.dimDiameter, cx: x, cy: y, r: r, a0: a, text: txt);

  const _Prim.cross(double x, double y, double e)
    : this._(kind: _PrimKind.cross, cx: x, cy: y, r: e);

  const _Prim.hatch(
    double x,
    double y,
    double w,
    double h,
    double a,
    double step,
  ) : this._(
        kind: _PrimKind.hatch,
        x1: x,
        y1: y,
        hw: w,
        hh: h,
        ang: a,
        step: step,
      );

  const _Prim.section(double x1, double y1, double x2, double y2, String ch)
    : this._(kind: _PrimKind.section, x1: x1, y1: y1, x2: x2, y2: y2, ch: ch);

  const _Prim.arrow(double x1, double y1, double x2, double y2)
    : this._(kind: _PrimKind.arrow, x1: x1, y1: y1, x2: x2, y2: y2);

  final _PrimKind kind;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double cx;
  final double cy;
  final double r;
  final double a0;
  final double a1;
  final int style;
  final String text;
  final double fh;
  final double off;
  final double hw;
  final double hh;
  final double ang;
  final double step;
  final String ch;

  /// 世界坐标外包框（同原型 primBBox，统一外扩 0.2）。
  Rect get worldBounds {
    var bx0 = 0.0;
    var by0 = 0.0;
    var bx1 = 0.0;
    var by1 = 0.0;
    switch (kind) {
      case _PrimKind.line:
      case _PrimKind.section:
      case _PrimKind.arrow:
        // 原型给 SEC/AR 用了 ±9 的宽松默认框；这里按真实线段收紧，
        // 避免把站点边缘外的图元也带进输出。
        bx0 = math.min(x1, x2);
        bx1 = math.max(x1, x2);
        by0 = math.min(y1, y2);
        by1 = math.max(y1, y2);
      case _PrimKind.circle:
      case _PrimKind.arc:
        bx0 = cx - r;
        bx1 = cx + r;
        by0 = cy - r;
        by1 = cy + r;
      case _PrimKind.text:
        final half = text.length * fh * 0.35;
        bx0 = cx - half;
        bx1 = cx + half;
        by0 = cy - fh;
        by1 = cy + fh;
      case _PrimKind.math:
        bx0 = cx - 0.1;
        bx1 = cx + _mathWidth(text, fh) + 0.1;
        by0 = cy - fh * 0.8 - 0.1;
        by1 = cy + fh * 0.3 + 0.1;
      case _PrimKind.dim:
        bx0 = math.min(x1, x2) - 0.9;
        bx1 = math.max(x1, x2) + 0.9;
        by0 = math.min(y1, y2) - 0.9;
        by1 = math.max(y1, y2) + 0.9;
      case _PrimKind.dimRadius:
      case _PrimKind.dimDiameter:
        bx0 = cx - r - 1.0;
        bx1 = cx + r + 1.0;
        by0 = cy - r - 1.0;
        by1 = cy + r + 1.0;
      case _PrimKind.cross:
        bx0 = cx - r;
        bx1 = cx + r;
        by0 = cy - r;
        by1 = cy + r;
      case _PrimKind.hatch:
        bx0 = x1;
        bx1 = x1 + hw;
        by0 = y1;
        by1 = y1 + hh;
    }
    return Rect.fromLTRB(bx0 - 0.2, by0 - 0.2, bx1 + 0.2, by1 + 0.2);
  }
}
