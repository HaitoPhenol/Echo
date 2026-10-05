import 'dart:async';

import 'package:flutter/material.dart';

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
            // 搜索建议区（仅搜索态展开）
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: searching
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: hasQuery
                          ? _ResultsView(
                              results: results,
                              onTap: onResultTap,
                            )
                          : _HistoryChips(
                              items: historyItems,
                              onTap: onHistoryTap,
                            ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Align(
              alignment: Alignment.centerRight,
              // 常规态与搜索态共用同一棵子树（胶囊始终是 Row 里的
              // Expanded），几何全部由静态常量推算，不使用 GlobalKey。
              // 尺寸变化交给外层 AnimatedSize 做平滑生长。
              child: AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                // 右、下边缘固定：展开时向左上方生长。
                alignment: Alignment.bottomRight,
                child: SizedBox(
                  width: searching ? screenWidth - 28 : _assemblyWidth,
                  height: searching ? searchHeight : barHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Row(
                        children: [
                          // 圆点仅常规态存在（搜索态随空位一并移除）。
                          if (!searching)
                            _NavDot(pressed: pressedDot == -1),
                          if (!searching)
                            const SizedBox(width: dotGap),
                          Expanded(child: _buildCapsule(searching)),
                          if (!searching)
                            const SizedBox(width: dotGap),
                          if (!searching)
                            _NavDot(pressed: pressedDot == 1),
                        ],
                      ),
                      // 倒计时边框仅 open 态（未输入）显示，
                      // 贴住生长中的胶囊外沿。
                      if (searching &&
                          controller.searchState == SearchState.open)
                        Positioned(
                          left: -2,
                          top: -2,
                          right: -2,
                          bottom: -2,
                          child: CustomPaint(
                            painter: FuseBorderPainter(
                              progress: controller.fuseProgress,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 胶囊本体：常规态窄条 / 搜索态全宽框。
  ///
  /// 这里不挂手势监听，也不挂 key：常规态按下判定由父级按
  /// 静态几何常量推算出的隐形热区统一处理。
  Widget _buildCapsule(bool searching) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: searching ? screenWidth - 28 : _barWidth,
      height: searching ? searchHeight : barHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: searching
            ? AppColors.searchBackground
            : Colors.white.withValues(alpha: pressed ? 0.22 : 0.16),
        borderRadius: BorderRadius.circular(searching ? 22 : 999),
        border: searching
            ? Border.all(color: Colors.white.withValues(alpha: 0.10))
            : null,
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
      child: searching ? _searchContent() : _thumb(),
    );
  }

  /// 常规态导航条里的位置滑块（行程以缩短后的导航条为准）。
  Widget _thumb() {
    // 滑块位置：页码 0 在最左、末页在最右（显示位置夹在合法区间），
    // 与页面轨道/滚筒同步呈现吸附节奏。
    final clampedP =
        controller.displayPosition.clamp(0, controller.pageCount - 1);
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
                  : Colors.white.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(999),
              border: pressed
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.40),
                      width: 1.25,
                    )
                  : null,
            ),
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
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.04),
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
  const _HistoryChips({required this.items, required this.onTap});

  final List<String> items;
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
        for (final text in items)
          _HistoryChip(text: text, onTap: () => onTap(text)),
      ],
    );
  }
}

/// 单个最近搜索胶囊。
class _HistoryChip extends StatefulWidget {
  const _HistoryChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  State<_HistoryChip> createState() => _HistoryChipState();
}

class _HistoryChipState extends State<_HistoryChip> {
  /// 点击后的闪白反馈态。
  bool _hit = false;

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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(maxWidth: 220),
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: _hit
              ? Colors.white
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _hit
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: _hit
                ? AppColors.inverse
                : Colors.white.withValues(alpha: 0.52),
          ),
        ),
      ),
    );
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
        color: Colors.white.withValues(alpha: pressed ? 0.42 : 0.16),
      ),
    );
  }
}
