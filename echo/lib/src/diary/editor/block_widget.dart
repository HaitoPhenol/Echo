import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../sy/diary_model.dart';
import 'block_commands.dart';
import 'block_editor_controller.dart';
import 'diary_capsule_chip.dart';
import 'editor_scope.dart';

/// 单个日记块：左侧「类型图标 + 拖拽把手」纵向簇 + 多行输入区，支持
/// 段落/H1–H3 排印与块底色。
///
/// 键位拦截不走 Focus 冒泡（EditableText 在块首退格时会把空删除
/// 标记为 handled，冒泡到不了祖先），而是利用 EditableText 刻意暴露的
/// `Action.overridable` 机制：祖先 [Actions] 覆盖删除/纵向移动两个
/// intent，不满足块级语义时经 `callingAction` 回落给框架默认行为。
///
/// 把手点击选中后，经 [OverlayPortal] 在块标锚点浮出排版工具条
/// （转段落/标题、13 档底色）；选中态与浮层共生，点屏障处取消。
/// 把手同时包在 `ReorderableDelayedDragStartListener` 内：长按起拖，
/// 松手由 `SliverReorderableList` 落位（见 [BlockEditorView]）。
class BlockWidget extends StatefulWidget {
  const BlockWidget({super.key, required this.state, required this.index});

  final BlockState state;

  /// 本块在块列表中的下标（`SliverReorderableList` 拖拽起点用）。
  final int index;

  @override
  State<BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<BlockWidget> {
  final LayerLink _blockLink = LayerLink();
  final OverlayPortalController _popover = OverlayPortalController();
  final GlobalKey _popoverCardKey = GlobalKey();
  final GlobalKey _blockCardKey = GlobalKey();

  /// 浮层朝上还是朝下；选中后按实测高度与屏幕剩余空间修正。
  bool _placeBelow = true;

  /// 浮层最大宽：与块容器等宽（首帧用屏宽兜底，实测后收敛）。
  double? _popoverMaxWidth;

  BlockState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final editor = BlockEditorScope.of(context);
    final block = state.block;

    // 时间戳块：App 独有解析（`custom-echo-stamp` 块级属性）→ 渲染为只读
    // 胶囊 chip，不含块标、不含浮层、不含可输入 TextField。光标由编辑页
    // 自动落到它的下一行，用户在此块上无法编辑（plan 决策 3/16）。
    if (block.isStamp) {
      return Container(
        // 时间戳胶囊上方留出更大间距，与上一段内容在视觉上分开
        // （用户原话；导出时由 SySerializer 在时间戳上一行插入空行，同工）。
        margin: const EdgeInsets.only(top: 12, bottom: 1),
        child: Align(
          alignment: Alignment.centerLeft,
          child: DiaryCapsuleChip(
            key: ValueKey<String>('diary-stamp-${block.id}'),
            label: block.text,
          ),
        ),
      );
    }

    final selected = editor.selectedBlockId == block.id;
    final readOnly = editor.locked;

    // show/hide 不允许在 build 阶段直接调用，随选中态帧后同步浮层。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (selected) {
        _popover.show();
        // 等浮层上树后按实测尺寸决定朝上/朝下、与块等宽，避免溢出屏幕。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || editor.selectedBlockId != block.id) return;
          final cardBox =
              _popoverCardKey.currentContext?.findRenderObject() as RenderBox?;
          final blockBox =
              _blockCardKey.currentContext?.findRenderObject() as RenderBox?;
          if (cardBox == null || blockBox == null) return;
          final screenHeight = MediaQuery.sizeOf(context).height;
          final blockTop = blockBox.localToGlobal(Offset.zero).dy;
          final blockBottom = blockTop + blockBox.size.height;
          final needed = cardBox.size.height + 12;
          final spaceBelow = screenHeight - blockBottom;
          final spaceAbove = blockTop;
          // 下方放得下就朝下；下方放不下但上方放得下就朝上；
          // 两侧都不够时优先朝下（贴底后屏幕内至少保留完整宽度）。
          final wantBelow = spaceBelow >= needed || spaceAbove < needed;
          if (wantBelow != _placeBelow ||
              _popoverMaxWidth != blockBox.size.width) {
            setState(() {
              _placeBelow = wantBelow;
              _popoverMaxWidth = blockBox.size.width;
            });
          }
        });
      } else {
        _popover.hide();
      }
    });

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
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        ),
      ),
    );

    return OverlayPortal(
      controller: _popover,
      overlayChildBuilder: (context) =>
          _buildPopover(context, editor: editor, readOnly: readOnly),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        child: CompositedTransformTarget(
          link: _blockLink,
          child: Container(
            key: _blockCardKey,
            decoration: BoxDecoration(
              color: BlockBackgroundPalette.fillOf(block.background),
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(
                      color: AppColors.accentBlue.withValues(alpha: 0.55),
                    )
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ReorderableDelayedDragStartListener(
                  index: widget.index,
                  enabled: !readOnly,
                  // 类型图标只在光标位于本块时浮出，且不占布局宽度，
                  // 故随 focusNode 重建。
                  child: ListenableBuilder(
                    listenable: state.focusNode,
                    builder: (context, _) => _BlockHandle(
                      selected: selected,
                      readOnly: readOnly,
                      showTypeIcon: state.focusNode.hasFocus,
                      block: block,
                      onTap: () =>
                          editor.selectBlock(selected ? null : block.id),
                    ),
                  ),
                ),
                Expanded(child: textField),
                const SizedBox(width: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 工具条浮层：全屏吞点屏障（点外部取消选中）+ 锚定块标的工具条。
  Widget _buildPopover(
    BuildContext context, {
    required BlockEditorController editor,
    required bool readOnly,
  }) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => editor.selectBlock(null),
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: _blockLink,
          targetAnchor: _placeBelow ? Alignment.bottomLeft : Alignment.topLeft,
          followerAnchor: _placeBelow
              ? Alignment.topLeft
              : Alignment.bottomLeft,
          offset: Offset(0, _placeBelow ? 6 : -6),
          child: _BlockFormatPopover(
            key: _popoverCardKey,
            maxWidth: _popoverMaxWidth ?? MediaQuery.sizeOf(context).width - 28,
            state: state,
            editor: editor,
            readOnly: readOnly,
          ),
        ),
      ],
    );
  }

  static const double _paragraphSize = 16;
  static const double _paragraphHeight = 1.55;

  TextStyle _styleFor(DiaryBlock block) {
    // 13 号底色近白（思源 midnight 取色 #dadada），自动转深色正文。
    final ink = BlockBackgroundPalette.needsDarkInk(block.background)
        ? AppColors.background
        : AppColors.textPrimary;
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
          color: ink,
        );
      case DiaryBlockKind.paragraph:
        return TextStyle(
          fontSize: _paragraphSize,
          height: _paragraphHeight,
          color: ink,
        );
    }
  }
}

/// 块排版浮层：段落/H1–H3 + 13 档底色 + 无色。命令全部走控制器，
/// 应用后浮层保持打开（可连续排版），点屏障或再点块标关闭。
class _BlockFormatPopover extends StatelessWidget {
  const _BlockFormatPopover({
    super.key,
    required this.maxWidth,
    required this.state,
    required this.editor,
    required this.readOnly,
  });

  final double maxWidth;
  final BlockState state;
  final BlockEditorController editor;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final block = state.block;
    final headingActive = block.kind == DiaryBlockKind.heading;

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF151920),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.tone2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToolButton(
                    key: const ValueKey('diary-turn-p'),
                    label: '正文',
                    active: block.kind == DiaryBlockKind.paragraph,
                    onTap: readOnly
                        ? null
                        : () =>
                              editor.turnInto(state, DiaryBlockKind.paragraph),
                  ),
                  for (final level in [1, 2, 3])
                    _ToolButton(
                      key: ValueKey('diary-turn-h$level'),
                      label: 'H$level',
                      active: headingActive && block.level == level,
                      onTap: readOnly
                          ? null
                          : () => editor.turnInto(
                              state,
                              DiaryBlockKind.heading,
                              level: level,
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(height: 1, color: AppColors.tone1),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (
                    var n = BlockBackgroundPalette.min;
                    n <= BlockBackgroundPalette.max;
                    n++
                  )
                    _Swatch(
                      key: ValueKey('diary-bg-$n'),
                      color: BlockBackgroundPalette.colors[n]!,
                      active: block.background == n,
                      onTap: readOnly
                          ? null
                          : () => editor.setBackground(state, n),
                    ),
                  _Swatch(
                    key: const ValueKey('diary-bg-clear'),
                    active: block.background == null,
                    onTap: readOnly
                        ? null
                        : () => editor.setBackground(state, null),
                    child: Icon(
                      Icons.close,
                      size: 13,
                      color: block.background == null
                          ? AppColors.accentBlue
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 浮层内的块类型按钮。
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.accentBlue.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? AppColors.accentBlue : AppColors.tone2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: active ? AppColors.accentBlue : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 26dp 色块；[child] 非空时画「无色」边框样式。
class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    this.color,
    required this.active,
    required this.onTap,
    this.child,
  });

  final Color? color;
  final bool active;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? AppColors.accentBlue : AppColors.tone2,
            width: active ? 1.6 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
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

/// 块左侧纵向簇（类型图标 + 拖拽把手）的统一着色：选中取强调蓝，常态取
/// 机能风暗灰——沿用把手既有取值，让同簇两项读数一致。
Color _gutterInk(bool selected) => selected
    ? AppColors.accentBlue
    : AppColors.mechInkDim.withValues(alpha: 0.7);

/// 浮在拖拽把手下方的**当前块类型**小图标（不占布局、忽略指针）：
/// 段落取 `notes`，H1–H3 取
/// `looks_one/two/3`（Material 图标名 1/2 为英文、3 起为数字；回读的
/// H4–H6 与 H3 同字号，退化为通用标题图标）。
class _BlockTypeIcon extends StatelessWidget {
  const _BlockTypeIcon({super.key, required this.block, required this.color});

  final DiaryBlock block;
  final Color color;

  IconData get _icon {
    if (block.kind != DiaryBlockKind.heading) return Icons.notes;
    return switch (block.level) {
      1 => Icons.looks_one,
      2 => Icons.looks_two,
      3 => Icons.looks_3,
      _ => Icons.title,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      child: Center(child: Icon(_icon, size: 14, color: color)),
    );
  }
}

/// 24dp 块标：点击选中并浮出排版工具条。长按起拖由外层
/// [ReorderableDelayedDragStartListener] 识别，本组件只负责选中与外观。
///
/// 块类型图标不再占左侧布局宽度，改为浮在把手正下方的
/// [IgnorePointer] 小图标：仅本块获得焦点时显式，不推挤正文。
class _BlockHandle extends StatelessWidget {
  const _BlockHandle({
    required this.selected,
    required this.readOnly,
    required this.showTypeIcon,
    required this.block,
    required this.onTap,
  });

  final bool selected;
  final bool readOnly;
  final bool showTypeIcon;
  final DiaryBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: readOnly ? null : onTap,
      child: SizedBox(
        width: 24,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(Icons.drag_indicator, size: 16, color: _gutterInk(selected)),
            if (showTypeIcon)
              Positioned(
                top: 15,
                child: IgnorePointer(
                  child: _BlockTypeIcon(
                    key: ValueKey<String>('diary-type-${block.id}'),
                    block: block,
                    color: _gutterInk(selected),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
