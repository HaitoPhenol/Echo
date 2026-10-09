import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/mechanical_style.dart';
import '../nav_physics.dart';

/// 机能风左下角页名牌（横滑唤醒时与转鼓同时浮现）。
///
/// 移植自设计工程稿 `ideas/mechanical_style_page.html` 的左下角
/// 「#pgname」（稿 L305-317、L918-938）：半透明面板色块内一个大字
/// 页名 + 下方 56px 短横线。显隐节奏与 [MechanicalPageDrum] 完全一致
/// （同一个 rollerVisible、同一组 fade/rise 时长/曲线），二者构成
/// 「分开的整体」；在此之上，页名叠加一层赛博故障（glitch）效果。
///
/// 故障在两个时机播放，都是整段约 620ms（三水平切片错时闪烁接通、
/// 整字幅度递减的数码抖动、灰色重影副本、若干 1px 故障白线扫过、
/// 下划线重新展开）：
/// - **唤醒时**：rollerVisible false→true 的同一帧播一次入场；
/// - **唤醒期间成功翻页**：横滑跨过页中点、activePage 硬切的同一帧
///   立即从头重播；连续跨页时每次切换都重播，节奏天然连贯。
///
/// 首/末页继续滑的边界回弹 activePage 不变，不触发故障；收回时也
/// 不做故障：故障即时回到稳态，跟随转鼓同一 fade/rise 淡出。
///
/// 组件只负责内容与显隐；屏幕位置由调用方用 [Positioned] 给定：
/// left:5vw，色块底边与右下转鼓面板底边对齐（52+安全区；
/// 原稿 bottom:26 的定位未采用，以用户真机裁决的底对齐为准）。
class MechanicalPageNamePlate extends StatefulWidget {
  const MechanicalPageNamePlate({
    super.key,
    required this.controller,
    required this.labels,
  });

  final NavPhysicsController controller;

  /// 按轨道顺序排列的页名（由 NavDestination.label 统一提供）。
  final List<String> labels;

  @override
  State<MechanicalPageNamePlate> createState() =>
      _MechanicalPageNamePlateState();
}

class _MechanicalPageNamePlateState extends State<MechanicalPageNamePlate>
    with TickerProviderStateMixin {
  /// 翻页故障序列。value=1 为稳态（整字常亮、无色差/白线）；
  /// 每次成功翻页 `forward(from: 0)` 重播，唤醒/收回时直接置 1。
  late final AnimationController _glitch = AnimationController(
    vsync: this,
    duration: MechanicalStyle.nameGlitchDuration,
  )..value = 1;

  late bool _lastVisible = widget.controller.rollerVisible;
  late int _lastIndex = widget.controller.activePage;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(covariant MechanicalPageNamePlate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      _lastVisible = widget.controller.rollerVisible;
      _lastIndex = widget.controller.activePage;
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _glitch.dispose();
    super.dispose();
  }

  /// 显隐/翻页事件转成故障时序。显隐骨架（AnimatedOpacity/AnimatedSlide）
  /// 由 build 直接读 controller，与此处监听各自独立、同一帧生效。
  void _onController() {
    final visible = widget.controller.rollerVisible;
    final index = widget.controller.activePage;
    if (visible != _lastVisible) {
      _lastVisible = visible;
      _lastIndex = index;
      if (visible) {
        // 唤醒：转鼓 fade/rise 的同帧，页名故障播一次入场；
        // _lastIndex 已同步当前页，之后只有真正翻过中点才会再播。
        _glitch.forward(from: 0);
      } else {
        // 收回：不做故障，直接回稳态，只留与转鼓相同的 fade/rise。
        _glitch.value = 1;
      }
    } else if (visible && index != _lastIndex) {
      // 唤醒期间成功翻页（跨中点硬切）：立即重播整段故障。连续跨页
      // 每次切换都从头来，形成连贯的故障连击；首/末页边界回弹时
      // activePage 不变，不会走到这里。
      _lastIndex = index;
      _glitch.forward(from: 0);
    } else {
      _lastIndex = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 显隐/硬切页名必须逐帧跟随 controller（与转鼓同一监听源）；
    // 故障切片的高频重建由各自的 AnimatedBuilder 承担。
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final visible = widget.controller.rollerVisible;
        final index = widget.controller.activePage.clamp(
          0,
          widget.labels.length - 1,
        );
        return _buildPlate(context, visible, index);
      },
    );
  }

  Widget _buildPlate(BuildContext context, bool visible, int index) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: MechanicalStyle.indicatorFadeDuration,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.4),
          duration: MechanicalStyle.indicatorRiseDuration,
          curve: const Cubic(0.3, 1.4, 0.4, 1),
          child: CustomPaint(
            // 面板底色 + 仿转鼓边框/角标一体绘制（见 _PlateFramePainter）。
            // 亮角标骑边框外扩 1px，CustomPaint 不裁剪，正常可见。
            painter: const _PlateFramePainter(),
            child: Stack(
              children: [
                // 非定位子：决定 Stack（即色块）的尺寸。
                Padding(
                  padding: const EdgeInsets.only(
                    left: MechanicalStyle.namePlatePadH,
                    top: MechanicalStyle.namePlatePadTop,
                    right: MechanicalStyle.namePlatePadH,
                    bottom: MechanicalStyle.namePlatePadBottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GlitchWord(word: widget.labels[index], glitch: _glitch),
                      const SizedBox(
                        height: MechanicalStyle.namePlateUnderlineGap,
                      ),
                      _GlitchUnderline(glitch: _glitch),
                    ],
                  ),
                ),
                // 故障白线压在最上层横切文字（不接手势）。
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _glitch,
                      builder: (context, _) => CustomPaint(
                        painter: _GlitchLinePainter(t: _glitch.value),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 故障文字：三个水平切片叠放同一文字，各片独立闪烁/错位，
/// 叠灰色重影副本；外层再套整字数码抖动。
class _GlitchWord extends StatelessWidget {
  const _GlitchWord({required this.word, required this.glitch});

  final String word;
  final Animation<double> glitch;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      // 稿 --serif 栈（Songti SC/STSong/Noto Serif CJK SC/SimSun…）：
      // 不打包字体，走系统 serif 通用族——Android 西文 NotoSerif、
      // 中文回退 NotoSerifCJK（无 Bold 面时由引擎合成加粗）。
      fontFamily: 'serif',
      fontSize: MechanicalStyle.namePlateFontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: MechanicalStyle.namePlateLetterSpacing,
      height: 1,
      color: AppColors.mechInk,
      // 稿 text-shadow:0 2px 12px rgba(0,0,0,.6)
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.6),
          offset: const Offset(0, 2),
          blurRadius: 12,
        ),
      ],
    );

    return AnimatedBuilder(
      animation: glitch,
      builder: (context, _) {
        final t = glitch.value;
        final shake = _glitchShake.transform(t);
        final chroma = _chromaEnvelope.transform(t);

        return Transform.translate(
          offset: shake,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < 3; i++)
                ClipRect(
                  clipper: _SliceClipper(i),
                  child: Transform.translate(
                    offset: _sliceShift[i].transform(t),
                    child: Stack(
                      children: [
                        // 灰色重影副本（极简单色风）：横向错位、
                        // 仅故障包络内可见。
                        Opacity(
                          opacity:
                              chroma * _sliceAlpha[i].transform(t),
                          child: Transform.translate(
                            offset: const Offset(
                              MechanicalStyle.nameGlitchChromaShift,
                              0,
                            ),
                            child: Text(
                              word,
                              style: baseStyle.copyWith(
                                color: AppColors.mechInkDim,
                                shadows: null,
                              ),
                            ),
                          ),
                        ),
                        Opacity(
                          opacity:
                              chroma * _sliceAlpha[i].transform(t),
                          child: Transform.translate(
                            offset: const Offset(
                              -MechanicalStyle.nameGlitchChromaShift,
                              0,
                            ),
                            child: Text(
                              word,
                              style: baseStyle.copyWith(
                                color: AppColors.mechInkDim,
                                shadows: null,
                              ),
                            ),
                          ),
                        ),
                        // 主字（定尺寸的非定位子）。
                        Opacity(
                          opacity: _sliceAlpha[i].transform(t),
                          child: Text(word, style: baseStyle),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 下方短横线：每次翻页后稍后重新展开（轻度过冲）；稳态为完整 56px。
class _GlitchUnderline extends StatelessWidget {
  const _GlitchUnderline({required this.glitch});

  final Animation<double> glitch;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glitch,
      builder: (context, _) {
        return Container(
          width:
              MechanicalStyle.namePlateUnderlineWidth *
              _underlineExpand.transform(glitch.value),
          height: MechanicalStyle.namePlateUnderlineHeight,
          color: AppColors.mechInk,
        );
      },
    );
  }
}

/// 水平切片裁剪区域：上/中/下三片，相邻片留重叠避免亚像素缝隙。
class _SliceClipper extends CustomClipper<Rect> {
  const _SliceClipper(this.index);

  /// 0=上片 1=中片 2=下片。
  final int index;

  static const List<(double, double)> _bands = [
    (0.0, 0.38),
    (0.32, 0.70),
    (0.64, 1.0),
  ];

  @override
  Rect getClip(Size size) {
    final (top, bottom) = _bands[index];
    // 下片底边外扩 12px：serif 合成粗体的下行笔画与文字柔和投影
    // （offset(0,2)+blur12）会画出行盒，不能卡在 1.0 处硬裁。
    final bottomEdge =
        size.height * bottom + (index == 2 ? 12.0 : 0.0);
    return Rect.fromLTRB(
      0,
      size.height * top,
      size.width,
      bottomEdge,
    );
  }

  @override
  bool shouldReclip(_SliceClipper oldDelegate) => oldDelegate.index != index;
}

/// 页名牌面板边框：模仿转鼓面板（1px mechDrumLine 细框 +
/// 16px/2px mechInk 亮角标），但面板向右开口——左边、上边通画，
/// 底边只画左半，右边不画（视作被右侧内容挡住的延续面板）；
/// 亮角标因此落在左上与左下两个实角上。
class _PlateFramePainter extends CustomPainter {
  const _PlateFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 稿 rgba(15,15,15,.90)：基色用 mechDrumPanel 具名 token。
    final fill = Paint()
      ..color = AppColors.mechDrumPanel.withValues(alpha: 0.90);
    canvas.drawRect(Offset.zero & size, fill);

    final line = Paint()
      ..color = AppColors.mechDrumLine
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    // 1px 线骑像素中心。
    const hx = 0.5;
    // 左边（通高）。
    canvas.drawLine(
      const Offset(hx, 0),
      Offset(hx, size.height),
      line,
    );
    // 上边（通宽）。
    canvas.drawLine(
      const Offset(0, hx),
      Offset(size.width, hx),
      line,
    );
    // 底边（左半）。
    canvas.drawLine(
      Offset(hx, size.height - hx),
      Offset(size.width / 2, size.height - hx),
      line,
    );

    // 亮角标：参数与转鼓 _CornerPainter 完全相同。
    final corner = Paint()
      ..color = AppColors.mechInk
      ..strokeWidth = MechanicalStyle.drumCornerStrokeWidth
      ..strokeCap = StrokeCap.square;
    const s = MechanicalStyle.drumCornerSize;
    final w = MechanicalStyle.drumCornerStrokeWidth / 2;

    // 左上：横 + 竖（骑边框角，与转鼓同一定位）。
    canvas.drawLine(Offset(-w, w), Offset(s, w), corner);
    canvas.drawLine(Offset(w, -w), Offset(w, s), corner);
    // 左下。
    canvas.drawLine(
      Offset(-w, size.height - w),
      Offset(s, size.height - w),
      corner,
    );
    canvas.drawLine(
      Offset(w, size.height - s),
      Offset(w, size.height + w),
      corner,
    );
  }

  @override
  bool shouldRepaint(_PlateFramePainter oldDelegate) => false;
}

/// 一条故障白线的出现窗口（时间均为相对动画 0..1）。
class _GlitchLine {
  const _GlitchLine(
    this.t0,
    this.t1,
    this.yFraction,
    this.xStartFraction,
    this.widthFraction,
    this.alpha,
  );

  final double t0;
  final double t1;
  final double yFraction;
  final double xStartFraction;
  final double widthFraction;
  final double alpha;
}

/// 故障白线绘制器：一张确定性时间表，线在窗口内向右扫动 40px；
/// 不引入随机数，保证每次播放观感一致、可测试。
class _GlitchLinePainter extends CustomPainter {
  const _GlitchLinePainter({required this.t});

  final double t;

  static const List<_GlitchLine> _lines = [
    _GlitchLine(0.07, 0.12, 0.22, 0.05, 0.50, 0.80),
    _GlitchLine(0.15, 0.19, 0.76, 0.48, 0.45, 0.90),
    _GlitchLine(0.25, 0.30, 0.50, 0.10, 0.80, 0.45),
    _GlitchLine(0.37, 0.42, 0.68, 0.30, 0.60, 0.70),
    _GlitchLine(0.50, 0.54, 0.32, 0.60, 0.34, 0.60),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final paint = Paint();
    for (final line in _lines) {
      if (t < line.t0 || t > line.t1) continue;
      final progress = (t - line.t0) / (line.t1 - line.t0);
      final x = size.width * line.xStartFraction + progress * 40;
      paint.color = AppColors.mechInk.withValues(alpha: line.alpha);
      canvas.drawRect(
        Rect.fromLTWH(
          x,
          size.height * line.yFraction,
          size.width * line.widthFraction,
          1.5,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GlitchLinePainter oldDelegate) => oldDelegate.t != t;
}

// ---------------------------------------------------------------------------
// 故障时序表（权重总和 100，按 TweenSequence 映射到动画 0..1）。
// 全部为递减幅度的硬关键帧——故障风要的是数码硬切，不是平滑过渡。
// 末态（t=1）必须是稳态：各片 alpha=1、位移归零、色差/白线消失、
// 下划线完整。
// ---------------------------------------------------------------------------

Offset _o(double x, double y) => Offset(x, y);

/// 整字数码抖动：0.0–0.55 一串递减脉冲，之后静止。
final TweenSequence<Offset> _glitchShake = TweenSequence<Offset>([
  TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 5),
  TweenSequenceItem(
    tween: ConstantTween(_o(MechanicalStyle.nameGlitchShakeMax, -2)),
    weight: 6,
  ),
  TweenSequenceItem(
    tween: ConstantTween(_o(-MechanicalStyle.nameGlitchShakeMax, 2)),
    weight: 6,
  ),
  TweenSequenceItem(tween: ConstantTween(_o(4, 1)), weight: 6),
  TweenSequenceItem(tween: ConstantTween(_o(-3, -2)), weight: 6),
  TweenSequenceItem(tween: ConstantTween(_o(3, 1)), weight: 6),
  TweenSequenceItem(tween: ConstantTween(_o(-2, -1)), weight: 6),
  TweenSequenceItem(tween: ConstantTween(_o(2, 1)), weight: 7),
  TweenSequenceItem(tween: ConstantTween(_o(-1, 0)), weight: 6),
  TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 46),
]);

/// 各切片透明度：中片先接通、下片最后，前段 0/低亮硬闪；末态全亮。
final List<TweenSequence<double>> _sliceAlpha = [
  // 上片
  TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 8),
    TweenSequenceItem(tween: ConstantTween(0.4), weight: 5),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 4),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 4),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 9),
    TweenSequenceItem(tween: ConstantTween(0.2), weight: 4),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 66),
  ]),
  // 中片（最先亮）
  TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 3),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 4),
    TweenSequenceItem(tween: ConstantTween(0.15), weight: 3),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 5),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 3),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 8),
    TweenSequenceItem(tween: ConstantTween(0.3), weight: 3),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 7),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 64),
  ]),
  // 下片（最后接通）
  TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 14),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 5),
    TweenSequenceItem(tween: ConstantTween(0.3), weight: 4),
    TweenSequenceItem(tween: ConstantTween(0.1), weight: 8),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 7),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 4),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 58),
  ]),
];

/// 切片横向错位：上/下片反向大位移错时归位，中片小幅；末态归零。
final List<TweenSequence<Offset>> _sliceShift = [
  // 上片
  TweenSequence<Offset>([
    TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 8),
    TweenSequenceItem(
      tween: ConstantTween(_o(MechanicalStyle.nameGlitchSliceShift, 0)),
      weight: 8,
    ),
    TweenSequenceItem(tween: ConstantTween(_o(-7, 1)), weight: 6),
    TweenSequenceItem(tween: ConstantTween(_o(5, 0)), weight: 6),
    TweenSequenceItem(tween: ConstantTween(_o(-3, 0)), weight: 6),
    TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 66),
  ]),
  // 中片
  TweenSequence<Offset>([
    TweenSequenceItem(tween: ConstantTween(_o(-4, 0)), weight: 5),
    TweenSequenceItem(tween: ConstantTween(_o(3, 0)), weight: 9),
    TweenSequenceItem(tween: ConstantTween(_o(-2, 0)), weight: 8),
    TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 78),
  ]),
  // 下片
  TweenSequence<Offset>([
    TweenSequenceItem(
      tween: ConstantTween(_o(-MechanicalStyle.nameGlitchSliceShift, -1)),
      weight: 12,
    ),
    TweenSequenceItem(tween: ConstantTween(_o(7, 0)), weight: 8),
    TweenSequenceItem(tween: ConstantTween(_o(-5, 1)), weight: 8),
    TweenSequenceItem(tween: ConstantTween(_o(3, 0)), weight: 6),
    TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 66),
  ]),
];

/// 色差副本包络：前段（含一次断闪）显现，0.42 前消失；末态为 0。
final TweenSequence<double> _chromaEnvelope = TweenSequence<double>([
  TweenSequenceItem(tween: ConstantTween(0.0), weight: 6),
  TweenSequenceItem(tween: ConstantTween(0.8), weight: 8),
  TweenSequenceItem(tween: ConstantTween(0.15), weight: 4),
  TweenSequenceItem(tween: ConstantTween(0.8), weight: 12),
  TweenSequenceItem(tween: Tween(begin: 0.8, end: 0.0), weight: 12),
  TweenSequenceItem(tween: ConstantTween(0.0), weight: 58),
]);

/// 下划线展开：0.18 起从 0 长出，冲过 100% 后回到 56px；末态完整。
final TweenSequence<double> _underlineExpand = TweenSequence<double>([
  TweenSequenceItem(tween: ConstantTween(0.0), weight: 18),
  TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.08), weight: 20),
  TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 8),
  TweenSequenceItem(tween: ConstantTween(1.0), weight: 54),
]);
