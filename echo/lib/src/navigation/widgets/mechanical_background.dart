import 'package:flutter/material.dart';

import '../../theme/mechanical_style.dart';

/// 机能风固定背景：实验底色 + 三层工程纹理（细网格 / 粗网格 / 点阵）。
///
/// 实验隔离组件（feat/page-background-art）：数值全部取自
/// [MechanicalStyle]，方案验收/放弃时随实验层整体处理。
///
/// 行为约定（A2，与设计稿 viewport 固定背景一致）：
/// * 纹理**固定在屏幕上**，不随横向翻页移动，页面内容从纹理上方滑过；
/// * 静态绘制，外包 [RepaintBoundary]，导航动画不会引发纹理重绘；
/// * 只画"表皮"，不承载任何交互。
class MechanicalBackground extends StatelessWidget {
  const MechanicalBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: ColoredBox(
        color: MechanicalStyle.baseBackground,
        child: CustomPaint(
          painter: _MechanicalGridPainter(),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// 三层背景纹理绘制器：细网格 → 粗网格 → 点阵。
///
/// 网格用单个 Path 收集全部线段后一次描边，点阵逐交点画圆；
/// 无任何可变参数，[shouldRepaint] 恒为 false。
class _MechanicalGridPainter extends CustomPainter {
  const _MechanicalGridPainter();

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
        canvas.drawCircle(
          Offset(x, y),
          MechanicalStyle.dotRadius,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MechanicalGridPainter oldDelegate) => false;
}
