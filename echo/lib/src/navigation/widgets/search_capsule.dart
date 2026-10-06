import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/nav_badge_service.dart';
import '../../services/search_service.dart';
import '../../theme/app_colors.dart';
import '../nav_physics.dart';
import 'fuse_border_painter.dart';

/// 胶囊导航线在底部的整体簇：搜索建议区 + 胶囊本体 + 倒计时边框。
///
/// 常规态只显示胶囊；长按后展开为全宽搜索框。搜索框上方区域：
/// - 输入框为空：显示最近搜索历史；
/// - 有关键词：显示实时搜索结果（无结果时显示空状态提示）。
///
/// 本组件只负责外观与内部小交互，数据与回调全部由父级注入，
/// 手势识别（方向锁定、上甩等）也由父级 [SmartNavScreen] 完成。
class SearchCapsule extends StatelessWidget {
  const SearchCapsule({
    super.key,
    required this.controller,
    required this.screenWidth,
    required this.pressed,
    required this.pressedDot,
    required this.focusNode,
    required this.textController,
    required this.historyItems,
    required this.results,
    required this.query,
    required this.onHistoryTap,
    required this.onResultTap,
    required this.onQueryChanged,
    required this.onSubmitted,
  });

  final NavPhysicsController controller;

  /// 屏幕宽度（搜索态宽度 = screenWidth - 28）。
  final double screenWidth;

  /// 常规态导航条是否处于按下态。
  final bool pressed;

  /// 当前处于按下色态的端点圆点：-1 左 / 1 右 / null 无。
  final int? pressedDot;

  final FocusNode focusNode;
  final TextEditingController textController;

  /// 最近搜索历史条目。
  final List<String> historyItems;

  /// 当前关键词的搜索结果。
  final List<SearchResult> results;

  /// 输入框当前文本。
  final String query;

  /// 点击历史条目。
  final ValueChanged<String> onHistoryTap;

  /// 点击搜索结果。
  final ValueChanged<SearchResult> onResultTap;

  /// 输入文本变化。
  final ValueChanged<String> onQueryChanged;

  /// 提交搜索（键盘搜索键）。
  final ValueChanged<String> onSubmitted;

  // 几何常量（逻辑像素）：父级计算隐形热区时共用同一来源，
  // 不再通过 GlobalKey 实时取矩形。
  //
  // 常规态整体 = 圆点(10) + 间距(5) + 导航条(W-30) + 间距(5) + 圆点(10)，
  // 整体宽度为半屏宽；搜索态为全宽（screenWidth - 28）、高 44。
  static const double sideMargin = 14;
  static const double bottomMargin = 16;
  static const double barHeight = 10;
  static const double dotDiameter = 10;
  static const double dotGap = dotDiameter / 2;
  static const double searchHeight = 44;

  /// 常规态圆点 + 导航条整体的宽度（半屏宽）。
  static double assemblyWidthFor(double screenWidth) => screenWidth / 2;

  /// 缩短后的导航条宽度。
  static double barWidthFor(double screenWidth) =>
      screenWidth / 2 - 2 * dotDiameter - 2 * dotGap;

  /// 圆点 + 导航条整体的宽度。
  double get _assemblyWidth => screenWidth / 2;

  /// 缩短后的导航条宽度。
  double get _barWidth => barWidthFor(screenWidth);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final searching = controller.isSearching;
        final hasQuery = query.trim().isNotEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 搜索建议区：仅搜索态挂载，开合均带弹入/淡出
            _PanelEntrance(
              visible: searching,
              contentBuilder: (entrance) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: hasQuery
                    ? _ResultsView(results: results, onTap: onResultTap)
                    : _HistoryChips(
                        items: historyItems,
                        entrance: entrance,
                        onTap: onHistoryTap,
                      ),
              ),
            ),
            // 胶囊本体形变：宽 380ms / 高 320ms，各自带弹性曲线，
            // 右下锚点固定，向左上方生长。
            Align(
              alignment: Alignment.centerRight,
              child: _CapsuleMorph(
                nav: controller,
                searching: searching,
                assemblyWidth: _assemblyWidth,
                searchWidth: screenWidth - 28,
                barHeight: barHeight,
                searchHeight: searchHeight,
                interior: (c, d, f) => _capsuleInterior(context, c, d, f),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 形变胶囊的内部内容（由 [_CapsuleMorph] 每帧调用，注入各部分
  /// 的不透明度，使内容/圆点/fuse 的淡入淡出与形变同一条时间轴）。
  Widget _capsuleInterior(
    BuildContext context,
    double contentOpacity,
    double dotOpacity,
    double fuseOpacity,
  ) {
    final searching = controller.isSearching;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 圆点仅常规态存在；开合瞬间快速淡入淡出（180ms）。
            if (dotOpacity > 0)
              Opacity(
                opacity: dotOpacity,
                child: _NavDot(pressed: pressedDot == -1),
              ),
            if (dotOpacity > 0) const SizedBox(width: dotGap),
            Expanded(child: _buildCapsule(context, searching)),
            if (dotOpacity > 0) const SizedBox(width: dotGap),
            if (dotOpacity > 0)
              Opacity(
                opacity: dotOpacity,
                child: _NavDot(pressed: pressedDot == 1),
              ),
          ],
        ),
        // 倒计时边框仅 open 态（未输入）显示；框体落定后才淡入。
        if (searching &&
            controller.searchState == SearchState.open &&
            fuseOpacity > 0)
          Positioned(
            left: -2,
            top: -2,
            right: -2,
            bottom: -2,
            child: Opacity(
              opacity: fuseOpacity,
              child: CustomPaint(
                painter: FuseBorderPainter(progress: controller.fuseProgress),
              ),
            ),
          ),
        // 搜索内容延迟淡入：框体生长初期不可见，避免文字在窄框中挤压。
        if (contentOpacity > 0)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: contentOpacity < 0.05,
              child: Opacity(opacity: contentOpacity, child: _searchContent()),
            ),
          ),
      ],
    );
  }

  /// 胶囊本体：常规态窄条 / 搜索态全宽框。
  ///
  /// 这里不挂手势监听，也不挂 key：常规态按下判定由父级按
  /// 静态几何常量推算出的隐形热区统一处理。
  /// 宽高由外层 [_CapsuleMorph] 统一驱动（Expanded 横向拉满、
  /// stretch 纵向拉满），这里只做颜色/边框/阴影等装饰过渡，避免
  /// 内外两层尺寸动画相互打架。
  Widget _buildCapsule(BuildContext context, bool searching) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: searching ? AppColors.searchBackground : AppColors.tone1,
        borderRadius: BorderRadius.circular(searching ? 22 : 999),
        border: searching ? Border.all(color: AppColors.tone1) : null,
        boxShadow: searching
            ? const [
                BoxShadow(
                  color: Color(0x8C000000),
                  blurRadius: 38,
                  offset: Offset(0, 14),
                ),
              ]
            : null,
      ),
      // 搜索内容由 _capsuleInterior 的 Positioned.fill 覆盖层统一构建
      // （便于延迟淡入）；这里搜索态不挂子节点，避免重复。
      child: searching
          ? null
          // 锚点铺在滑块之上；外层 AnimatedContainer 已开裁剪，
          // 锚点发光不会超出导航条。
          : Stack(children: [_thumb(), _anchors(context)]),
    );
  }

  /// 常规态导航条里的位置滑块（行程以缩短后的导航条为准）。
  Widget _thumb() {
    // 滑块位置：页码 0 在最左、末页在最右（显示位置夹在合法区间），
    // 与页面轨道/滚筒同步呈现吸附节奏。
    final clampedP = controller.displayPosition.clamp(
      0,
      controller.pageCount - 1,
    );
    // 滑块宽度 = 导航条长度 / 页面数：除了当前位置，也能大致反映
    // 页面总数（今后支持用户自定义页面时会随之自动变化）。
    final thumbWidth = _barWidth / controller.pageCount;
    final travel = _barWidth - thumbWidth;
    final left = clampedP / (controller.pageCount - 1) * travel;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: 0,
          bottom: 0,
          width: thumbWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: pressed
                  ? AppColors.inverse.withValues(alpha: 0.94)
                  : AppColors.tone2,
              borderRadius: BorderRadius.circular(999),
              border: pressed
                  ? Border.all(color: AppColors.tone2, width: 1.25)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// 导航条内各页的定位锚点：竖短条，位于滑块之上。
  ///
  /// 锚点按页段中心排列（与滑块「导航条/页面数」的分段一致）；
  /// 通过 [NavBadgeScope] 读取状态，通知/异常变化时自动重建。
  Widget _anchors(BuildContext context) {
    final badges = NavBadgeScope.maybeOf(context);
    final segment = _barWidth / controller.pageCount;

    return Stack(
      children: [
        for (var i = 0; i < controller.pageCount; i++)
          Positioned(
            // 宽 2、上下各留 2 → 长度 6，稍短于导航条高度 10。
            left: (i + 0.5) * segment - 1,
            top: 2,
            bottom: 2,
            width: 2,
            child: _NavAnchor(
              key: ValueKey<String>('nav-anchor-$i'),
              level: badges?.levelOf(i) ?? NavBadgeLevel.normal,
            ),
          ),
      ],
    );
  }

  /// 搜索态内容：放大镜图标 + 文本输入框。
  Widget _searchContent() {
    final isInput = controller.searchState == SearchState.input;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 18,
            color: isInput ? AppColors.accentBlue : AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              onChanged: onQueryChanged,
              onSubmitted: onSubmitted,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
              cursorColor: AppColors.accentBlue,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '搜索页面、联系人、文件…',
                hintStyle: TextStyle(color: Color(0xFF5A646E)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 搜索建议区（历史/结果）的入场与退场包装。
///
/// 对齐 HTML 参考：面板整体从下方 14px、scale .97 弹入（340ms 曲线
/// (.3,1.2,.4,1)）；不透明度 250ms、延迟 80ms；高度交给
/// [AnimatedSize] 生长。关闭时反向播放完毕后才卸载内容，随后高度收起。
class _PanelEntrance extends StatefulWidget {
  const _PanelEntrance({required this.visible, required this.contentBuilder});

  final bool visible;

  /// 内容构建：注入面板时间轴，供内部条目（历史胶囊）取错峰区间。
  final Widget Function(Animation<double> entrance) contentBuilder;

  @override
  State<_PanelEntrance> createState() => _PanelEntranceState();
}

class _PanelEntranceState extends State<_PanelEntrance>
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
  void didUpdateWidget(_PanelEntrance oldWidget) {
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

/// 胶囊本体的形变器：宽、高沿各自的时长与弹性曲线过渡，
/// 同时在同一条时间轴上驱动搜索内容、圆点、fuse 的淡入淡出。
///
/// 用持久的 [State] + [AnimationController] 驱动 [SizedBox]，渲染对象
/// 跨帧保持稳定（条件插入导致重建会让动画被跳过——本项目曾踩过此坑）。
class _CapsuleMorph extends StatefulWidget {
  const _CapsuleMorph({
    required this.nav,
    required this.searching,
    required this.assemblyWidth,
    required this.searchWidth,
    required this.barHeight,
    required this.searchHeight,
    required this.interior,
  });

  final NavPhysicsController nav;

  /// 当前是否搜索态（由父级在 build 时捕获；不能直接读 nav.isSearching
  /// 做新旧值比较——同一个可变对象读不到旧值）。
  final bool searching;

  final double assemblyWidth;
  final double searchWidth;
  final double barHeight;
  final double searchHeight;

  /// 内部内容构建，参数依次为：搜索内容/圆点/fuse 的不透明度。
  final Widget Function(
    double contentOpacity,
    double dotOpacity,
    double fuseOpacity,
  )
  interior;

  @override
  State<_CapsuleMorph> createState() => _CapsuleMorphState();
}

class _CapsuleMorphState extends State<_CapsuleMorph>
    with TickerProviderStateMixin {
  late final AnimationController _width = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final AnimationController _height = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  // 圆点：开合头 180ms 快速淡入淡出。
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

  @override
  void initState() {
    super.initState();
    final searching = widget.searching;
    _width.value = _height.value = _chrome.value = searching ? 1 : 0;
    _fuse.value = searching ? 1 : 0;
  }

  @override
  void didUpdateWidget(_CapsuleMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searching != oldWidget.searching) {
      if (widget.searching) {
        _width.forward();
        _height.forward();
        _chrome.forward();
        _fuse.forward(from: 0);
      } else {
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
        final w =
            widget.assemblyWidth +
            (widget.searchWidth - widget.assemblyWidth) * wt;
        final h =
            widget.barHeight + (widget.searchHeight - widget.barHeight) * ht;
        // 搜索内容：延迟 100ms 淡入、320ms 淡完（相对宽度 380ms 时间轴）。
        final content = Curves.easeOut.transform(
          const Interval(100 / 380, 320 / 380).transform(_width.value),
        );
        final dot = 1 - Curves.easeIn.transform(_chrome.value);
        final fuse = const Interval(320 / 620, 1).transform(_fuse.value);
        return SizedBox(
          width: w,
          height: h,
          child: widget.interior(content, dot, fuse),
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

/// 实时搜索结果列表。
class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.results, required this.onTap});

  final List<SearchResult> results;
  final ValueChanged<SearchResult> onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          '无匹配结果',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }

    // 限制最大高度，避免结果过多时顶满整个屏幕。
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            for (final result in results)
              _ResultTile(result: result, onTap: () => onTap(result)),
          ],
        ),
      ),
    );
  }
}

/// 单条搜索结果行。
class _ResultTile extends StatefulWidget {
  const _ResultTile({required this.result, required this.onTap});

  final SearchResult result;
  final VoidCallback onTap;

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.tone1,
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(
              result.icon ?? Icons.search,
              size: 18,
              color: AppColors.pageLabel,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (result.subtitle != null)
              Text(
                result.subtitle!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 搜索框为空时显示的最近搜索胶囊流。
class _HistoryChips extends StatelessWidget {
  const _HistoryChips({
    required this.items,
    required this.entrance,
    required this.onTap,
  });

  final List<String> items;

  /// 面板入场时间轴（0→1），各胶囊在其上取错峰区间。
  final Animation<double> entrance;

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          '暂无最近搜索',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < items.length; i++)
          _HistoryChip(
            text: items[i],
            index: i,
            entrance: entrance,
            onTap: () => onTap(items[i]),
          ),
      ],
    );
  }
}

/// 单个最近搜索胶囊。
class _HistoryChip extends StatefulWidget {
  const _HistoryChip({
    required this.text,
    required this.index,
    required this.entrance,
    required this.onTap,
  });

  final String text;

  /// 在历史流中的序号（决定错峰延迟：100ms + 40ms/个）。
  final int index;

  /// 面板入场时间轴。
  final Animation<double> entrance;

  final VoidCallback onTap;

  @override
  State<_HistoryChip> createState() => _HistoryChipState();
}

class _HistoryChipState extends State<_HistoryChip> {
  /// 点击后的闪白反馈态。
  bool _hit = false;

  // 面板时间轴总长 720ms（见 _PanelEntrance）。
  static const double _timelineMs = 720;
  static const double _startMs = 100;
  static const double _staggerMs = 40;
  static const double _opacityMs = 260;
  static const double _transformMs = 340;

  late final double _s = (_startMs + _staggerMs * widget.index) / _timelineMs;

  late final Animation<double> _opacity = CurvedAnimation(
    parent: widget.entrance,
    curve: Interval(_s, (_s + _opacityMs / _timelineMs).clamp(0, 1)),
  );
  late final Animation<double> _pop = CurvedAnimation(
    parent: widget.entrance,
    curve: Interval(
      _s,
      (_s + _transformMs / _timelineMs).clamp(0, 1),
      curve: const Cubic(0.3, 1.4, 0.4, 1),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _hit = true);
        Timer(const Duration(milliseconds: 180), () {
          if (mounted) setState(() => _hit = false);
        });
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: widget.entrance,
        builder: (context, child) {
          final v = _pop.value.clamp(0.0, 1.0);
          // 从下方 8px、scale .85 弹入（曲线带过冲）。
          return Transform.translate(
            offset: Offset(0, 8 * (1 - v)),
            child: Transform.scale(scale: 0.85 + 0.15 * v, child: child),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(maxWidth: 220),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          // 历史项不设底色：仅保留胶囊描边；按下时描边、文字提亮。
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(color: _hit ? AppColors.tone2 : AppColors.tone1),
            ),
          ),
          // 不能用容器自身 alignment（会使容器撑满可用宽度、失去自适应）；
          // widthFactor:1 让 Center 仅包裹文字宽度，同时在固定高度内居中。
          child: Center(
            widthFactor: 1,
            child: Opacity(
              opacity: _opacity.value,
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: _hit ? AppColors.tone4 : AppColors.tone2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 导航条上的单个页面定位锚点。
///
/// 形态类似滚筒的中央刻度（竖直短条）；发光样式对齐快捷弧选中项
/// 的光晕，由外层导航条裁剪。三种状态：
/// - [NavBadgeLevel.normal]：静止白色、微光；
/// - [NavBadgeLevel.notification]：绿色缓慢呼吸；
/// - [NavBadgeLevel.exception]：红色急促闪烁。
class _NavAnchor extends StatefulWidget {
  const _NavAnchor({super.key, required this.level});

  final NavBadgeLevel level;

  @override
  State<_NavAnchor> createState() => _NavAnchorState();
}

class _NavAnchorState extends State<_NavAnchor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    _configure(widget.level);
  }

  @override
  void didUpdateWidget(_NavAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.level != oldWidget.level) _configure(widget.level);
  }

  /// 按状态启停循环动画（呼吸慢、闪烁快）。
  void _configure(NavBadgeLevel level) {
    switch (level) {
      case NavBadgeLevel.normal:
        _controller.stop();
        _controller.value = 1;
      case NavBadgeLevel.notification:
        _controller.duration = const Duration(milliseconds: 1700);
        _controller.repeat(reverse: true);
      case NavBadgeLevel.exception:
        _controller.duration = const Duration(milliseconds: 620);
        _controller.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 关键：必须随动画每帧重建，否则 DecoratedBox 只在首次构建时
    // 取一次 _curve.value，呼吸/闪烁会“冻结”，直到别的事件顺带重建。
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        switch (widget.level) {
          case NavBadgeLevel.normal:
            // 本体即色板 tone3（白 α0.72）。
            return _tick(base: Colors.white, fill: 0.72, glow: 0.30);
          case NavBadgeLevel.notification:
            final t = _curve.value;
            return _tick(
              base: AppColors.anchorGreen,
              fill: 0.35 + 0.65 * t,
              glow: 0.75 * t,
            );
          case NavBadgeLevel.exception:
            final t = _curve.value;
            return _tick(
              base: AppColors.anchorRed,
              fill: 0.18 + 0.82 * t,
              glow: 0.90 * t,
            );
        }
      },
    );
  }

  /// 一根圆角竖短条 + 同色发光（光晕被导航条裁剪，不超出条外）。
  Widget _tick({
    required Color base,
    required double fill,
    required double glow,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: base.withValues(alpha: fill),
        borderRadius: BorderRadius.circular(1),
        boxShadow: [
          BoxShadow(color: base.withValues(alpha: glow), blurRadius: 8),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }
}

/// 导航条两端的翻页圆点。
///
/// 视觉为直径 10 的实心圆：默认色 = 导航条颜色（白 α0.16），
/// 按下色 = 拇指滑块颜色（白 α0.42）。
/// 自身不响应手势，热区与触发由父级 [SmartNavScreen] 统一处理。
class _NavDot extends StatelessWidget {
  const _NavDot({required this.pressed});

  /// 是否处于按下色态。
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: SearchCapsule.dotDiameter,
      height: SearchCapsule.dotDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pressed ? AppColors.tone2 : AppColors.tone1,
      ),
    );
  }
}
