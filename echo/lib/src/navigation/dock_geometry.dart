import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 底部「三条一行」停靠区的几何事实来源。
///
/// 屏幕底部同一水平线上等高地住着三兄弟（原型
/// ideas/another_two_lines.html）：
/// - **把手条**（左）：宽 12% 屏宽；单击弹出本页操作竖单、右拖出抽屉；
/// - **AI 条**（中）：虹彩流动条，长按呼出对话框；
/// - **导航条整体**（右，含两端翻页圆点）：宽半屏。
///
/// 三条与屏幕边缘、条与条之间的间距全部为 [sideMargin]（14px）：
/// `14 + 把手(12%) + 14 + AI条(38%-56) + 14 + 导航整体(50%) + 14 = 屏宽`。
///
/// 所有视觉矩形与隐形热区都由本类静态常量/函数配合 MediaQuery 推算，
/// 不在运行时用 GlobalKey 测量（原因见工程规范事故 4）。
abstract final class DockGeometry {
  /// 屏幕两侧留白 & 三条之间的统一间距。
  static const double sideMargin = 14;

  /// 三条距屏幕底部（安全区之上）的距离。
  static const double bottomMargin = 16;

  /// 三条的共同高度（也是翻页圆点的直径）。
  static const double barHeight = 10;

  /// 翻页圆点直径。
  static const double dotDiameter = 10;

  /// 导航条与两端圆点的间距（一个半径）。
  static const double dotGap = dotDiameter / 2;

  /// 搜索态全宽胶囊高度。
  static const double searchHeight = 44;

  /// 把手条占屏宽比例（12vw）。
  static const double handleFraction = 0.12;

  /// 把手条宽度。
  static double handleWidthFor(double screenWidth) =>
      screenWidth * handleFraction;

  /// 把手条常态下的左边距（= [sideMargin]）。
  static double handleLeftFor(double screenWidth) => sideMargin;

  /// AI 条左边距（屏幕留白 + 把手宽 + 间距）。
  static double aiLeftFor(double screenWidth) =>
      sideMargin + handleWidthFor(screenWidth) + sideMargin;

  /// AI 条宽度（38vw - 56：扣除两侧留白与两条间距后恰填满中段）。
  static double aiWidthFor(double screenWidth) =>
      screenWidth * 0.38 - 4 * sideMargin;

  /// 导航条整体（圆点 + 条 + 圆点）宽度：半屏宽。
  static double navAssemblyWidthFor(double screenWidth) => screenWidth / 2;

  /// 缩短后的导航条本体宽度（扣除两端圆点与间距）。
  static double navBarWidthFor(double screenWidth) =>
      screenWidth / 2 - 2 * dotDiameter - 2 * dotGap;

  // ================================================================
  //  本页操作竖单（把手单击后向上生长的胶囊）
  // ================================================================

  /// 竖单内圆形按钮直径：把手宽 - 12，夹在 32~42 之间。
  static double menuButtonDiameterFor(double handleWidth) =>
      (handleWidth - 12).clamp(32.0, 42.0);

  /// 竖单按钮与胶囊边缘的留白（横、纵一致）。
  ///
  /// 必须等于 (把手宽 − 按钮直径) / 2：胶囊两端圆弧半径为把手宽的
  /// 一半，其圆心在边缘内 w/2 处；上下留白取此值时，最上/最下按钮
  /// 的圆心与端弧圆心重合——端弧恰好是按钮圆外扩同圈边距的同心圆，
  /// 胶囊端头不会在按钮之外多突出一截。
  static double menuEdgeInsetFor(double handleWidth) =>
      (handleWidth - menuButtonDiameterFor(handleWidth)) / 2;

  /// 竖单完全展开后的高度：3 个按钮 + 2 个间距(10) + 上下同心留白。
  static double menuHeightFor(double handleWidth) {
    final diameter = menuButtonDiameterFor(handleWidth);
    final edge = menuEdgeInsetFor(handleWidth);
    return 3 * diameter + 2 * 10 + 2 * edge;
  }

  // ================================================================
  //  侧边抽屉（把手右拖）
  // ================================================================

  /// 抽屉宽度：78% 屏宽，最大 340。
  static double drawerWidthFor(double screenWidth) =>
      math.min(screenWidth * 0.78, 340.0);

  /// 抽屉完全打开时把手条停靠的左边距（抽屉右缘 + 14px 间距）。
  static double dockedHandleLeftFor(double screenWidth) =>
      drawerWidthFor(screenWidth) + sideMargin;

  // ================================================================
  //  快捷操作弧（导航条竖直上甩）
  // ================================================================

  /// 弧上按钮直径（QuickActionArc 的视觉尺寸也取此值，保证按钮
  /// 尺寸只有一处事实来源）。
  static const double quickArcButtonDiameter = 40;

  /// 热区边缘超出按钮边缘的最小距离：按钮与热区之间至少 10。
  static const double quickArcHotMargin = 10;

  /// 曲线半轴：按用户真实手指轨迹（系统「指针位置」录得，见
  /// docs/component-reports/）量得——横:纵 ≈ 116:184 ≈ 1:1.59 的
  /// 四分之一椭圆弧。
  static const double quickArcSemiX = 116;
  static const double quickArcSemiY = 184;

  /// 快捷弧曲线上参数为 [t] 的点：t=0 为导航条上的起点，
  /// t=1 为末端。
  ///
  /// 椭圆参数方程（θ = πt/2）：
  /// `x = ox + a·(1−cos θ)`，`y = oy − b·sin θ`。
  /// 起点切向竖直、末端切向水平，与实测轨迹近似。
  static Offset quickArcPoint(Offset origin, double t) {
    final theta = math.pi / 2 * t;
    return Offset(
      origin.dx + quickArcSemiX * (1 - math.cos(theta)),
      origin.dy - quickArcSemiY * math.sin(theta),
    );
  }

  // 曲线弧长积分表（按需惰性构建，缓存复用）：
  // _arcCumulative[k] = t = k/_arcSamples 处的累计弧长。
  static const int _arcSamples = 480;
  static List<double>? _arcCumulative;
  static double _arcTotalLength = 0;

  static void _ensureArcTable() {
    if (_arcCumulative != null) return;

    final cumulative = List<double>.filled(_arcSamples + 1, 0);
    var prev = Offset.zero;
    for (var k = 0; k <= _arcSamples; k++) {
      final p = quickArcPoint(Offset.zero, k / _arcSamples);
      if (k > 0) {
        cumulative[k] = cumulative[k - 1] + (p - prev).distance;
      }
      prev = p;
    }
    _arcCumulative = cumulative;
    _arcTotalLength = cumulative.last;
  }

  /// 弧长比例 [u]（0 = 曲线起点，1 = 末端）对应的参数 t。
  ///
  /// 在积分表中定位后线性插值，精度 = 半段误差（480 段下
  /// 远小于 0.1px）。
  static double _tAtArcFraction(double u) {
    _ensureArcTable();
    final table = _arcCumulative!;
    final target = u.clamp(0, 1) * _arcTotalLength;

    // 二分找到目标落在的段。
    var lo = 0;
    var hi = _arcSamples;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (table[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final k = lo == 0 ? 0 : lo - 1;
    final segLength = table[k + 1] - table[k];
    final within = segLength == 0 ? 0.0 : (target - table[k]) / segLength;
    return (k + within) / _arcSamples;
  }

  /// 曲线上**弧长比例**为 [u] 的点：u=0 为起点、u=1 为末端。
  ///
  /// 与 [quickArcPoint]（按参数 t 取点）不同，这里等距的 u
  /// 对应等距的弧长——沿曲线排布多个元素时应使用本接口。
  static Offset pointAtArcFraction(Offset origin, double u) {
    return quickArcPoint(origin, _tAtArcFraction(u));
  }

  /// 一次快捷弧布局的结果：各按钮圆心 + 统一热区半径。
  ///
  /// 按钮沿曲线按**弧长等距**排布（不是参数 t 等距——椭圆上
  /// 那会导致间距忽大忽小）。
  static QuickArcLayout layoutQuickArc({
    required Offset origin,
    required int count,
  }) {
    final minRadius = quickArcButtonDiameter / 2;
    final maxRadius = minRadius + quickArcHotMargin;

    if (count <= 0) {
      return QuickArcLayout(centers: const [], hotRadius: maxRadius);
    }
    if (count == 1) {
      return QuickArcLayout(
        centers: [quickArcPoint(origin, _tAtArcFraction(0.5))],
        hotRadius: maxRadius,
      );
    }

    // 逐级放宽的居中「弧长比例」窗口。
    const spans = [0.60, 0.72, 0.84, 0.96];
    for (final span in spans) {
      final centers = <Offset>[
        for (var i = 0; i < count; i++)
          quickArcPoint(
            origin,
            _tAtArcFraction(0.5 - span / 2 + span * i / (count - 1)),
          ),
      ];

      // 弧长等距：各相邻圆心距应一致，取最小值做保守半径。
      var minDistance = double.infinity;
      for (var i = 1; i < count; i++) {
        minDistance = math.min(
          minDistance,
          (centers[i] - centers[i - 1]).distance,
        );
      }

      final radius = ((minDistance - quickArcHotMargin) / 2)
          .clamp(minRadius, maxRadius)
          .toDouble();

      // 相邻热区边缘间隙 ≥ 10 即收工。
      if (minDistance >= 2 * radius + quickArcHotMargin) {
        return QuickArcLayout(centers: centers, hotRadius: radius);
      }
    }

    // 数量极端多：采用最宽窗口并夹到最小热区。
    const span = 0.96;
    return QuickArcLayout(
      centers: <Offset>[
        for (var i = 0; i < count; i++)
          quickArcPoint(
            origin,
            _tAtArcFraction(0.5 - span / 2 + span * i / (count - 1)),
          ),
      ],
      hotRadius: minRadius,
    );
  }
}

/// 一次快捷弧布局的结果：各按钮圆心 + 统一热区半径。
class QuickArcLayout {
  const QuickArcLayout({required this.centers, required this.hotRadius});

  /// 按从下到上（曲线 t 从小到大）排列的按钮圆心。
  final List<Offset> centers;

  /// 统一热区半径（选择与触发判定共用）。
  final double hotRadius;
}
