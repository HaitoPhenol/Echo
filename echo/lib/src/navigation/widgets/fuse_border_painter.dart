import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 搜索胶囊「倒计时烧蚀」边框的画笔。
///
/// 原型用上下两条 SVG 路径配合 stroke-dasharray，从右端开始烧蚀；
/// 这里用 [PathMetric.extractPath] 取每条路径的前段（长度按进度比例），
/// 达到同样的逐段消失效果。
class FuseBorderPainter extends CustomPainter {
  FuseBorderPainter({required this.progress});

  /// 边框剩余进度：1 = 完整，0 = 全部烧完。
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // 画布比胶囊每边大 4px（见搜索胶囊的 Positioned 外扩），
    // 描边宽度 7，因此描边中心线需内缩半个线宽。
    const strokeWidth = 7.0;
    final width = size.width;
    final height = size.height;

    final xRight = width - strokeWidth / 2;
    final xLeft = strokeWidth / 2;
    final yTop = strokeWidth / 2;
    final yBottom = height - strokeWidth / 2;
    final yMiddle = height / 2;

    // 半圆端头的半径（52px 高的画布对应 22.5）。
    final radius = height / 2 - strokeWidth / 2;
    final radiusOffset = Radius.circular(radius);

    // 上半路径：右端中点 → 右上圆弧 → 顶边直线 → 左上圆弧 → 左端中点。
    final topPath = Path()
      ..moveTo(xRight, yMiddle)
      ..arcToPoint(
        Offset(xRight - radius, yTop),
        radius: radiusOffset,
        clockwise: false,
      )
      ..lineTo(xLeft + radius, yTop)
      ..arcToPoint(
        Offset(xLeft, yMiddle),
        radius: radiusOffset,
        clockwise: false,
      );

    // 下半路径：右端中点 → 右下圆弧 → 底边直线 → 左下圆弧 → 左端中点。
    final bottomPath = Path()
      ..moveTo(xRight, yMiddle)
      ..arcToPoint(
        Offset(xRight - radius, yBottom),
        radius: radiusOffset,
        clockwise: true,
      )
      ..lineTo(xLeft + radius, yBottom)
      ..arcToPoint(
        Offset(xLeft, yMiddle),
        radius: radiusOffset,
        clockwise: true,
      );

    final paint = Paint()
      ..color = AppColors.accentBlue.withValues(alpha: 0.95)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 按进度截取路径的前段绘制。
    for (final path in [topPath, bottomPath]) {
      final metric = path.computeMetrics().first;
      final drawLength = metric.length * progress.clamp(0, 1);
      canvas.drawPath(metric.extractPath(0, drawLength), paint);
    }
  }

  @override
  bool shouldRepaint(FuseBorderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
