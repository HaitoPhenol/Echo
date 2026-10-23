import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/mechanical_style.dart';
import 'blueprint_sheet.dart';

/// 机能风背景：底色 + 三层工程纹理（细网格 / 粗网格 / 点阵）
/// + 冷启动生成的示意底图 + 顶部一对十字定位标记。
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
/// * 示意底图（[BlueprintSheet]）是**整屏一张静态图**：冷启动按时间种子
///   生成一次并缓存，翻页时不平移（与纹理层形成两个深度），
///   尺寸/像素密度变化时重新生成；
/// * 静态绘制：纹理层、底图层与十字层各外包 [RepaintBoundary]，平移只改
///   [Transform] 偏移，导航动画不会引发背景重绘；
/// * 只画"表皮"，不承载任何交互。
class MechanicalBackground extends StatefulWidget {
  const MechanicalBackground({super.key, this.panOffsetX = 0});

  /// 纹理层水平平移（dp）。
  ///
  /// 由调用方按「页面显示位置 × 屏宽」计算并取模一个纹理周期；
  /// 传入任意实数都安全——绘制区已左右各多铺一个周期。
  final double panOffsetX;

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

  /// 冷启动示意底图（整屏一张，栅格化后由绘制器直接贴图）。
  ui.Image? _sheet;

  /// 正在生成的尺寸（避免依赖变化时对同一尺寸重复排队）。
  Size? _sheetRequest;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cached = BlueprintSheet.peek(size, dpr);
    if (cached != null) {
      _sheet = cached;
      return;
    }
    if (_sheetRequest == size) return;
    _sheetRequest = size;
    // 延到首帧之后再栅格化：不与启动帧争用 raster 线程。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadSheet(size, dpr),
    );
  }

  Future<void> _loadSheet(Size size, double dpr) async {
    final image = await BlueprintSheet.ensure(size, dpr);
    if (!mounted || image == null) return;
    if (MediaQuery.sizeOf(context) != size) return;
    setState(() => _sheet = image);
  }

  @override
  Widget build(BuildContext context) {
    // 虚拟顶边：状态栏下沿 + 8dp 呼吸位（顶部十字位置）。
    final topBoundary =
        MediaQuery.viewPaddingOf(context).top + 8 > MechanicalStyle.frameInset
        ? MediaQuery.viewPaddingOf(context).top + 8
        : MechanicalStyle.frameInset;

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
                    originShiftX:
                        MechanicalStyle.gridOriginShiftX + _jitterX,
                    originShiftY:
                        MechanicalStyle.gridOriginShiftY + _jitterY,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),

          // -------- 冷启动生成的示意底图（静态，不随翻页平移） --------
          if (_sheet != null)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _BlueprintPainter(_sheet!),
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

/// 示意底图绘制器：把冷启动栅格化的整屏图按逻辑尺寸贴回背景。
///
/// 图已按设备像素密度生成，这里只做一次缩放贴图，无任何生成/排版开销；
/// 只在换图（尺寸或种子变化）时重绘。
class _BlueprintPainter extends CustomPainter {
  _BlueprintPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter oldDelegate) =>
      oldDelegate.image != image;
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
