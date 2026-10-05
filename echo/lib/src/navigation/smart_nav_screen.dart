import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/template_page.dart';
import 'nav_physics.dart';
import 'widgets/nav_roller.dart';
import 'widgets/quick_action_arc.dart';
import 'widgets/search_capsule.dart';

/// 智能导航实验主屏。
///
/// 屏幕内容：
/// - 底层：横向页面轨道（模板阶段为 10 个只显示数字的空白页）；
/// - 右下角：滑动胶囊导航线（手势总入口）；
/// - 浮层：滚筒指示器、快捷操作弧、触发涟漪。
///
/// 支持的全部手势（移植自 ideas/smart_line.html）：
/// - 横滑胶囊：翻页（慢拖精调、快甩穿越）；
/// - 竖直上甩：打开快捷操作弧，横移选择、松手触发；
/// - 双击胶囊：按点击的横向位置直达对应页；
/// - 长按 0.45s：展开搜索框与最近搜索，2s 倒计时结束自动收起。
class SmartNavScreen extends StatefulWidget {
  const SmartNavScreen({super.key});

  @override
  State<SmartNavScreen> createState() => _SmartNavScreenState();
}

class _SmartNavScreenState extends State<SmartNavScreen>
    with TickerProviderStateMixin {
  /// 模板阶段的页面总数。
  static const int _pageCount = 10;

  late final NavPhysicsController _nav;

  // 搜索输入相关
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchTextController = TextEditingController();

  /// 底部胶囊簇的 key：用于「搜索态点击外部关闭」的命中判断。
  final GlobalKey _capsuleClusterKey = GlobalKey();

  /// 快捷操作弧组件的 key：用于调用其收起方法。
  final GlobalKey<QuickActionArcState> _quickArcKey = GlobalKey();

  /// 胶囊常规态是否按下（视觉）。
  bool _capsulePressed = false;

  /// 当前进行中的手势（无则为 null）。
  _DragGesture? _gesture;

  /// 长按 450ms 展开搜索的计时器。
  Timer? _holdTimer;

  /// 上一次单击（短按）时刻，用于 300ms 内判定双击。
  double? _lastTapTime;

  /// 单调时钟（手势判定用）。
  final Stopwatch _clock = Stopwatch()..start();

  // 快捷操作弧状态
  bool _quickArcShown = false;
  int _quickSelection = 1;
  final List<Offset> _quickPositions = [];

  /// 当前正在播放的涟漪列表。
  final List<_RippleSpec> _ripples = [];

  double get _now =>
      _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;

  @override
  void initState() {
    super.initState();

    // 状态栏/导航栏图标保持浅色并走透明边缘到边缘布局。
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    _nav = NavPhysicsController(
      vsync: this,
      pageCount: _pageCount,
      onActivePageChanged: (_) => HapticFeedback.selectionClick(),
      // 用闭包延迟引用 _nav，避免初始化表达式中访问尚未赋值的字段。
      onSettled: () => _nav.scheduleRollerHide(),
    );

    _searchFocusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _nav.dispose();
    _searchFocusNode.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  // ================================================================
  //  搜索焦点处理
  // ================================================================

  void _handleFocusChange() {
    if (_searchFocusNode.hasFocus) {
      _nav.beginInput();
    } else {
      // 延时判断：从输入框切到历史胶囊等场景会先失焦再被重新聚焦。
      Timer(const Duration(milliseconds: 150), () {
        if (mounted &&
            !_searchFocusNode.hasFocus &&
            _nav.searchState == SearchState.input) {
          _nav.closeSearch();
        }
      });
    }
  }

  // ================================================================
  //  手势：按下
  // ================================================================

  /// 根 Listener 的按下处理：当前仅用于「搜索态点击胶囊簇外部 → 关闭」。
  void _handleRootPointerDown(PointerDownEvent event) {
    if (!_nav.isSearching) return;

    final renderObject = _capsuleClusterKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      final clusterRect =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (!clusterRect.contains(event.position)) {
        _searchFocusNode.unfocus();
        _nav.closeSearch();
      }
    }
  }

  /// 胶囊常规态按下：开始一次手势的生命周期（方向待定）。
  void _handleCapsulePointerDown(PointerDownEvent event) {
    final now = _now;
    final isDoubleTap =
        _lastTapTime != null && now - _lastTapTime! < 0.3;
    _lastTapTime = null;

    _nav.beginGrab();
    _gesture = _DragGesture(
      pointer: event.pointer,
      x0: event.position.dx,
      y0: event.position.dy,
      doubleTap: isDoubleTap,
    );

    setState(() => _capsulePressed = true);

    // 长按 450ms 且期间未移动 → 展开搜索。
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 450), () {
      final gesture = _gesture;
      if (gesture != null && !gesture.moved) {
        _gesture = null;
        setState(() => _capsulePressed = false);
        HapticFeedback.mediumImpact();
        _nav.openSearch();
      }
    });
  }

  // ================================================================
  //  手势：移动（含方向锁定）
  // ================================================================

  void _handleRootPointerMove(PointerMoveEvent event) {
    final gesture = _gesture;
    if (gesture == null || event.pointer != gesture.pointer) return;

    // 方向锁定前：根据位移主方向决定本次手势用途。
    if (!gesture.moved) {
      final dx = event.position.dx - gesture.x0;
      final dy = event.position.dy - gesture.y0;
      final absDx = dx.abs();
      final absDy = dy.abs();

      if (absDx > 8 && absDx > absDy * 1.1) {
        _lockPageDrag(gesture, event);
      } else if (dy < -16 && absDy > absDx * 2) {
        _lockQuickArc(gesture, event);
      } else if (math.sqrt(absDx * absDx + absDy * absDy) > 28) {
        // 超过死区后按主导方向归类；向下一律按翻页处理。
        if (absDx > absDy) {
          _lockPageDrag(gesture, event);
        } else if (dy < 0) {
          _lockQuickArc(gesture, event);
        } else {
          _lockPageDrag(gesture, event);
        }
      } else {
        return;
      }
    }

    if (gesture.isQuick) {
      _updateQuickSelection(event.position.dx);
      return;
    }

    _nav.dragUpdate(event.position.dx);
  }

  /// 锁定为横向翻页拖动。
  void _lockPageDrag(_DragGesture gesture, PointerMoveEvent event) {
    gesture.moved = true;
    gesture.isQuick = false;
    _holdTimer?.cancel();
    _nav.showRoller();
    _nav.dragStart(event.position.dx);
  }

  /// 锁定为竖直上甩：打开快捷操作弧。
  void _lockQuickArc(_DragGesture gesture, PointerMoveEvent event) {
    gesture.moved = true;
    gesture.isQuick = true;
    _holdTimer?.cancel();
    setState(() {
      _capsulePressed = false;
      _computeQuickPositions();
      _quickSelection = 1;
      _quickArcShown = true;
    });
  }

  /// 快捷弧上根据手指横坐标更新选中项。
  void _updateQuickSelection(double globalX) {
    final threshold0 = (_quickPositions[0].dx + _quickPositions[1].dx) / 2;
    final threshold1 = (_quickPositions[1].dx + _quickPositions[2].dx) / 2;
    final next = globalX < threshold0
        ? 0
        : globalX > threshold1
            ? 2
            : 1;

    if (next != _quickSelection) {
      HapticFeedback.selectionClick();
      setState(() => _quickSelection = next);
    }
  }

  // ================================================================
  //  手势：松手 / 取消
  // ================================================================

  void _handleRootPointerUp(PointerUpEvent event) {
    _releaseGesture(event.pointer, cancelled: false, globalX: event.position.dx);
  }

  void _handleRootPointerCancel(PointerCancelEvent event) {
    _releaseGesture(event.pointer, cancelled: true);
  }

  /// 手势结束的统一处理。
  void _releaseGesture(
    int pointer, {
    required bool cancelled,
    double? globalX,
  }) {
    final gesture = _gesture;
    if (gesture == null || pointer != gesture.pointer) return;

    _gesture = null;
    _holdTimer?.cancel();
    setState(() => _capsulePressed = false);

    // 快捷操作弧：触发或直接收起。
    if (gesture.isQuick) {
      _quickArcKey.currentState?.dismiss(fire: !cancelled);
      return;
    }

    // 未移动：单击（记录时间用于双击判定）或双击直达。
    if (!gesture.moved) {
      if (!cancelled && gesture.doubleTap && globalX != null) {
        _nav.snapTo(_pageAtX(globalX).round());
      } else if (!cancelled) {
        _lastTapTime = _now;
      }
      return;
    }

    // 已移动：速度足够大则惯性滑动，否则就近吸附。
    if (!cancelled && _nav.dragReleaseVelocity.abs() > 1.15) {
      _nav.startFling(_nav.dragReleaseVelocity);
    } else {
      _nav.snapTo(_nav.nearestPage(_nav.position));
    }
  }

  /// 快捷弧触发：在选中项处显示涟漪。
  ///
  /// 真实快捷操作后续在此接入（当前仅视觉反馈）。
  void _handleQuickFire(int index) {
    setState(() {
      _ripples.add(_RippleSpec(center: _quickPositions[index]));
    });
    // TODO: 接入三个快捷操作的真实行为。
  }

  // ================================================================
  //  几何计算
  // ================================================================

  /// 屏幕横坐标 → 页位置（双击直达用，滑块行程 = 半屏 - 滑块宽）。
  double _pageAtX(double globalX) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final capsuleWidth = screenWidth / 2;
    final thumbWidth = capsuleWidth * 0.24;
    final capsuleLeft = screenWidth - 14 - capsuleWidth;

    final center = (globalX - capsuleLeft)
        .clamp(thumbWidth / 2, capsuleWidth - thumbWidth / 2);
    return (center - thumbWidth / 2) /
        (capsuleWidth - thumbWidth) *
        (_pageCount - 1);
  }

  /// 计算快捷弧三个操作项的位置。
  ///
  /// 以胶囊中心水平位置为弧心横坐标，弧心纵坐标距屏幕底 21px，
  /// 半径 108，角度 205° / 258° / 311°（从左到右）。
  void _computeQuickPositions() {
    final size = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    final capsuleWidth = size.width / 2;
    final centerX = size.width - 14 - capsuleWidth / 2;
    final centerY = size.height - safeBottom - 21;

    const radius = 108.0;
    const anglesDeg = [205.0, 258.0, 311.0];

    _quickPositions
      ..clear()
      ..addAll(anglesDeg.map((angle) {
        final rad = angle * math.pi / 180;
        return Offset(
          centerX + radius * math.cos(rad),
          centerY + radius * math.sin(rad),
        );
      }));
  }

  // ================================================================
  //  构建
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleRootPointerDown,
        onPointerMove: _handleRootPointerMove,
        onPointerUp: _handleRootPointerUp,
        onPointerCancel: _handleRootPointerCancel,
        child: Stack(
          children: [
            // -------- 横向页面轨道 --------
            Positioned.fill(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _nav,
                  builder: (context, _) {
                    final renderedPosition =
                        _nav.rubberized(_nav.position);
                    return Stack(
                      children: [
                        Positioned(
                          left: -renderedPosition * screenSize.width,
                          top: 0,
                          bottom: 0,
                          width: screenSize.width * _pageCount,
                          child: Row(
                            children: List.generate(
                              _pageCount,
                              (i) => Expanded(child: TemplatePage(index: i)),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // -------- 快捷操作弧 --------
            if (_quickArcShown)
              QuickActionArc(
                key: _quickArcKey,
                positions: List.of(_quickPositions),
                selection: _quickSelection,
                onFire: _handleQuickFire,
                onDismissed: () {
                  setState(() => _quickArcShown = false);
                },
              ),

            // -------- 触发涟漪 --------
            for (final spec in _ripples)
              Positioned(
                left: spec.center.dx - 30,
                top: spec.center.dy - 30,
                child: _Ripple(
                  onEnded: () {
                    setState(() => _ripples.remove(spec));
                  },
                ),
              ),

            // -------- 滚筒指示器（含页名标签） --------
            Positioned(
              right: 14,
              bottom: 52 + safeBottom,
              child: NavRoller(
                controller: _nav,
                width: screenSize.width / 2,
              ),
            ),

            // -------- 底部胶囊簇（历史 + 胶囊 + 倒计时边框） --------
            Positioned(
              left: 14,
              right: 14,
              bottom: 16 +
                  safeBottom +
                  (_nav.searchState == SearchState.input
                      ? keyboardInset
                      : 0),
              child: SearchCapsule(
                key: _capsuleClusterKey,
                controller: _nav,
                screenWidth: screenSize.width,
                pressed: _capsulePressed,
                focusNode: _searchFocusNode,
                textController: _searchTextController,
                onGesturePointerDown: _handleCapsulePointerDown,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一次手势生命周期的记录。
class _DragGesture {
  _DragGesture({
    required this.pointer,
    required this.x0,
    required this.y0,
    required this.doubleTap,
  });

  /// 指针 id（多指情况下区分）。
  final int pointer;

  /// 按下位置
  final double x0;
  final double y0;

  /// 本次按下是否构成双击的第二击。
  final bool doubleTap;

  /// 是否已完成方向锁定。
  bool moved = false;

  /// 是否为竖直上甩（快捷弧）手势。
  bool isQuick = false;
}

/// 一个涟漪的位置描述。
class _RippleSpec {
  _RippleSpec({required this.center});

  /// 涟漪圆心。
  final Offset center;
}

/// 快捷操作触发处的扩散涟漪。
///
/// 60px 的亮白圆环从 0.45 倍扩散到 2.5 倍并淡出，时长 650ms。
class _Ripple extends StatefulWidget {
  const _Ripple({required this.onEnded});

  /// 动画结束后回调（父级将其移除）。
  final VoidCallback onEnded;

  @override
  State<_Ripple> createState() => _RippleState();
}

class _RippleState extends State<_Ripple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onEnded();
      }
    });

  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.2, 0.7, 0.3, 1),
  ).drive(Tween(begin: 0.45, end: 2.5));

  late final Animation<double> _opacity =
      Tween(begin: 1.0, end: 0.0).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66FFFFFF),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
