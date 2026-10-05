import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../nav_physics.dart';
import 'fuse_border_painter.dart';

/// 胶囊导航线在底部的整体簇：最近搜索历史 + 胶囊本体 + 倒计时边框。
///
/// 常规态只显示胶囊；长按后展开为全宽搜索框，上方浮现最近搜索胶囊，
/// 外围显示倒计时边框。本组件只负责外观与内部小交互，
/// 手势识别（方向锁定、上甩等）由父级 [SmartNavScreen] 完成。
class SearchCapsule extends StatelessWidget {
  const SearchCapsule({
    super.key,
    required this.controller,
    required this.screenWidth,
    required this.pressed,
    required this.focusNode,
    required this.textController,
    required this.visualKey,
  });

  final NavPhysicsController controller;

  /// 屏幕宽度（搜索态宽度 = screenWidth - 28）。
  final double screenWidth;

  /// 常规态胶囊是否处于按下态。
  final bool pressed;

  final FocusNode focusNode;
  final TextEditingController textController;

  /// 胶囊可视本体的 key：父级据此取得真实几何，
  /// 计算放大后的触控热区（避开系统底部手势区）。
  final Key visualKey;

  /// 演示用最近搜索（模板数据，后续接入真实搜索历史）。
  static const List<String> demoRecentSearches = [
    '周报模板',
    '会议室预订',
    '报销流程',
    '张伟',
    '五月的旅行照片',
    '跨部门项目同步会议纪要归档',
    '密码生成器推荐',
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final searching = controller.isSearching;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HistoryChips(
              visible: searching,
              onChipTap: _selectHistory,
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
                      left: -4,
                      top: -4,
                      right: -4,
                      bottom: -4,
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

  /// 点击某条历史：直接带入输入框并进入输入态。
  void _selectHistory(String text) {
    textController.text = text;
    focusNode.requestFocus();
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
    // 滑块位置：页码 0 在最左、末页在最右（位置夹在合法区间）。
    final clampedP = controller.position.clamp(0, controller.pageCount - 1);
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

/// 搜索框上方的最近搜索胶囊流。
///
/// 随搜索态展开/收起（高度动画），每个胶囊点击后短暂闪白作为反馈。
class _HistoryChips extends StatelessWidget {
  const _HistoryChips({required this.visible, required this.onChipTap});

  final bool visible;
  final ValueChanged<String> onChipTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(left: 2, right: 2, bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final text in SearchCapsule.demoRecentSearches)
                    _HistoryChip(text: text, onTap: () => onChipTap(text)),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
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
