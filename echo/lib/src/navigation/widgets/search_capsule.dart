import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/nav_badge_service.dart';
import '../../services/search_service.dart';
import '../../theme/app_colors.dart';
import '../nav_physics.dart';
import 'fuse_border_painter.dart';

/// 滑块常态填充色：**不透明灰** 0xFF838383（131/255≈.514），视觉
/// 与旧的「tone1 条底（白 α.16）上叠 tone2 滑块（白 α.42）」合成
/// 结果一致——合成白量 = 0.16 + (1−0.16)×0.42 ≈ 0.513。
/// 注意不能写成 0x83FFFFFF（半透明白）：外观相同但挡不住下层锚点。
/// 锚点常态同色（tone2 叠 tone1 视觉同为 .51），被滑块盖住时完全
/// 不可见，离开滑块时也无色差。
const Color _thumbFill = Color(0xFF838383);

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
            // 胶囊区域：导航条始终静止（圆点/滑块/锚点不参与动画），
            // 搜索框作为独立覆盖层在其上方做缩放过渡，盖住导航条。
            _CapsuleMorph(
              nav: controller,
              searching: searching,
              assemblyWidth: _assemblyWidth,
              searchWidth: screenWidth - 28,
              barHeight: barHeight,
              searchHeight: searchHeight,
              navAssembly: _navAssembly(context),
              pill: _searchPill,
            ),
          ],
        );
      },
    );
  }

  /// 静止导航条整体：圆点 + 窄条（含滑块与锚点）。
  ///
  /// 永远是常规态外观，搜索开合期间也不变——搜索框覆盖层会盖住它。
  Widget _navAssembly(BuildContext context) {
    return Row(
      children: [
        _NavDot(pressed: pressedDot == -1),
        const SizedBox(width: dotGap),
        Expanded(child: _navBar(context)),
        const SizedBox(width: dotGap),
        _NavDot(pressed: pressedDot == 1),
      ],
    );
  }

  /// 静止导航条本体：tone1 底色，内部铺滑块与锚点。
  Widget _navBar(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.tone1,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      // 锚点画在滑块**之下**、始终全部挂载；滑块不透明，物理遮挡
      // 当前位置的锚点——无显隐逻辑，翻页途中也就没有边缘弹出。
      // 容器已开裁剪，锚点发光不会超出导航条。
      child: Stack(children: [_anchors(context), _thumb()]),
    );
  }

  /// 独立搜索 pill 的内容（与真实导航条组件解耦：真实组件在搜索期间
  /// 由 [_CapsuleMorph] 隐藏，这里重建一个 pill）。
  ///
  /// 起始帧与常规导航条完全一致（圆点 + tone1 圆角条 + 滑块/锚点），
  /// 随后形状变色/长高、圆点与滑块淡出、宽度向左生长；关闭时反向
  /// 收回——滑块/锚点在收回途中不出现，只在最后由真实导航条揭示。
  ///
  /// **性能结构（逐帧动画期间不做文本重布局）**：
  /// - 颜色+边框画在 ClipRRect **之外**（边框线跨盒缘，画在裁剪区内
  ///   会被裁掉一半）；
  /// - 滑块/锚点、输入内容都放在**固定尺寸**的 Positioned 层里，只动
  ///   不透明度；内容超出 pill 当前尺寸的部分由 [ClipRRect] 裁掉。
  ///   TextField/RenderParagraph 每帧约束不变，布局直接命中缓存；
  /// - 圆角每帧**显式夹到 min(宽/2, 高/2)**：渲染器对超大名义半径
  ///   做横纵独立夹取（rx 夹宽/2、ry 夹高/2），会出现椭圆直边、像
  ///   矩形遮罩；显式夹取后两端始终是半圆；
  /// - 投影与 fuse 画在裁剪区外（阴影不会被裁）。
  ///
  /// 参数：
  /// - [frameWidth]：pill 当前外框宽（morph 每帧算出，直接传入）；
  /// - [chrome]：装饰进度（0=常规态外观，1=搜索态外观），180ms；
  /// - [navChrome]：滑块/锚点不透明度（开——随 chrome 淡出；关——恒 0）；
  /// - [contentOpacity]：输入内容不透明度；
  /// - [dotOpacity]：圆点不透明度；
  /// - [fuseOpacity]：倒计时边框不透明度。
  Widget _searchPill(
    BuildContext context,
    double frameWidth,
    double chrome,
    double navChrome,
    double contentOpacity,
    double dotOpacity,
    double fuseOpacity,
  ) {
    // 条本体相对 pill 外框的内缩：常规态给两端圆点留位（15px），
    // 搜索态填满外框（与全宽搜索框一致）。
    final inset = 15.0 * (1 - chrome);
    final barColor = Color.lerp(
      AppColors.tone1,
      const Color(0xFF0F141A),
      chrome,
    )!;
    // 名义圆角 999→22；显式夹到条本体半宽/半高，保证两端始终半圆
    // （不能依赖渲染器对超大半径的处理）。
    final r = (999 + (22 - 999) * chrome).clamp(0.0, frameWidth / 2 - inset);
    final radius = BorderRadius.circular(r);
    // 搜索框落定后的固定目标宽（与 morph 的 searchWidth 一致）。
    final targetWidth = MediaQuery.sizeOf(context).width - 28;
    final borderColor = AppColors.tone1.withValues(
      alpha: AppColors.tone1.a * chrome,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 投影层：画在裁剪区之外，模糊阴影不会被 ClipRRect 切掉。
        if (chrome > 0.02)
          Positioned(
            left: inset,
            right: inset,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x8C000000)
                        .withValues(alpha: (0x8C / 255) * chrome),
                    blurRadius: 38,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
            ),
          ),
        // 形状层（颜色 + 边框）：画在 ClipRRect 之外，边框完整可见。
        Positioned(
          left: inset,
          right: inset,
          top: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: radius,
              border: chrome > 0.02 ? Border.all(color: borderColor) : null,
            ),
          ),
        ),
        // 内容层：统一按当前半圆角裁剪。
        Positioned.fill(
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                // 圆点：开合头快速淡变；置于形状之上。
                if (dotOpacity > 0)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: Opacity(
                      opacity: dotOpacity,
                      child: const _NavDot(pressed: false),
                    ),
                  ),
                if (dotOpacity > 0)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Opacity(
                      opacity: dotOpacity,
                      child: const _NavDot(pressed: false),
                    ),
                  ),
                // 滑块/锚点：几何固定不动（相对右下锚点），只做淡出，
                // 因此每帧约束不变、无重布局。
                if (navChrome > 0.01)
                  Positioned(
                    right: 15,
                    bottom: 0,
                    width: _barWidth,
                    height: barHeight,
                    child: Opacity(
                      opacity: navChrome,
                      child: Stack(children: [_anchors(context), _thumb()]),
                    ),
                  ),
                // 输入内容：固定为落定后的目标尺寸，只做延迟淡入；
                // 生长途中超出 pill 左边界的部分被外层 ClipRRect 裁掉。
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: targetWidth,
                  height: searchHeight,
                  child: IgnorePointer(
                    ignoring: contentOpacity < 0.05,
                    child: Opacity(
                      opacity: contentOpacity,
                      child: _searchContent(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 倒计时边框：仅 open 态（未输入）且框体落定后才淡入。
        if (controller.searchState == SearchState.open && fuseOpacity > 0)
          Positioned(
            right: -2,
            bottom: -2,
            width: targetWidth + 4,
            height: searchHeight + 4,
            child: Opacity(
              opacity: fuseOpacity,
              child: CustomPaint(
                painter: FuseBorderPainter(progress: controller.fuseProgress),
              ),
            ),
          ),
      ],
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
            // 按下时**无外观变化**（用户拍板：变黑/描边都显得奇怪）；
            // 保持不透明常态灰，才能持续挡住下方锚点。
            decoration: BoxDecoration(
              color: _thumbFill,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ],
    );
  }

  /// 导航条内各页的定位锚点：竖短条，位于滑块之下、始终全部挂载。
  ///
  /// 锚点按页段中心排列（与滑块「导航条/页面数」的分段一致）；
  /// 通过 [NavBadgeScope] 读取状态，通知/异常变化时自动重建。
  ///
  /// 不做任何显隐：滑块不透明、正覆盖当前页段时锚点被物理遮挡；
  /// 拖动滑块时锚点自然地从滑块边缘「滑入滑出」，无阈值切换、
  /// 不会在边缘弹出露馅。
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
class _CapsuleMorph extends StatefulWidget {
  const _CapsuleMorph({
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
  void didUpdateWidget(_CapsuleMorph oldWidget) {
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
            // 本体色与滑块完全一致（tone2，白 α0.42）、不发光：
            // 滑块滑过锚点时同色叠加，锚点像“融入”滑块而不是浮在其上。
            return _tick(base: Colors.white, fill: 0.42, glow: 0);
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
/// 按下色 = 滑块常态颜色 tone2（白 α0.42）。
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
