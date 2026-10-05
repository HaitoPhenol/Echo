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
    required this.focusNode,
    required this.textController,
    required this.visualKey,
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

  /// 常规态胶囊是否处于按下态。
  final bool pressed;

  final FocusNode focusNode;
  final TextEditingController textController;

  /// 胶囊可视本体的 key：父级据此取得真实几何，
  /// 计算放大后的触控热区。
  final Key visualKey;

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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildCapsule(searching),
                  // 倒计时边框仅在 open 态（未输入）显示。
                  if (controller.searchState == SearchState.open)
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
          ],
        );
      },
    );
  }

  /// 胶囊本体：常规态窄条 / 搜索态全宽框，尺寸由隐式动画过渡。
  ///
  /// 注意：这里不挂手势监听。常规态按下判定由父级用 [visualKey]
  /// 取真实矩形后，在放大的热区内统一处理。
  Widget _buildCapsule(bool searching) {
    return AnimatedContainer(
      key: visualKey,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: searching ? screenWidth - 28 : screenWidth / 2,
      height: searching ? 44 : 10,
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

  /// 常规态胶囊里的位置滑块。
  Widget _thumb() {
    // 滑块位置：页码 0 在最左、末页在最右（显示位置夹在合法区间），
    // 与页面轨道/滚筒同步呈现吸附节奏。
    final clampedP =
        controller.displayPosition.clamp(0, controller.pageCount - 1);
    final travel = screenWidth / 2 - screenWidth / 2 * 0.24;
    final left = clampedP / (controller.pageCount - 1) * travel;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: 0,
          bottom: 0,
          width: screenWidth / 2 * 0.24,
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
