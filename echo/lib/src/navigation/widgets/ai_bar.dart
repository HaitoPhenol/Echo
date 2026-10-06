import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../dock_geometry.dart';

/// 底部三条居中的 **AI 条**。
///
/// 与把手条/导航条同高（10px），但视觉是一条持续流动的虹彩带
/// （蓝→紫→粉→琥珀→绿→青循环，7s 匀速一周），条外罩着同色
/// 模糊光晕。手势由父级 SmartNavScreen 识别：
/// - 长按 450ms：呼出 AI 对话框；
/// - 单击：预留，不做任何事。
///
/// 按压时整体增亮（亮度 ×1.3）、光晕不透明度 .55→.95（对齐原型
/// ideas/another_two_lines.html）。
///
/// 虹彩六色是 AI 条专属识别色、不属于中性亮度阶梯，按项目约定
/// 就地定义在本文件，不进共享色板。
class AiBar extends StatefulWidget {
  const AiBar({super.key, required this.pressed});

  /// 是否处于按压态（增亮 + 光晕加强）。
  final bool pressed;

  @override
  State<AiBar> createState() => _AiBarState();
}

class _AiBarState extends State<AiBar> with SingleTickerProviderStateMixin {
  /// 虹彩流动一周的时长（与原型一致）。
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 光晕上下各外溢 4px：用 OverflowBox 给画师 18px 高的画布，
    // 视觉本体仍占 10px，命中区域由父级隐形热区决定。
    return RepaintBoundary(
      child: OverflowBox(
        minHeight: DockGeometry.barHeight + 8,
        maxHeight: DockGeometry.barHeight + 8,
        alignment: Alignment.center,
        child: AnimatedBuilder(
          animation: _flow,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _AiFlowPainter(
              phase: _flow.value,
              pressed: widget.pressed,
            ),
          ),
        ),
      ),
    );
  }
}

/// 虹彩条 + 光晕画师。
///
/// 渐变在一个 [_periodWidth]（条宽的 2.8 倍，对应原型 background-size:
/// 280%）宽的循环上首尾同色，配合 [ui.TileMode.repeated] 平移着色器，
/// 相位走到 1 时与 0 完全一致，无限滚动无接缝。
class _AiFlowPainter extends CustomPainter {
  _AiFlowPainter({required this.phase, required this.pressed});

  /// 流动相位 0..1（一周）。
  final double phase;

  final bool pressed;

  /// 虹彩循环色（首尾相同以保证接缝连续）。
  static const List<Color> _colors = [
    Color(0xFF7AA2FF),
    Color(0xFFB48AFF),
    Color(0xFFFF8AD0),
    Color(0xFFFFC46B),
    Color(0xFF6FD6A8),
    Color(0xFF5EC8E8),
    Color(0xFF7AA2FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = DockGeometry.barHeight;
    final periodWidth = size.width * 2.8;
    final shift = phase * periodWidth;

    final barTop = (size.height - barHeight) / 2;
    final barRect = Rect.fromLTWH(0, barTop, size.width, barHeight);
    final barRRect = RRect.fromRectAndRadius(
      barRect,
      const Radius.circular(barHeight / 2),
    );
    // 光晕只在竖直方向外扩 4px，横向与条等宽（对齐原型 ::before）。
    final haloRect = Rect.fromLTRB(0, barTop - 4, size.width, barTop + barHeight + 4);
    final haloRRect = RRect.fromRectAndRadius(
      haloRect,
      Radius.circular(haloRect.height / 2),
    );

    Paint buildPaint({required bool halo}) {
      // 渐变按一个完整循环周期创建，repeated 模式下平移着色器即可无缝
      // 滚动。注意只能动 shader 起点：若 translate 画布，条体本身会
      // 跟着相位滑出屏幕。
      // 对齐原型 linear-gradient(110deg)：相对水平方向下倾 20°。
      final shader = const LinearGradient(
        colors: _colors,
        tileMode: ui.TileMode.repeated,
        transform: GradientRotation(20 * math.pi / 180),
      ).createShader(Rect.fromLTWH(-shift, 0, periodWidth, size.height));
      final paint = Paint()..shader = shader;
      if (halo) {
        paint
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7)
          // 不透明渐变叠 alpha 滤镜得到半透明光晕。
          ..colorFilter = ColorFilter.matrix(<double>[
            1, 0, 0, 0, 0,
            0, 1, 0, 0, 0,
            0, 0, 1, 0, 0,
            0, 0, 0, pressed ? 0.95 : 0.55, 0,
          ]);
      } else if (pressed) {
        // brightness(1.3)：RGB 通道整体放大（超 1 的部分由渲染器夹取）。
        paint.colorFilter = const ColorFilter.matrix(<double>[
          1.3, 0, 0, 0, 0,
          0, 1.3, 0, 0, 0,
          0, 0, 1.3, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      }
      return paint;
    }

    // 光晕在下、条在上；条体位置固定，流动只发生在着色器内部
    //（光晕允许竖直外溢，条本身由 rrect 约束形状）。
    canvas.drawRRect(haloRRect, buildPaint(halo: true));
    canvas.drawRRect(barRRect, buildPaint(halo: false));
  }

  @override
  bool shouldRepaint(_AiFlowPainter old) =>
      old.phase != phase || old.pressed != pressed;
}
