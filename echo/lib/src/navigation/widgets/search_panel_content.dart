import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/search_service.dart';
import '../../theme/app_colors.dart';

/// 实时搜索结果列表。
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.results, required this.onTap});

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
              ResultTile(result: result, onTap: () => onTap(result)),
          ],
        ),
      ),
    );
  }
}

/// 单条搜索结果行。
class ResultTile extends StatefulWidget {
  const ResultTile({super.key, required this.result, required this.onTap});

  final SearchResult result;
  final VoidCallback onTap;

  @override
  State<ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<ResultTile> {
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
class HistoryChips extends StatelessWidget {
  const HistoryChips({
    super.key,
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
          HistoryChip(
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
class HistoryChip extends StatefulWidget {
  const HistoryChip({
    super.key,
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
  State<HistoryChip> createState() => _HistoryChipState();
}

class _HistoryChipState extends State<HistoryChip> {
  /// 点击后的闪白反馈态。
  bool _hit = false;

  // 面板时间轴总长 720ms（见 PanelEntrance）。
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
