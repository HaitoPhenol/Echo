import 'package:flutter/material.dart';

import '../nav_physics.dart';

/// 搜索建议区（历史/结果）的入场与退场包装。
///
/// 对齐 HTML 参考：面板整体从下方 14px、scale .97 弹入（340ms 曲线
/// (.3,1.2,.4,1)）；不透明度 250ms、延迟 80ms；高度交给
/// [AnimatedSize] 生长。关闭时反向播放完毕后才卸载内容，随后高度收起。
class PanelEntrance extends StatefulWidget {
  const PanelEntrance({
    super.key,
    required this.visible,
    required this.contentBuilder,
  });

  final bool visible;

  /// 内容构建：注入面板时间轴，供内部条目（历史胶囊）取错峰区间。
  final Widget Function(Animation<double> entrance) contentBuilder;

  @override
  State<PanelEntrance> createState() => _PanelEntranceState();
}

class _PanelEntranceState extends State<PanelEntrance>
    with SingleTickerProviderStateMixin {
  /// 时间轴总长：覆盖最末位胶囊的错峰弹入（100 + 40×7 + 340 ≈ 720ms）。
  static const Duration _timeline = Duration(milliseconds: 720);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _timeline,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _c,
    curve: const Interval(80 / 720, 330 / 720),
  );
  late final Animation<double> _pop = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 340 / 720, curve: Cubic(0.3, 1.2, 0.4, 1)),
  );

  /// 内容是否需要挂载（退场动画播完前保持挂载）。
  bool _keep = false;

  @override
  void initState() {
    super.initState();
    _keep = widget.visible;
    _c.value = widget.visible ? 1 : 0;
    _c.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !widget.visible && mounted) {
        setState(() => _keep = false);
      }
    });
  }

  @override
  void didUpdateWidget(PanelEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        setState(() => _keep = true);
        _c.forward();
      } else {
        _c.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 340),
      curve: const Cubic(0.3, 1.2, 0.4, 1),
      alignment: Alignment.bottomCenter,
      child: _keep
          ? FadeTransition(
              opacity: _opacity,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final v = _pop.value;
                  return Transform.translate(
                    offset: Offset(0, 14 * (1 - v)),
                    child: Transform.scale(
                      scale: 0.97 + 0.03 * v,
                      child: child,
                    ),
                  );
                },
                child: widget.contentBuilder(_c),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// 胶囊区域的动画器（真实导航条与搜索 pill 完全解耦）。
///
/// - 常规态：只显示真实导航条 [navAssembly]（静止于右下锚点）。
/// - 唤起：同一帧隐藏真实导航条、挂载独立搜索 [pill]——pill 起始帧与
///   导航条外观完全一致，因此切换不可察觉；随后 pill 沿宽/高时间轴
///   缩放到全宽搜索框。
/// - 收回：pill 反向缩回（途中不含滑块/锚点），播完的同一帧隐藏
///   pill、重新显示真实导航条。
///
/// 用持久的 [State] + [AnimationController] 驱动尺寸，渲染对象跨帧
/// 稳定（条件插入导致重建会让动画被跳过——本项目曾踩过此坑）。
class CapsuleMorph extends StatefulWidget {
  const CapsuleMorph({
    super.key,
    required this.nav,
    required this.searching,
    required this.assemblyWidth,
    required this.searchWidth,
    required this.barHeight,
    required this.searchHeight,
    required this.navAssembly,
    required this.pill,
  });

  final NavPhysicsController nav;

  /// 当前是否搜索态（由父级在 build 时捕获；不能直接读 nav.isSearching
  /// 做新旧值比较——同一个可变对象读不到旧值）。
  final bool searching;

  final double assemblyWidth;
  final double searchWidth;
  final double barHeight;
  final double searchHeight;

  /// 真实导航条整体（圆点 + 窄条 + 滑块 + 锚点）。
  final Widget navAssembly;

  /// 独立搜索 pill 构建，参数依次为：context、frameWidth（pill 当前
  /// 外框宽）、chrome（装饰进度）、navChrome（滑块/锚点不透明度）、
  /// 输入内容/圆点/fuse 不透明度。
  final Widget Function(
    BuildContext context,
    double frameWidth,
    double chrome,
    double navChrome,
    double contentOpacity,
    double dotOpacity,
    double fuseOpacity,
  )
  pill;

  @override
  State<CapsuleMorph> createState() => _CapsuleMorphState();
}

class _CapsuleMorphState extends State<CapsuleMorph>
    with TickerProviderStateMixin {
  late final AnimationController _width = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final AnimationController _height = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  // 装饰（颜色/圆角/描边/圆点）：开合头 180ms 快速过渡。
  late final AnimationController _chrome = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  // fuse：延迟 320ms 后 300ms 淡入（框体落定才出现）。
  late final AnimationController _fuse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  static const Cubic _widthCurve = Cubic(0.3, 1.1, 0.3, 1);
  static const Cubic _heightCurve = Cubic(0.3, 1.2, 0.4, 1);

  /// 搜索 pill 是否挂载（开——立即挂载；关——播完才卸载）。
  bool _keepPill = false;

  /// 真实导航条是否显示（开——立即隐藏；关——pill 播完同一帧再显示）。
  bool _showNav = true;

  /// 当前开合方向（决定 pill 内滑块/锚点是否参与：关——不参与）。
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    final searching = widget.searching;
    _keepPill = searching;
    _showNav = !searching;
    _width.value = _height.value = _chrome.value = searching ? 1 : 0;
    _fuse.value = searching ? 1 : 0;
    _width.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !widget.searching && mounted) {
        setState(() {
          _keepPill = false;
          _showNav = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(CapsuleMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searching != oldWidget.searching) {
      if (widget.searching) {
        _opening = true;
        setState(() {
          _showNav = false;
          _keepPill = true;
        });
        _width.forward();
        _height.forward();
        _chrome.forward();
        _fuse.forward(from: 0);
      } else {
        _opening = false;
        _width.reverse();
        _height.reverse();
        _chrome.reverse();
        _fuse.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _width,
        _height,
        _chrome,
        _fuse,
        widget.nav,
      ]),
      builder: (context, _) {
        final wt = _widthCurve.transform(_width.value);
        final ht = _heightCurve.transform(_height.value);
        final areaHeight =
            widget.barHeight + (widget.searchHeight - widget.barHeight) * ht;
        final w =
            widget.assemblyWidth +
            (widget.searchWidth - widget.assemblyWidth) * wt;

        final chrome = _chrome.value.clamp(0.0, 1.0);
        // 滑块/锚点：唤起时随 chrome 淡出；收回时恒不显示（只由
        // 最后揭示的真实导航条呈现，避免收缩途中穿帮）。
        final navChrome = (_opening ? 1 - chrome : 0.0).clamp(0.0, 1.0);
        final dot = (1 - chrome).clamp(0.0, 1.0);
        // 输入内容：延迟 100ms 淡入、320ms 淡完（相对宽度时间轴）。
        final content = Interval(
          100 / 380,
          320 / 380,
          curve: Curves.easeOut,
        ).transform(_width.value).clamp(0.0, 1.0);
        final fuse = Interval(
          320 / 620,
          1,
        ).transform(_fuse.value).clamp(0.0, 1.0);

        return SizedBox(
          height: areaHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 真实导航条：仅非搜索态显示，完全不参与动画。
              if (_showNav)
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: widget.assemblyWidth,
                  height: widget.barHeight,
                  child: widget.navAssembly,
                ),
              // 独立搜索 pill：右下锚点缩放到目标状态。
              // RepaintBoundary：开合期间的重绘只发生在这一层，
              // 不向上污染页面轨道/滚筒的绘制。
              if (_keepPill)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: w,
                      height: areaHeight,
                      child: widget.pill(
                        context,
                        w,
                        chrome,
                        navChrome,
                        content,
                        dot,
                        fuse,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _chrome.dispose();
    _fuse.dispose();
    super.dispose();
  }
}
