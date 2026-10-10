import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'block_editor_controller.dart';

/// 编辑页标题栏的结构撤销/重做入口。
///
/// 只覆盖**结构操作**（拆/合块、转标题、底色）；字符级撤销仍由
/// TextField 内建 UndoHistory 在键盘聚焦时提供。状态随控制器
/// 历史栈自动启停；文档锁定（导出只读）时恒禁用。
class EditorHistoryButtons extends StatelessWidget {
  const EditorHistoryButtons({super.key, required this.controller});

  final BlockEditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final locked = controller.locked;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HistoryIcon(
              icon: Icons.undo,
              semanticLabel: '撤销',
              enabled: !locked && controller.canUndo,
              onTap: controller.undo,
            ),
            _HistoryIcon(
              icon: Icons.redo,
              semanticLabel: '重做',
              enabled: !locked && controller.canRedo,
              onTap: controller.redo,
            ),
          ],
        );
      },
    );
  }
}

class _HistoryIcon extends StatelessWidget {
  const _HistoryIcon({
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.pageLabel
        : AppColors.mechInkDim.withValues(alpha: 0.45);
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 17, color: color),
      iconSize: 17,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      splashRadius: 14,
      tooltip: semanticLabel,
    );
  }
}
