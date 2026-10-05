import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/haptics.dart';
import '../services/search_service.dart';
import 'nav_destination.dart';
import 'nav_physics.dart';
import 'quick_action.dart';
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
  /// 双击判定窗口（秒）：300ms，与 AOSP ViewConfiguration 一致。
  static const double _doubleTapWindow = 0.30;

  /// 导航目的地配置（页面轨道、滚筒、页面搜索的唯一来源）。
  late final List<NavDestination> _destinations;

  /// 快捷操作配置。
  late final List<QuickAction> _quickActions;

  /// 搜索历史存储与搜索服务。
  late final SearchHistoryStore _searchHistory;
  late final SearchService _searchService;

  late final NavPhysicsController _nav;

  // 搜索输入相关
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchTextController = TextEditingController();

  /// 底部胶囊簇的 key：用于「搜索态点击外部关闭」的命中判断。
  final GlobalKey _capsuleClusterKey = GlobalKey();

  /// 胶囊可视本体的 key：取真实矩形以计算常规态的扩大触控热区。
  final GlobalKey _capsuleVisualKey = GlobalKey();

  /// 快捷操作弧组件的 key：用于调用其收起方法。
  final GlobalKey<QuickActionArcState> _quickArcKey = GlobalKey();

  /// 胶囊常规态是否按下（视觉）。
  bool _capsulePressed = false;

  /// 搜索框当前文本与结果（由 SearchService 实时计算）。
  String _searchQuery = '';
  List<SearchResult> _searchResults = const [];

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

    // ---- 组装配置与服务（依赖关系：providers → searchService）----
    _destinations = buildDefaultDestinations();
    _quickActions = buildDefaultQuickActions();
    _searchHistory = InMemorySearchHistoryStore();
    _searchService = SearchService(
      history: _searchHistory,
      providers: [
        NavDestinationSearchProvider(
          destinations: _destinations,
          onDestinationSelected: _jumpToDestination,
        ),
      ],
    );

    _nav = NavPhysicsController(
      vsync: this,
      pageCount: _destinations.length,
      onActivePageChanged: (_) => Haptics.tick(),
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
          _resetSearchPanel();
        }
      });
    }
  }

  // ================================================================
  //  搜索面板：数据与交互
  // ================================================================

  /// 搜索结果数据源选中了某目的地：跳转到对应页面。
  void _jumpToDestination(int index) {
    _nav.snapTo(index);
  }

  /// 输入文本变化：实时查询并刷新结果。
  void _handleQueryChanged(String value) {
    setState(() {
      _searchQuery = value;
      _searchResults = _searchService.searchAll(value);
    });
  }

  /// 键盘提交搜索：记录到历史（结果已实时展示，无需额外动作）。
  void _handleSubmitted(String value) {
    if (value.trim().isNotEmpty) {
      _searchHistory.add(value);
    }
  }

  /// 点击历史条目：带入输入框、定位光标到末尾并立即执行搜索。
  void _handleHistoryTap(String text) {
    _searchTextController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _searchFocusNode.requestFocus();
    _handleQueryChanged(text);
  }

  /// 点击搜索结果：执行结果动作（跳页等）、记入历史并收起面板。
  void _handleResultTap(SearchResult result) {
    result.onSelect();
    _searchHistory.add(result.title);
    _exitSearch();
  }

  /// 收起搜索面板（失焦 + 关闭 + 清空临时状态）。
  void _exitSearch() {
    _searchFocusNode.unfocus();
    _nav.closeSearch();
    _resetSearchPanel();
  }

  /// 清空输入框与结果，为下次打开做准备。
  void _resetSearchPanel() {
    _searchTextController.clear();
    _searchQuery = '';
    _searchResults = const [];
  }

  // ================================================================
  //  手势：按下
  // ================================================================

  /// 根 Listener 的按下处理（统管搜索态关闭与常规态抓取）。
  void _handleRootPointerDown(PointerDownEvent event) {
    if (_nav.isSearching) {
      // 搜索态：点击胶囊簇外部 → 关闭搜索。
      final clusterRect = _rectOf(_capsuleClusterKey);
      if (clusterRect != null && !clusterRect.contains(event.position)) {
        _exitSearch();
        return;
      }
      // open 态点击可视胶囊本体 → 聚焦进入输入态。
      if (_nav.searchState == SearchState.open) {
        final capsuleRect = _rectOf(_capsuleVisualKey);
        if (capsuleRect != null && capsuleRect.contains(event.position)) {
          _searchFocusNode.requestFocus();
        }
      }
      return;
    }

    // 常规态：胶囊视觉上只有 10px 高、难以按中，这里在不改变
    // 外观和位置的前提下，把触控热区向上扩大为约 50px 高的隐形条，
    // 手指落在胶囊上方空白处也能抓取。
    //
    // 注意：下沿不向下扩——底部边缘是安卓全面屏手势区，
    // 从过低处开始上甩会被系统识别为「回桌面」。
    final capsuleRect = _rectOf(_capsuleVisualKey);
    if (capsuleRect == null) return;

    final hitRect = Rect.fromLTRB(
      capsuleRect.left - 24,
      capsuleRect.top - 32,
      capsuleRect.right + 8,
      capsuleRect.bottom,
    );
    if (hitRect.contains(event.position)) {
      _beginCapsuleGrab(event);
    }
  }

  /// 读取某 key 对应组件的全局矩形。
  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 胶囊常规态按下：开始一次手势的生命周期（方向待定）。
  void _beginCapsuleGrab(PointerDownEvent event) {
    final now = _now;
    final isDoubleTap =
        _lastTapTime != null && now - _lastTapTime! < _doubleTapWindow;
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
        Haptics.confirm();
        _resetSearchPanel();
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
      Haptics.tick();
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
    Haptics.confirm();
    // 执行配置中该快捷操作的真实行为（当前为「开发中」占位反馈）。
    _quickActions[index].onSelect(context);
    setState(() {
      _ripples.add(_RippleSpec(center: _quickPositions[index]));
    });
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
        (_destinations.length - 1);
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
    // 胶囊位置保持原样（底边距 16）。
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
                    // 显示位置含橡胶带与磁力吸附曲线。
                    final renderedPosition = _nav.displayPosition;
                    return Stack(
                      children: [
                        Positioned(
                          left: -renderedPosition * screenSize.width,
                          top: 0,
                          bottom: 0,
                          width:
                              screenSize.width * _destinations.length,
                          child: Row(
                            // 页面由导航配置驱动：每个目的地的 pageBuilder
                            // 经 Builder 注入上下文，全部 Expanded 等宽。
                            children: [
                              for (final destination in _destinations)
                                Expanded(
                                  child: Builder(
                                    builder: destination.pageBuilder,
                                  ),
                                ),
                            ],
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
                actions: _quickActions,
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
                destinations: _destinations,
                width: screenSize.width / 2,
              ),
            ),

            // -------- 底部胶囊簇（历史 + 胶囊 + 倒计时边框） --------
            //
            // 键盘弹出时安卓端 adjustResize 会自动压缩窗口高度，
            // 胶囊随之自然停在键盘上方，这里不再手动加键盘高度，
            // 否则会双重补偿导致搜索框飞到过高位置。
            Positioned(
              left: 14,
              right: 14,
              bottom: 16 + safeBottom,
              child: SearchCapsule(
                key: _capsuleClusterKey,
                controller: _nav,
                screenWidth: screenSize.width,
                pressed: _capsulePressed,
                focusNode: _searchFocusNode,
                textController: _searchTextController,
                visualKey: _capsuleVisualKey,
                historyItems: _searchHistory.items,
                results: _searchResults,
                query: _searchQuery,
                onHistoryTap: _handleHistoryTap,
                onResultTap: _handleResultTap,
                onQueryChanged: _handleQueryChanged,
                onSubmitted: _handleSubmitted,
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
