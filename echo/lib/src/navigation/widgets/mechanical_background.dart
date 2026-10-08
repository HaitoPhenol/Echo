import 'package:flutter/material.dart';

import '../../theme/mechanical_style.dart';

/// 机能风固定背景：实验底色 + 三层工程纹理（细网格 / 粗网格 / 点阵）
/// + 描边框与左上/右下对角十字定位标记。
///
/// 实验隔离组件（feat/page-background-art）：数值全部取自
/// [MechanicalStyle]，方案验收/放弃时随实验层整体处理。
///
/// 行为约定（A2/A3，与设计稿 viewport 固定背景一致）：
/// * 纹理与边框**固定在屏幕上**，不随横向翻页移动，页面内容从其上方滑过；
/// * 静态绘制，外包 [RepaintBoundary]，导航动画不会引发背景重绘；
/// * 只画"表皮"，不承载任何交互。
class MechanicalBackground extends StatelessWidget {
  const MechanicalBackground({super.key});

  @override
  Widget build(BuildContext context) {
    // 状态栏高度（dp）：描边框上边距要避开左上角时钟。
    final statusBarTop = MediaQuery.viewPaddingOf(context).top;
    final inset = MechanicalStyle.frameInset;
    final framePadding = EdgeInsets.fromLTRB(
      inset,
      statusBarTop + 8 > inset ? statusBarTop + 8 : inset,
      inset,
      inset,
    );

    return RepaintBoundary(
      child: ColoredBox(
        color: MechanicalStyle.baseBackground,
        child: CustomPaint(
          painter: _MechanicalGridPainter(framePadding: framePadding),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// 背景绘制器：细网格 → 粗网格 → 点阵 → 描边框 → 对角双十字。
///
/// 网格用单个 Path 收集全部线段后一次描边，点阵逐交点画圆；
/// 唯二入参是边框内边距，[shouldRepaint] 仅在边距变化时为 true。
class _MechanicalGridPainter extends CustomPainter {
  const _MechanicalGridPainter({required this.framePadding});

  /// 描边框相对屏幕四边的内边距（上边距已避让状态栏）。
  final EdgeInsets framePadding;

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

    // -------- 描边框（内缩 14dp，白 α.14）--------
    final frameRect = Rect.fromLTWH(
      framePadding.left,
      framePadding.top,
      size.width - framePadding.horizontal,
      size.height - framePadding.vertical,
    );
    canvas.drawRect(
      frameRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = MechanicalStyle.frameStrokeWidth
        ..color = MechanicalStyle.frameColor
        ..isAntiAlias = false,
    );

    // -------- 左上 / 右下对角双十字（22dp，白 α.50）--------
    // 与原稿一致：十字中心精确压在边框角点上。
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = MechanicalStyle.crossStrokeWidth
      ..color = MechanicalStyle.crossColor
      ..isAntiAlias = false;
    _paintCross(canvas, frameRect.topLeft, crossPaint);
    _paintCross(canvas, frameRect.bottomRight, crossPaint);
  }

  @override
  bool shouldRepaint(covariant _MechanicalGridPainter oldDelegate) =>
      oldDelegate.framePadding != framePadding;
}
