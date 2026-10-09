import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/mechanical_style.dart';
import '../nav_physics.dart';
import 'mechanical_indicator_lifecycle.dart';

/// 机能风 3D 页码转鼓指示器（右下角页码指示）。
///
/// 移植自设计工程稿 `ideas/mechanical_style_page.html` 的右下角
/// 「滚筒模块」（稿 L319-345），相对原稿做了精简（导航线本身已传达
/// 页位，冗余指示删除）：
/// - 顶行：闪烁 blip + PAGE 标签（原稿右上 NO.0N 编号已删）；
/// - 主体：贴了 N 个大数字牌片的圆柱（rotateY 转鼓），横滑时跟手
///   连续转动（吃 [NavPhysicsController.displayPosition]）；
/// - 底部 2px 进度条；面板左上/右下各一道直角亮线。
/// （原稿视窗右侧的竖排刻度列已删，面板随之收窄，给左下页名牌让位。）
///
/// 显隐由 rollerVisible 驱动，统一走 `MechanicalIndicatorLifecycle`
/// （入场 fade+rise；退场水平百叶窗故障熄灭，与页名牌同帧同节奏），
/// 手势唤醒机制不在本组件内；圆点 stepPage / snapTo
/// 路径不显示转鼓，只有横滑 dragStart 才唤醒。左下角的
/// `MechanicalPageNamePlate` 与本组件共用同一显隐节奏。
class MechanicalPageDrum extends StatelessWidget {
  const MechanicalPageDrum({
    super.key,
    required this.controller,
    required this.pageCount,
  });

  final NavPhysicsController controller;

  /// 转鼓总页数（牌片数量）。
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final panelWidth =
        MechanicalStyle.drumPadH * 2 + MechanicalStyle.drumViewWidth;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MechanicalIndicatorLifecycle(
          visible: controller.rollerVisible,
          instant: controller.rollerInstantHide,
          child: SizedBox(
            width: panelWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.mechDrumPanel,
                border: Border.all(color: AppColors.mechDrumLine),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: MechanicalStyle.drumPadH,
                      top: MechanicalStyle.drumPadTop,
                      right: MechanicalStyle.drumPadH,
                      bottom: MechanicalStyle.drumPadBottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _DrumHead(),
                        const SizedBox(height: MechanicalStyle.drumHeadGap),
                        _DrumView(controller: controller, pageCount: pageCount),
                      ],
                    ),
                  ),
                  // 底部进度条：暗轨 + 跟手填充，贴面板最底边（稿 .pbar）。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      height: MechanicalStyle.drumProgressHeight,
                      child: ColoredBox(color: AppColors.mechDrumProgressTrack),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    height: MechanicalStyle.drumProgressHeight,
                    child: _DrumProgressFill(
                      controller: controller,
                      trackWidth: panelWidth,
                      pageCount: pageCount,
                    ),
                  ),
                  // 左上/右下直角亮线。
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _CornerPainter()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 顶行：闪烁小方块 + PAGE 标签。
class _DrumHead extends StatelessWidget {
  const _DrumHead();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Blip(),
        SizedBox(width: 8),
        Text(
          'PAGE',
          style: TextStyle(
            fontSize: MechanicalStyle.drumTagFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: MechanicalStyle.drumTagLetterSpacing,
            color: AppColors.mechInkDim,
          ),
        ),
      ],
    );
  }
}

/// 闪烁状态小方块：稿 blip 1.2s steps(2) 硬切明灭。
class _Blip extends StatefulWidget {
  const _Blip();

  @override
  State<_Blip> createState() => _BlipState();
}

class _BlipState extends State<_Blip> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MechanicalStyle.drumBlipPeriod,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // steps(2,start)：前半周期亮、后半周期灭。
        final on = _controller.value < 0.5;
        return SizedBox(
          width: MechanicalStyle.drumBlipSize,
          height: MechanicalStyle.drumBlipSize,
          child: ColoredBox(color: on ? AppColors.mechInk : Colors.transparent),
        );
      },
    );
  }
}

/// 3D 视窗：裁切 + 圆柱牌片 + 左右虚线竖边。
///
/// 牌片用单层 [CustomPainter] 在一个 Canvas 上直接合成「透视 × 旋转 ×
/// 推进」矩阵绘制（而不是嵌套多个带 3D Transform 的 widget 层）：
/// 后者在 Impeller 下会出现牌片整层不渲染的问题，Canvas 4×4 变换是
/// Skia/Impeller 共有的底层稳定路径。
class _DrumView extends StatelessWidget {
  const _DrumView({required this.controller, required this.pageCount});

  final NavPhysicsController controller;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MechanicalStyle.drumViewWidth,
      height: MechanicalStyle.drumViewHeight,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DrumPainter(
                  controller: controller,
                  pageCount: pageCount,
                ),
              ),
            ),
            // 左右虚线竖边（前景，不随鼓转动）。
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ViewEdgePainter()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 转鼓牌片绘制器：每张数字牌片是圆柱上的一个扇区。
class _DrumPainter extends CustomPainter {
  _DrumPainter({required this.controller, required this.pageCount})
    : super(repaint: controller);

  final NavPhysicsController controller;
  final int pageCount;

  @override
  void paint(Canvas canvas, Size size) {
    final segmentDeg = 360 / pageCount;
    final drumAngleDeg = -controller.displayPosition * segmentDeg;
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 收集可见面并按深度排序：z=R·cos(world) 小（更靠后）的先画，
    // 正面最后画，模拟深度遮挡（Canvas 无深度缓冲）。
    final faces = <({int index, double worldDeg})>[];
    for (var i = 0; i < pageCount; i++) {
      final world = _wrapDeg(drumAngleDeg + i * segmentDeg);
      // ±90° 以外背向观察者（CSS backface-visibility:hidden）。
      if (world.abs() < 90) faces.add((index: i, worldDeg: world));
    }
    faces.sort((a, b) => b.worldDeg.abs().compareTo(a.worldDeg.abs()));

    for (final face in faces) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: (face.index + 1).toString().padLeft(2, '0'),
          style: const TextStyle(
            fontSize: MechanicalStyle.drumNumberFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: MechanicalStyle.drumNumberLetterSpacing,
            color: AppColors.mechDrumNumber,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // TextPainter 的 paint 原点是行盒左上角；用 ascent/descent 让
      // 墨水块几何中心落在牌片原点（数字无下行笔画，视觉基本居中）。
      final line = textPainter.computeLineMetrics().first;
      final dx = -textPainter.width / 2;
      final dy = -(line.ascent + line.descent) / 2;

      // 单点透视投影（CSS perspective(520)、灭点在视窗中心）。
      //
      // 不能写成 T(c)·P·… 的外包平移：那样屏幕平移会被透视除法
      // 连带除以 w，灭点漂移、z=R 上的牌片既不居中也不放大。
      // 这里把平移放到齐次 w 一侧，使 (0,0,R) 严格投影到 (cx,cy)，
      // 输出坐标 = c + v·persp/(persp-z)。
      final p = 1 / MechanicalStyle.drumPerspective;
      final matrix =
          Matrix4(
              1,
              0,
              0,
              0, // col 0
              0,
              1,
              0,
              0, // col 1
              -cx * p,
              -cy * p,
              1,
              -p, // col 2
              cx,
              cy,
              0,
              1, // col 3（屏幕平移）
            )
            ..rotateY(face.worldDeg * math.pi / 180)
            ..translateByDouble(0, 0, MechanicalStyle.drumRadius, 1)
            ..translateByDouble(dx, dy, 0, 1);

      canvas.save();
      canvas.transform(matrix.storage);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  static double _wrapDeg(double deg) {
    var a = deg % 360;
    if (a > 180) a -= 360;
    if (a < -180) a += 360;
    return a;
  }

  @override
  bool shouldRepaint(_DrumPainter oldDelegate) =>
      oldDelegate.pageCount != pageCount;
}

/// 底部进度填充：宽度 = 面板宽 × 当前进度（稿 #pfill scaleX）。
class _DrumProgressFill extends StatelessWidget {
  const _DrumProgressFill({
    required this.controller,
    required this.trackWidth,
    required this.pageCount,
  });

  final NavPhysicsController controller;
  final double trackWidth;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final progress = pageCount <= 1
            ? 0.0
            : (controller.displayPosition / (pageCount - 1)).clamp(0.0, 1.0);
        return SizedBox(
          width: trackWidth * progress,
          child: const ColoredBox(color: AppColors.mechInk),
        );
      },
    );
  }
}

/// 视窗左右两条竖直虚线（稿 border-left/right:1px dashed --line）。
class _ViewEdgePainter extends CustomPainter {
  const _ViewEdgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mechDrumLine
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    for (final dx in [0.5, size.width - 0.5]) {
      for (double y = 0; y < size.height; y += dash + gap) {
        canvas.drawLine(
          Offset(dx, y),
          Offset(dx, math.min(y + dash, size.height)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ViewEdgePainter oldDelegate) => false;
}

/// 面板左上/右下直角亮线（稿 #ind::before / ::after，16px、2px）。
class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mechInk
      ..strokeWidth = MechanicalStyle.drumCornerStrokeWidth
      ..strokeCap = StrokeCap.square;
    const s = MechanicalStyle.drumCornerSize;
    final w = MechanicalStyle.drumCornerStrokeWidth / 2;

    // 左上：横 + 竖（稿定位 top:-2px;left:-2px，即骑在边框角上）。
    canvas.drawLine(Offset(-w, w), Offset(s, w), paint);
    canvas.drawLine(Offset(w, -w), Offset(w, s), paint);

    // 右下。
    canvas.drawLine(
      Offset(size.width - s, size.height - w),
      Offset(size.width + w, size.height - w),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - w, size.height - s),
      Offset(size.width - w, size.height + w),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}
