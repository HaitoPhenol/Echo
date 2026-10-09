import 'package:flutter/material.dart';

import '../services/chat_store.dart';
import '../services/nav_badge_service.dart';
import '../theme/app_colors.dart';

/// 终端页的锚点调试面板（仅开发测试用，真实通知/异常源接入后移除）。
///
/// 三个按钮对应锚点验收的三个场景：
/// - 「模拟：聊天新消息」：向会话列表插入一条未读会话，行内呼吸绿点
///   与聊天页锚点由 [ChatStore] 联动；
/// - 「模拟：异常」：终端页锚点进入红色急闪；
/// - 「处理异常」：显式解除终端页异常态；无待处理异常时按钮禁用，
///   文案变为「当前无待处理异常」。
///
/// 异常模拟/处理都作用于终端页自身。[consolePageIndex] 是终端页在导航
/// 配置中的下标，由接线处（nav_destination.dart）按稳定 id 解析后
/// 传入，组件内不写死页序号（页面调序后不会作用到错误的页）。
class ConsoleBadgeControls extends StatelessWidget {
  const ConsoleBadgeControls({
    super.key,
    required this.consolePageIndex,
  });

  /// 终端页下标（异常模拟/处理的作用页）。
  final int consolePageIndex;

  @override
  Widget build(BuildContext context) {
    final badges = NavBadgeScope.of(context);
    final chatStore = ChatStoreScope.of(context);
    // 依赖 NavBadgeScope：异常态变化时本面板自动重建，按钮随之
    // 在「处理异常」与禁用文案之间切换。
    final hasError =
        badges.levelOf(consolePageIndex) == NavBadgeLevel.exception;
    return _DebugButtonRow(
      buttons: [
        _DebugAction(
          label: '模拟：聊天新消息',
          onTap: () {
            chatStore.addIncoming();
            _toast(context, '已模拟：聊天新消息');
          },
        ),
        _DebugAction(
          label: '模拟：异常',
          onTap: () {
            badges.reportException(consolePageIndex);
            _toast(context, '已模拟：异常');
          },
        ),
        _DebugAction(
          label: hasError ? '处理异常' : '当前无待处理异常',
          enabled: hasError,
          onTap: () {
            badges.resolveException(consolePageIndex);
            _toast(context, '异常已处理');
          },
        ),
      ],
    );
  }
}

/// 一行小号描边按钮，居中自动换行。
class _DebugButtonRow extends StatelessWidget {
  const _DebugButtonRow({required this.buttons});

  final List<_DebugAction> buttons;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final action in buttons)
          OutlinedButton(
            onPressed: action.enabled ? action.onTap : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              side: const BorderSide(color: AppColors.tone1),
              foregroundColor: AppColors.tone3,
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: Text(action.label),
          ),
      ],
    );
  }
}

/// 按钮的最小描述。
class _DebugAction {
  const _DebugAction({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
}

/// 轻提示：明确告诉用户模拟动作已发生（避免「按了没反应」）。
void _toast(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.clearSnackBars();
  messenger?.showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 1)),
  );
}
