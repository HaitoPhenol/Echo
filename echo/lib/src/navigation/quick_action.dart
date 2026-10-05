import 'package:flutter/material.dart';

/// 快捷操作弧上的一个操作。
///
/// - [id]：稳定标识；
/// - [icon]：弧上显示的图标；
/// - [label]：操作名（无障碍与后续文案用）；
/// - [onSelect]：用户在弧上选中并松手时执行。
class QuickAction {
  const QuickAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onSelect,
  });

  /// 稳定 id。
  final String id;

  /// 操作图标。
  final IconData icon;

  /// 操作名称。
  final String label;

  /// 选中并松手时的行为。
  final void Function(BuildContext context) onSelect;
}

/// 构建默认快捷操作列表（弧上从左到右）。
///
/// 当前三个操作都处于「已接入接口、行为待实现」状态：
/// 触发时弹出统一的「开发中」提示，保证用户永远能得到明确反馈，
/// 而不是按了没有反应。
///
/// 接入真实功能的做法：替换对应 [QuickAction] 的 `onSelect`，
/// 例如扫码、新建会话、语音助手等；也可以调整数量与顺序。
List<QuickAction> buildDefaultQuickActions() {
  return [
    QuickAction(
      id: 'apps',
      icon: Icons.apps,
      label: '应用',
      onSelect: (context) => _showPending(context, '应用'),
    ),
    QuickAction(
      id: 'create',
      icon: Icons.add,
      label: '新建',
      onSelect: (context) => _showPending(context, '新建'),
    ),
    QuickAction(
      id: 'voice',
      icon: Icons.mic_none,
      label: '语音',
      onSelect: (context) => _showPending(context, '语音'),
    ),
  ];
}

/// 未实现操作的统一占位反馈。
void _showPending(BuildContext context, String name) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.clearSnackBars();
  messenger?.showSnackBar(
    SnackBar(
      content: Text('「$name」功能开发中'),
      duration: const Duration(seconds: 1),
    ),
  );
}
