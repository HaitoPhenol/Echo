import 'package:flutter/widgets.dart';

import 'block_editor_controller.dart';

/// 向编辑子树提供 [BlockEditorController]（块组件经它读样式、
/// 发命令；结构变化时整棵子树 rebuild，ListView 外的状态不丢）。
class BlockEditorScope extends InheritedNotifier<BlockEditorController> {
  const BlockEditorScope({
    super.key,
    required BlockEditorController controller,
    required super.child,
  }) : super(notifier: controller);

  static BlockEditorController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, '子树中缺少 BlockEditorScope');
    return controller!;
  }

  static BlockEditorController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BlockEditorScope>()
      ?.notifier;
}
