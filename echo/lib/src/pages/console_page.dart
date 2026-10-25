/// 终端页（R6）：App 内的 ECP 命令行宿主。
///
/// 零新内核——交互编排直接复用搜索栏 slash 面板的
/// [SlashConsoleController]（含确认卡 / PIN 解锁 / 命令历史召回），
/// 执行仍走 `ControlChannel.slash` 同一条总线与鉴权；本页只负责
/// 换皮（整页结果流 + 底部常驻输入行）与终端语义的两个开关：
/// - `acceptBareCommands`：`sys.ping` 与 `/sys.ping` 等价（裸命令）；
/// - `completionEnabled = false`：无候选条，Enter 直接提交。
///
/// 结果渲染复用 [ConsoleResultList] / [SlashResultCard]，模态卡复用
/// [SlashSheetHost]，方向与「终端页是核心的第二个消费者」一致。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../control/bootstrap.dart';
import '../control/slash_ui/slash_command_layer.dart'
    show ConsoleResultList, SlashKeyEvents;
import '../control/slash_ui/slash_console_controller.dart';
import '../control/slash_ui/slash_sheets.dart';
import '../theme/app_colors.dart';
import '../theme/layout_metrics.dart';
import '../theme/mechanical_style.dart';

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key, this.footer});

  /// 页内附属区域（当前用于 debug 锚点调试面板；release 传 null）。
  final Widget? footer;

  // ---------------------------------------------------------------
  //  布局度量（手工微调入口：改这里，不动 build 表达式）
  // ---------------------------------------------------------------

  /// 页面左右留白（与底部停靠三条的 14 对齐）。
  static const double sidePadding = LayoutMetrics.dockSideMargin;

  /// 状态栏下沿到 kicker 的额外距离（避开顶部坐标读数条）。
  static const double headerTopGap = 26;

  /// kicker 与结果流之间的间距。
  static const double headerBottomGap = 10;

  /// 结果流上下留白。
  static const double resultListPaddingV = 8;

  /// 底部为停靠胶囊预留的高度：底距 16 + 胶囊高 48 + 间隙 8。
  ///
  /// 页面层不反向依赖 navigation 层（依赖方向是导航持有页面），
  /// 故按页面自身所需的避让高度就近定义，与 ChatPage 同范式。
  static const double bottomDockClearance =
      LayoutMetrics.dockBottomMargin + 48 + 8;

  /// 输入行高度（触控友好，留足纵向内边距）。
  static const double inputRowHeight = 44;

  /// 输入行与结果流 / 模态卡之间的间距。
  static const double inputRowGap = 8;

  /// 终端页结果上限（长生命周期宿主，环形裁剪已完成条目）。
  static const int resultLimit = 200;

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  /// 交互编排（无 ControlBootstrap 的 widget 测试下为 null）。
  SlashConsoleController? _controller;

  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final control = ControlBootstrap.instance;
    if (control == null) return;
    _controller = SlashConsoleController(
      bus: control.bus,
      auth: control.auth,
      acceptBareCommands: true,
      completionEnabled: false,
      entryLimit: ConsolePage.resultLimit,
      onEditText: (value) => _input.value = value,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 提交当前输入行：执行后清空输入，焦点留在输入框便于连续命令。
  void _submitCurrent() {
    final controller = _controller;
    if (controller == null) return;
    final text = _input.text;
    if (text.trim().isEmpty) return;
    // 不 await：结果经核心通知回流（running→done），本页只做清空。
    unawaited(controller.submit(text));
    _input.clear();
    controller.bind('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    // 键盘弹起时页面轨道已被整体垫高，底部停靠件被键盘遮住，无需再
    // 预留停靠高度；否则小屏加 PIN/确认卡会把输入行挤出可视区。
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final controller = _controller;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: padding.top + ConsolePage.headerTopGap),
        if (controller == null)
          const _Header(entryCount: 0)
        else
          ListenableBuilder(
            listenable: controller.core,
            builder: (context, _) =>
                _Header(entryCount: controller.core.entries.length),
          ),
        if (widget.footer != null) ...[
          const SizedBox(height: 8),
          widget.footer!,
        ],
        SizedBox(height: ConsolePage.headerBottomGap),
        Expanded(
          child: controller == null
              ? const _Unavailable()
              : _ResultStream(controller: controller),
        ),
        if (controller != null) SlashSheetHost(controller: controller),
        SizedBox(height: ConsolePage.inputRowGap),
        _InputRow(
          controller: _input,
          focusNode: _focus,
          enabled: controller != null,
          onChanged: controller?.bind,
          onSubmit: _submitCurrent,
          onRecall: controller,
        ),
        SizedBox(
          height:
              padding.bottom +
              (keyboardOpen
                  ? ConsolePage.inputRowGap
                  : ConsolePage.bottomDockClearance),
        ),
      ],
    );

    return ColoredBox(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ConsolePage.sidePadding,
        ),
        child: body,
      ),
    );
  }
}

/// 顶部区：机能风 kicker + 行数读数。
class _Header extends StatelessWidget {
  const _Header({required this.entryCount});

  final int entryCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'SEC.01 '),
              const TextSpan(
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  color: AppColors.mechInkDim,
                ),
                text: '// ',
              ),
              const TextSpan(text: 'CONSOLE'),
            ],
          ),
          style: const TextStyle(
            fontSize: MechanicalStyle.kickerFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: MechanicalStyle.kickerLetterSpacing,
            color: AppColors.mechInk,
            height: 1.2,
          ),
        ),
        const Spacer(),
        Text(
          entryCount == 0 ? 'READY' : '$entryCount REC',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            letterSpacing: 1.2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 结果流：整页可滚，reverse 使最新结果贴底、旧结果向上回看。
class _ResultStream extends StatelessWidget {
  const _ResultStream({required this.controller});

  final SlashConsoleController controller;

  @override
  Widget build(BuildContext context) {
    // 只监听结果核心：输入框每次 bind 也会通知 controller，没必要整表重建。
    return ListenableBuilder(
      listenable: controller.core,
      builder: (context, _) {
        if (controller.core.entries.isEmpty) {
          return const Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                '输入命令并回车执行，例如 sys.ping',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          );
        }
        return SingleChildScrollView(
          reverse: true,
          padding: const EdgeInsets.symmetric(
            vertical: ConsolePage.resultListPaddingV,
          ),
          child: ConsoleResultList(controller: controller),
        );
      },
    );
  }
}

/// 底部常驻输入行：提示符 + 等宽输入框 + 执行按钮。
class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onSubmit,
    required this.onRecall,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSubmit;

  /// 键事件宿主（↑↓ 历史召回 / Esc 清行）；无控制面时为 null。
  final SlashConsoleController? onRecall;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontFamily: 'monospace',
      ),
      cursorColor: AppColors.accentBlue,
      textInputAction: TextInputAction.send,
      decoration: const InputDecoration(
        isCollapsed: true,
        contentPadding: EdgeInsets.symmetric(vertical: 12),
        hintText: 'command…',
        hintStyle: TextStyle(
          color: AppColors.textMuted,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
        border: InputBorder.none,
      ),
      onChanged: onChanged,
      onSubmitted: (_) => onSubmit(),
    );

    return SizedBox(
      height: ConsolePage.inputRowHeight,
      child: Row(
        children: [
          const Text(
            '›',
            style: TextStyle(
              color: AppColors.accentBlue,
              fontSize: 16,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: onRecall == null
                ? field
                : SlashKeyEvents(controller: onRecall!, child: field),
          ),
          const SizedBox(width: 8),
          _SendButton(enabled: enabled, onPressed: onSubmit),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '执行命令',
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentBlue,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          '执行',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// 无控制面（未走 ControlBootstrap 的宿主/测试）时的说明占位。
class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          '控制面未挂载，终端不可用',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
    );
  }
}
