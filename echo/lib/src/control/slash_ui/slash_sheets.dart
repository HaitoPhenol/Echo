/// slash 指令态的三类模态卡（G2）：PIN 面板（首装两输/解锁/重试）、
/// destructive 确认卡、多行正文编辑。
///
/// 三者同屏至多一个，由 [SlashSheetHost] 统一监听控制器并按优先级
/// 挂载（PIN > 确认卡 > 多行）。卡片只负责呈现与采集，裁决/重放/
/// 互斥全部在 SlashConsoleController / 总线，不在此重复。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import 'slash_console_controller.dart';

/// 卡片宿主：监听控制器，按当前阶段挂对应卡（无卡时零占位）。
class SlashSheetHost extends StatelessWidget {
  const SlashSheetHost({super.key, required this.controller});

  final SlashConsoleController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.pinSheet.visible) {
          return _PinSheet(controller: controller, state: controller.pinSheet);
        }
        final confirm = controller.confirmPending;
        if (confirm != null) {
          return _ConfirmSheet(controller: controller, pending: confirm);
        }
        if (controller.multilineOpen) {
          return _MultilineSheet(controller: controller);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// 三类卡共用的深色面板容器。
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.overlaySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.tone1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

// ---- PIN 面板 -----------------------------------------------------------

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.controller, required this.state});

  final SlashConsoleController controller;
  final PinSheetState state;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final TextEditingController _pin = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void didUpdateWidget(covariant _PinSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 阶段推进（首装→再输）/重试/焚会话复位时清空输入并保持聚焦。
    if (oldWidget.state.mode != widget.state.mode ||
        (oldWidget.state.error == null && widget.state.error != null)) {
      _pin.clear();
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  ({String title, String subtitle}) get _copy => switch (widget.state.mode) {
    PinSheetMode.firstInstall => (
      title: '首次使用 · 设置 PIN',
      subtitle: '4–32 位数字；只存加盐哈希，进入 3 级权限前需要它',
    ),
    PinSheetMode.firstInstallConfirm => (
      title: '再输入一遍 PIN',
      subtitle: '两次一致即完成设置并自动继续原命令',
    ),
    PinSheetMode.unlock => (
      title: '需要 3 级权限',
      subtitle: '输入 PIN 解锁；会话仅本次前台有效，切后台立即失效',
    ),
    PinSheetMode.hidden => (title: '', subtitle: ''),
  };

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return _SheetScaffold(
      children: [
        Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 15,
              color: widget.state.error != null
                  ? AppColors.anchorRed
                  : AppColors.accentBlue,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                copy.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              onTap: widget.state.busy ? null : widget.controller.cancelPin,
              child: const Icon(
                Icons.close,
                size: 15,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          copy.subtitle,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pin,
                focusNode: _focus,
                obscureText: true,
                enabled: !widget.state.busy,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                ],
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  letterSpacing: 3,
                ),
                cursorColor: AppColors.accentBlue,
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  filled: true,
                  fillColor: const Color(0x0DFFFFFF),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: widget.state.error != null
                          ? AppColors.anchorRed.withValues(alpha: 0.6)
                          : AppColors.tone1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.accentBlue),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.tone1),
                  ),
                  hintText: 'PIN',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                ),
                onSubmitted: (v) => widget.controller.submitPin(v),
              ),
            ),
            const SizedBox(width: 8),
            _PinActionButton(
              busy: widget.state.busy,
              isConfirm: widget.state.mode == PinSheetMode.firstInstallConfirm,
              onPressed: () => widget.controller.submitPin(_pin.text),
            ),
          ],
        ),
        if (widget.state.error != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.state.error!,
            style: const TextStyle(color: AppColors.anchorRed, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _PinActionButton extends StatelessWidget {
  const _PinActionButton({
    required this.busy,
    required this.isConfirm,
    required this.onPressed,
  });

  final bool busy;
  final bool isConfirm;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentBlue,
          foregroundColor: AppColors.inverse,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(isConfirm ? '确认' : '确定'),
      ),
    );
  }
}

// ---- destructive 确认卡 -------------------------------------------------

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.controller, required this.pending});

  final SlashConsoleController controller;
  final PendingConfirm pending;

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      children: [
        Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: AppColors.anchorRed,
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '执行 3 级破坏性命令',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              onTap: controller.cancelConfirm,
              child: const Icon(
                Icons.close,
                size: 15,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${pending.cmd} --confirm',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
        if (pending.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            pending.summary,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
        const SizedBox(height: 6),
        const Text(
          '执行后立即生效，不可撤销。',
          style: TextStyle(color: AppColors.anchorRed, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: controller.cancelConfirm,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: controller.confirmRun,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.anchorRed,
                foregroundColor: AppColors.tone4,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('确认执行'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---- 多行正文 -----------------------------------------------------------

class _MultilineSheet extends StatefulWidget {
  const _MultilineSheet({required this.controller});

  final SlashConsoleController controller;

  @override
  State<_MultilineSheet> createState() => _MultilineSheetState();
}

class _MultilineSheetState extends State<_MultilineSheet> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final draft = c.multiline;
    return _SheetScaffold(
      children: [
        Row(
          children: [
            const Icon(Icons.subject, size: 15, color: AppColors.accentBlue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '多行正文 · --${draft?.param ?? 'text'}（换行原样保留）',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              onTap: c.closeMultiline,
              child: const Icon(
                Icons.close,
                size: 15,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          focusNode: _focus,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          cursorColor: AppColors.accentBlue,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0x0DFFFFFF),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.tone1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accentBlue),
            ),
            hintText: '在此输入正文…',
            hintStyle: const TextStyle(color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: c.closeMultiline,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => c.submitMultilineText(_text.text),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentBlue,
                foregroundColor: AppColors.inverse,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('发送'),
            ),
          ],
        ),
      ],
    );
  }
}
