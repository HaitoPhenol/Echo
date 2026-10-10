import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../sy/diary_model.dart';
import 'block_commands.dart';
import 'block_editor_controller.dart';
import 'editor_scope.dart';

/// 单个日记块：48dp 块标 + 多行输入区，支持段落/H1–H3 排印与块底色。
///
/// 键位拦截不走 Focus 冒泡（EditableText 在块首退格时会把空删除
/// 标记为 handled，冒泡到不了祖先），而是利用 EditableText 刻意暴露的
/// `Action.overridable` 机制：祖先 [Actions] 覆盖删除/纵向移动两个
/// intent，不满足块级语义时经 `callingAction` 回落给框架默认行为。
class BlockWidget extends StatelessWidget {
  const BlockWidget({super.key, required this.state});

  final BlockState state;

  @override
  Widget build(BuildContext context) {
    final editor = BlockEditorScope.of(context);
    final block = state.block;
    final selected = editor.selectedBlockId == block.id;
    final readOnly = editor.locked || block.readonly;

    final textField = Actions(
      actions: <Type, Action<Intent>>{
        DeleteCharacterIntent: _BlockStartDeleteAction(editor, state),
        ExtendSelectionVerticallyToAdjacentLineIntent: _BlockVerticalMoveAction(
          editor,
          state,
        ),
      },
      child: TextField(
        controller: state.controller,
        focusNode: state.focusNode,
        readOnly: readOnly,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        style: _styleFor(block),
        cursorColor: AppColors.accentBlue,
        cursorRadius: const Radius.circular(1),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 9,
          ),
          hintText: block.readonly ? null : '写点什么…',
          hintStyle: TextStyle(
            color: AppColors.textMuted,
            fontSize: _paragraphSize,
            height: _paragraphHeight,
          ),
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: BlockBackgroundPalette.fillOf(block.background),
        borderRadius: BorderRadius.circular(8),
        border: selected
            ? Border.all(color: AppColors.accentBlue.withValues(alpha: 0.55))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _BlockHandle(
            selected: selected,
            readOnly: readOnly,
            onTap: () => editor.selectBlock(selected ? null : block.id),
          ),
          Expanded(child: textField),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  static const double _paragraphSize = 16;
  static const double _paragraphHeight = 1.55;

  TextStyle _styleFor(DiaryBlock block) {
    switch (block.kind) {
      case DiaryBlockKind.heading:
        // M3 会再校准字号/字距，先保证层级一眼可辨。
        final size = switch (block.level) {
          1 => 25.0,
          2 => 21.0,
          _ => 18.0,
        };
        return TextStyle(
          fontSize: size,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        );
      case DiaryBlockKind.paragraph:
        return const TextStyle(
          fontSize: _paragraphSize,
          height: _paragraphHeight,
          color: AppColors.textPrimary,
        );
    }
  }
}

/// 块首退格拦截：仅在折叠光标位于 offset 0 且满足合并/删块条件时
/// 接管；其余情况回落给 EditableText 默认字符删除。
class _BlockStartDeleteAction extends Action<DeleteCharacterIntent> {
  _BlockStartDeleteAction(this._editor, this._state);

  final BlockEditorController _editor;
  final BlockState _state;

  @override
  Object? invoke(DeleteCharacterIntent intent) {
    if (!intent.forward && _editor.handleBackspace(_state)) {
      return null;
    }
    return callingAction?.invoke(intent);
  }
}

/// ↑/↓ 在块边界时跳到相邻块；块内多行移动回落给框架。
/// （Shift 纵向扩展选区不拦截。）
class _BlockVerticalMoveAction
    extends Action<ExtendSelectionVerticallyToAdjacentLineIntent> {
  _BlockVerticalMoveAction(this._editor, this._state);

  final BlockEditorController _editor;
  final BlockState _state;

  @override
  Object? invoke(ExtendSelectionVerticallyToAdjacentLineIntent intent) {
    if (intent.collapseSelection &&
        _editor.handleVerticalMove(_state, up: !intent.forward)) {
      return null;
    }
    return callingAction?.invoke(intent);
  }
}

/// 48dp 块标（M3 在此挂转标题/底色/拖拽菜单）。
class _BlockHandle extends StatelessWidget {
  const _BlockHandle({
    required this.selected,
    required this.readOnly,
    required this.onTap,
  });

  final bool selected;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.accentBlue
        : AppColors.mechInkDim.withValues(alpha: 0.7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: readOnly ? null : onTap,
      child: SizedBox(
        width: 48,
        child: Center(
          child: Icon(Icons.drag_indicator, size: 18, color: color),
        ),
      ),
    );
  }
}
