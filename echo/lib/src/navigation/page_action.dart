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

/// 构建**某一页**的本页操作列表（竖单内从上到下的排列顺序）。
///
/// 设计约定（见 [PageAction] 类注释）：把手条竖单显示的是**当前所在
/// 页面**的操作，各页本应独立、互不相同。本函数按页面 id 分派：
/// - **笔记页**：两个常驻入口——「今日日记」直接跳进今日日记编辑页、
///   「补记」弹日期选择器补录过去某天（2026-10-19 从月列表页顶栏的
///   「+」迁来，改为笔记页常驻），不再显示刷新 / 分享 / 置顶等占位项；
/// - 其余页面：暂沿用占位演示项 [buildDefaultPageActions]。
///
/// [onOpenTodayDiary]：笔记页「今日日记」项的行为（由导航屏注入，
/// 内部驱动日记内层栈到今日编辑页）。
/// [onBackfill]：笔记页「补记」项的行为（由导航屏注入，内部弹日期
/// 选择器并把日记内层栈带到所选日期的编辑页）。
/// [notesEditorActive]：笔记页栈顶是否为**日编辑页**（仅此时显示
/// 「插入时间戳」）。
/// [onInsertStamp]：在当前编辑页光标所在块下一行插入一个时间戳段的
/// 行为；无可用编辑页时返回 false。
List<PageAction> buildPageActions(
  String pageId, {
  required VoidCallback onOpenTodayDiary,
  required VoidCallback onBackfill,
  bool notesEditorActive = false,
  bool Function()? onInsertStamp,
}) {
  if (pageId == 'notes') {
    final insertStamp = onInsertStamp;
    return [
      PageAction(
        id: 'diary-today',
        icon: Icons.edit_calendar,
        label: '今日日记',
        onSelect: (_) => onOpenTodayDiary(),
      ),
      PageAction(
        id: 'backfill',
        icon: Icons.add,
        label: '补记',
        onSelect: (_) => onBackfill(),
      ),
      // 仅在日编辑页显示：在光标块下一行快速插入一个时间戳超级块。
      if (notesEditorActive && insertStamp != null)
        PageAction(
          id: 'insert-stamp',
          icon: Icons.add_alarm,
          label: '插入时间戳',
          onSelect: (_) => insertStamp(),
        ),
    ];
  }
  return buildDefaultPageActions();
}

/// 构建**占位演示**的本页操作列表（竖单内从上到下的排列顺序）。
///
/// 给尚未接入真实操作的页面（非笔记页）兜底使用；当前三个操作都处于
/// 「已接入接口、行为待实现」状态：触发时弹出统一的「开发中」提示，
/// 保证用户永远能得到明确反馈，而不是按了没有反应。
///
/// 接入真实功能的做法：在 [buildPageActions] 中按页面 id 返回专门
/// 的操作列表（参考笔记页分支），不再复用本占位列表。
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
