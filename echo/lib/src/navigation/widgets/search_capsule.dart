import 'package:flutter/material.dart';

import '../../control/slash_ui/slash_ui.dart';
import '../../services/nav_badge_service.dart';
import '../../services/search_service.dart';
import '../../theme/app_colors.dart';
import '../dock_geometry.dart';
import '../nav_destination_specs.dart';
import '../nav_physics.dart';
import 'fuse_border_painter.dart';
import 'search_panel_content.dart';
import 'search_pill_morph.dart';

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
    required this.pageIds,
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
    this.slashMode = false,
    this.slashController,
  });

  final NavPhysicsController controller;

  /// 各页目的地的稳定 id（与页面轨道顺序一致），锚点状态按 id 查询。
  final List<String> pageIds;

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

  /// ECP P3-G2：当前为 slash 指令态（输入首字符 `/`）。
  /// 指令态下图标/提示语换肤，且不挂搜索历史/结果建议区（让位给
  /// SlashCommandLayer 的补全条与结果卡）。
  final bool slashMode;

  /// 指令态键事件编排（Esc/↑↓/Tab/Enter）；仅 [slashMode] 时包到
  /// 输入区外层。
  final SlashConsoleController? slashController;

  // 几何事实（边距/高度/圆点/搜索尺寸/宽度规则）统一收在
  // DockGeometry：把手条、AI 条、竖单、抽屉与本组件共用同一来源，
  // 不再通过 GlobalKey 实时取矩形。
  //
  // 常规态整体 = 圆点(10) + 间距(5) + 导航条(W-30) + 间距(5) + 圆点(10)，
  // 整体宽度为半屏宽；搜索态为全宽（screenWidth - 28）、高 44。

  /// 圆点 + 导航条整体的宽度。
  double get _assemblyWidth => DockGeometry.navAssemblyWidthFor(screenWidth);

  /// 缩短后的导航条宽度。
  double get _barWidth => DockGeometry.navBarWidthFor(screenWidth);

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
            // 搜索建议区：仅搜索态挂载，开合均带弹入/淡出。
            // slash 指令态让位给 SlashCommandLayer（补全条/结果卡/
            // 模态卡由 smart_nav_screen 叠在胶囊上方）。
            if (!slashMode)
              PanelEntrance(
                visible: searching,
                contentBuilder: (entrance) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: hasQuery
                      ? ResultsView(results: results, onTap: onResultTap)
                      : HistoryChips(
                          items: historyItems,
                          entrance: entrance,
                          onTap: onHistoryTap,
                        ),
                ),
              ),
            // 胶囊区域：导航条始终静止（圆点/滑块/锚点不参与动画），
            // 搜索框作为独立覆盖层在其上方做缩放过渡，盖住导航条。
            CapsuleMorph(
              nav: controller,
              searching: searching,
              assemblyWidth: _assemblyWidth,
              searchWidth: screenWidth - 2 * DockGeometry.sideMargin,
              barHeight: DockGeometry.barHeight,
              searchHeight: DockGeometry.searchHeight,
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
        // 无障碍：左圆点 = 上一页（G6 最小集，只加语义不改外观/命中）。
        Semantics(
          button: true,
          label: '上一页',
          child: _NavDot(pressed: pressedDot == -1),
        ),
        const SizedBox(width: DockGeometry.dotGap),
        Expanded(child: _navBar(context)),
        const SizedBox(width: DockGeometry.dotGap),
        Semantics(
          button: true,
          label: '下一页',
          child: _NavDot(pressed: pressedDot == 1),
        ),
      ],
    );
  }

  /// 静止导航条本体：tone1 底色，内部铺滑块与锚点。
  Widget _navBar(BuildContext context) {
    final index = controller.activePage;
    final total = controller.pageCount;
    final prev = index > 0 ? index - 1 : index;
    final next = index < total - 1 ? index + 1 : index;
    // onIncrease/onDecrease 要求 value 与相应增减值配套（Flutter 语义断言）。
    String pageValue(int i) => '第 ${i + 1} 页，共 $total 页：${_pageLabelAt(i)}';
    return Semantics(
      container: true,
      label: '导航条',
      value: pageValue(index),
      increasedValue: pageValue(next),
      decreasedValue: pageValue(prev),
      // 翻页动作用控制器既有路径，等价于点右/左圆点翻一页。
      onIncrease: () => controller.stepPage(1),
      onDecrease: () => controller.stepPage(-1),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: AppColors.tone1,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        // 锚点画在滑块**之下**、始终全部挂载；滑块不透明，物理遮挡
        // 当前位置的锚点——无显隐逻辑，翻页途中也就没有边缘弹出。
        // 容器已开裁剪，锚点发光不会超出导航条。
        child: Stack(children: [_anchors(context), _thumb()]),
      ),
    );
  }

  /// 当前页名（无障碍播报用）：[pageIds] 与 [kNavDestinationSpecs]
  /// 以稳定 id 对齐；缺配或越界返回空串。
  String _pageLabelAt(int index) {
    if (index < 0 || index >= pageIds.length) return '';
    final id = pageIds[index];
    for (final spec in kNavDestinationSpecs) {
      if (spec.id == id) return spec.label;
    }
    return '';
  }

  /// 独立搜索 pill 的内容（与真实导航条组件解耦：真实组件在搜索期间
  /// 由 [CapsuleMorph] 隐藏，这里重建一个 pill）。
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
    final targetWidth =
        MediaQuery.sizeOf(context).width - 2 * DockGeometry.sideMargin;
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
                    height: DockGeometry.barHeight,
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
                  height: DockGeometry.searchHeight,
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
            height: DockGeometry.searchHeight + 4,
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
              key: ValueKey<String>('nav-anchor-${pageIds[i]}'),
              level: badges?.levelOf(pageIds[i]) ?? NavBadgeLevel.normal,
            ),
          ),
      ],
    );
  }

  /// 搜索态内容：放大镜（slash 指令态换终端符）+ 文本输入框。
  Widget _searchContent() {
    final isInput = controller.searchState == SearchState.input;
    final field = Padding(
      padding: const EdgeInsets.only(left: 10, right: 10),
      child: Row(
        children: [
          Icon(
            slashMode ? Icons.terminal : Icons.search,
            size: 18,
            color: slashMode || isInput
                ? AppColors.accentBlue
                : AppColors.textMuted,
          ),
          const SizedBox(width: 3),
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              onChanged: onQueryChanged,
              onSubmitted: onSubmitted,
              style: TextStyle(
                color: slashMode ? AppColors.accentBlue : AppColors.textPrimary,
                fontSize: 16,
              ),
              cursorColor: AppColors.accentBlue,
              // 指令态用回车（多行命令语义），搜索态保持键盘搜索键。
              textInputAction: slashMode
                  ? TextInputAction.done
                  : TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: slashMode
                    ? '输入命令 · 尾随 ? 看 man · ↑↓ 历史'
                    : '搜索页面、联系人、文件…',
                hintStyle: const TextStyle(color: Color(0xFF5A646E)),
              ),
            ),
          ),
          // 输入态右侧操作区：左退格、右发送（右缘为主操作）。
          // 文字为空时两者禁用，避免误触。
          if (isInput)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: textController,
              builder: (context, value, _) {
                final hasText = value.text.isNotEmpty;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CapsuleAction(
                      icon: Icons.backspace_outlined,
                      tooltip: '退格到上一个空格',
                      onTap: hasText ? _deleteToPreviousSpace : null,
                    ),
                    _CapsuleAction(
                      icon: Icons.send,
                      tooltip: slashMode ? '执行命令' : '搜索',
                      onTap: hasText ? _submitQuery : null,
                      color: AppColors.accentBlue,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
    // slash 键事件（Esc/↑↓/Tab/Enter 补全）只在指令态包一层；
    // 搜索态行为零变化。
    if (slashMode && slashController != null) {
      return SlashKeyEvents(controller: slashController!, child: field);
    }
    return field;
  }

  /// 退格：删掉末尾一个词，保留它前面的分隔空格。
  ///
  /// `sys.ping --help` → `sys.ping `；无空格时整段清空；纯空格也清空。
  /// 程序化改文本不会触发 onChanged，需手动回调刷新补全/搜索建议。
  void _deleteToPreviousSpace() {
    final text = textController.text;
    if (text.isEmpty) return;
    var end = text.length;
    while (end > 0 && text[end - 1] == ' ') {
      end--;
    }
    final space = end == 0 ? -1 : text.lastIndexOf(' ', end - 1);
    final cut = space < 0 ? 0 : space + 1;
    final next = text.substring(0, cut);
    textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    onQueryChanged(next);
  }

  /// 发送：与键盘提交/搜索键同一路径，空文本不提交。
  void _submitQuery() {
    final text = textController.text;
    if (text.trim().isEmpty) return;
    onSubmitted(text);
  }
}

/// 胶囊内的紧凑图标按钮（28×28 命中区，随外部深色底走）。
class _CapsuleAction extends StatelessWidget {
  const _CapsuleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = AppColors.textMuted,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      color: enabled ? color : color.withValues(alpha: 0.35),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      splashRadius: 14,
      // IconButton 默认带 48×48 的最小点击区（MaterialTapTargetSize.padded），
      // 只改 constraints 按钮实际仍占 48 宽。shrinkWrap 后命中区就是 28×28。
      style: IconButton.styleFrom(
        minimumSize: const Size(28, 48),
        maximumSize: const Size(28, 48),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
      width: DockGeometry.dotDiameter,
      height: DockGeometry.dotDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pressed ? AppColors.tone2 : AppColors.tone1,
      ),
    );
  }
}
