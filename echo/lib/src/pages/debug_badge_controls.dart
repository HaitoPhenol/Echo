import 'package:flutter/material.dart';

import '../services/nav_badge_service.dart';

// 页面序号（测试脚手架直接按当前 4 页顺序引用；
// 正式接入时由各业务模块在自己的上下文中上报，不会硬编码序号）。
const int _chatPage = 1;
const int _notesPage = 2;

/// 控制台页的通知模拟按钮（仅开发测试用，真实通知接入后移除）。
///
/// 对应验收场景：聊天新消息（绿）、日志报错（红）。
class ConsoleBadgeControls extends StatelessWidget {
  const ConsoleBadgeControls({super.key});

  @override
  Widget build(BuildContext context) {
    final badges = NavBadgeScope.of(context);
    return _DebugButtonRow(
      buttons: [
        _DebugAction(
          label: '模拟：聊天新消息',
          onTap: () {
            badges.postNotification(_chatPage);
            _toast(context, '已模拟：聊天新消息');
          },
        ),
        _DebugAction(
          label: '模拟：日志报错',
          onTap: () {
            badges.reportException(_notesPage);
            _toast(context, '已模拟：日志报错');
          },
        ),
      ],
    );
  }
}

/// 日志页的「处理异常」按钮（仅开发测试用）。
///
/// 异常未处理完成时按钮可点；处理后状态恢复，按钮变为禁用文案。
class LogBadgeControls extends StatelessWidget {
  const LogBadgeControls({super.key});

  @override
  Widget build(BuildContext context) {
    final badges = NavBadgeScope.of(context);
    final hasError = badges.levelOf(_notesPage) == NavBadgeLevel.exception;
    return _DebugButtonRow(
      buttons: [
        _DebugAction(
          label: hasError ? '处理异常' : '当前无待处理异常',
          enabled: hasError,
          onTap: () {
            badges.resolveException(_notesPage);
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
              side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              foregroundColor: Colors.white.withValues(alpha: 0.78),
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
