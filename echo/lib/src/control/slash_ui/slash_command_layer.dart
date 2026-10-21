/// slash 指令态浮层（G2）：搜索胶囊上方的补全条 + 结果流 +
/// 模态卡宿主。
///
/// 本 Widget **不拥有**输入框（输入框仍是搜索胶囊里的 TextField，
/// 搜索/指令共用一个控制器），只做四件事：
/// 1. 监听 [SlashConsoleController]，指令态激活时挂载、退出时零占位；
/// 2. 候选补全条（点选插入；↑↓/Enter/Tab/Esc 键事件经外层
///    [SlashKeyEvents] 静态助手绑定到 TextField 的 focus 上下文，
///    见 [wrapInput]）；
/// 3. 结果卡片流（正序、最新在底、限高内滚、JSON 长按复制在卡片内）；
/// 4. PIN/确认/多行三类模态卡（SlashSheetHost）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../slash/completion.dart';
import '../slash/console_core.dart';
import 'slash_console_controller.dart';
import 'slash_result_card.dart';
import 'slash_sheets.dart';

class SlashCommandLayer extends StatelessWidget {
  const SlashCommandLayer({
    super.key,
    required this.controller,
    this.maxHeightFactor = 0.45,
  });

  final SlashConsoleController controller;

  /// 整个浮层（补全 + 结果 + 模态卡）的最大高度占屏比。
  ///
  /// G4-BUG-3：模态卡（确认/PIN/多行）始终以固有高度完整布局在约束盒
  /// 底部；补全/结果区是唯一可压缩项，空间不足时整块在内部滚动（可被
  /// 压到 0），任何高度下都不会把卡片按钮挤出 RenderBox 造成溢出区
  /// hitTest 恒 false（「可见不可点」）。
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.active &&
            !controller.pinSheet.visible &&
            !controller.multilineOpen &&
            controller.confirmPending == null) {
          return const SizedBox.shrink();
        }
        final mq = MediaQuery.of(context);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: mq.size.height * maxHeightFactor,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 可压缩区（Flexible + 内部滚动）：结果流/多行入口/补全条
              // 争用剩余高度，最坏可被压到 0（G4-BUG-3：模态卡必须完整，
              // 故此区必须可压缩，补全条不能钉在 Flexible 外）；reverse 使
              // 溢出时整层默认停在最底，底部的补全条优先可见。
              Flexible(
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ResultsList(controller: controller),
                      if (controller.active && controller.canOpenMultiline)
                        Align(
                          alignment: Alignment.centerRight,
                          child: _MultilineToggle(controller: controller),
                        ),
                      // 补全候选条恒置于消息列表（结果流）**底部**：reverse
                      // 滚动默认停在最底，候选贴着输入框始终首先可见，不再
                      // 被历史结果顶到列表顶端而离开视线。
                      if (controller.active)
                        _CompletionBar(controller: controller),
                    ],
                  ),
                ),
              ),
              // 模态卡宿主在 Flexible 之外：非弹性项以固有高度布局，
              // 永远完整落在约束盒内（G4-BUG-3）。
              SlashSheetHost(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

// ---- 补全候选条 ---------------------------------------------------------

class _CompletionBar extends StatelessWidget {
  const _CompletionBar({required this.controller});

  final SlashConsoleController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.completion;
    if (result.candidates.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.overlaySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tone1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Text(
              _segmentLabel(result.segment),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                letterSpacing: 0.8,
              ),
            ),
          ),
          for (var i = 0; i < result.candidates.length; i++)
            _CandidateTile(
              candidate: result.candidates[i],
              selected: i == controller.candidateIndex,
              onTap: () => controller.applyCandidate(result.candidates[i]),
            ),
        ],
      ),
    );
  }

  String _segmentLabel(CompletionSegment s) => switch (s) {
    CompletionSegment.namespace => '命名空间',
    CompletionSegment.verb => '命令',
    CompletionSegment.param => '参数',
    CompletionSegment.none => '',
  };
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final CompletionCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: selected ? const Color(0x147AA2FF) : null,
        child: Row(
          children: [
            Text(
              candidate.label,
              style: TextStyle(
                color: selected ? AppColors.accentBlue : AppColors.textPrimary,
                fontSize: 12,
                fontFamily: candidate.label.startsWith('--')
                    ? 'monospace'
                    : null,
              ),
            ),
            if (candidate.hint.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                candidate.hint,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                candidate.detail,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- 结果流（倒序） -----------------------------------------------------

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.controller});

  final SlashConsoleController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.core.entries;
    if (entries.isEmpty) return const SizedBox.shrink();
    // 用普通 Column 而非 shrinkWrap/reverse 的 ListView：本区已身处外层
    // SingleChildScrollView 之内，嵌套的滚动体会在竖直拖拽的手势竞技场
    // 抢先胜出却零可滚范围（内容 == 视口），使整层「拖不动、滚不到顶」。
    // 按 entries 追加序正序排列：新结果落在列表最底、紧贴补全条/输入框，
    // 而不是插到顶部把旧结果往下顶。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EntryCard(entry: entries[i]),
          ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final ConsoleEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 命令回显行：等宽小字 + busy 转圈 + 状态点。
        Row(
          children: [
            if (entry.status == ConsoleEntryStatus.running)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  entry.ok ? Icons.check_circle_outline : Icons.cancel,
                  size: 12,
                  color: entry.ok ? AppColors.anchorGreen : AppColors.anchorRed,
                ),
              ),
            Expanded(
              child: Text(
                entry.line,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (entry.view != null) SlashResultCard(view: entry.view!),
      ],
    );
  }
}

// ---- 多行进文本入口 -----------------------------------------------------

class _MultilineToggle extends StatelessWidget {
  const _MultilineToggle({required this.controller});

  final SlashConsoleController controller;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: controller.openMultiline,
      icon: const Icon(Icons.subject, size: 13),
      label: const Text('多行正文', style: TextStyle(fontSize: 11)),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentBlue,
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

// ---- 键事件助手 ---------------------------------------------------------

/// 指令态键事件绑定：包在搜索 TextField 外层即可（生产宿主
/// smart_nav_screen 调用）。
///
/// - Esc：退出指令态（清输入、回搜索语义）；
/// - ↑/↓：候选选择优先，无候选展开时 ↑↓ 召回命令历史；
/// - Tab / Enter（有高亮候选时）：应用候选但不提交；
/// - Enter 无候选：放行（TextField.onSubmitted 正常提交）。
///
/// 只在 controller.active 时拦截，搜索态零影响。
class SlashKeyEvents extends StatelessWidget {
  const SlashKeyEvents({
    super.key,
    required this.controller,
    required this.child,
  });

  final SlashConsoleController controller;
  final Widget child;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!controller.active) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      controller.exitSlash();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return controller.handleUp()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return controller.handleDown()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.tab) {
      return controller.applySelected()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.enter) {
      // 有高亮候选时 Enter 先补全；候选段 none 时放行提交。
      return controller.handleEnter()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) => _onKey(node, event),
      canRequestFocus: false,
      child: child,
    );
  }
}
