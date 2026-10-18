import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// 层级列表通用行：左侧大字标签、右侧辅助信息与箭头。
/// 行间分隔由背景机械网格承担，本行不画线。
///
/// 行首亮度**只两档**（均取自现有亮度阶梯，不自造透明度）：
/// · [highlight] 亮（主文字色 · 阶 4）——含今天的项：日页「今天」、
///   当前年行、当前月行；
/// · 默认 暗（[AppColors.pageLabel] · 阶 3）——其余年 / 月 / 日项
///   （含已归档）。
/// 已归档（正文已清理）不再另占行首色档，改由「已归档」徽标与
/// [dim] 降档的副文案 / 箭头标识。
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

  /// 降档弱化副文案与箭头（已归档：正文已从本机清理）。
  /// 不影响行首亮度——行首只分「含今天 / 不含今天」两档。
  final bool dim;

  /// 强调显示（含今天的项：今天 / 当前年 / 当前月）。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    // 行首只两档：亮 = 含今天（主文字色），暗 = 其余（页名标签色）。
    final headColor = highlight ? AppColors.textPrimary : AppColors.pageLabel;
    final subColor = dim
        ? AppColors.mechInkDim.withValues(alpha: 0.55)
        : AppColors.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // 2026-10-18 紧凑化：纵向内边距 14 → 5，行距（实测 ≈170 设备
          // 像素）压到 ≈120，减少列表留白；横向 4 不变。
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                // 行首定宽列：各层列表内行首与副文案起点对齐。宽度按最长
                // 行首「2026 年」（4 位数字 + 空格 + 汉字，22px/w600）留
                // 余量；maxLines=1 兜住极大字号下的折行。
                width: 96,
                child: Text(
                  head,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
