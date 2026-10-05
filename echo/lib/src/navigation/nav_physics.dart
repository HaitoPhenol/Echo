import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 搜索面板所处的状态（对应原型中的 searchMode：off / open / input）。
enum SearchState {
  /// 胶囊常规态
  off,

  /// 已展开为搜索框、尚未开始输入（倒计时边框烧蚀中）
  open,

  /// 输入框已获得焦点（倒计时取消，胶囊随键盘上抬）
  input,
}

/// 页面位置的运动阶段。
enum _MoveMode {
  /// 静止
  idle,

  /// 手指拖动中
  drag,

  /// 松手后的惯性滑动
  fling,

  /// 弹簧吸附到某一页
  snap,
}

/// 智能导航线的物理与状态控制器。
///
/// 职责：
/// - 维护当前页位置 [position]（拖动期间允许短暂越界）与速度 [velocity]；
/// - 横滑时的「速度自适应增益」——慢拖精调、快甩穿越，增益取值
///   按当前页面数量（4 页）整体压低，保证跟手；
/// - 松手后的指数摩擦惯性滑动（fling）与弹簧吸附（snap）；
/// - 两端越界时的橡胶带压缩（[rubberized]）+ 页内非线性磁力曲线
///   （[displayPosition]）：靠近整页粘滞、两页之间滑落，形成吸附感；
/// - 长按搜索态：0.65s 宽限 + 2s 倒计时边框，烧完自动收起；
/// - 滚筒与页名标签的显示、延时隐藏。
///
/// 注意：[position] 始终是线性物理位置，所有吸附/橡胶带效果只在
/// [displayPosition] 这一层做，物理模拟保持简单稳定。
///
/// UI 层通过 [AnimatedBuilder] 监听本控制器（它是一个 [ChangeNotifier]）。
class NavPhysicsController extends ChangeNotifier {
  NavPhysicsController({
    required TickerProvider vsync,
    this.pageCount = 10,
    this.onActivePageChanged,
    this.onSettled,
  }) {
    _clock.start();
    // Ticker 的帧回调指向实例方法，只能在构造函数体中创建。
    _ticker = vsync.createTicker(_handleTick);
  }

  /// 可导航页面总数（模板阶段为 10 页空白页）。
  final int pageCount;

  /// 激活页发生变化时回调（用于触感反馈等）。
  ValueChanged<int>? onActivePageChanged;

  /// 运动完全停止、落位完成时回调。
  VoidCallback? onSettled;

  // ==================== 常量（取值与原型一致） ====================

  /// 滚筒中相邻两个页标的间距（逻辑像素）。
  static const double rollerPitch = 54;

  // ==================== 内部时钟与帧回调 ====================

  /// 手势速度与倒计时共用的单调时钟。
  final Stopwatch _clock = Stopwatch();

  /// 物理循环帧驱动器。
  late final Ticker _ticker;

  /// 当前时间（秒）。
  double get _now =>
      _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;

  /// 上一物理帧时间，用于计算 dt。
  double _lastTickTime = 0;

  // ==================== 页面位置状态 ====================

  /// 当前页位置（0..pageCount-1），拖动期间允许越界。
  double position = 0;

  /// 当前速度（页/秒）。
  double velocity = 0;

  /// 弹簧吸附目标页。
  int _target = 0;

  /// 当前运动阶段。
  _MoveMode _mode = _MoveMode.idle;

  /// 当前激活页（四舍五入后的页号）。
  int activePage = 0;

  // ==================== 滚筒显隐 ====================

  /// 滚筒（及页名标签）是否可见。
  bool rollerVisible = false;

  Timer? _rollerHideTimer;

  // ==================== 搜索态 ====================

  /// 搜索面板状态。
  SearchState searchState = SearchState.off;

  /// 倒计时边框剩余进度（1 = 完整，0 = 烧完）。
  double fuseProgress = 1;

  /// 倒计时开始烧蚀的时钟时刻（比展开时刻晚 0.65s 宽限）。
  double? _fuseBurnStart;

  /// 是否处于搜索态（open 或 input）。
  bool get isSearching => searchState != SearchState.off;

  // ****************************************************************
  //  手势拖动
  // ****************************************************************

  // 拖动过程的速度平滑/累计字段
  late double _dragStartPosition;
  late double _dragAccumulation;
  late double _dragLastX;
  late double _dragLastT;
  late double _dragSmoothVelocity;
  late double _dragReportVelocity;
  late double _dragLastPosition;

  /// 手指按下胶囊（搜索态关闭）时调用：中断一切进行中的运动。
  void beginGrab() {
    _mode = _MoveMode.idle;
    velocity = 0;
    if (_ticker.isActive) _ticker.stop();
    notifyListeners();
  }

  /// 横滑方向锁定时调用，开始一次页面拖动。
  void dragStart(double globalX) {
    _mode = _MoveMode.drag;
    velocity = 0;
    _dragStartPosition = position;
    _dragAccumulation = 0;
    _dragLastX = globalX;
    _dragLastT = _now;
    _dragSmoothVelocity = 0;
    _dragReportVelocity = 0;
    _dragLastPosition = position;
  }

  /// 横滑移动中调用，[globalX] 为指针的屏幕横坐标。
  void dragUpdate(double globalX) {
    final t = _now;
    var dt = t - _dragLastT;
    _dragLastT = t;

    // 事件间隔过大（停顿/掉帧）时先衰减旧速度并把步长压回合理范围，
    // 避免下一帧算出爆炸速度。
    if (dt > 0.12) {
      _dragSmoothVelocity *= math.exp(-dt / 0.09);
      dt = 0.008;
    }
    dt = math.max(dt, 0.008);

    final dx = globalX - _dragLastX;
    _dragLastX = globalX;

    // 指针瞬时速度的一阶低通平滑（时间常数 90ms，与原型一致）。
    _dragSmoothVelocity +=
        (dx / dt - _dragSmoothVelocity) * (1 - math.exp(-dt / 0.09));

    // 速度自适应增益：慢拖低增益精调，快甩高增益穿越（取值已按
    // 4 页场景整体压低，避免轻轻一滑就飞过太多页）。
    final gain = _gainOf(_dragSmoothVelocity);

    // 向左滑（dx < 0）页码增大，故取负；54px 的拖动对应一个页标间距。
    _dragAccumulation -= dx * gain / rollerPitch;
    position = _dragStartPosition + _dragAccumulation;

    // 上报速度（页/秒），供松手时判断是否进入惯性滑动。
    _dragReportVelocity = 0.72 * _dragReportVelocity +
        0.28 * ((position - _dragLastPosition) / dt);
    _dragLastPosition = position;

    _updateActivePage();
    notifyListeners();
  }

  /// 松手时取出的最终速度（页/秒）。
  double get dragReleaseVelocity => _dragReportVelocity;

  /// 根据指针速度（px/s）计算位移增益。
  ///
  /// 页面精简为 4 个后整体压低：慢拖 0.25（约 216px 翻过一页，
  /// 便于精调），快甩最高 0.60（一次甩动通常越过 2~3 页）。
  double _gainOf(double pointerVelocity) {
    final t = math.min(pointerVelocity.abs() / 1200, 1);
    final smooth = t * t * (3 - 2 * t); // smoothstep
    return 0.25 + 0.35 * smooth;
  }

  // ****************************************************************
  //  渲染位置：橡胶带 + 非线性磁力曲线
  // ****************************************************************

  /// 供界面使用的最终显示位置。
  ///
  /// 处理顺序：先对越界做 [rubberized] 橡胶带压缩；在合法区间内
  /// 再套用页内磁力曲线 [_magneticFraction]——靠近整页时位移被压缩
  /// （粘滞、不容易离开当前页），两页中间位移被放大（自然滑落），
  /// 且 f(0)=0、f(0.5)=0.5、f(1)=1，整数位置严格不变。
  double get displayPosition {
    final r = rubberized(position);
    // 越界的橡胶带区域保持线性，不再叠加磁力曲线。
    if (r <= 0) return r;
    if (r >= pageCount - 1) return r;

    final n = r.floorToDouble();
    return n + _magneticFraction(r - n);
  }

  /// 页内磁力曲线：端点处斜率 [_magneticEndSlope]（<1，粘滞），
  /// 中点处斜率 >1（滑落加速）；曲线关于 (0.5, 0.5) 中心对称。
  ///
  /// 三次 Hermite 形式：
  /// f(x) = (-2x³+3x²) + m·(2x³-3x²+x)
  static double _magneticFraction(double x) {
    const m = _magneticEndSlope;
    return (-2 * x * x * x + 3 * x * x) +
        m * (2 * x * x * x - 3 * x * x + x);
  }

  /// 磁力曲线在整页处（x=0/1）的斜率。
  /// 越小越"粘"：取 0.75，即靠近整页时移动速度降到 75%。
  static const double _magneticEndSlope = 0.75;

  // ****************************************************************
  //  松手后的运动：惯性滑动 / 弹簧吸附
  // ****************************************************************

  /// 以给定初速度进入惯性滑动（速度单位：页/秒）。
  void startFling(double v) {
    _mode = _MoveMode.fling;
    velocity = v.clamp(-20, 20).toDouble();
    _ensureTicking();
    notifyListeners();
  }

  /// 进入弹簧吸附，落到 [target] 页。
  void snapTo(int target, {double initialVelocity = 0}) {
    _mode = _MoveMode.snap;
    _target = target.clamp(0, pageCount - 1);
    velocity = initialVelocity;
    _ensureTicking();
    notifyListeners();
  }

  /// 把任意位置四舍五入到最近的合法页号。
  int nearestPage(double value) =>
      value.clamp(0, pageCount - 1).round();

  /// 渲染用橡胶带：越界部分压缩 70%，最多溢出 0.35 页。
  double rubberized(double value) {
    if (value < 0) {
      return -math.min(-value * 0.3, 0.35);
    }
    if (value > pageCount - 1) {
      return (pageCount - 1) +
          math.min((value - (pageCount - 1)) * 0.3, 0.35);
    }
    return value;
  }

  /// 物理循环：每帧推进位置/速度，并驱动搜索倒计时。
  void _handleTick(Duration elapsed) {
    final now = _now;
    final dt = (now - _lastTickTime).clamp(0.001, 0.05);
    _lastTickTime = now;

    var motionChanged = false;

    if (_mode == _MoveMode.fling) {
      // 指数摩擦：每秒速度衰减到 e^-3.1 ≈ 4.5%。
      velocity *= math.exp(-3.1 * dt);
      position += velocity * dt;

      if (position <= 0) {
        // 撞到左边界：速度清零并吸附首页。
        position = 0;
        velocity = 0;
        _mode = _MoveMode.snap;
        _target = 0;
      } else if (position >= pageCount - 1) {
        // 撞到右边界：速度清零并吸附末页。
        position = pageCount - 1;
        velocity = 0;
        _mode = _MoveMode.snap;
        _target = pageCount - 1;
      } else if (velocity.abs() < 0.9) {
        // 速度过低，结束惯性，就近吸附。
        _mode = _MoveMode.snap;
        _target = nearestPage(position);
      }
      motionChanged = true;
    } else if (_mode == _MoveMode.snap) {
      // 临界阻尼附近的弹簧：刚度 240、阻尼 26。
      velocity += ((_target - position) * 240 - 26 * velocity) * dt;
      position += velocity * dt;

      if ((_target - position).abs() < 0.004 && velocity.abs() < 0.08) {
        position = _target.toDouble();
        velocity = 0;
        _mode = _MoveMode.idle;
        onSettled?.call();
      }
      motionChanged = true;
    }

    // 搜索倒计时边框：0.65s 宽限后开始烧，2s 烧完自动收起。
    if (searchState == SearchState.open && _fuseBurnStart != null) {
      final burned = now - _fuseBurnStart!;
      if (burned >= 0) {
        final percent = math.max(0.0, 100 - burned * 50);
        fuseProgress = percent / 100;
        motionChanged = true;
        if (percent <= 0) {
          closeSearch();
        }
      }
    }

    _updateActivePage();
    if (motionChanged) notifyListeners();

    // 无事可做时停掉帧回调以节省电量。
    if (_mode == _MoveMode.idle && searchState != SearchState.open) {
      _ticker.stop();
    }
  }

  /// 启动帧循环（已在运行则忽略），并重置帧间计时。
  void _ensureTicking() {
    if (!_ticker.isActive) {
      _lastTickTime = _now;
      _ticker.start();
    }
  }

  /// 根据当前位置更新激活页，变化时触发回调。
  void _updateActivePage() {
    final next = nearestPage(position);
    if (next != activePage) {
      activePage = next;
      onActivePageChanged?.call(next);
    }
  }

  // ****************************************************************
  //  滚筒显隐
  // ****************************************************************

  /// 显示滚筒与页名标签（拖动开始时调用）。
  void showRoller() {
    _rollerHideTimer?.cancel();
    if (!rollerVisible) {
      rollerVisible = true;
      notifyListeners();
    }
  }

  /// 落位后延时隐藏滚筒（原型延时 650ms）。
  void scheduleRollerHide() {
    _rollerHideTimer?.cancel();
    _rollerHideTimer = Timer(const Duration(milliseconds: 650), () {
      if (rollerVisible) {
        rollerVisible = false;
        notifyListeners();
      }
    });
  }

  // ****************************************************************
  //  搜索态切换
  // ****************************************************************

  /// 打开搜索态（长按 0.45s 触发）。
  void openSearch() {
    searchState = SearchState.open;
    _rollerHideTimer?.cancel();
    rollerVisible = false;
    fuseProgress = 1;
    // 边框先完整展示 0.65s，再开始 2s 烧蚀。
    _fuseBurnStart = _now + 0.65;
    _ensureTicking();
    notifyListeners();
  }

  /// 进入输入态（输入框获得焦点 / 选择历史项），倒计时取消。
  void beginInput() {
    if (searchState == SearchState.input) return;
    searchState = SearchState.input;
    _fuseBurnStart = null;
    notifyListeners();
  }

  /// 关闭搜索态，恢复常规胶囊。
  void closeSearch() {
    searchState = SearchState.off;
    _fuseBurnStart = null;
    fuseProgress = 1;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _rollerHideTimer?.cancel();
    super.dispose();
  }
}
