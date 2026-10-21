import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 胶囊外观基元（2026-10-18 模板重设）。
///
/// 由原 `ui/widgets/diary_capsule_row.dart` 的私有 `_Capsule` / `_Emoji`
/// 提取公开化，供两处共用：
/// * [DiaryCapsuleRow]（文档根 `custom-*` 数据五槽）；
/// * [BlockWidget] 的时间戳块分支（`custom-echo-stamp` 只读胶囊）。
///
/// 放 `editor/` 的依据：`ui/widgets/**` 已 import `editor/**`（既有依赖
/// 方向），反向 import 不新增依赖（plan 决策 15）。外观与参数与原实现一致。
class DiaryCapsuleChip extends StatelessWidget {
  const DiaryCapsuleChip({
    super.key,
    this.leading,
    this.label,
    this.onTap,
    this.dimmed = false,
  });

  /// 前导表情/图标；null 时只有文字。
  final Widget? leading;

  /// 文字；null 时只有前导。
  final String? label;

  final VoidCallback? onTap;

  /// 取数中降透明度（仅数据胶囊使用）。
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (leading != null) ...[leading!, const SizedBox(width: 4)],
      if (label != null)
        Text(
          label!,
          style: const TextStyle(fontSize: 11, color: AppColors.pageLabel),
        ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.tone1,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// 胶囊前导 emoji：字号随胶囊文字（11）略大一号，保证表情可辨。
class DiaryCapsuleEmoji extends StatelessWidget {
  const DiaryCapsuleEmoji(this.glyph, {super.key});

  final String glyph;

  @override
  Widget build(BuildContext context) =>
      Text(glyph, style: const TextStyle(fontSize: 12));
}
