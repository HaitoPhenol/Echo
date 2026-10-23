import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/mechanical_style.dart';
import 'blueprint_canvas.dart';

/// 机能风背景：底色 + 三层工程纹理（细网格 / 粗网格 / 点阵）
/// + 无限画布示意底图 + 顶部一对十字定位标记。
///
/// 颜色取自 [AppColors] 的机能风视觉层色组，几何取自
/// [MechanicalStyle]（稿号溯源见两文件注释）。
///
/// 行为约定：
/// * 纹理与页面轨道**同步平移**（[panOffsetX] 与翻页 1:1 同速率）：
///   翻页时网格与点阵跟页面内容一起滑动；顶部十字是屏幕标定物，
///   始终钉在屏幕角上，不参与平移；
/// * 纹理是周期图案（周期 = 粗网格 [MechanicalStyle.coarseGridSpacing]），
///   平移量取模后视觉仍与无限铺满的 1:1 平移一致；纹理绘制区左右各多铺
///   一个周期，平移后不会露出空白边；
/// * 三层纹理相对绘制区左上角有整体平移（[MechanicalStyle.gridOriginShiftX/Y]
///   + 每次冷启动随机 0~128dp 的抖动，见 [_jitterX] / [_jitterY]）；
/// * 不画实体描边框、不画底部十字：仅顶部两个十字标定
///   「状态栏下沿、左右各 14dp」的位置；
/// * 示意底图（[BlueprintCanvas]）是**画在网格图纸上的内容**：冷启动固定
///   种子，按世界格坐标即时生成可见图元（无限画布），随 [canvasOffsetX]
///   连续平移，与网格同原点、同速率，不做平铺/取模，因此不会跳变；
/// * 静态绘制：纹理层与底图层各外包 [RepaintBoundary]，网格平移只改
///   [Transform] 偏移；底图层仅在翻页过程中重绘自身；
/// * 只画"表皮"，不承载任何交互。
class MechanicalBackground extends StatefulWidget {
  const MechanicalBackground({
    super.key,
    this.panOffsetX = 0,
    this.canvasOffsetX = 0,
  });

  /// 纹理层水平平移（dp）。
  ///
  /// 由调用方按「页面显示位置 × 屏宽」计算并取模一个纹理周期；
  /// 传入任意实数都安全——绘制区已左右各多铺一个周期。
  final double panOffsetX;

  /// 示意底图层水平平移（dp，**未取模**）。
  ///
  /// 底图是无限画布，不是周期图案：必须传连续的翻页位移，
  /// 取模会让世界坐标瞬间跳回，图案随之跳变。
  final double canvasOffsetX;

  /// 纹理层左右额外绘制宽度 = 一个粗网格周期。
  ///
  /// 必须 ≥ 平移量的取值周期，否则平移后左/右边缘会露出空白底色。
  static const double _bleed = MechanicalStyle.coarseGridSpacing;

  @override
  State<MechanicalBackground> createState() => _MechanicalBackgroundState();
}

class _MechanicalBackgroundState extends State<MechanicalBackground> {
  /// 本次冷启动固定的纹理原点随机抖动（各轴 0~128dp）。
  ///
  /// 与 [MechanicalStyle.gridOriginShiftX/Y] 相加后使用：静态基值保证
  /// 纹理与十字/点阵的对位关系，随机量让每次启动的格线落点不同。
  /// 取在 State 里且只算一次——热重载/重建/翻页都不会重新摇。
  late final double _jitterX =
      math.Random().nextDouble() * MechanicalStyle.coarseGridSpacing;
  late final double _jitterY =
      math.Random().nextDouble() * MechanicalStyle.coarseGridSpacing;

  @override
  Widget build(BuildContext context) {
    // 虚拟顶边：状态栏下沿 + 8dp 呼吸位（顶部十字位置）。
    final topBoundary =
        MediaQuery.viewPaddingOf(context).top + 8 > MechanicalStyle.frameInset
        ? MediaQuery.viewPaddingOf(context).top + 8
        : MechanicalStyle.frameInset;

    // 网格与底图共用同一世界原点（静态基值 + 冷启动抖动）。
    final originX = MechanicalStyle.gridOriginShiftX + _jitterX;
    final originY = MechanicalStyle.gridOriginShiftY + _jitterY;

    // 纯装饰视觉层，无障碍树中排除播报（G6）。
    return ExcludeSemantics(
      child: Stack(
        // 纹理层向左越出一个周期，裁剪交给外层（屏幕级）Stack。
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: ColoredBox(color: AppColors.mechBackground),
          ),

          // -------- 会随页面平移的纹理层 --------
          Positioned(
            left: -MechanicalBackground._bleed,
            right: -MechanicalBackground._bleed,
            top: 0,
            bottom: 0,
            child: Transform.translate(
              offset: Offset(widget.panOffsetX, 0),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _MechanicalGridPainter(
                    originShiftX: originX,
                    originShiftY: originY,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),

          // -------- 无限画布示意底图（画在网格纸上，同原点同速平移） --------
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _BlueprintCanvasPainter(
                  camera: Offset(widget.canvasOffsetX + originX, originY),
                ),
                size: Size.infinite,
              ),
            ),
          ),

          // -------- 钉在屏幕上的顶部双十字 --------
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _MechanicalCrossPainter(topBoundary: topBoundary),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 示意底图绘制器：按当前相机位置枚举可见世界格，即时生成并绘制。
///
/// 图案只取决于格坐标与冷启动种子，与视口位置无关；
/// 平移即换一批可见格，边缘处的图案天然连续，不存在平铺跳变。
class _BlueprintCanvasPainter extends CustomPainter {
  const _BlueprintCanvasPainter({required this.camera});

  /// 世界原点在屏幕上的 dp 坐标。
  final Offset camera;

  @override
  void paint(Canvas canvas, Size size) {
    final ops = BlueprintCanvas.build(
      size: size,
      camera: camera,
      seed: BlueprintCanvas.seed,
    );
    for (final op in ops) {
      op.paint(canvas);
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintCanvasPainter oldDelegate) =>
      oldDelegate.camera != camera;
}

/// 纹理绘制器：细网格 → 粗网格 → 点阵。
///
/// 网格用单个 Path 收集全部线段后一次描边，点阵逐交点画圆；
/// 三层共用同一原点平移（[originShiftX/Y]，含冷启动随机抖动），
/// 保证点阵仍压在粗网格交点上。绘制参数整次启动固定，
/// 一次绘制长期复用（_bleed 区域一并铺满）。
class _MechanicalGridPainter extends CustomPainter {
  _MechanicalGridPainter({
    required this.originShiftX,
    required this.originShiftY,
  });

  /// 纹理原点平移（dp）= 静态基值 + 本次冷启动随机抖动。
  final double originShiftX;
  final double originShiftY;

  @override
  void paint(Canvas canvas, Size size) {
    // -------- 细网格（16dp，白 α.03）--------
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

    // -------- 粗网格（128dp，白 α.07）--------
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

    // -------- 点阵（128dp 交点，r=1，白 α.15）--------
    // 与粗网格同原点平移，点保持压在粗网格交点上。
    final dotPaint = Paint()
      ..color = AppColors.mechGridDot
      ..style = PaintingStyle.fill;
    final spacing = MechanicalStyle.dotGridSpacing;
    final shiftX = originShiftX % spacing;
    final shiftY = originShiftY % spacing;
    for (double x = -spacing + shiftX; x <= size.width; x += spacing) {
      for (double y = -spacing + shiftY; y <= size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), MechanicalStyle.dotRadius, dotPaint);
      }
    }
  }

  /// 画一组间距 [spacing] 的网格，整体平移取本绘制器的原点平移；
  /// 循环从 -spacing 起、到 size 边界止，保证平移后铺满整个绘制区。
  void _addGrid(Path path, Size size, double spacing) {
    final shiftX = originShiftX % spacing;
    final shiftY = originShiftY % spacing;
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

  @override
  bool shouldRepaint(covariant _MechanicalGridPainter oldDelegate) =>
      oldDelegate.originShiftX != originShiftX ||
      oldDelegate.originShiftY != originShiftY;
}

/// 顶部双十字绘制器：固定层，不随纹理平移。
class _MechanicalCrossPainter extends CustomPainter {
  const _MechanicalCrossPainter({required this.topBoundary});

  /// 顶部十字中心的 y（状态栏下沿 + 呼吸位）。
  final double topBoundary;

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
  bool shouldRepaint(covariant _MechanicalCrossPainter oldDelegate) =>
      oldDelegate.topBoundary != topBoundary;
}
