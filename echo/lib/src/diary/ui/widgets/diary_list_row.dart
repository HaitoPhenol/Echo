import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// 层级列表通用行：左侧大字标签、右侧辅助信息与箭头，
/// 下方 tone1 细线。dim 态用于整月枚举中尚无草稿的日期。
class DiaryListRow extends StatelessWidget {
  const DiaryListRow({
    super.key,
    required this.head,
    required this.onTap,
    this.sub,
    this.trailing,
    this.dim = false,
    this.highlight = false,
  });

  /// 行首大字（年 / 月 / 日）。
  final String head;

  /// 行首大字下方的辅助小字（星期 / 预览）。
  final String? sub;

  /// 最右侧自定义内容（通常留空，箭头由本行绘制）。
  final Widget? trailing;

  final VoidCallback onTap;

  /// 弱化显示（无草稿的日期）。
  final bool dim;

  /// 强调显示（今天）。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final headColor = dim
        ? AppColors.mechInkDim
        : highlight
            ? AppColors.textPrimary
            : AppColors.pageLabel;
    final subColor = dim
        ? AppColors.mechInkDim.withValues(alpha: 0.55)
        : AppColors.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  head,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: headColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  sub ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: subColor, height: 1.3),
                ),
              ),
              ?trailing,
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: dim
                    ? AppColors.mechInkDim.withValues(alpha: 0.5)
                    : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
