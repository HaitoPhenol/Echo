import 'package:flutter/material.dart';

import '../../theme/mechanical_style.dart';
import '../dock_geometry.dart';

/// 机能风固定背景：实验底色 + 三层工程纹理（细网格 / 粗网格 / 点阵）
/// + 四角十字定位标记。
///
/// 实验隔离组件（feat/page-background-art）：数值全部取自
/// [MechanicalStyle]，方案验收/放弃时随实验层整体处理。
///
/// 行为约定：
/// * 纹理与十字**固定在屏幕上**，不随横向翻页移动，页面内容从其上方滑过；
/// * 不画实体描边框（实验改版）：四角十字标定一条虚拟边界——
///   顶边在状态栏下沿（+8dp 呼吸位）、底边即底部停靠三条的共同顶线
///   （[DockGeometry] 事实来源）、左右各内缩 14dp；
/// * 静态绘制，外包 [RepaintBoundary]，导航动画不会引发背景重绘；
/// * 只画"表皮"，不承载任何交互。
class MechanicalBackground extends StatelessWidget {
  const MechanicalBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;

    // 虚拟顶边：状态栏下沿 + 8dp 呼吸位（顶部十字位置 A3 起保持不变）。
    final topBoundary = mq.viewPadding.top + 8 > MechanicalStyle.frameInset
        ? mq.viewPadding.top + 8
        : MechanicalStyle.frameInset;

    // 虚拟底边：底部停靠三条（把手/AI/导航）的共同顶线。
    final bottomBoundary = size.height -
        mq.viewPadding.bottom -
        DockGeometry.bottomMargin -
        DockGeometry.barHeight;

    return RepaintBoundary(
      child: ColoredBox(
        color: MechanicalStyle.baseBackground,
        child: CustomPaint(
          painter: _MechanicalGridPainter(
            sideInset: MechanicalStyle.frameInset,
            topBoundary: topBoundary,
            bottomBoundary: bottomBoundary,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// 背景绘制器：细网格 → 粗网格 → 点阵 → 四角十字。
///
/// 网格用单个 Path 收集全部线段后一次描边，点阵逐交点画圆；
/// 入参仅为虚拟边界坐标，[shouldRepaint] 只在边界变化时为 true。
class _MechanicalGridPainter extends CustomPainter {
  const _MechanicalGridPainter({
    required this.sideInset,
    required this.topBoundary,
    required this.bottomBoundary,
  });

  /// 虚拟边界左右内缩（14dp）。
  final double sideInset;

  /// 虚拟顶边 y（状态栏下沿 + 呼吸位）。
  final double topBoundary;

  /// 虚拟底边 y（停靠三条的共同顶线）。
  final double bottomBoundary;

  void _addGrid(Path path, Size size, double spacing) {
    // 竖线。
    for (double x = 0; x <= size.width; x += spacing) {
      path
        ..moveTo(x, 0)
        ..lineTo(x, size.height);
    }
    // 横线。
    for (double y = 0; y <= size.height; y += spacing) {
      path
        ..moveTo(0, y)
        ..lineTo(size.width, y);
    }
  }

  /// 在 [corner] 处画一个边长 [MechanicalStyle.crossSize] 的十字，
  /// 十字中心即角点，横纵两笔各向内外延伸半个边长。
  void _paintCross(Canvas canvas, Offset corner, Paint paint) {
    final half = MechanicalStyle.crossSize / 2;
    canvas.drawLine(
      corner.translate(-half, 0),
      corner.translate(half, 0),
      paint,
    );
    canvas.drawLine(
      corner.translate(0, -half),
      corner.translate(0, half),
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // -------- 细网格（32dp，白 α.05）--------
    final finePath = Path();
    _addGrid(finePath, size, MechanicalStyle.fineGridSpacing);
    canvas.drawPath(
      finePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = MechanicalStyle.fineGridStrokeWidth
        ..color = MechanicalStyle.fineGridColor
        ..isAntiAlias = false,
    );

    // -------- 粗网格（128dp，白 α.10）--------
    final coarsePath = Path();
    _addGrid(coarsePath, size, MechanicalStyle.coarseGridSpacing);
    canvas.drawPath(
      coarsePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = MechanicalStyle.coarseGridStrokeWidth
        ..color = MechanicalStyle.coarseGridColor
        ..isAntiAlias = false,
    );

    // -------- 点阵（128dp 交点，r=1，白 α.22）--------
    // 与粗网格交点重合，压在网格线之上，还原原型 dot 层视觉。
    final dotPaint = Paint()
      ..color = MechanicalStyle.dotColor
      ..style = PaintingStyle.fill;
    for (double x = 0; x <= size.width; x += MechanicalStyle.dotGridSpacing) {
      for (double y = 0;
          y <= size.height;
          y += MechanicalStyle.dotGridSpacing) {
        canvas.drawCircle(Offset(x, y), MechanicalStyle.dotRadius, dotPaint);
      }
    }

    // -------- 四角十字（标定虚拟边界，无实体框线）--------
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = MechanicalStyle.crossStrokeWidth
      ..color = MechanicalStyle.crossColor
      ..isAntiAlias = false;
    final left = sideInset;
    final right = size.width - sideInset;
    _paintCross(canvas, Offset(left, topBoundary), crossPaint);
    _paintCross(canvas, Offset(right, topBoundary), crossPaint);
    _paintCross(canvas, Offset(left, bottomBoundary), crossPaint);
    _paintCross(canvas, Offset(right, bottomBoundary), crossPaint);
  }

  @override
  bool shouldRepaint(covariant _MechanicalGridPainter oldDelegate) =>
      oldDelegate.sideInset != sideInset ||
      oldDelegate.topBoundary != topBoundary ||
      oldDelegate.bottomBoundary != bottomBoundary;
}
