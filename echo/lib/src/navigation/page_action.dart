import 'package:flutter/material.dart';

/// 把手条竖单上的一个「本页操作」。
///
/// 与 [QuickAction]（导航条上甩的全局快捷弧）同构但语义不同：
/// 本页操作作用于**当前所在页面**，今后可按页面配置不同内容；
/// 快捷弧的操作是全局的。
///
/// - [id]：稳定标识；
/// - [icon]：竖单圆形按钮上的图标；
/// - [label]：操作名称（无障碍与「开发中」提示用）；
/// - [onSelect]：用户在竖单上点按该按钮时执行。
class PageAction {
  const PageAction({
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

  /// 点按按钮时的行为。
  final void Function(BuildContext context) onSelect;
}

/// 构建默认本页操作列表（竖单内从上到下的排列顺序）。
///
/// 当前三个操作都处于「已接入接口、行为待实现」状态：
/// 触发时弹出统一的「开发中」提示，保证用户永远能得到明确反馈，
/// 而不是按了没有反应。
///
/// 接入真实功能的做法：替换对应 [PageAction] 的 `onSelect`，
/// 或改为按当前页面返回不同的操作列表（刷新/分享/置顶等）。
List<PageAction> buildDefaultPageActions() {
  return [
    PageAction(
      id: 'refresh',
      icon: Icons.refresh,
      label: '刷新',
      onSelect: (context) => _showPending(context, '刷新'),
    ),
    PageAction(
      id: 'share',
      icon: Icons.ios_share,
      label: '分享',
      onSelect: (context) => _showPending(context, '分享'),
    ),
    PageAction(
      id: 'pin',
      icon: Icons.push_pin_outlined,
      label: '置顶',
      onSelect: (context) => _showPending(context, '置顶'),
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
