import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/mechanical_style.dart';

/// 机能风固定背景：实验底色 + 三层工程纹理（细网格 / 粗网格 / 点阵）
/// + 顶部一对十字定位标记。
///
/// 实验隔离组件（feat/page-background-art）：数值全部取自
/// [MechanicalStyle]，方案验收/放弃时随实验层整体处理。
///
/// 行为约定：
/// * 纹理与十字**固定在屏幕上**，不随横向翻页移动，页面内容从其上方滑过；
/// * 三层纹理相对屏幕左上角有整体平移（[MechanicalStyle.gridOriginShiftX/Y]）；
/// * 不画实体描边框、不画底部十字（实验改版）：仅顶部两个十字标定
///   「状态栏下沿、左右各 14dp」的位置；
/// * 静态绘制，外包 [RepaintBoundary]，导航动画不会引发背景重绘；
/// * 只画"表皮"，不承载任何交互。
class MechanicalBackground extends StatelessWidget {
  const MechanicalBackground({super.key});

  @override
  Widget build(BuildContext context) {
    // 虚拟顶边：状态栏下沿 + 8dp 呼吸位（顶部十字位置）。
    final topBoundary =
        MediaQuery.viewPaddingOf(context).top + 8 > MechanicalStyle.frameInset
        ? MediaQuery.viewPaddingOf(context).top + 8
        : MechanicalStyle.frameInset;

    return RepaintBoundary(
      child: ColoredBox(
        color: AppColors.mechBackground,
        child: CustomPaint(
          painter: _MechanicalGridPainter(topBoundary: topBoundary),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// 背景绘制器：细网格 → 粗网格 → 点阵 → 顶部双十字。
///
/// 网格用单个 Path 收集全部线段后一次描边，点阵逐交点画圆；
/// 入参仅为顶部边界坐标，[shouldRepaint] 只在其变化时为 true。
class _MechanicalGridPainter extends CustomPainter {
  const _MechanicalGridPainter({required this.topBoundary});

  /// 顶部十字中心的 y（状态栏下沿 + 呼吸位）。
  final double topBoundary;

  /// 画一组间距 [spacing] 的网格，整体平移取自 MechanicalStyle；
  /// 循环从 -spacing 起、到 width+spacing 止，保证平移后屏幕铺满。
  void _addGrid(Path path, Size size, double spacing) {
    final shiftX = MechanicalStyle.gridOriginShiftX % spacing;
    final shiftY = MechanicalStyle.gridOriginShiftY % spacing;
    // 竖线。
    for (double x = -spacing + shiftX; x <= size.width; x += spacing) {
      path
        ..moveTo(x, 0)
        ..lineTo(x, size.height);
    }
    // 横线。
    for (double y = -spacing + shiftY; y <= size.height; y += spacing) {
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
        ..color = AppColors.mechFineGrid
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
        ..color = AppColors.mechCoarseGrid
        ..isAntiAlias = false,
    );

    // -------- 点阵（128dp 交点，r=1，白 α.22）--------
    // 与粗网格同原点平移，点保持压在粗网格交点上。
    final dotPaint = Paint()
      ..color = AppColors.mechGridDot
      ..style = PaintingStyle.fill;
    final spacing = MechanicalStyle.dotGridSpacing;
    final shiftX = MechanicalStyle.gridOriginShiftX % spacing;
    final shiftY = MechanicalStyle.gridOriginShiftY % spacing;
    for (double x = -spacing + shiftX; x <= size.width; x += spacing) {
      for (double y = -spacing + shiftY; y <= size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), MechanicalStyle.dotRadius, dotPaint);
      }
    }

    // -------- 顶部双十字（标定状态栏下沿，无实体框线、无底部十字）--------
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = MechanicalStyle.crossStrokeWidth
      ..color = AppColors.mechCoarseGrid
      ..isAntiAlias = false;
    _paintCross(
      canvas,
      Offset(MechanicalStyle.frameInset, topBoundary),
      crossPaint,
    );
    _paintCross(
      canvas,
      Offset(size.width - MechanicalStyle.frameInset, topBoundary),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MechanicalGridPainter oldDelegate) =>
      oldDelegate.topBoundary != topBoundary;
}
